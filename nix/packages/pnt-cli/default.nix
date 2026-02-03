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

      # Configure cargo to use crane's vendored dependencies (offline build)
      # and reuse crane's cargoArtifacts for incremental compilation.
      # Crane's vendorCargoDeps output includes a config.toml with the correct
      # source replacement directives.
      preBuild = ''
        mkdir -p .cargo
        cp ${rustPkgs.cargoVendorDir}/config.toml .cargo/config.toml
        export CARGO_TARGET_DIR="${rustPkgs.cargoArtifacts}/target"
      '';

      env.PYO3_PYTHON = python.interpreter;
    });
  };

  checks = {
    pnt-cli-clippy = rustPkgs.clippy;
    pnt-cli-nextest = rustPkgs.nextest;
  };
}
