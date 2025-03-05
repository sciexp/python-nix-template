# List all recipes
default:
    @just --list

# Contents (alphabetical)
## CI/CD
## Conda package
## Monorepo
## Nix
## Python package
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
  eval "$(teller sh)" && \
  gh secret set CACHIX_AUTH_TOKEN --repo={{ repo }} --body="$CACHIX_AUTH_TOKEN" && \
  gh secret set FAST_FORWARD_PAT --repo={{ repo }} --body="$FAST_FORWARD_PAT" && \
  gh secret set GITGUARDIAN_API_KEY --repo={{ repo }} --body="$GITGUARDIAN_API_KEY"
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
conda-build:
    pixi build

# Create and sync conda environment with pixi
[group('conda package')]
conda-env:
    pixi install
    @echo "Conda environment is ready. Activate it with 'pixi shell'"

# Update pixi lockfile
[group('conda package')]
pixi-lock:
    pixi list
    pixi tree

# Update conda environment
[group('conda package')]
conda-lock:
    pixi project export conda-explicit-spec conda/ --ignore-pypi-errors

# Run tests in conda environment with pixi
[group('conda package')]
conda-test:
    pixi run -e test pytest

# Run linting in conda environment with pixi
[group('conda package')]
conda-lint:
    pixi run -e lint ruff check src/

# Run linting and fix errors in conda environment with pixi
[group('conda package')]
conda-lint-fix:
    pixi run -e lint ruff check --fix src/

# Run type checking in conda environment with pixi
[group('conda package')]
conda-type:
    pixi run -e types pyright src/

# Run all checks in conda environment (lint, type, test)
[group('conda package')]
conda-check: conda-lint conda-type conda-test
    @printf "\n\033[92mAll conda checks passed!\033[0m\n"

## Monorepo

# Apply monorepo patch to convert project to monorepo structure
[group('monorepo')]
monorepo_patch:
    git apply scripts/monorepo_pyproject.patch

# Reverse monorepo patch to revert to single package structure
[group('monorepo')]
monorepo_reverse:
    git apply --reverse scripts/monorepo_pyproject.patch

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

# Define the project variable
gcp_project_id := env_var_or_default('GCP_PROJECT_ID', 'development')

# Show existing secrets
[group('secrets')]
show:
  @teller show

# Create a secret with the given name
[group('secrets')]
create-secret name:
  @gcloud secrets create {{name}} --replication-policy="automatic" --project {{gcp_project_id}}

# Populate a single secret with the contents of a dotenv-formatted file
[group('secrets')]
populate-single-secret name path:
  @gcloud secrets versions add {{name}} --data-file={{path}} --project {{gcp_project_id}}

# Populate each line of a dotenv-formatted file as a separate secret
[group('secrets')]
populate-separate-secrets path:
  @grep -v '^[[:space:]]*#' {{path}} | while IFS= read -r line; do \
     KEY=$(echo $line | cut -d '=' -f 1); \
     VALUE=$(echo $line | cut -d '=' -f 2); \
     gcloud secrets create $KEY --replication-policy="automatic" --project {{gcp_project_id}} 2>/dev/null; \
     printf "$VALUE" | gcloud secrets versions add $KEY --data-file=- --project {{gcp_project_id}}; \
   done

# Complete process: Create a secret and populate it with the entire contents of a dotenv file
[group('secrets')]
create-and-populate-single-secret name path:
  @just create-secret {{name}}
  @just populate-single-secret {{name}} {{path}}

# Complete process: Create and populate separate secrets for each line in the dotenv file
[group('secrets')]
create-and-populate-separate-secrets path:
  @just populate-separate-secrets {{path}}

# Retrieve the contents of a given secret
[group('secrets')]
get-secret name:
  @gcloud secrets versions access latest --secret={{name}} --project={{gcp_project_id}}

# Create empty dotenv from template
[group('secrets')]
seed-dotenv:
  @cp .template.env .env

# Export unique secrets to dotenv format
[group('secrets')]
export:
  @teller export env | sort | uniq | grep -v '^$' > .secrets.env

# Check secrets are available in teller shell.
[group('secrets')]
check-secrets:
  @printf "Check teller environment for secrets\n\n"
  @teller run -s -- env | grep -E 'GITHUB|CACHIX' | teller redact

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
