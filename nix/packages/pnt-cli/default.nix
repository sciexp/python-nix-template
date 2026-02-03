# Python + Rust composition for pnt-cli.
#
# Imports rust.nix for crane derivations, then creates a Python package
# overlay that injects cargoVendorDir and CARGO_TARGET_DIR into the
# uv2nix-generated pnt-cli derivation. Exports the overlay and Rust checks
# for flake composition.
{
  pkgs,
  lib,
  crane,
  python,
}:
let
  rustPkgs = import ./rust.nix {
    inherit
      pkgs
      lib
      crane
      python
      ;
  };
in
{
  overlay = final: prev: {
    pnt-cli = prev.pnt-cli.overrideAttrs (old: {
      # Inject pre-vendored Cargo deps (crane's vendoring, not rustPlatform's)
      cargoVendorDir = rustPkgs.cargoVendorDir;

      # Reuse crane's cargoArtifacts for incremental builds
      preBuild = ''
        export CARGO_TARGET_DIR="${rustPkgs.cargoArtifacts}/target"
      '';

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

      env.PYO3_PYTHON = python.interpreter;
    });
  };

  checks = {
    pnt-cli-clippy = rustPkgs.clippy;
    pnt-cli-nextest = rustPkgs.nextest;
  };
}
