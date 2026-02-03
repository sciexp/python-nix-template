# List all recipes
default:
    @just --list

# Contents
## CI/CD
## Conda
## Containers
## Docs
## Nix
## Python
## Release
## Rust
## Secrets
## Template

## CI/CD

# Build a category of nix flake outputs for CI matrix
[group('CI/CD')]
ci-build-category system category:
    bash scripts/ci/ci-build-category.sh {{system}} {{category}}

# Scan repository for hardcoded secrets
[group('CI/CD')]
scan-secrets:
    gitleaks detect --verbose --redact

# Scan staged files for hardcoded secrets (pre-commit)
[group('CI/CD')]
scan-staged:
    gitleaks protect --staged --verbose --redact

# Set gcloud context
[group('CI/CD')]
gcloud-context:
    gcloud config configurations activate "$GCP_PROJECT_NAME"

# Update github vars for repo from environment variables
[group('CI/CD')]
ghvars repo="sciexp/python-nix-template":
  @echo "vars before updates:"
  @echo
  PAGER=cat gh variable list --repo={{ repo }}
  @echo
  gh variable set CACHIX_CACHE_NAME --repo={{ repo }} --body="$CACHIX_CACHE_NAME"
  gh variable set FAST_FORWARD_ACTOR --repo={{ repo }} --body="$FAST_FORWARD_ACTOR"
  @echo
  @echo "vars after updates (wait 3 seconds for github to update):"
  sleep 3
  @echo
  PAGER=cat gh variable list --repo={{ repo }}

# Update github secrets for repo from environment variables
[group('CI/CD')]
ghsecrets repo="sciexp/python-nix-template":
  @echo "secrets before updates:"
  @echo
  PAGER=cat gh secret list --repo={{ repo }}
  @echo
  sops exec-env vars/shared.yaml '\
  gh secret set CACHIX_AUTH_TOKEN --repo={{ repo }} --body="$CACHIX_AUTH_TOKEN" && \
  gh secret set CODECOV_TOKEN --repo={{ repo }} --body="$CODECOV_TOKEN" && \
  gh secret set FAST_FORWARD_PAT --repo={{ repo }} --body="$FAST_FORWARD_PAT" && \
  gh secret set GITGUARDIAN_API_KEY --repo={{ repo }} --body="$GITGUARDIAN_API_KEY" && \
  gh secret set UV_PUBLISH_TOKEN --repo={{ repo }} --body="$UV_PUBLISH_TOKEN" && \
  gh secret set CLOUDFLARE_ACCOUNT_ID --repo={{ repo }} --body="$CLOUDFLARE_ACCOUNT_ID" && \
  gh secret set CLOUDFLARE_API_TOKEN --repo={{ repo }} --body="$CLOUDFLARE_API_TOKEN"'
  @echo
  @echo "secrets after updates (wait 3 seconds for github to update):"
  sleep 3
  @echo
  PAGER=cat gh secret list --repo={{ repo }}

# Run pre-commit hooks (see pre-commit.nix and note the yaml is git-ignored)
[group('CI/CD')]
pre-commit:
  pre-commit run --all-files

# List available workflows and associated jobs using act
[group('CI/CD')]
list-workflows:
  @act -l

# Test build-docs job locally with act
[group('CI/CD')]
test-docs-build branch=`git branch --show-current`:
  @echo "Testing docs build job locally (branch: {{branch}})..."
  @sops exec-env vars/shared.yaml 'act workflow_dispatch \
    -W .github/workflows/deploy-docs.yaml \
    -j build-docs \
    -s CI_AGE_KEY -s CACHIX_AUTH_TOKEN \
    -s GITHUB_TOKEN="$(gh auth token)" \
    --var CACHIX_CACHE_NAME \
    --input debug_enabled=false \
    --input branch={{branch}}'

# Test full deploy-docs workflow locally with act
[group('CI/CD')]
test-docs-deploy branch=`git branch --show-current`:
  @echo "Testing full docs deployment workflow locally (branch: {{branch}})..."
  @echo "Note: Cloudflare deployment may not work in local environment"
  @sops exec-env vars/shared.yaml 'act workflow_dispatch \
    -W .github/workflows/deploy-docs.yaml \
    -s CI_AGE_KEY -s CACHIX_AUTH_TOKEN \
    -s CLOUDFLARE_API_TOKEN -s CLOUDFLARE_ACCOUNT_ID \
    -s GITHUB_TOKEN="$(gh auth token)" \
    --var CACHIX_CACHE_NAME \
    --input debug_enabled=false \
    --input branch={{branch}}'

