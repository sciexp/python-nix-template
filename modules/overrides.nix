{
  inputs,
  ...
}:
{
  perSystem =
    {
      config,
      self',
      pkgs,
      lib,
      ...
    }:
    let
      # Function to create package-specific overrides
      mkPackageOverrides =
        { pkgs }:
        final: prev: {
          # Example overrides for specific packages
          # numpy = prev.numpy.overrideAttrs (old: {
          #   buildInputs = (old.buildInputs or []) ++ [ pkgs.openblas ];
          # });

          # Example of fixing a package that needs specific build system dependencies
          # tensorflow = prev.tensorflow.overrideAttrs (old: {
          #   nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
          #     (final.resolveBuildSystem {
          #       setuptools = [];
          #       wheel = [];
          #       numpy = [];
          #     })
          #   ];
          # });
        };

      # Function to create sdist-specific overrides
      mkSdistOverrides =
        { pkgs }:
        final: prev: {
          # Example overrides for source distributions
          # pyzmq = prev.pyzmq.overrideAttrs (old: {
          #   buildInputs = (old.buildInputs or []) ++ [ pkgs.zeromq ];
          #   nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
          #     (final.resolveBuildSystem {
          #       cmake = [];
          #       ninja = [];
          #       packaging = [];
          #     })
          #   ];
          # });
        };
    in
    {
      # Expose the override functions for use in other modules
      _module.args = {
        packageOverrides = mkPackageOverrides { inherit pkgs; };
        sdistOverrides = mkSdistOverrides { inherit pkgs; };
      };
    };
}
