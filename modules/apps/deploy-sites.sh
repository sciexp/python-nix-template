#!/usr/bin/env bash
# shellcheck shell=bash
# deploy-sites.sh — build the python-nix-template quarto docs site at runtime
# and deploy it to Cloudflare Workers (preview or production).
#
# This app bakes the docs *source* (not a pre-built payload) plus the toolchain
# into its closure, then at runtime: copies the baked source to a writable
# tmpdir, `git init`s a throwaway SCM root (DVC here is SCM-coupled, so `dvc
# pull` requires a git repo at the root), pulls the DVC-tracked freeze cache
# from R2, builds the quarto site, and (for preview/production) deploys the
# resulting docs/_site to the `python-nix-template` Cloudflare Worker. The
# `build` subcommand runs only the build half and performs no deploy. Notebook
# execution is out-of-band (per-document `freeze: true`, DVC-tracked): the build
# path only `dvc pull`s the freeze and renders against it, never re-executing
# notebooks.
#
# Git metadata is resolved at the top of the run (before the tmpdir is entered)
# so the git fallback queries the original worktree, not the .git-less tmpdir.
#
# Required (config, injected by deploy-sites.nix via runtimeEnv):
#   DOCS_SRC       store path of the baked source fileset
#                  (.dvc/config, docs/, wrangler.jsonc, docs/_freeze.dvc).
#   QUARTO_PYTHON  python interpreter of the docs venv (quartodoc + pnt_core).
#   WRANGLER       wrangler entrypoint; invoked as `node "$WRANGLER"`.
#
# Required (secret, caller-provided via inherited env):
#   CLOUDFLARE_API_TOKEN     wrangler auth token (deploy).
#   CLOUDFLARE_ACCOUNT_ID    Cloudflare account id (account-scoped ops).
#   AWS_ACCESS_KEY_ID        R2 S3 HMAC key id (dvc pull).
#   AWS_SECRET_ACCESS_KEY    R2 S3 HMAC secret (dvc pull).
#
# Optional (env-first with git fallback): every GIT_* consumer is
# `${GIT_X:-$(git … 2>/dev/null || true)}` so the script runs both inside an
# effects sandbox (no .git; env pre-populated by the effect preamble) and from
# a live worktree (env unset; git fallback resolves locally):
#   GIT_REV, GIT_REV_SHORT, GIT_REV_SHORT12, GIT_BRANCH, GIT_COMMIT_MSG,
#   GIT_WORKTREE_STATUS.
# Optional (caller debugging / overrides):
#   DEPLOY_SITES_DEBUG, DEPLOY_HOST, DEPLOY_DEPLOYER,
#   GITHUB_ACTIONS / GITHUB_ACTOR / GITHUB_WORKFLOW.

set -euo pipefail

# Worker identity from wrangler.jsonc and the existing justfile recipes.
WORKER_NAME="python-nix-template"
WORKERS_SUBDOMAIN="sciexp"
PRODUCTION_URL="https://python-nix-template.scientistexperience.net"

usage() {
  cat <<'EOF'
usage: deploy-sites build
       deploy-sites preview <branch>
       deploy-sites production
       deploy-sites --help

Build the python-nix-template quarto docs site at runtime and (for preview /
production) deploy it to Cloudflare Workers.

Subcommands:
  build              Run only the build half (copy baked source -> git init ->
                     dvc pull -> quartodoc build/interlinks -> quarto render),
                     leaving docs/_site in a tmpdir whose path is printed. No
                     wrangler deploy; CLOUDFLARE_* credentials are not required.
  preview <branch>   Build the site, then upload a Cloudflare Workers preview
                     version tagged with the current HEAD 12-char SHA, aliased
                     at b-<sanitized-branch>. <branch> defaults to the current
                     branch; an explicit value is required when HEAD is detached.
  production         Build the site, then promote the existing preview version
                     matching the current HEAD 12-char SHA to 100% production
                     traffic, or fall back to a direct `wrangler deploy` when no
                     matching preview version exists.

Flags:
  --help, -h         Print this usage and exit 0.

Environment contract (see top-of-file header for full details):
  Required (config, injected by deploy-sites.nix):
    DOCS_SRC, QUARTO_PYTHON, WRANGLER
  Required (secret, caller-provided):
    AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY            (all subcommands)
    CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID         (preview / production)
  Optional (env-first with git/shell fallback):
    GIT_REV, GIT_REV_SHORT, GIT_REV_SHORT12, GIT_BRANCH, GIT_COMMIT_MSG,
    GIT_WORKTREE_STATUS, DEPLOY_HOST, DEPLOY_DEPLOYER
  Optional (caller debugging / overrides):
    DEPLOY_SITES_DEBUG, GITHUB_ACTIONS / GITHUB_ACTOR / GITHUB_WORKFLOW

Examples:
  nix run .#deploy-sites -- build
  nix run .#deploy-sites -- preview my-feature-branch
  nix run .#deploy-sites -- production
EOF
}

