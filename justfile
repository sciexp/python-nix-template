# List all recipes
default:
    @just --list

# Contents
## CI/CD
## Conda package
## Docs
## Nix
## Python package
## Release
## Secrets
## Template

## CI/CD

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

## Conda package

# Package commands (conda)
[group('conda package')]
conda-build package="python-nix-template":
    pixi build --manifest-path=packages/{{package}}/pyproject.toml

# Create and sync conda environment with pixi
[group('conda package')]
conda-env package="python-nix-template":
    pixi install --manifest-path=packages/{{package}}/pyproject.toml
    @echo "Conda environment is ready. Activate it with 'pixi shell'"

# Update pixi lockfile
[group('conda package')]
pixi-lock package="python-nix-template":
    pixi list --manifest-path=packages/{{package}}/pyproject.toml
    pixi tree --manifest-path=packages/{{package}}/pyproject.toml

# Update conda environment
[group('conda package')]
conda-lock package="python-nix-template":
    pixi project export conda-explicit-spec packages/{{package}}/conda/ --manifest-path=packages/{{package}}/pyproject.toml --ignore-pypi-errors

# Run tests in conda environment with pixi
[group('conda package')]
conda-test package="python-nix-template":
    pixi run -e test --manifest-path=packages/{{package}}/pyproject.toml pytest

# Run linting in conda environment with pixi
[group('conda package')]
conda-lint package="python-nix-template":
    pixi run -e lint --manifest-path=packages/{{package}}/pyproject.toml ruff check src/

# Run linting and fix errors in conda environment with pixi
[group('conda package')]
conda-lint-fix package="python-nix-template":
    pixi run -e lint --manifest-path=packages/{{package}}/pyproject.toml ruff check --fix src/

# Run type checking in conda environment with pixi
[group('conda package')]
conda-type package="python-nix-template":
    pixi run -e types --manifest-path=packages/{{package}}/pyproject.toml pyright src/

# Run all checks in conda environment (lint, type, test)
[group('conda package')]
conda-check package="python-nix-template": (conda-lint package) (conda-type package) (conda-test package)
    @printf "\n\033[92mAll conda checks passed!\033[0m\n"

## Nix

# Enter the Nix development shell
[group('nix')]
dev: 
    nix develop

# Validate the Nix flake configuration
[group('nix')]
flake-check:
    nix flake check

# Update all flake inputs to their latest versions
[group('nix')]
flake-update:
    nix flake update

# Run CI checks locally with `om ci`
[group('nix')]
ci:
    om ci

# Build development container image
[group('nix')]
container-build-dev:
    nix build .#devcontainerImage

# Run development container with port 8888 exposed
[group('nix')]
container-run-dev:
    docker load < $(nix build .#devcontainerImage --print-out-paths)
    docker run -it --rm -p 8888:8888 mypackage-dev:latest

# Build production container image
[group('nix')]
container-build:
    nix build .#containerImage

# Run production container with port 8888 exposed
[group('nix')]
container-run:
    docker load < $(nix build .#containerImage --print-out-paths)
    docker run -it --rm -p 8888:8888 mypackage:latest

## Python package

# Package commands
[group('python package')]
uv-build: _ensure-venv
    uv build

# Sync and enter uv virtual environment
[group('python package')]
venv: _ensure-venv
    uv sync
    @echo "Virtual environment is ready. Activate it with 'source .venv/bin/activate'"

# Update lockfile from pyproject.toml
[group('python package')]
uv-lock: _ensure-venv
    uv lock

# Run tests
[group('python package')]
test:
    pytest

# Run tests in uv virtual environment
[group('python package')]
uv-test: _ensure-venv
    uv run pytest

# Run linting
[group('python package')]
lint:
    ruff check src/

# Run linting in uv virtual environment
[group('python package')]
uv-lint: _ensure-venv
    uvx ruff check src/

# Run linting and fix errors
[group('python package')]
lint-fix:
    ruff check --fix src/

# Run linting and fix errors in uv virtual environment
[group('python package')]
uv-lint-fix: _ensure-venv
    uvx ruff check --fix src/

# Run type checking in uv virtual environment
[group('python package')]
type:
    pyright src/

# Run type checking in uv virtual environment
[group('python package')]
uv-type: _ensure-venv
    uv run pyright src/

# Run all checks (lint, type, test)
[group('python package')]
check: lint type test
    @printf "\n\033[92mAll checks passed!\033[0m\n"

# Helper recipes
_ensure-venv:
    #!/usr/bin/env bash
    if [ ! -d ".venv" ]; then
        uv venv
    fi

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

# Rotate a specific secret
[group('secrets')]
rotate-secret secret_name:
  @echo "Rotating {{ secret_name }}..."
  @echo "Enter new value for {{ secret_name }}:"
  @read -s NEW_VALUE && \
    sops vars/shared.yaml --set '["{{ secret_name }}"] "'$NEW_VALUE'"' && \
    echo "✅ {{ secret_name }} rotated successfully"

# Update keys for existing secrets files after adding new recipients
[group('secrets')]
updatekeys:
  @for file in $(find vars -name "*.yaml"); do \
    echo "Updating keys for: $file"; \
    sops updatekeys "$file"; \
  done
  @echo "✅ Keys updated for all secrets files"

## Template

# Initialize new project from template
[group('template')]
template-init:
    echo "Use: nix --accept-flake-config run github:juspay/omnix -- init github:sciexp/python-nix-template -o new-python-project"

# Verify template functionality by creating and checking a test project
[group('template')]
template-verify:
    om init -t .#default ./tmp-verify-template
    cd ./tmp-verify-template && nix flake check
    rm -rf ./tmp-verify-template

## GCP Service Account for DVC

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

## Documentation

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
