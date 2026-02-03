# Python + Rust composition for pnt-cli.
#
# Imports rust.nix for crane derivations, then creates a Python package
# overlay that injects vendored cargo deps into the uv2nix-generated pnt-cli
# derivation. Crane's cargoArtifacts caching applies to the Rust-only check
# derivations (clippy, nextest); the maturin wheel build compiles Rust from
# source within the pyproject.nix derivation using vendored dependencies.
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

      # Configure cargo to use crane's vendored dependencies for offline builds.
      # Crane's vendorCargoDeps output includes a config.toml with source
      # replacement directives pointing to the vendored crate store paths.
      preBuild = ''
        mkdir -p .cargo
        cp ${rustPkgs.cargoVendorDir}/config.toml .cargo/config.toml
      '';

      env.PYO3_PYTHON = python.interpreter;
    });
  };

  checks = {
    pnt-cli-clippy = rustPkgs.clippy;
    pnt-cli-nextest = rustPkgs.nextest;
  };
}