# --- argv preflight -------------------------------------------------------

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

if [[ $# -lt 1 ]]; then
  echo "error: missing subcommand" >&2
  usage >&2
  exit 2
fi

mode="$1"
shift

case "$mode" in
  build | preview | production) ;;
  *)
    echo "error: unknown subcommand '$mode'" >&2
    usage >&2
    exit 2
    ;;
esac

# --- config env preflight -------------------------------------------------

: "${DOCS_SRC:?DOCS_SRC not set; deploy-sites.nix must inject the baked source fileset}"
: "${QUARTO_PYTHON:?QUARTO_PYTHON not set; deploy-sites.nix must inject the docs venv python}"
: "${WRANGLER:?WRANGLER not set; deploy-sites.nix must inject the wrangler entrypoint}"
[[ -d "$DOCS_SRC" ]] || {
  echo "error: DOCS_SRC '$DOCS_SRC' is not a directory" >&2
  exit 1
}

# --- secret env preflight -------------------------------------------------
#
# Guard against both unset and the literal string "null" (a sops/jq miss yields
# "null" rather than an empty value). Secrets arrive via inherited env; the app
# never decrypts them itself.
require_secret() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" || "$value" == "null" ]]; then
    echo "error: $name is required and must be non-empty (got '${value}')" >&2
    echo "       the caller must export it (sops exec-env, direnv, or GHA env)" >&2
    exit 1
  fi
}
# AWS_* feed the R2 dvc pull and are required by every mode (all build the
# site). CLOUDFLARE_* are consumed only by the wrangler deploy, so the build
# subcommand does not require them.
require_secret AWS_ACCESS_KEY_ID
require_secret AWS_SECRET_ACCESS_KEY
if [[ "$mode" != "build" ]]; then
  require_secret CLOUDFLARE_API_TOKEN
  require_secret CLOUDFLARE_ACCOUNT_ID
fi

# --- commit metadata ------------------------------------------------------
#
# Resolve ALL git metadata HERE, before the tmpdir is created and entered, so
# the git fallback queries the ORIGINAL cwd (the live worktree) rather than the
# .git-less tmpdir copy. Order per source: (a) injected GIT_* env (the effect
# path injects these at eval time, where no worktree exists); (b) else git
# against the current worktree (the `nix run` / GHA path); (c) else a safe
# default. The git fallbacks are errexit-tolerant so a missing .git surfaces as
# empty/"dirty" rather than aborting.
commit_sha="${GIT_REV:-$(git rev-parse HEAD 2>/dev/null || true)}"
commit_tag="${GIT_REV_SHORT12:-$(git rev-parse --short=12 HEAD 2>/dev/null || true)}"
commit_short="${GIT_REV_SHORT:-$(git rev-parse --short HEAD 2>/dev/null || true)}"
current_branch="${GIT_BRANCH:-$(git branch --show-current 2>/dev/null || true)}"
commit_msg="${GIT_COMMIT_MSG:-$(git log -1 --pretty=format:'%s' 2>/dev/null || true)}"
if [[ -n "${GIT_WORKTREE_STATUS:-}" ]]; then
  git_status="$GIT_WORKTREE_STATUS"
elif git diff-index --quiet HEAD -- 2>/dev/null; then
  git_status="clean"
else
  # Non-zero from `git diff-index` covers both "dirty worktree" and "not a git
  # repository" — collapse both to "dirty" so version_message is always
  # well-formed.
  git_status="dirty"
fi

