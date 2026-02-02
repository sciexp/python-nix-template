# Package distribution channels

This document describes the distribution channel support for each package in the repository, covering the uv/PyPI and pixi/conda-forge dependency resolution paths.

## Channel overview

Both packages support dual-channel distribution through uv (PyPI) and pixi (conda-forge).
Each package maintains independent lock files for both channels: `uv.lock` for PyPI resolution and `pixi.lock` for conda-forge resolution.

The nix devshell is the primary execution environment.
Justfile recipes wrap both uv and pixi commands, invoked via `nix develop -c just <recipe>`.
uv and pixi serve as dependency resolution tools consumed by the nix layer, not standalone execution contexts.

## Per-package channel support

### pnt-functional

| Channel | Supported | Lock file | Runtime dependencies |
|---------|-----------|-----------|---------------------|
| uv/PyPI | Yes | `packages/pnt-functional/uv.lock` | beartype, expression |
| pixi/conda-forge | Yes | `packages/pnt-functional/pixi.lock` | beartype, expression, python |

Runtime dependencies (`beartype`, `expression`) are available on both PyPI and conda-forge.
No channel-specific dependency graph differences for this package.

### python-nix-template

| Channel | Supported | Lock file | Runtime dependencies |
|---------|-----------|-----------|---------------------|
| uv/PyPI | Yes | `packages/python-nix-template/uv.lock` | (none) |
| pixi/conda-forge | Yes | `packages/python-nix-template/pixi.lock` | python |

This package has no runtime dependencies beyond the Python interpreter.
Dev dependencies (pytest, ruff, hypothesis, pyright, jupyter, quartodoc) are available on both channels.

## Dependency graph differences

The conda-forge channel resolves the full native dependency tree including system libraries (libffi, openssl, ncurses, etc.) that PyPI assumes are provided by the system.
This means pixi.lock files are substantially larger than uv.lock files for the same package, reflecting the completeness of the conda dependency graph.

The pixi configuration includes `pixi-build` preview feature for conda package building via `pixi-build-python` backend.
This allows packages to be built as conda packages in addition to PyPI wheels.

## Justfile recipe mapping

| Operation | uv/PyPI recipe | pixi/conda recipe |
|-----------|---------------|-------------------|
| Test | `just test <pkg>` | `just conda-test <pkg>` |
| Lint | `just lint <pkg>` | `just conda-lint <pkg>` |
| Lint + fix | `just lint-fix <pkg>` | `just conda-lint-fix <pkg>` |
| Type check | `just type <pkg>` | `just conda-type <pkg>` |
| All checks | `just check <pkg>` | `just conda-check <pkg>` |
| Build | `just uv-build <pkg>` | `just conda-build <pkg>` |
| Lock | `just uv-lock <pkg>` | `just pixi-lock <pkg>` |

All recipes accept a package parameter defaulting to `python-nix-template`.
