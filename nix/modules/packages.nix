{ inputs
, ...
}:
{
  perSystem =
    { config
    , self'
    , pkgs
    , lib
    , baseWorkspace
    , pythonSets
    , editablePythonSets
    , pythonVersions
    , ...
    }:
    {
      # nix build
      packages = rec {
        mypackage311 = pythonSets.py311.mkVirtualEnv "mypackage-3.11" baseWorkspace.deps.default;
        mypackage312 = pythonSets.py312.mkVirtualEnv "mypackage-3.12" baseWorkspace.deps.default;

        default = mypackage312;
      };

      # nix run
      # apps = {
      #   default = {
      #     type = "app";
      #     program = "${pkgs.lib.getExe self'.packages.default}";
      #   };
      # };

      # defer to pre-commit
      # formatter = pkgs.nixfmt-rfc-style;
    };
}
