# pnt deploy-sites Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Build and deploy the pnt quarto docs site reproducibly via nix, and migrate the DVC backing store from GCS/Drive to Cloudflare R2.

**Architecture:** A single `perSystem.apps.deploy-sites` `writeShellApplication` into whose closure nix bakes the source fileset (`.dvc/config`, `docs/`, `wrangler.jsonc`) plus the toolchain; at runtime the app copies the baked source to a tmpdir, runs `dvc pull` then `quartodoc build`/`interlinks` then `quarto render docs` to produce `_site`, then deploys that build to Cloudflare Workers under real node (preview or production). There is no separate `pnt-docs` derivation: the app builds and deploys in one imperative step. CI invokes the app (which builds and deploys) with sops-supplied secrets. DVC is retained but repointed at an s3-compatible R2 remote.

**Tech Stack:** nix/flake-parts, uv2nix, quarto + quartodoc, Cloudflare Workers + wrangler (node), Cloudflare R2 (s3) + DVC, sops, GitHub Actions, just.

---

## Task 1: deploy-sites build+deploy app

- [ ] **Step 1:** Create `modules/apps/deploy-sites.nix` defining `perSystem.apps.deploy-sites` as a `writeShellApplication` that bakes the `lib.fileset` source (`.dvc/config`, `docs/`, `wrangler.jsonc`) plus the toolchain `runtimeInputs`: `quarto` (with `QUARTO_PYTHON` pointed at the uv2nix docs venv), the python env providing `quartodoc` + `pnt_core`, `dvc` + `dvc-s3`, `nodejs` + `wrangler`, `jq`, `git`, `coreutils`.
- [ ] **Step 2:** Create `modules/apps/deploy-sites.sh` with `preview <branch>` / `production` subcommands: copy the baked source to a tmpdir -> `dvc pull --force --allow-missing` (R2; `AWS_*` from env) -> `quartodoc build` + `quartodoc interlinks` -> `quarto render docs` to produce `_site` (reusing the quarto `_freeze` cache, never executing notebooks) -> then the `node`-wrangler deploy. Preview = `node "$WRANGLER" versions upload --preview-alias b-<safe-branch> --tag <sha12>`; production = promote the version whose `workers/tag` annotation matches the sha12 (`versions list --json` match -> `versions deploy <id>@100%`), else fresh-build fallback `node "$WRANGLER" deploy`. Derive git metadata env-first (`GIT_REV_SHORT12`) with a git fallback; read credentials from inherited `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` (deploy) and `AWS_*` (R2 dvc pull) env; run wrangler under real `node`, not bun.
- [ ] **Step 3:** Verify `nix build .#deploy-sites` builds the app and `nix run .#deploy-sites -- preview <branch>` builds the site and uploads a working preview from a clean checkout (under `sops exec-env`). Commit.

## Task 2: GHA rewire

- [ ] **Step 1:** Edit `.github/workflows/deploy-docs.yaml` to deploy via `nix run .#deploy-sites` (the app now builds AND deploys; there is no `.#pnt-docs` payload to build), keeping the sops step that supplies the Cloudflare env.
- [ ] **Step 2:** Keep the `docs-deploy-{preview,production}` justfile recipes as thin wrappers calling `nix run .#deploy-sites`.
- [ ] **Step 3:** Verify a `workflow_dispatch` run produces a live preview URL. Commit.

## Task 3: DVC GCS to R2

- [ ] **Step 1:** Provision an R2 bucket and a dashboard-minted R2 S3 HMAC keypair via wrangler/MCP/dashboard (no terranix).
- [ ] **Step 2:** Rewrite `.dvc/config` to an s3 remote: `url=s3://<bucket>/projects/python-nix-template/cas`, `endpointurl=https://<accountid>.r2.cloudflarestorage.com`, `region=auto`.
- [ ] **Step 3:** Add `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (the R2 keypair) to sops `vars/shared.yaml`.
- [ ] **Step 4:** Swap the justfile DVC recipes from `uvx --with dvc-gdrive,dvc-gs` to `--with dvc-s3`; drop the `sops -d vars/dvc-sa.json` GCP-SA dance; retire `vars/dvc-sa.json` and the gdrive remote.
- [ ] **Step 5:** Verify `just data-sync` pulls from R2 cleanly, a push round-trips, and the docs build is still green. Commit.

## Deferred (do not implement)

The buildbot-nix/hercules-ci effect that runs the `deploy-sites` build+deploy app as a CI effect — invoking it via an eval-time store path so the build happens in-effect — is out of scope for this change (blocked by CAM-23 and vanixiets PR-A). It is documented in design.md (Non-Goals), brainstorm.md, and tasks.md §4; no Linear issue is created for it now.