# Trigger docs build job remotely on GitHub (requires workflow on main)
[group('CI/CD')]
gh-docs-build branch=`git branch --show-current` debug="false":
  #!/usr/bin/env bash
  echo "Triggering docs build workflow on GitHub (branch: {{branch}}, debug: {{debug}})..."
  echo "Note: This requires deploy-docs.yaml to exist on the default branch"
  gh workflow run deploy-docs.yaml \
    --repo ${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)} \
    --ref "{{branch}}" \
    --field debug_enabled="{{debug}}" \
    --field branch="{{branch}}"
  echo "Check workflow status with: just gh-docs-status"

# View recent workflow runs status
[group('CI/CD')]
gh-workflow-status workflow="deploy-docs.yaml" branch=`git branch --show-current` limit="5":
  #!/usr/bin/env bash
  echo "Recent docs workflow runs:"
  gh run list \
    --workflow={{workflow}} \
    --branch={{branch}} \
    --limit={{limit}} \
    --repo ${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}

# Watch a specific docs workflow run
[group('CI/CD')]
gh-docs-watch run_id="":
  #!/usr/bin/env bash
  if [ -z "{{run_id}}" ]; then
    echo "Getting latest workflow run..."
    RUN_ID=$(gh run list --workflow=deploy-docs.yaml --limit=1 --json databaseId -q '.[0].databaseId' \
      --repo ${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)})
    echo "Watching run: $RUN_ID"
    gh run watch $RUN_ID --repo ${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
  else
    gh run watch {{run_id}} --repo ${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
  fi

# View logs for a specific docs workflow run
[group('CI/CD')]
gh-docs-logs run_id="" job="":
  #!/usr/bin/env bash
  REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
  if [ -z "{{run_id}}" ]; then
    echo "Getting latest workflow run..."
    RUN_ID=$(gh run list --workflow=deploy-docs.yaml --limit=1 --json databaseId -q '.[0].databaseId' --repo $REPO)
  else
    RUN_ID="{{run_id}}"
  fi

  if [ -z "{{job}}" ]; then
    echo "Available jobs in run $RUN_ID:"
    gh run view $RUN_ID --repo $REPO --json jobs -q '.jobs[].name'
    echo ""
    echo "Viewing full run logs..."
    gh run view $RUN_ID --log --repo $REPO
  else
    echo "Viewing logs for job '{{job}}' in run $RUN_ID..."
    gh run view $RUN_ID --log --repo $REPO | grep -A 100 "{{job}}"
  fi

# Re-run a failed docs workflow
[group('CI/CD')]
gh-docs-rerun run_id="" failed_only="true":
  #!/usr/bin/env bash
  REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
  if [ -z "{{run_id}}" ]; then
    echo "Getting latest workflow run..."
    RUN_ID=$(gh run list --workflow=deploy-docs.yaml --limit=1 --json databaseId -q '.[0].databaseId' --repo $REPO)
  else
    RUN_ID="{{run_id}}"
  fi

  if [ "{{failed_only}}" = "true" ]; then
    echo "Re-running failed jobs in run $RUN_ID..."
    gh run rerun --failed $RUN_ID --repo $REPO
  else
    echo "Re-running all jobs in run $RUN_ID..."
    gh run rerun $RUN_ID --repo $REPO
  fi

# Cancel a running docs workflow
[group('CI/CD')]
gh-docs-cancel run_id="":
  #!/usr/bin/env bash
  REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
  if [ -z "{{run_id}}" ]; then
    echo "Getting latest workflow run..."
    RUN_ID=$(gh run list --workflow=deploy-docs.yaml --limit=1 --json databaseId -q '.[0].databaseId' --repo $REPO)
    echo "Canceling run: $RUN_ID"
    gh run cancel $RUN_ID --repo $REPO
  else
    gh run cancel {{run_id}} --repo $REPO
  fi

# Discover packages as JSON array for CI matrix
[group('CI/CD')]
list-packages-json:
    @ls -d packages/*/pyproject.toml | while read f; do \
      d=$(dirname "$f"); \
      n=$(basename "$d"); \
      printf '{"name":"%s","path":"%s"}\n' "$n" "$d"; \
    done | jq -sc '.'

# Sync dependencies for a package via uv
[group('CI/CD')]
ci-sync package:
    cd packages/{{package}} && uv sync --all-extras --dev

# Run linting for a package
[group('CI/CD')]
ci-lint package:
    cd packages/{{package}} && uv run ruff check src/

# Run tests for a package
[group('CI/CD')]
ci-test package:
    cd packages/{{package}} && uv run pytest

# Run type checking for a package
[group('CI/CD')]
ci-typecheck package:
    cd packages/{{package}} && uv run pyright src/

# Run all checks for a package (lint, typecheck, test)
[group('CI/CD')]
ci-check package: (ci-lint package) (ci-typecheck package) (ci-test package)
    @printf "\nAll CI checks passed for {{package}}.\n"

## Conda

# Package commands (conda)
[group('conda')]
conda-build package="python-nix-template":
    pixi build --manifest-path=packages/{{package}}/pyproject.toml

# Create and sync conda environment with pixi
[group('conda')]
conda-env package="python-nix-template":
    pixi install --manifest-path=packages/{{package}}/pyproject.toml
    @echo "Conda environment is ready. Activate it with 'pixi shell'"

# Update pixi lockfile
[group('conda')]
pixi-lock package="python-nix-template":
    pixi list --manifest-path=packages/{{package}}/pyproject.toml
    pixi tree --manifest-path=packages/{{package}}/pyproject.toml

# Update conda environment
[group('conda')]
conda-lock package="python-nix-template":
    pixi project export conda-explicit-spec packages/{{package}}/conda/ --manifest-path=packages/{{package}}/pyproject.toml --ignore-pypi-errors

# Run tests in conda environment with pixi
[group('conda')]
conda-test package="python-nix-template":
    pixi run -e test --manifest-path=packages/{{package}}/pyproject.toml test

# Run linting in conda environment with pixi
[group('conda')]
conda-lint package="python-nix-template":
    pixi run -e lint --manifest-path=packages/{{package}}/pyproject.toml lint-check

# Run linting and fix errors in conda environment with pixi
[group('conda')]
conda-lint-fix package="python-nix-template":
    pixi run -e lint --manifest-path=packages/{{package}}/pyproject.toml lint

# Run type checking in conda environment with pixi
[group('conda')]
conda-type package="python-nix-template":
    pixi run -e types --manifest-path=packages/{{package}}/pyproject.toml types

# Run all checks in conda environment (lint, type, test)
[group('conda')]
conda-check package="python-nix-template": (conda-lint package) (conda-type package) (conda-test package)
    @printf "\n\033[92mAll conda checks passed!\033[0m\n"

## Containers

# Build production container image
[group('containers')]
container-build-production CONTAINER="pnt-cli":
    nix build ".#{{CONTAINER}}ProductionImage" -L

# Load production container to local Docker daemon
[group('containers')]
container-load-production CONTAINER="pnt-cli":
    nix run ".#{{CONTAINER}}ProductionImage.copyToDockerDaemon"

# Push production container manifest (requires registry auth)
[group('containers')]
container-push-production CONTAINER="pnt-cli" VERSION="0.0.0" +TAGS="":
    VERSION={{VERSION}} TAGS={{TAGS}} nix run --impure ".#{{CONTAINER}}Manifest" -L

# Build dev container image
[group('containers')]
container-build-dev:
    nix build .#devcontainerImage -L

# Run dev container with port 8888 exposed
[group('containers')]
container-run-dev:
    docker load < $(nix build .#devcontainerImage --no-link --print-out-paths)
    docker run -it --rm -p 8888:8888 python-nix-template-dev:latest

# Build production-deps container image
[group('containers')]
container-build:
    nix build .#containerImage -L

# Run production-deps container with port 8888 exposed
[group('containers')]
container-run:
    docker load < $(nix build .#containerImage --no-link --print-out-paths)
    docker run -it --rm -p 8888:8888 python-nix-template:latest

# Push dev container manifests (requires registry auth)
[group('containers')]
container-push-dev VERSION="0.0.0" +TAGS="":
    VERSION={{VERSION}} TAGS={{TAGS}} nix run --impure ".#python-nix-templateManifest" -L
    VERSION={{VERSION}} TAGS={{TAGS}} nix run --impure ".#python-nix-template-devManifest" -L

# Display container CI matrix
[group('containers')]
container-matrix:
    nix eval .#containerMatrix --json | jq .

## Nix

# Enter the Nix development shell
[group('nix')]
dev:
    nix develop

# Validate the Nix flake configuration for the current system
[group('nix')]
flake-check:
    #!/usr/bin/env bash
    set -euo pipefail
    SYSTEM=$(nix eval --impure --raw --expr builtins.currentSystem)
    echo "Validating flake for $SYSTEM..."
    nix flake metadata
    echo "Evaluating checks for $SYSTEM..."
    nix eval ".#checks.$SYSTEM" --apply builtins.attrNames --json
    echo "Building checks for $SYSTEM..."
    for check in $(nix eval ".#checks.$SYSTEM" --apply builtins.attrNames --json | jq -r '.[]'); do
      echo "Building check: $check"
      nix build ".#checks.$SYSTEM.$check" --no-link -L
    done

# Update all flake inputs to their latest versions
[group('nix')]
flake-update:
    nix flake update

# Run CI checks locally with `om ci`
[group('nix')]
ci:
    om ci

## Python

# Run tests for a package
[group('python')]
test package="python-nix-template":
    cd packages/{{package}} && pytest

# Run tests for all packages
[group('python')]
test-all:
    #!/usr/bin/env bash
    set -euo pipefail
    for dir in packages/*/; do
      pkg=$(basename "$dir")
      echo "Testing $pkg..."
      (cd "$dir" && pytest)
    done

# Build a package with uv
[group('python')]
uv-build package="python-nix-template":
    cd packages/{{package}} && uv build

# Sync a package environment with uv
[group('python')]
uv-sync package="python-nix-template":
    cd packages/{{package}} && uv sync

# Update lockfile for a package
[group('python')]
uv-lock package="python-nix-template":
    cd packages/{{package}} && uv lock

# Run linting for a package
[group('python')]
lint package="python-nix-template":
    cd packages/{{package}} && ruff check src/

# Run linting for all packages
[group('python')]
lint-all:
    ruff check packages/

# Run linting and fix errors for a package
[group('python')]
lint-fix package="python-nix-template":
    cd packages/{{package}} && ruff check --fix src/

# Run type checking for a package
[group('python')]
type package="python-nix-template":
    cd packages/{{package}} && pyright src/

# Run all checks for a package (lint, type, test)
[group('python')]
check package="python-nix-template": (lint package) (type package) (test package)
    @printf "\nAll Python checks passed for {{package}}.\n"

## Rust

# Build Rust crates for a package
[group('rust')]
cargo-build package="pnt-cli":
    cd packages/{{package}}/crates && cargo build

# Run Rust tests via cargo test
[group('rust')]
cargo-test package="pnt-cli":
    cd packages/{{package}}/crates && cargo test

# Run Rust clippy lints
[group('rust')]
cargo-clippy package="pnt-cli":
    cd packages/{{package}}/crates && cargo clippy --all-targets -- --deny warnings

# Run Rust tests via cargo-nextest
[group('rust')]
cargo-nextest package="pnt-cli":
    cd packages/{{package}}/crates && cargo nextest run --no-tests=pass

# Run all Rust checks (clippy, test)
[group('rust')]
cargo-check package="pnt-cli": (cargo-clippy package) (cargo-test package)
    @printf "\nAll Rust checks passed for {{package}}.\n"

## Secrets

# Show existing secrets using sops
[group('secrets')]
show-secrets:
  @echo "=== Shared secrets (vars/shared.yaml) ==="
  @sops -d vars/shared.yaml
  @echo

# Edit shared secrets file
[group('secrets')]
edit-secrets:
  @sops vars/shared.yaml

# Create a new sops encrypted file
[group('secrets')]
new-secret file:
  @sops {{ file }}

# Export unique secrets to dotenv format using sops
[group('secrets')]
export-secrets:
  @echo "# Exported from sops secrets" > .secrets.env
  @sops -d vars/shared.yaml | grep -E '^[A-Z_]+:' | sed 's/: /=/' >> .secrets.env
  @sort -u .secrets.env -o .secrets.env

# Run command with all shared secrets as environment variables
[group('secrets')]
run-with-secrets +command:
  @sops exec-env vars/shared.yaml '{{ command }}'

# Check secrets are available in sops environment
[group('secrets')]
check-secrets:
  @printf "Check sops environment for secrets\n\n"
  @sops exec-env vars/shared.yaml 'env | grep -E "GITHUB|CACHIX|CLOUDFLARE" | sed "s/=.*$/=***REDACTED***/"'

# Show specific secret value from shared secrets
[group('secrets')]
get-secret key:
  @sops -d vars/shared.yaml | grep "^{{ key }}:" | cut -d' ' -f2-

# Validate all sops encrypted files can be decrypted
[group('secrets')]
validate-secrets:
  @echo "Validating sops encrypted files..."
  @for file in $(find vars -name "*.yaml"); do \
    echo "Testing: $file"; \
    sops -d "$file" > /dev/null && echo "  ✅ Valid" || echo "  ❌ Failed"; \
  done

# Initialize sops age key for new developers
[group('secrets')]
sops-init:
  @echo "Checking sops configuration..."
  @if [ ! -f ~/.config/sops/age/keys.txt ]; then \
    echo "Generating age key..."; \
    mkdir -p ~/.config/sops/age; \
    age-keygen -o ~/.config/sops/age/keys.txt; \
    echo ""; \
    echo "✅ Age key generated. Add this public key to .sops.yaml:"; \
    grep "public key:" ~/.config/sops/age/keys.txt; \
  else \
    echo "✅ Age key already exists"; \
    grep "public key:" ~/.config/sops/age/keys.txt; \
  fi

# Add existing age key to local configuration
[group('secrets')]
sops-add-key:
  #!/usr/bin/env bash
  set -euo pipefail

  # Ensure keys.txt exists and has proper permissions
  mkdir -p ~/.config/sops/age
  touch ~/.config/sops/age/keys.txt
  chmod 600 ~/.config/sops/age/keys.txt

  # Prompt for key description
  printf "Enter age key description (e.g., 'project [dev|ci|admin]'): "
  read -r key_description
  [[ -z "${key_description}" ]] && { echo "❌ Description cannot be empty"; exit 1; }

  # Prompt for public key
  printf "Enter age public key (age1...): "
  read -r public_key
  if [[ ! "${public_key}" =~ ^age1[a-z0-9]{58}$ ]]; then
    echo "❌ Invalid age public key format (must start with 'age1' and be 62 chars)"
    exit 1
  fi

  # Prompt for private key (hidden input)
  printf "Enter age private key (AGE-SECRET-KEY-...): "
  read -rs private_key
  echo  # New line after hidden input
  if [[ ! "${private_key}" =~ ^AGE-SECRET-KEY-[A-Z0-9]{59}$ ]]; then
    echo "❌ Invalid age private key format"
    exit 1
  fi

  # Check if key already exists
  if grep -q "${private_key}" ~/.config/sops/age/keys.txt 2>/dev/null; then
    echo "⚠️  This private key already exists in keys.txt"
    exit 1
  fi

  # Append to keys.txt with proper formatting
  {
    echo ""
    echo "# ${key_description}"
    echo "# public key: ${public_key}"
    echo "${private_key}"
  } >> ~/.config/sops/age/keys.txt

  echo "✅ Age key added successfully for: ${key_description}"
  echo "   Public key: ${public_key}"

# Add or update a secret non-interactively
[group('secrets')]
set-secret secret_name secret_value:
  @sops set vars/shared.yaml '["{{ secret_name }}"]' '"{{ secret_value }}"'
  @echo "✅ {{ secret_name }} has been set/updated"

# Rotate a specific secret interactively
[group('secrets')]
rotate-secret secret_name:
  @echo "Rotating {{ secret_name }}..."
  @echo "Enter new value for {{ secret_name }}:"
  @read -s NEW_VALUE && \
    sops set vars/shared.yaml '["{{ secret_name }}"]' "\"$NEW_VALUE\"" && \
    echo "✅ {{ secret_name }} rotated successfully"

# Update keys for existing secrets files after adding new recipients
[group('secrets')]
updatekeys:
  @for file in $(find vars -name "*.*"); do \
    echo "Updating keys for: $file"; \
    sops updatekeys "$file"; \
  done
  @echo "✅ Keys updated for all secrets files"

## Template

# Initialize new project from template
[group('template')]
template-init:
    echo "Use: nix --accept-flake-config run github:juspay/omnix/v1.3.0 -- init github:sciexp/python-nix-template -o new-python-project"

# Verify template functionality by creating and checking a test project
[group('template')]
template-verify:
    om init -t .#default ./tmp-verify-template
    cd ./tmp-verify-template && nix flake check
    rm -rf ./tmp-verify-template

# GCP service account for DVC

# Enable Google Drive API in GCP project
[group('secrets')]
gcp-enable-drive-api:
  @echo "Enabling Google Drive API..."
  @sops exec-env vars/shared.yaml 'gcloud services enable drive.googleapis.com --project="$GCP_PROJECT_ID"'
  @echo "✅ Google Drive API enabled"
  @echo "Verifying..."
  @sops exec-env vars/shared.yaml 'gcloud services list --enabled --project="$GCP_PROJECT_ID" | grep drive || echo "⚠️  Drive API not found in enabled services"'

# Create GCP service account for DVC access (run once)
[group('secrets')]
gcp-sa-create:
  @echo "Creating GCP service account for DVC..."
  @sops exec-env vars/shared.yaml 'gcloud iam service-accounts create dvc-sa \
    --display-name="DVC Service Account" \
    --project="$GCP_PROJECT_ID"'
  @echo "✅ Service account created: dvc-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com"

# Grant Storage Object User role for GCS access
[group('secrets')]
gcp-sa-storage-user:
  @echo "Granting Storage Object User role for GCS access..."
  @sops exec-env vars/shared.yaml 'gcloud projects add-iam-policy-binding "$GCP_PROJECT_ID" \
    --member="serviceAccount:dvc-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectUser"'
  @echo "✅ Storage Object User role granted"
  @echo ""
  @echo "⚠️  IMPORTANT: Add dvc-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com as an editor to your relevant folder or bucket."

# Download service account key (for key rotation)
[group('secrets')]
gcp-sa-key-download:
  @echo "Downloading service account key..."
  @sops exec-env vars/shared.yaml 'gcloud iam service-accounts keys create vars/dvc-sa.tmp.json \
      --iam-account=dvc-sa@"$GCP_PROJECT_ID".iam.gserviceaccount.com \
      --project="$GCP_PROJECT_ID"'

# Encrypt service account key with sops
[group('secrets')]
gcp-sa-key-encrypt:
  @echo "Encrypting service account key with sops..."
  @sops -e vars/dvc-sa.tmp.json > vars/dvc-sa.json
  @rm -f vars/dvc-sa.tmp.json
  @echo "✅ Service account key encrypted and saved to vars/dvc-sa.json"

# Helper: Run any DVC command with decrypted service account
[group('secrets')]
dvc-run +command:
  #!/usr/bin/env bash
  set -euo pipefail
  sops -d vars/dvc-sa.json > .dvc-sa.json
  trap 'rm -f .dvc-sa.json' EXIT
  uvx --with dvc-gdrive,dvc-gs dvc {{command}}

# List existing service account keys (for auditing)
[group('secrets')]
gcp-sa-keys-list:
  @sops exec-env vars/shared.yaml 'gcloud iam service-accounts keys list \
    --iam-account=dvc-sa@"$GCP_PROJECT_ID".iam.gserviceaccount.com \
    --project="$GCP_PROJECT_ID"'

# Rotate service account key
[group('secrets')]
gcp-sa-key-rotate:
  @echo "Rotating service account key..."
  @echo "Step 1: Creating new key..."
  @just gcp-sa-key-download
  @echo ""
  @echo "Step 2: List existing keys (note the KEY_ID to delete):"
  @just gcp-sa-keys-list
  @echo ""
  @echo "Step 3: After verifying new key works, delete old key with:"
  @echo "  just gcp-sa-key-delete KEY_ID"

# Delete a specific service account key
[group('secrets')]
gcp-sa-key-delete key_id:
  @sops exec-env vars/shared.yaml 'gcloud iam service-accounts keys delete {{key_id}} \
    --iam-account=dvc-sa@"$GCP_PROJECT_ID".iam.gserviceaccount.com \
    --project="$GCP_PROJECT_ID" --quiet'
  @echo "✅ Key {{key_id}} deleted"

## Release

# Release testing with yarn
[group('release')]
test-release:
    yarn test-release

# Test release as if on main branch
[group('release')]
test-release-as-main:
    yarn test-release:main

# Test release with explicit branch override
[group('release')]
test-release-on-current-branch:
    yarn test-release:current

# Test release directly on release branch
[group('release')]
test-release-direct:
    yarn test-release:direct

# Test package release
[group('release')]
test-package-release package-name="python-nix-template" branch="main":
    yarn workspace {{package-name}} test-release -b {{branch}}

# Preview release version for a package (dry-run semantic-release)
[group('release')]
preview-version base-branch package-path:
    #!/usr/bin/env bash
    set -euo pipefail
    PACKAGE_NAME=$(basename "{{package-path}}")
    yarn workspace "$PACKAGE_NAME" install
    unset GITHUB_ACTIONS
    yarn workspace "$PACKAGE_NAME" test-release -b "{{base-branch}}"

# Run semantic-release for a package
[group('release')]
release-package package-name dry-run="false":
    #!/usr/bin/env bash
    set -euo pipefail
    yarn workspace {{package-name}} install
    if [ "{{dry-run}}" = "true" ]; then
        unset GITHUB_ACTIONS
        yarn workspace {{package-name}} test-release -b main
    else
        yarn workspace {{package-name}} release
    fi

## Docs

# Add quartodoc extension
[group('docs')]
docs-extensions:
    (cd docs && quarto add machow/quartodoc)

# Build quartodoc API reference
[group('docs')]
docs-reference:
    quartodoc build --verbose --config docs/_quarto.yml
    (cd docs && quartodoc interlinks)

# Build docs
[group('docs')]
docs-build: data-sync docs-reference
    quarto render docs

# Preview docs locally
[group('docs')]
docs-local:
    quarto preview docs --no-browser --port 7780

# Check docs
[group('docs')]
docs-check:
    quarto check docs

# Run local docs deployment
[group('docs')]
docs-dev: docs-build
  yarn dlx wrangler dev

# Deploy docs
[group('docs')]
docs-deploy: docs-build
  yarn dlx wrangler deploy

# Preview docs on remote
[group('docs')]
docs-preview-deploy: data-sync docs-build
  yarn dlx wrangler versions upload --preview-alias b-$(git branch --show-current)

# Sync data from drive (using encrypted service account)
[group('docs')]
data-sync:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Decrypting service account for DVC..."
  sops -d vars/dvc-sa.json > .dvc-sa.json
  trap 'rm -f .dvc-sa.json' EXIT
  uvx --with dvc-gdrive,dvc-gs dvc pull --force --allow-missing
  echo "✅ DVC data synced"

# docs-sync: docs-build
# Sync docs freeze data to DVC remote
[group('docs')]
docs-sync:
  #!/usr/bin/env bash
  set -euo pipefail
  echo "Syncing docs freeze data to DVC remote..."
  sops -d vars/dvc-sa.json > .dvc-sa.json
  chmod 600 .dvc-sa.json
  trap 'rm -f .dvc-sa.json' EXIT
  uvx --with dvc-gdrive,dvc-gs dvc status
  uvx --with dvc-gdrive,dvc-gs dvc add docs/_freeze -v
  uvx --with dvc-gdrive,dvc-gs dvc push
  uvx --with dvc-gdrive,dvc-gs dvc status
  git status
  printf "\n\033[92mCommit relevant updates to the docs/_freeze.dvc lock file to the git repo\033[0m\n"


