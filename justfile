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
    uv pip install -e ".[test]"
    uv run pytest

# Run linting
[group('python package')]
lint: _ensure-venv
    uv pip install -e ".[lint]"
    uv run ruff check src/

# Helper recipes
_ensure-venv:
    #!/usr/bin/env bash
    if [ ! -d ".venv" ]; then
        uv venv
    fi
