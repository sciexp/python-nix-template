# Crane + uv2nix + maturin integration architecture

This document describes the target architecture for integrating Rust extension modules into python-nix-template's federated Python monorepo pattern.

## Context

The template is migrating from a single-lock uv workspace (Cargo-style) to a federated independent-lock pattern (LangChain-style).
Some Python packages may contain Rust extension modules built via pyo3/maturin.
These Rust extensions may themselves be federated cargo workspaces with multiple crates.

The goal is optimal build caching at both the Rust (crane's cargoArtifacts) and Python (uv2nix virtualenvs) levels while maintaining full federation—no root-level coordination required.

## Reference implementations

Local repositories demonstrating component patterns:

- `~/projects/rust-workspace/ironstar` — crane + rust-flake patterns, cargoArtifacts sharing, CI matrix builds
- `~/projects/planning-workspace/langchain` — federated Python monorepo, per-package independence, path dependencies via `[tool.uv.sources]`
- `~/projects/planning-workspace/langgraph` — federated Python with PEP 420 namespace packages, PEP 735 dependency groups
- `~/projects/nix-workspace/uv` — uv workspace mechanics, Cargo-inspired design
- `~/projects/nix-workspace/uv2nix` — Python packaging via pyproject-nix overlays
- `~/projects/nix-workspace/pyproject.nix` — maturin build system support, importCargoLock
- `~/projects/maturin` — pyo3 build backend, cargo workspace integration via manifest-path

## Target directory structure

```
python-nix-template/
├── flake.nix                           # Top-level orchestration
├── nix/
│   ├── modules/
│   │   ├── python.nix                  # uv2nix integration, per-package overlays
│   │   └── rust/                       # Shared crane utilities
│   │       ├── lib.nix                 # mkCraneLib, buildRustPackage helpers
│   │       └── overlays.nix            # Cross-package Rust overlay composition
│   └── packages/                       # Per-package Nix modules
│       ├── pnt-cli/
│       │   ├── default.nix             # Python + Rust composition
│       │   └── rust.nix                # crane configuration for this package's crates
│       └── pnt-functional/
│           └── default.nix             # Pure Python package
│
├── packages/                           # Python packages (federated, independent locks)
│   ├── pnt-cli/                        # Example: CLI with Rust backend
│   │   ├── pyproject.toml              # maturin build-system, manifest-path binding
│   │   ├── uv.lock                     # Independent lock (optional)
│   │   ├── src/pnt_cli/                # Python wrapper code
│   │   └── crates/                     # Federated Rust workspace for THIS package
│   │       ├── Cargo.toml              # [workspace] members = ["pnt-cli-core", "pnt-cli-py"]
│   │       ├── Cargo.lock
│   │       ├── pnt-cli-core/           # Pure Rust library
│   │       │   └── Cargo.toml
│   │       └── pnt-cli-py/             # pyo3 extension module
│   │           └── Cargo.toml          # depends on pnt-cli-core via workspace
│   │
│   └── pnt-functional/                 # Pure Python package
│       ├── pyproject.toml
│       └── src/pnt_functional/
```

## Integration patterns

### Pattern 1: Per-package Rust module (rust.nix)

Each Python package with Rust extensions gets a `nix/packages/{name}/rust.nix` that encapsulates crane configuration.

```nix
# nix/packages/pnt-cli/rust.nix
{ pkgs, crane, lib, ... }:
let
  src = ../../../packages/pnt-cli/crates;

  # Standard crane pattern from ironstar
  crane-lib = crane.mkLib pkgs;

  commonArgs = {
    inherit src;
    pname = "pnt-cli-rust";
    strictDeps = true;
    CARGO_PROFILE = "release";
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = lib.optionals pkgs.stdenv.isDarwin [
      pkgs.darwin.apple_sdk.frameworks.Security
    ];
  };

  # Shared dependency artifacts (expensive compilation cached)
  cargoArtifacts = crane-lib.buildDepsOnly commonArgs;

in {
  # Export for Python package to consume
  inherit cargoArtifacts;

  # Individual crate derivations (for testing, inspection)
  pnt-cli-core = crane-lib.buildPackage (commonArgs // {
    inherit cargoArtifacts;
    cargoExtraArgs = "-p pnt-cli-core";
  });

  # Vendored deps for maturin's cargo invocation
  cargoVendorDir = crane-lib.vendorCargoDeps { inherit src; };

  # Checks (clippy, tests) reusing cached artifacts
  clippy = crane-lib.cargoClippy (commonArgs // {
    inherit cargoArtifacts;
    cargoClippyExtraArgs = "--all-targets -- --deny warnings";
  });

  nextest = crane-lib.cargoNextest (commonArgs // {
    inherit cargoArtifacts;
    partitions = 1;
    partitionType = "count";
  });
}
```

Key principles from `~/projects/rust-workspace/ironstar/modules/rust.nix`:

- Single `buildDepsOnly` call creates `cargoArtifacts` shared by all build targets
- `commonArgs` pattern ensures derivation hash consistency (see ironstar FAQ on constant rebuilds)
- `vendorCargoDeps` provides offline cargo builds without IFD

### Pattern 2: Python package overlay (default.nix)

The Python package Nix module composes the Rust derivation with uv2nix's overlay system.

```nix
# nix/packages/pnt-cli/default.nix
{ pkgs, lib, crane, ... }:
let
  rustPkgs = import ./rust.nix { inherit pkgs crane lib; };

in {
  # Override for this package in the Python package set
  overlay = final: prev: {
    pnt-cli = prev.pnt-cli.overrideAttrs (old: {
      # Inject pre-vendored Cargo deps (crane's vendoring, not rustPlatform's)
      cargoVendorDir = rustPkgs.cargoVendorDir;

      # Reuse crane's cargoArtifacts for incremental builds
      preBuild = ''
        export CARGO_TARGET_DIR="${rustPkgs.cargoArtifacts}/target"
      '';

      nativeBuildInputs = old.nativeBuildInputs ++ [
        pkgs.cargo
        pkgs.rustc
      ] ++ final.resolveBuildSystem {
        maturin = [ ];
      };

      buildInputs = (old.buildInputs or [ ]) ++
        lib.optionals pkgs.stdenv.isDarwin [
          pkgs.darwin.apple_sdk.frameworks.Security
        ];
    });
  };

  # Export Rust checks for flake checks
  checks = {
    pnt-cli-clippy = rustPkgs.clippy;
    pnt-cli-nextest = rustPkgs.nextest;
  };
}
```

### Pattern 3: Top-level Python module composition

The `nix/modules/python.nix` composes all package overlays into the final Python set.

Version-conflict invariant: all federated packages must resolve compatible versions for shared dependencies.
Per-package uv2nix overlays are composed sequentially into a single package set via `lib.composeManyExtensions`.
If two packages resolve different versions of the same dependency, the later overlay silently wins with no error.
Enforce version alignment by running `uv lock --check` in each package directory after updating any shared dependency.

```nix
# nix/modules/python.nix
{ inputs, ... }:
{
  perSystem = { pkgs, lib, system, ... }:
  let
    # Load each Python package independently (no root workspace)
    loadPackage = name: path:
      let
        workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
          workspaceRoot = path;
        };
      in {
        inherit workspace;
        overlay = workspace.mkPyprojectOverlay { sourcePreference = "sdist"; };
      };

    packages = {
      pnt-cli = loadPackage "pnt-cli" ../../packages/pnt-cli;
      pnt-functional = loadPackage "pnt-functional" ../../packages/pnt-functional;
    };

    # Package-specific Nix modules with optional Rust overlays
    packageModules = {
      pnt-cli = import ../packages/pnt-cli { inherit pkgs lib; crane = inputs.crane; };
      pnt-functional = { overlay = _: _: { }; checks = { }; };
    };

    # Compose all overlays
    pythonBase = pkgs.callPackage inputs.pyproject-nix.build.packages {
      python = pkgs.python312;
    };

    pythonSet = pythonBase.overrideScope (lib.composeManyExtensions [
      # uv2nix overlays for each package
      packages.pnt-cli.overlay
      packages.pnt-functional.overlay
      # Custom Rust integration overlays
      packageModules.pnt-cli.overlay
    ]);

  in {
    packages = {
      pnt-cli = pythonSet.pnt-cli;
      pnt-functional = pythonSet.pnt-functional;
    };

    checks = packageModules.pnt-cli.checks // packageModules.pnt-functional.checks;
  };
}
```

### Pattern 4: pyproject.toml maturin binding

The Python package's pyproject.toml binds maturin to the specific pyo3 crate.

```toml
# packages/pnt-cli/pyproject.toml
[build-system]
requires = ["maturin>=1.5"]
build-backend = "maturin"

[project]
name = "pnt-cli"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = []

[tool.maturin]
manifest-path = "crates/pnt-cli-py/Cargo.toml"
module-name = "pnt_cli._native"
features = ["pyo3/extension-module"]
python-source = "src"

[tool.uv.sources]
# Path dependencies for local development (federated pattern)
pnt-functional = { path = "../pnt-functional", editable = true }

[dependency-groups]
dev = ["pytest>=8.0", "mypy>=1.10"]
```

Key maturin configuration:

- `manifest-path` points to the pyo3 crate within the Rust workspace
- `module-name` controls where the compiled extension appears in the Python package
- `python-source` tells maturin where Python code lives (alongside the native module)

### Pattern 5: CI matrix strategy

Extend ironstar's category-based CI to handle mixed packages.

```yaml
# .github/workflows/ci.yaml
jobs:
  nix-build:
    strategy:
      matrix:
        include:
          # Rust dependency caching (expensive, cached aggressively)
          - package: pnt-cli
            category: rust-deps
            cache-key: rust-deps-${{ hashFiles('packages/pnt-cli/crates/Cargo.lock') }}

          # Rust checks (clippy, tests)
          - package: pnt-cli
            category: rust-checks

          # Python wheel build (depends on rust-deps)
          - package: pnt-cli
            category: python-wheel

          # Pure Python packages
          - package: pnt-functional
            category: python-wheel

    steps:
      - uses: DeterminateSystems/nix-installer-action@main
      - uses: DeterminateSystems/flake-checker-action@main

      - name: Build category
        run: |
          case "${{ matrix.category }}" in
            rust-deps)
              nix build ".#packages.x86_64-linux.${{ matrix.package }}-cargoArtifacts"
              ;;
            rust-checks)
              nix build ".#checks.x86_64-linux.${{ matrix.package }}-clippy"
              nix build ".#checks.x86_64-linux.${{ matrix.package }}-nextest"
              ;;
            python-wheel)
              nix build ".#packages.x86_64-linux.${{ matrix.package }}"
              ;;
          esac
```

## Caching strategy

The architecture achieves optimal caching through layered artifact reuse.

### Layer 1: Rust dependency artifacts (cargoArtifacts)

Crane's `buildDepsOnly` compiles all Cargo dependencies without project code.
This derivation changes only when `Cargo.lock` changes.
CI caches this derivation via Cachix or GitHub Actions cache.
Rebuild time: minutes → seconds when cached.

### Layer 2: Rust project artifacts

Crane's `buildPackage` with `inherit cargoArtifacts` compiles only project code.
Changes when Rust source files change.
Incremental: only changed crates recompile.

### Layer 3: Python wheel

Maturin produces a wheel containing the compiled `.so` and Python source.
uv2nix converts this to a Nix derivation.
Changes when Python source or Rust output changes.

### Layer 4: Python virtualenv

uv2nix's `mkVirtualEnv` composes all package wheels.
Changes when any dependency wheel changes.
For development, use editable installs to avoid full rebuilds.

## Testing strategy

Rust-level tests run via crane (cargoNextest) for fast iteration and artifact reuse.
Python-level tests run via pytest within the uv2nix virtualenv.
Integration tests exercise the full Python → Rust boundary.

```nix
# In nix/packages/pnt-cli/default.nix
checks = {
  # Rust unit tests (fast, cached)
  pnt-cli-rust-unit = rustPkgs.nextest;

  # Rust lint (fast, cached)
  pnt-cli-clippy = rustPkgs.clippy;

  # Python integration tests
  pnt-cli-pytest = pythonSet.mkVirtualEnv "pnt-cli-test-env" {
    pnt-cli = [ "dev" ];
  } // {
    checkPhase = ''
      pytest packages/pnt-cli/tests/
    '';
  };
};
```

## Migration path

The implementation follows the beads epic dependency chain:

1. **pnt-dre**: Infrastructure alignment (concurrent with pnt-4jg)
   - Establishes nix/modules/ and nix/packages/ structure
   - Aligns CI patterns with this architecture

2. **pnt-4jg**: Dependency model migration (concurrent with pnt-dre)
   - Removes root uv workspace
   - Establishes per-package path dependencies
   - Documents federated pattern

3. **pnt-btz**: pyo3/Rust extension integration (after pnt-dre and pnt-4jg)
   - Creates pnt-cli package scaffold with crates/ directory
   - Implements rust.nix and default.nix patterns
   - Validates full crane + uv2nix + maturin integration

## Open questions

### Cross-package Rust dependencies

If multiple Python packages share Rust crates, options include:

1. **Workspace-level Rust crates**: A shared `crates/` at repository root, imported by multiple Python packages
2. **Published crates**: Publish shared crates to crates.io or a private registry
3. **Path dependencies**: Use Cargo's workspace-level path dependencies across package boundaries

The federated model prefers option 2 (published crates) for maximum independence, but option 1 may be pragmatic during development.

### cargoArtifacts sharing across Python packages

If multiple Python packages have Rust extensions with overlapping dependencies, we could share cargoArtifacts.
This requires a shared `Cargo.lock` or careful alignment of dependency versions.
Initial recommendation: keep cargoArtifacts per-package for simplicity, optimize later if build times warrant.

### Editable development workflow

For local development, developers want fast iteration without full Nix rebuilds.
Recommend: use `uv sync` + `maturin develop` outside Nix for iteration, Nix for CI and reproducible builds.
The Nix derivations serve as the source of truth; local development uses native tooling for speed.

## References

- ironstar crane patterns: `~/projects/rust-workspace/ironstar/modules/rust.nix`
- ironstar CI matrix: `~/projects/rust-workspace/ironstar/.github/workflows/ci.yaml`
- LangChain federation: `~/projects/planning-workspace/langchain/libs/`
- uv2nix overlay pattern: `~/projects/nix-workspace/uv2nix/doc/patterns/`
- pyproject.nix maturin: `~/projects/nix-workspace/pyproject.nix/doc/src/builders.md`
- maturin workspace support: `~/projects/maturin/guide/src/project_layout.md`