deploy_host="${DEPLOY_HOST:-${HOSTNAME%%.*}}"
deployer="${DEPLOY_DEPLOYER:-${GITHUB_ACTOR:-$(whoami 2>/dev/null || echo unknown)}}"

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  deploy_context="${GITHUB_WORKFLOW:-CI}"
  deploy_msg="Deployed by ${deployer} from ${current_branch} via ${deploy_context}"
else
  deploy_msg="Deployed by ${deployer} from ${current_branch} on ${deploy_host}"
fi

# --- materialise writable copy --------------------------------------------
#
# DVC writes its cache and quarto/quartodoc write generated artifacts during
# the build, so the read-only baked source must be copied into a writable
# tmpdir before the build runs. Git metadata was already resolved above against
# the original cwd; everything below operates inside the tmpdir.
tmpdir=$(mktemp -d -t deploy-sites.XXXXXX)
if [[ -n "${DEPLOY_SITES_DEBUG:-}" ]]; then
  echo "[deploy-sites] DEBUG: preserving tmpdir at $tmpdir" >&2
  trap 'echo "[deploy-sites] DEBUG: tmpdir preserved at $tmpdir" >&2' EXIT
else
  trap 'rm -rf "$tmpdir"' EXIT
fi
cp -R "$DOCS_SRC"/. "$tmpdir/"
chmod -R u+w "$tmpdir"
cd "$tmpdir"

# --- build the site -------------------------------------------------------
#
# git init -> DVC pull (R2; AWS_* from env) -> quartodoc build + interlinks ->
# quarto render, mirroring the justfile docs-reference/docs-build sequence.
# Notebooks are never executed here; the per-document freeze cache pulled from
# R2 is the authoritative render input.
build_site() {
  # Isolate HOME and XDG dirs into the per-run tmpdir. A host quarto/deno SASS
  # cache contaminated by a different quarto version surfaces as a deno_kv
  # SassCache RangeError during `quarto render`. Fresh per-run dirs give quarto
  # a clean cache.
  local run_home="$tmpdir/.home"
  export HOME="$run_home"
  export XDG_CACHE_HOME="$run_home/.cache"
  export XDG_DATA_HOME="$run_home/.local/share"
  export XDG_CONFIG_HOME="$run_home/.config"
  mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME"

  # This repo is SCM-coupled DVC (.dvc/config has no `core.no_scm`), so `dvc
  # pull` requires a git repo at the root. The baked source has no .git, so
  # initialise a throwaway repo in the tmpdir to give DVC its SCM root. This is
  # uniform across the worktree and effect paths (git is a runtimeInput). No
  # commit or identity is needed: `dvc pull` only walks .dvc files and the
  # remote, it does not create git objects.
  echo ">> git init (throwaway SCM root for DVC)"
  git init -q

  echo ">> dvc pull (R2 freeze cache)"
  dvc pull --force --allow-missing

  echo ">> quartodoc build"
  quartodoc build --verbose --config docs/_quarto.yml

  echo ">> quartodoc interlinks"
  (cd docs && quartodoc interlinks)

  echo ">> quarto render"
  quarto render docs

  if [[ ! -d "docs/_site" ]]; then
    echo "error: quarto render did not produce docs/_site" >&2
    exit 1
  fi
  if [[ -z "$(ls -A docs/_site 2>/dev/null)" ]]; then
    echo "error: docs/_site is empty after quarto render" >&2
    exit 1
  fi
  echo ">> site built at $tmpdir/docs/_site"
}

if [[ "$mode" == "build" ]]; then
  echo "Building ${WORKER_NAME} docs site (no deploy)"
  echo "Commit: ${commit_short:-unknown} (${git_status})"
  echo "Full SHA: ${commit_sha:-unknown}"
  echo "Tag: ${commit_tag:-unknown}"
  echo ""
  build_site
  echo ""
  echo "Build complete (no deploy performed)"
  echo "  Site: $tmpdir/docs/_site"
  echo "  Commit: ${commit_short:-unknown} (${git_status})"
  echo "  Tag: ${commit_tag:-unknown}"
  exit 0
fi

