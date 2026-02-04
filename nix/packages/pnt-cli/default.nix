# pnt-cli: PyO3/maturin package with crane-maturin test suite.
#
# crane-maturin's buildMaturinPackage provides the standalone build and
# comprehensive passthru.tests (pytest, clippy, doc, fmt, cargo test).
# The overlay uses pyproject-nix's nixpkgsPrebuilt to install from
# crane-maturin's output, eliminating duplicate Rust compilation while
# preserving uv2nix resolver metadata (passthru.dependencies) from prev.
{
  pkgs,
  lib,
  crane,
  crane-maturin,
  pyproject-nix,
  python,
}:
let
  cmLib = crane-maturin.mkLib crane pkgs;
  hacks = pkgs.callPackage pyproject-nix.build.hacks { };

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

  # Standalone crane-maturin build for test suite and Python package output.
  # nixpkgsPrebuilt installs from this derivation, avoiding duplicate Rust
  # compilation in the uv2nix overlay. passthru.tests provides checks.
  cmPackage = cmLib.buildMaturinPackage {
    pname = "pnt-cli";
    inherit src testSrc python;
  };
in
{
  # Install crane-maturin's pre-built output into the uv2nix package set via
  # nixpkgsPrebuilt. This preserves uv2nix's passthru.dependencies (from prev)
  # for resolveVirtualEnv while using crane-maturin's compiled artifacts.
  #
  # Note on passthru key spaces: uv2nix owns dependencies, optional-dependencies,
  # and dependency-groups. crane-maturin contributes crate, tests, withCoverage.
  # If either upstream adds keys that collide, the shallow merge will clobber.
  overlay = final: prev: {
    pnt-cli =
      (hacks.nixpkgsPrebuilt {
        from = cmPackage;
        prev = prev.pnt-cli;
      }).overrideAttrs
        (old: {
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
