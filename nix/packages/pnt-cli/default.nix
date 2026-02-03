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
      preBuild = ''
        mkdir -p .cargo
        cat > .cargo/config.toml <<CARGO_CONFIG
        [source.crates-io]
        replace-with = "vendored-sources"

        [source.vendored-sources]
        directory = "${rustPkgs.cargoVendorDir}"
        CARGO_CONFIG

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
