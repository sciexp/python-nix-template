# Core package management
default:
    @just --list

# Package commands
[group('python package')]
build: _ensure-venv
    uv build

# Sync and enter uv virtual environment
[group('python package')]
venv: _ensure-venv
    uv sync
    @echo "Virtual environment is ready. Activate it with 'source .venv/bin/activate'"

# Update lockfile from pyproject.toml
[group('python package')]
lock: _ensure-venv
    uv lock

# Run tests
[group('python package')]
test: _ensure-venv
    uv run pytest

# Run linting
[group('python package')]
lint: _ensure-venv
    uvx ruff check src/

# Run linting and fix errors
[group('python package')]
lint-fix: _ensure-venv
    uvx ruff check --fix src/

# Run type checking
[group('python package')]
type: _ensure-venv
    uv run pyright src/

# Run all checks (lint, type, test)
[group('python package')]
check: lint type test
    @printf "\n\033[92mAll checks passed!\033[0m\n"

# Package commands (conda)
[group('conda package')]
build-conda:
    pixi build

# Create and sync conda environment with pixi
[group('conda package')]
conda-env:
    pixi install
    @echo "Conda environment is ready. Activate it with 'pixi shell'"

# Update conda environment pixi lockfile
[group('conda package')]
lock-conda:
    pixi lock

# Run tests in conda environment with pixi
[group('conda package')]
test-conda:
    pixi run -e test pytest

# Run linting in conda environment with pixi
[group('conda package')]
lint-conda:
    pixi run -e lint ruff check src/

# Run linting and fix errors in conda environment with pixi
[group('conda package')]
lint-fix-conda:
    pixi run -e lint ruff check --fix src/

# Run type checking in conda environment with pixi
[group('conda package')]
type-conda:
    pixi run -e types pyright src/

# Run all checks in conda environment (lint, type, test)
[group('conda package')]
check-conda: lint-conda type-conda test-conda
    @printf "\n\033[92mAll conda checks passed!\033[0m\n"

# Helper recipes
_ensure-venv:
    #!/usr/bin/env bash
    if [ ! -d ".venv" ]; then
        uv venv
    fi
