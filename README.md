# python-nix-template

A nix template for python packages managed with
[uv2nix](https://github.com/pyproject-nix/uv2nix) and
[flake-parts](https://github.com/hercules-ci/flake-parts). The structure mirrors
those in the [omnix registry](#credits) to the extent possible with python and
its ecosystem.

## Template usage

You can use [omnix](https://omnix.page/om/init.html)[^omnix] to initialize this template:

```sh
nix --accept-flake-config run github:juspay/omnix -- \
init github:sciexp/python-nix-template -o new-python-project
```

[^omnix]: If you have omnix installed you just need `om init ...` and not `nix run ... -- init`

### Quick Start

The template supports three types of development environments:

1. nix devshell
2. python virtualenv via uv
3. conda environments via pixi

The intended workflow is to run

```sh
make bootstrap
```

only the very first time you are setting up one of these templates. This will
verify you have the [nix package manager](https://nix.dev) and
[direnv](https://direnv.net/) installed. After this running

```sh
direnv allow
```

will ensure you have all development tools on a project directory-specific
version of your PATH variable. These include the `just` task runner, which
provides an alternative to using [GNU Make](https://www.gnu.org/software/make/)
as a task runner. See the [task runner](#task-runner) section for a listing of
development commands.

#### python virtualenv

1. Create and sync virtual environment:

   ```sh
   just venv
   source .venv/bin/activate
   ```

2. Run tests:

   ```sh
   just test
   ```

3. Run linting:

   ```sh
   just lint
   ```

4. Build package:

   ```sh
   just build
   ```

## Features

- Modern python packaging with `pyproject.toml`
- Fast dependency management with `uv`
- Reproducible developer environments and builds with `nix` and `uv2nix`
- See the optional monorepo workspace package [pnt-functional](./packages/pnt-functional)
  for a brief illustration of functional programming patterns (disabled by default):
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

This project uses [`just`](https://just.systems/man/en/) as a task runner, which
is provided in the [development shell](#prerequisites). List available commands
by running `just` alone.

<details>
<summary>just recipes</summary>

```sh
default                                           # List all recipes

[CI/CD]
gcloud-context                                    # Set gcloud context
ghsecrets repo="sciexp/python-nix-template" # Update github secrets for repo from environment variables
ghvars repo="sciexp/python-nix-template" # Update github vars for repo from environment variables
pre-commit                                        # Run pre-commit hooks (see pre-commit.nix and note the yaml is git-ignored)

[conda package]
conda-build                                       # Package commands (conda)
conda-check                                       # Run all checks in conda environment (lint, type, test)
conda-env                                         # Create and sync conda environment with pixi
conda-lint                                        # Run linting in conda environment with pixi
conda-lint-fix                                    # Run linting and fix errors in conda environment with pixi
conda-lock                                        # Update conda environment
conda-test                                        # Run tests in conda environment with pixi
conda-type                                        # Run type checking in conda environment with pixi
pixi-lock                                         # Update pixi lockfile

[nix]
ci                                                # Run CI checks locally with `om ci`
container-build                                   # Build production container image
container-build-dev                               # Build development container image
container-run                                     # Run production container with port 8888 exposed
container-run-dev                                 # Run development container with port 8888 exposed
dev                                               # Enter the Nix development shell
flake-check                                       # Validate the Nix flake configuration
flake-update                                      # Update all flake inputs to their latest versions

[python package]
check                                             # Run all checks (lint, type, test)
lint                                              # Run linting
lint-fix                                          # Run linting and fix errors
test                                              # Run tests
type                                              # Run type checking in uv virtual environment
uv-build                                          # Package commands
uv-lint                                           # Run linting in uv virtual environment
uv-lint-fix                                       # Run linting and fix errors in uv virtual environment
uv-lock                                           # Update lockfile from pyproject.toml
uv-test                                           # Run tests in uv virtual environment
uv-type                                           # Run type checking in uv virtual environment
venv                                              # Sync and enter uv virtual environment

[secrets]
check-secrets                                     # Check secrets are available in teller shell.
create-and-populate-separate-secrets path         # Complete process: Create and populate separate secrets for each line in the dotenv file
create-and-populate-single-secret name path       # Complete process: Create a secret and populate it with the entire contents of a dotenv file
create-secret name                                # Create a secret with the given name
export                                            # Export unique secrets to dotenv format
get-secret name                                   # Retrieve the contents of a given secret
populate-separate-secrets path                    # Populate each line of a dotenv-formatted file as a separate secret
populate-single-secret name path                  # Populate a single secret with the contents of a dotenv-formatted file
seed-dotenv                                       # Create empty dotenv from template
show                                              # Show existing secrets

[template]
template-init                                     # Initialize new project from template
template-verify                                   # Verify template functionality by creating and checking a test project
```

</details>

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
