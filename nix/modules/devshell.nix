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
      baseWorkspace,
      editablePythonSets,
      pythonVersions,
      ...
    }:
    let
      # Function to create development shell
      mkDevShell =
        {
          name,
          pythonVersion,
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
            just
            pixi
            teller
            uv
            virtualenv
            config.packages.set-git-env
          ];

          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = "${virtualenv}/bin/python";
            UV_PYTHON_DOWNLOADS = "never";
          };

          shellHook = ''
            unset PYTHONPATH
            export REPO_ROOT=$(git rev-parse --show-toplevel)
            set-git-env
          '';
        };
    in
    {
      devShells = rec {
        # Create development shells for each Python version
        pythonNixTemplate311 = mkDevShell {
          name = "python-nix-template-3.11";
          pythonVersion = "py311";
        };

        pythonNixTemplate312 = mkDevShell {
          name = "python-nix-template-3.12";
          pythonVersion = "py312";
        };

        # Default shell uses Python 3.12
        default = pythonNixTemplate312;
      };
    };
}
