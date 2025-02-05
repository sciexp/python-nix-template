# python-nix-template

A nix template for a python package managed with uv and uv2nix.

## Features

- Modern python packaging with `pyproject.toml`
- Fast dependency management with `uv`
- Reproducible developer environemtns and builds with `nix` and `uv2nix`

## Development

This project uses `just` for task running. List available commands with:

```bash
just
```

### Quick Start

1. Create and sync virtual environment:

   ```bash
   just venv
   source .venv/bin/activate
   ```

2. Run tests:

   ```bash
   just test
   ```

3. Run linting:

   ```bash
   just lint
   ```

4. Build package:

   ```bash
   just build
   ```

Run `just` alone for a listing of available recipes.
