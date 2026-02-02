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
      packageWorkspaces,
      editablePythonSets,
      pythonVersions,
      ...
    }:
    let
      # Merge deps from all independent package workspaces, unioning extras lists
      # for shared dependency names rather than silently dropping via //
      allDeps = lib.foldlAttrs (
        acc: _: pkg:
        lib.zipAttrsWith (_: values: lib.unique (lib.flatten values)) [
          acc
          pkg.workspace.deps.all
        ]
      ) { } packageWorkspaces;

      mkDevShell =
        {
          name,
          pythonVersion,
        }:
        let
          python = pythonVersions.${pythonVersion};
          pythonEnv = editablePythonSets.${pythonVersion};
          virtualenv = pythonEnv.mkVirtualEnv "${name}-dev-env" allDeps;
        in
        pkgs.mkShell {
          inherit name;
          inputsFrom = [ config.pre-commit.devShell ];
          packages = with pkgs; [
            just
            pixi
            quarto
            teller
            uv
            yarn-berry
            virtualenv
            age
            sops
            ssh-to-age
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
        pythonNixTemplate311 = mkDevShell {
          name = "python-nix-template-3.11";
          pythonVersion = "py311";
        };

        pythonNixTemplate312 = mkDevShell {
          name = "python-nix-template-3.12";
          pythonVersion = "py312";
        };

        default = pythonNixTemplate312;
      };
    };
}
