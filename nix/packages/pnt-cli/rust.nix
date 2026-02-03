# Crane configuration for pnt-cli's Rust extension crates.
#
# Follows the commonArgs pattern from ironstar: a single buildDepsOnly call
# creates cargoArtifacts shared by buildPackage, cargoClippy, and cargoNextest.
# PYO3_PYTHON is set explicitly to prevent path-dependent rebuilds.
{
  pkgs,
  lib,
  crane,
  python,
}:
let
  crane-lib = crane.mkLib pkgs;

  src = ../../../packages/pnt-cli/crates;

  commonArgs = {
    inherit src;
    pname = "pnt-cli-rust";
    strictDeps = true;
    CARGO_PROFILE = "release";
    env.PYO3_PYTHON = python.interpreter;
    nativeBuildInputs = [
      pkgs.pkg-config
      python
    ];
  };

  cargoArtifacts = crane-lib.buildDepsOnly commonArgs;
in
{
  inherit cargoArtifacts;

  cargoVendorDir = crane-lib.vendorCargoDeps { inherit src; };

  clippy = crane-lib.cargoClippy (
    commonArgs
    // {
      inherit cargoArtifacts;
      cargoClippyExtraArgs = "--all-targets -- --deny warnings";
    }
  );

  nextest = crane-lib.cargoNextest (
    commonArgs
    // {
      inherit cargoArtifacts;
      partitions = 1;
      partitionType = "count";
      cargoNextestExtraArgs = "--no-tests=pass";
    }
  );
}
