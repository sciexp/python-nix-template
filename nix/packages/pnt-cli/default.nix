# pnt-cli: PyO3/maturin package with crane-maturin test suite.
#
# crane-maturin's buildMaturinPackage provides the standalone build and
# comprehensive passthru.tests (pytest, clippy, doc, fmt, cargo test).
# The overlay augments the uv2nix base with Rust build support, preserving
# pyproject-nix hooks and resolver metadata. crane-maturin's vendored
# cargo dependencies are injected via preBuild.
{
  pkgs,
  lib,
  crane,
  crane-maturin,
  python,
}:
let
  cmLib = crane-maturin.mkLib crane pkgs;

  pyFilter = path: _type: builtins.match ".*\\.pyi?$|.*/pyproject\\.toml$" path != null;

  testFilter = path: _type: builtins.match ".*/tests(/.*\\.py)?$" path != null;

  sourceFilter = path: type: (pyFilter path type) || (cmLib.filterCargoSources path type);

  src = lib.cleanSourceWith {
    src = cmLib.path ../../../packages/pnt-cli;
    filter = sourceFilter;
  };

  testSrc = lib.cleanSourceWith {
    src = cmLib.path ../../../packages/pnt-cli;
    filter = path: type: (sourceFilter path type) || (testFilter path type);
  };

  # Standalone crane-maturin build for test suite and artifact caching.
  # The overlay does not replace the uv2nix base with this derivation —
  # instead it augments the base and extracts passthru.tests for checks.
  cmPackage = cmLib.buildMaturinPackage {
    pname = "pnt-cli";
    inherit src testSrc python;
  };
in
{
  # Augment uv2nix base with Rust build support, keeping pyproject-nix hooks
  # (pythonOutputDistPhase, resolveVirtualEnv metadata) intact.
  overlay = final: prev: {
    pnt-cli = prev.pnt-cli.overrideAttrs (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [ ])
        ++ [
          pkgs.cargo
          pkgs.rustc
          python
        ]
        ++ final.resolveBuildSystem {
          maturin = [ ];
        };

      preBuild = ''
        mkdir -p .cargo
        cp ${cmPackage.cargoVendorDir}/config.toml .cargo/config.toml
      '';

      env.PYO3_PYTHON = python.interpreter;

      passthru = (old.passthru or { }) // {
        inherit (cmPackage.passthru) crate tests withCoverage;
      };
    });
  };

  checks =
    lib.mapAttrs'
      (name: drv: {
        name = "pnt-cli-${name}";
        value = drv;
      })
      (
        builtins.removeAttrs cmPackage.passthru.tests [
          "test-coverage"
          "pytest-coverage"
        ]
      );
}
