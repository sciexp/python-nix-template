# python-nix-template

A nix template for a python package managed with uv and uv2nix.

## Features

- Modern python packaging with `pyproject.toml`
- Fast dependency management with `uv`
- Reproducible developer environments and builds with `nix` and `uv2nix`
- Industrial-strength functional programming patterns:
  - Railway-oriented programming with `expression` for type-safe error handling
  - Effect tracking via monad transformers for composable side effects
  - Runtime type checking with `beartype` for robust type safety
  - Pure functions and immutable data types for reliable code
  - Composition of effectful functions using monadic bind operations

## Example Package

The template includes an example package demonstrating functional programming best practices:

- Railway-oriented validation and error handling
- Effect tracking for side effects and error propagation
- Type-safe function composition with monadic operations
- Comprehensive test coverage with property-based testing
- Runtime type checking for additional safety

## Development

This project uses `just` for task running. List available commands with:

```bash
just
```

### Prerequisites

If you'd like to develop `python-nix-template` you'll need the [nix package
manager](https://nix.dev). You can optionally make use of
[direnv](https://direnv.net/) to automatically activate the environment. The
project includes a Makefile to help bootstrap your development environment.

It provides:

1. Installation of the nix package manager using the Determinate Systems
   installer
2. Installation of direnv for automatic environment activation
3. Link to instructions for shell configuration

To get started, run:

   ```bash
   make bootstrap
   ```

Run `make` alone for a listing of available targets.

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
