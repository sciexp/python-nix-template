# python-nix-template

A nix template for python packages managed with
[uv2nix](https://github.com/pyproject-nix/uv2nix) and
[flake-parts](https://github.com/hercules-ci/flake-parts). The structure mirrors
those in the [omnix registry](#credits) to the extent possible with python and
its ecosystem.

## Features

- Modern python packaging with `pyproject.toml`
- Fast dependency management with `uv`
- Reproducible developer environments and builds with `nix` and `uv2nix`
- Functional programming patterns briefly illustrated in the sample package:
  - Railway-oriented programming with `expression` for type-safe error handling
  - Effect tracking via monad transformers for composable side effects
  - Runtime type checking with `beartype` for robust type safety
  - Pure functions and immutable data types for reliable code
  - Composition of effectful functions using monadic bind operations
- conda ecosystem compatibility via `pixi`

## Development

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

```shell
make bootstrap
```

Run `make` alone for a listing of available targets.

After nix and direnv are installed, you can either run `direnv allow` or `nix
develop` to enter a [development shell](./nix/modules/devshell.nix) that will
contain necessary system-level dependencies.

### Task runner

This project uses `just` as a task runner, which is provided in the [development
shell](#prerequisites). List available commands with:

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

Run `just` alone for a listing of all available task recipes.

## credits

### python

- [beartypte/beartype](https://github.com/beartype/beartype)
- [dbrattli/Expression](https://github.com/dbrattli/Expression)

### python in nix

- [uv2nix](https://github.com/pyproject-nix/uv2nix)

### nix

See the [omnix registry
flake](https://github.com/juspay/omnix/blob/1.0.0/crates/omnix-init/registry/flake.nix)

- [srid/haskell-template](https://github.com/srid/haskell-template)
- [srid/rust-nix-template](https://github.com/srid/rust-nix-template)
- [hercules-ci/flake-parts](https://github.com/hercules-ci/flake-parts)
