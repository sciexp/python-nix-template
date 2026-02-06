# python-nix-template

A nix template for python packages managed with
[uv2nix](https://github.com/pyproject-nix/uv2nix) and
[flake-parts](https://github.com/hercules-ci/flake-parts).
The structure mirrors those in the [omnix registry](#credits) to the extent possible with python and its ecosystem.

## Template usage

You can use [omnix](https://omnix.page/om/init.html)[^omnix] to initialize this template:

```sh
nix --accept-flake-config run github:juspay/omnix -- \
init github:sciexp/python-nix-template -o new-python-project
```

[^omnix]: If you have omnix installed you just need `om init ...` and not `nix run ... -- init`

tl;dr

<details><summary>instantiate a monorepo variant of the template</summary>

```sh
PROJECT_DIRECTORY=pnt-mono && \
PROJECT_SNAKE_CASE=$(echo "$PROJECT_DIRECTORY" | tr '-' '_') && \
PARAMS=$(cat <<EOF
{
  "package-name-kebab-case": "$PROJECT_DIRECTORY",
  "package-name-snake-case": "$PROJECT_SNAKE_CASE",
  "monorepo-package": true,
  "pyo3-package": true,
  "git-org": "pnt-mono",
  "author": "Pnt Mono",
  "author-email": "mono@pnt.org",
  "project-description": "A Python monorepo project using Nix and uv2nix",
  "vscode": true,
  "github-ci": true,
  "docs": true,
  "nix-template": false
}
EOF
) && \
nix --accept-flake-config run github:juspay/omnix/v1.3.2 -- init github:sciexp/python-nix-template/main -o "$PROJECT_DIRECTORY" --non-interactive --params "$PARAMS" && \
(command -v direnv >/dev/null 2>&1 && direnv revoke "./$PROJECT_DIRECTORY/" || true) && \
cd "$PROJECT_DIRECTORY" && \
git init && \
git commit --allow-empty -m "initial commit (empty)" && \
git add . && \
for pkg in packages/*/; do [ -f "$pkg/pyproject.toml" ] && (cd "$pkg" && nix run github:NixOS/nixpkgs/nixos-unstable#uv -- lock); done && \
git add . && \
nix develop --accept-flake-config -c just test-all
```

</details>

You can run `direnv allow` to enter the shell environment that contains
development dependencies or `nix develop --accept-flake-config` to enter (or add
`-c command` to execute individual commands within) the development shell.

<details><summary>instantiate a single-package variant of the template</summary>

```sh
PROJECT_DIRECTORY=pnt-new && \
PROJECT_SNAKE_CASE=$(echo "$PROJECT_DIRECTORY" | tr '-' '_') && \
PARAMS=$(cat <<EOF
{
  "package-name-kebab-case": "$PROJECT_DIRECTORY",
  "package-name-snake-case": "$PROJECT_SNAKE_CASE",
  "monorepo-package": false,
  "pyo3-package": false,
  "git-org": "pnt-new",
  "author": "Pnt New",
  "author-email": "new@pnt.org",
  "project-description": "A Python project using Nix and uv2nix",
  "vscode": true,
  "github-ci": true,
  "docs": true,
  "nix-template": false
}
EOF
) && \
nix --accept-flake-config run github:juspay/omnix/v1.3.2 -- init github:sciexp/python-nix-template/main -o "$PROJECT_DIRECTORY" --non-interactive --params "$PARAMS" && \
(command -v direnv >/dev/null 2>&1 && direnv revoke "./$PROJECT_DIRECTORY/" || true) && \
cd "$PROJECT_DIRECTORY" && \
git init && \
git commit --allow-empty -m "initial commit (empty)" && \
git add . && \
for pkg in packages/*/; do [ -f "$pkg/pyproject.toml" ] && (cd "$pkg" && nix run github:NixOS/nixpkgs/nixos-unstable#uv -- lock); done && \
git add . && \
nix develop --accept-flake-config -c just test-all
```

</details>

except you may want to update the git ref/rev of the template if you need to pin to a
particular version:

- `github:sciexp/python-nix-template/main`
- `github:sciexp/python-nix-template/v0.1.0`
- `github:sciexp/python-nix-template/3289dla`
- `github:sciexp/python-nix-template/devbranch`.

### Quick start

#### Nix-managed environment

The template supports three types of development environments:

1. nix devshell
2. python virtualenv via uv
3. conda environments via pixi

The intended workflow is to run

```sh
make bootstrap
```

only the very first time you are setting up one of these templates.
This will verify you have the [nix package manager](https://nix.dev) and [direnv](https://direnv.net/) installed.
Registration of the repository contents requires creating a git repository, for example with

```sh
git init && git commit --allow-empty -m "initial commit (empty)" && git add .
```

but does not require committing.
After this running

```sh
direnv allow
```

will ensure you have all development tools on a project directory-specific version of your PATH variable.
These include the `just` task runner, which provides an alternative to using [GNU Make](https://www.gnu.org/software/make/) as a task runner.
See the [task runner](#task-runner) section for a listing of development commands.

You should now be able to run `just test-all` to confirm all package tests pass in the devshell environment, or `just test <package-name>` to test a specific package.

> [!NOTE]
> This template uses an independent-lock pattern where each package under
> `packages/` maintains its own `pyproject.toml` and `uv.lock`. There is no root
> `pyproject.toml` or uv workspace. After instantiation, lock each package
> individually:
>
> ```sh
> for pkg in packages/*/; do [ -f "$pkg/pyproject.toml" ] && (cd "$pkg" && uv lock); done
> ```

If you choose to modify packages or add dependencies, run `just uv-lock <package-name>` to update the lock file for that specific package.

#### Python virtualenv

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
- conda ecosystem compatibility via `pixi`

<details><summary>Optional packages</summary>

The template includes optional packages controlled by omnix template parameters.
Both default to false for the single-package variant and can be set to true individually or together.

*pnt-functional* (`monorepo-package` parameter) provides a brief illustration of functional programming patterns in Python.
It demonstrates railway-oriented programming with `expression` for type-safe error handling, effect tracking via monad transformers for composable side effects, runtime type checking with `beartype`, pure functions and immutable data types, and composition of effectful functions using monadic bind operations.
See [packages/pnt-functional](./packages/pnt-functional) for details.

*pnt-cli* (`pyo3-package` parameter) is a Rust extension module demonstrating Python-Rust interop via [pyo3](https://pyo3.rs) and [maturin](https://www.maturin.rs).
It exposes Rust functions callable from Python through a compiled native module (`pnt_cli._native`).
The Rust side is organized as a Cargo workspace with a core library crate and a pyo3 binding crate under `packages/pnt-cli/crates/`.
On the Nix side, the build uses [crane](https://github.com/ipetkov/crane) for incremental Rust compilation caching and [crane-maturin](https://github.com/vlaci/crane-maturin) for producing maturin-compatible wheels.
The resulting artifact is installed into the uv2nix package set via `pyproject-nix`'s `nixpkgsPrebuilt`, avoiding duplicate Rust compilation during Nix evaluation.
See [packages/pnt-cli](./packages/pnt-cli) and [nix/packages/pnt-cli](./nix/packages/pnt-cli) for the implementation.

</details>

## Development

### Prerequisites

If you'd like to develop `python-nix-template` you'll need the [nix package manager](https://nix.dev).
You can optionally make use of [direnv](https://direnv.net/) to automatically activate the environment.
The project includes a Makefile to help bootstrap your development environment.

It provides:

1. Installation of the nix package manager using the Determinate Systems installer
2. Installation of direnv for automatic environment activation
3. Link to instructions for shell configuration

To get started, run:

```shell
make bootstrap
```

Run `make` alone for a listing of available targets.

After nix and direnv are installed, you can either run `direnv allow` or `nix develop` to enter a [development shell](./nix/modules/devshell.nix) that will contain necessary system-level dependencies.

### Task runner

This project uses [`just`](https://just.systems/man/en/) as a task runner, which is provided in the [development shell](#prerequisites).
List available commands by running `just` alone.

<details>
<summary>just recipes</summary>

```sh
default                                     # List all recipes

[CI/CD]
gcloud-context                              # Set gcloud context
ghsecrets repo="sciexp/python-nix-template" # Update github secrets for repo from environment variables
ghvars repo="sciexp/python-nix-template"    # Update github vars for repo from environment variables
pre-commit                                  # Run pre-commit hooks (see pre-commit.nix and note the yaml is git-ignored)

[conda package]
conda-build                                 # Package commands (conda)
conda-check                                 # Run all checks in conda environment (lint, type, test)
conda-env                                   # Create and sync conda environment with pixi
conda-lint                                  # Run linting in conda environment with pixi
conda-lint-fix                              # Run linting and fix errors in conda environment with pixi
conda-lock                                  # Update conda environment
conda-test                                  # Run tests in conda environment with pixi
conda-type                                  # Run type checking in conda environment with pixi
pixi-lock                                   # Update pixi lockfile

[nix]
ci                                          # Run CI checks locally with `om ci`
container-build                             # Build production container image
container-build-dev                         # Build development container image
container-run                               # Run production container with port 8888 exposed
container-run-dev                           # Run development container with port 8888 exposed
dev                                         # Enter the Nix development shell
flake-check                                 # Validate the Nix flake configuration
flake-update                                # Update all flake inputs to their latest versions

[python package]
check                                       # Run all checks (lint, type, test)
lint                                        # Run linting
lint-fix                                    # Run linting and fix errors
test                                        # Run tests
type                                        # Run type checking in uv virtual environment
uv-build                                    # Package commands
uv-lint                                     # Run linting in uv virtual environment
uv-lint-fix                                 # Run linting and fix errors in uv virtual environment
uv-lock                                     # Update lockfile from pyproject.toml
uv-test                                     # Run tests in uv virtual environment
uv-type                                     # Run type checking in uv virtual environment
venv                                        # Sync and enter uv virtual environment

[secrets]
check-secrets                               # Check secrets are available in sops environment.
create-and-populate-separate-secrets path   # Complete process: Create and populate separate secrets for each line in the dotenv file
create-and-populate-single-secret name path # Complete process: Create a secret and populate it with the entire contents of a dotenv file
create-secret name                          # Create a secret with the given name
export                                      # Export unique secrets to dotenv format
get-secret name                             # Retrieve the contents of a given secret
populate-separate-secrets path              # Populate each line of a dotenv-formatted file as a separate secret
populate-single-secret name path            # Populate a single secret with the contents of a dotenv-formatted file
seed-dotenv                                 # Create empty dotenv from template
show                                        # Show existing secrets

[template]
template-init                               # Initialize new project from template
template-verify                             # Verify template functionality by creating and checking a test project
```

</details>

## Credits

### Python

- [beartype](https://github.com/beartype/beartype) -- gradual runtime type checking
- [Expression](https://github.com/dbrattli/Expression) -- functional programming abstractions for Python

### Python in Nix

- [uv2nix](https://github.com/pyproject-nix/uv2nix) -- Nix integration for uv-managed Python workspaces
- [pyproject.nix](https://github.com/pyproject-nix/pyproject.nix) -- Nix library for Python project management, used by uv2nix for build-system resolution
- [pyproject-build-systems](https://github.com/pyproject-nix/build-system-pkgs) -- pre-built Python build-system packages for Nix

### Rust in Nix

- [crane](https://github.com/ipetkov/crane) -- Nix library for building Rust projects with incremental compilation caching
- [crane-maturin](https://github.com/vlaci/crane-maturin) -- crane extension for building maturin/pyo3 Python-Rust packages
- [rust-overlay](https://github.com/oxalica/rust-overlay) -- Nix overlay providing nightly and stable Rust toolchains

### Nix

<details><summary>omnix registry and flake-parts ecosystem</summary>

See the [omnix registry flake](https://github.com/juspay/omnix/blob/1.0.0/crates/omnix-init/registry/flake.nix)

- [srid/haskell-template](https://github.com/srid/haskell-template)
- [srid/rust-nix-template](https://github.com/srid/rust-nix-template)
- [hercules-ci/flake-parts](https://github.com/hercules-ci/flake-parts)

</details>
