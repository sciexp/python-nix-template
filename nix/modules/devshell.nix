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
    , editablePythonSets
    , pythonVersions
    , ...
    }:
    let
      # Function to create development shell
      mkDevShell =
        { name
        , pythonVersion
        ,
        }:
        let
          # Get the actual Python interpreter first
          python = pythonVersions.${pythonVersion};
          # Then create the editable environment
          pythonEnv = editablePythonSets.${pythonVersion};
          virtualenv = pythonEnv.mkVirtualEnv "${name}-dev-env" baseWorkspace.deps.all;
        in
        pkgs.mkShell {
          inherit name;
          inputsFrom = [ config.pre-commit.devShell ];
          packages = with pkgs; [
            virtualenv
            uv
            just
          ];

          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = "${virtualenv}/bin/python";
            UV_PYTHON_DOWNLOADS = "never";
          };

          shellHook = ''
            unset PYTHONPATH
            export REPO_ROOT=$(git rev-parse --show-toplevel)
          '';
        };
    in
    {
      devShells = rec {
        # Create development shells for each Python version
        mypackage311 = mkDevShell {
          name = "mypackage-3.11";
          pythonVersion = "py311";
        };

        mypackage312 = mkDevShell {
          name = "mypackage-3.12";
          pythonVersion = "py312";
        };

        # Default shell uses Python 3.12
        default = mypackage312;
      };
    };
}