# wrangler reads wrangler.jsonc relative to the tmpdir root; its
# assets.directory ("docs/_site") resolves against this cwd.
WRANGLER_CONFIG="$tmpdir/wrangler.jsonc"
[[ -f "$WRANGLER_CONFIG" ]] || {
  echo "error: baked source does not contain wrangler.jsonc at $WRANGLER_CONFIG" >&2
  exit 1
}
export WRANGLER_CONFIG

case "$mode" in
  preview)
    branch="${1:-${current_branch:-}}"
    if [[ -z "$branch" ]]; then
      echo "error: preview requires a <branch> argument" >&2
      echo "usage: deploy-sites preview <branch>" >&2
      exit 2
    fi

    safe_branch=$(echo "$branch" \
      | tr '/' '-' \
      | tr -c 'a-zA-Z0-9-' '-' \
      | sed 's/--*/-/g; s/^-//; s/-$//' \
      | cut -c1-40)

    version_message="[${branch}] ${commit_msg} (${commit_tag}, ${git_status})"

    echo "Deploying preview for ${WORKER_NAME} on branch: ${branch}"
    echo "Sanitized alias: b-${safe_branch}"
    echo "Commit: ${commit_short} (${git_status})"
    echo "Full SHA: ${commit_sha}"
    echo "Tag: ${commit_tag}"
    echo "Message: ${commit_msg}"
    echo ""

    build_site

    # Capture wrangler's machine-readable NDJSON event log via
    # WRANGLER_OUTPUT_FILE_PATH. wrangler 4.x does not accept --json on
    # `versions upload`; the NDJSON stream is the authoritative
    # machine-readable channel and carries the `version-upload` event with
    # `version_id`.
    wrangler_upload_ndjson="$tmpdir/wrangler-versions-upload.ndjson"
    wrangler_upload_stdout="$tmpdir/wrangler-versions-upload.stdout"
    wrangler_upload_stderr="$tmpdir/wrangler-versions-upload.stderr"
    : > "$wrangler_upload_ndjson"
    : > "$wrangler_upload_stdout"
    : > "$wrangler_upload_stderr"
    export WRANGLER_OUTPUT_FILE_PATH="$wrangler_upload_ndjson"

    printf '>> wrangler upload: node %s --config %s versions upload --preview-alias %s --tag %s --message %q\n' \
      "$WRANGLER" "$WRANGLER_CONFIG" "b-${safe_branch}" "$commit_tag" "$version_message" >&2

    set +e
    node "$WRANGLER" --config "$WRANGLER_CONFIG" versions upload \
        --preview-alias "b-${safe_branch}" \
        --tag "$commit_tag" \
        --message "$version_message" \
      > >(tee "$wrangler_upload_stdout") \
      2> >(tee "$wrangler_upload_stderr" >&2)
    wrangler_upload_rc=$?
    set -e

    unset WRANGLER_OUTPUT_FILE_PATH

    # Post-condition (a): extract a non-empty Worker Version ID. Primary:
    # NDJSON `version-upload` event. Fallback: stdout `Worker Version ID:` line.
    version_id=""
    if [[ -s "$wrangler_upload_ndjson" ]]; then
      version_id=$(
        jq -rs '
          map(select(type == "object" and (.type // "") == "version-upload"))
          | .[0].version_id // empty
        ' "$wrangler_upload_ndjson" 2>/dev/null || true
      )
    fi
    if [[ -z "$version_id" ]]; then
      version_id=$(
        grep -oE 'Worker Version ID: [a-f0-9-]+' "$wrangler_upload_stdout" 2>/dev/null \
          | awk '{print $NF}' \
          | head -1 || true
      )
    fi
    if [[ -z "$version_id" ]]; then
      set +e
      echo "" >&2
      echo "error: wrangler exited ${wrangler_upload_rc} but produced no Worker Version ID" >&2
      echo "  raw wrangler event log: $wrangler_upload_ndjson" >&2
      echo "  raw wrangler stdout:    $wrangler_upload_stdout" >&2
      echo "  raw wrangler stderr:    $wrangler_upload_stderr" >&2
      echo "  hints:" >&2
      echo "    - confirm CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are exported" >&2
      echo "    - if linux-x64 regression, confirm wrangler runs under real node, not bun" >&2
      echo "--- begin raw wrangler NDJSON ---" >&2
      cat "$wrangler_upload_ndjson" >&2 || true
      echo "--- end raw wrangler NDJSON ---" >&2
      echo "--- begin raw wrangler stdout ---" >&2
      cat "$wrangler_upload_stdout" >&2 || true
      echo "--- end raw wrangler stdout ---" >&2
      echo "--- begin raw wrangler stderr ---" >&2
      cat "$wrangler_upload_stderr" >&2 || true
      echo "--- end raw wrangler stderr ---" >&2
      set -e
      exit 1
    fi

    # Post-condition (b): cross-check via versions list that the upload landed
    # server-side with the expected commit tag annotation. The `| cat` pipe
    # ensures wrangler's stdout is delivered through a pipe-shaped fd before
    # redirection (observed: `wrangler … --json > file` intermittently produces
    # zero bytes whereas `wrangler … --json | cat > file` is reliable).
    wrangler_list_json="$tmpdir/wrangler-versions-list.json"
    node "$WRANGLER" --config "$WRANGLER_CONFIG" versions list --json \
      | cat > "$wrangler_list_json"

    matched_count=$(jq --arg tag "$commit_tag" \
      '[.[] | select(.annotations["workers/tag"] == $tag)] | length' \
      "$wrangler_list_json" 2>/dev/null || echo 0)
    if [[ "$matched_count" -lt 1 ]]; then
      echo "" >&2
      echo "error: uploaded version with tag ${commit_tag} not found in versions list" >&2
      echo "  raw versions list output: $wrangler_list_json" >&2
      exit 1
    fi

    echo ""
    echo "Version uploaded successfully"
    echo "  Worker Version ID: ${version_id}"
    echo "  Tag: ${commit_tag}"
    echo "  Full SHA: ${commit_sha}"
    echo "  Message: ${version_message}"
    echo "  Preview URL: https://b-${safe_branch}-${WORKER_NAME}.${WORKERS_SUBDOMAIN}.workers.dev"
    ;;

  production)
    echo "Deploying ${WORKER_NAME} to production from branch: ${current_branch}"
    echo "Current commit: ${commit_short}"
    echo "Full SHA: ${commit_sha}"
    echo "Looking for existing version with tag: ${commit_tag}"
    echo "Deployment message: ${deploy_msg}"
    echo ""

    build_site

    # Query for an existing version uploaded from this commit (via preview).
    wrangler_list_json="$tmpdir/wrangler-versions-list.json"
    node "$WRANGLER" --config "$WRANGLER_CONFIG" versions list --json \
      | cat > "$wrangler_list_json"

    existing_version=$(jq -r --arg tag "$commit_tag" \
      '.[] | select(.annotations["workers/tag"] == $tag) | .id' \
      "$wrangler_list_json" 2>/dev/null | head -1 || true)

    if [[ -n "$existing_version" ]]; then
      echo "found existing version: ${existing_version}"
      echo "  this version was already built and tested in preview"
      echo "  promoting to 100% production traffic..."
      echo ""

      deploy_ndjson="$tmpdir/wrangler-versions-deploy.ndjson"
      deploy_stdout="$tmpdir/wrangler-versions-deploy.stdout"
      : > "$deploy_ndjson"
      : > "$deploy_stdout"
      export WRANGLER_OUTPUT_FILE_PATH="$deploy_ndjson"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" versions deploy \
          "${existing_version}@100%" \
          --yes \
          --message "$deploy_msg" \
        | tee "$deploy_stdout"

      unset WRANGLER_OUTPUT_FILE_PATH

      deployment_id=""
      if [[ -s "$deploy_ndjson" ]]; then
        deployment_id=$(
          jq -rs '
            map(select(type == "object" and (.type // "") == "version-deploy"))
            | .[0].deployment_id // empty
          ' "$deploy_ndjson" 2>/dev/null || true
        )
      fi
      if [[ -z "$deployment_id" ]]; then
        deployment_id=$(
          grep -oiE '(Deployment ID|deployment_id)[[:space:]]*:[[:space:]]*[a-f0-9-]+' \
            "$deploy_stdout" 2>/dev/null \
            | awk '{print $NF}' \
            | head -1 || true
        )
      fi
      if [[ -z "$deployment_id" ]]; then
        echo "" >&2
        echo "error: wrangler exited 0 but produced no Deployment ID" >&2
        echo "  raw wrangler event log: $deploy_ndjson" >&2
        echo "  raw wrangler stdout:    $deploy_stdout" >&2
        exit 1
      fi

      deployments_list_json="$tmpdir/wrangler-deployments-list.json"
      node "$WRANGLER" --config "$WRANGLER_CONFIG" deployments list --json \
        | cat > "$deployments_list_json"

      found_count=$(jq --arg did "$deployment_id" --arg vid "$existing_version" \
        '[.[] | select(
           .id == $did
           or .deployment_id == $did
           or ((.versions // []) | map(.version_id // .id // "") | index($vid) != null)
         )] | length' \
        "$deployments_list_json" 2>/dev/null || echo 0)
      if [[ "$found_count" -lt 1 ]]; then
        echo "" >&2
        echo "error: deployment ${deployment_id} (version ${existing_version}) not found in deployments list" >&2
        echo "  raw deployments list output: $deployments_list_json" >&2
        exit 1
      fi

      echo ""
      echo "successfully promoted version ${existing_version} to production"
      echo "  Deployment ID: ${deployment_id}"
      echo "  tag: ${commit_tag}"
      echo "  full SHA: ${commit_sha}"
      echo "  deployed by: ${deploy_msg}"
      echo "  production URL: ${PRODUCTION_URL}"
    else
      echo "warning: no existing version found with tag: ${commit_tag}"
      echo "  falling back to direct deploy of the freshly built site..."
      echo ""

      deploy_ndjson="$tmpdir/wrangler-deploy.ndjson"
      deploy_stdout="$tmpdir/wrangler-deploy.stdout"
      : > "$deploy_ndjson"
      : > "$deploy_stdout"
      export WRANGLER_OUTPUT_FILE_PATH="$deploy_ndjson"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" deploy \
          --message "$deploy_msg" \
        | tee "$deploy_stdout"

      unset WRANGLER_OUTPUT_FILE_PATH

      deploy_version_id=""
      if [[ -s "$deploy_ndjson" ]]; then
        deploy_version_id=$(
          jq -rs '
            map(select(type == "object" and (.type // "") == "deploy"))
            | .[0].version_id // empty
          ' "$deploy_ndjson" 2>/dev/null || true
        )
      fi
      if [[ -z "$deploy_version_id" ]]; then
        deploy_version_id=$(
          grep -oiE '(Current Version ID|Worker Version ID|version_id)[[:space:]]*:[[:space:]]*[a-f0-9-]+' \
            "$deploy_stdout" 2>/dev/null \
            | awk '{print $NF}' \
            | head -1 || true
        )
      fi
      if [[ -z "$deploy_version_id" ]]; then
        echo "" >&2
        echo "error: wrangler exited 0 but produced no Deployment Version ID (fallback direct deploy)" >&2
        echo "  raw wrangler event log: $deploy_ndjson" >&2
        echo "  raw wrangler stdout:    $deploy_stdout" >&2
        exit 1
      fi

      deployments_list_json="$tmpdir/wrangler-deployments-list.json"
      node "$WRANGLER" --config "$WRANGLER_CONFIG" deployments list --json \
        | cat > "$deployments_list_json"

      found_count=$(jq --arg vid "$deploy_version_id" \
        '[.[] | select(
           .id == $vid
           or .deployment_id == $vid
           or ((.versions // []) | map(.version_id // .id // "") | index($vid) != null)
         )] | length' \
        "$deployments_list_json" 2>/dev/null || echo 0)
      if [[ "$found_count" -lt 1 ]]; then
        echo "" >&2
        echo "error: deployment for version ${deploy_version_id} not found in deployments list (fallback direct deploy)" >&2
        echo "  raw deployments list output: $deployments_list_json" >&2
        exit 1
      fi

      echo ""
      echo "deployed freshly built site directly to production"
      echo "  Deployment Version ID: ${deploy_version_id}"
      echo "  tag: ${commit_tag}"
      echo "  full SHA: ${commit_sha}"
      echo "  deployed by: ${deploy_msg}"
      echo "  production URL: ${PRODUCTION_URL}"
      echo "  warning: this version was not tested in preview first"
    fi
    ;;
esac
