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
      hasCli = builtins.pathExists ../packages/pnt-cli;

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
          packages =
            with pkgs;
            [
              just
              pixi
              quarto
              uv
              bun
              nodejs
              virtualenv
              age
              gitleaks
              sops
              ssh-to-age
            ]
            ++ lib.optionals hasCli (
              with pkgs;
              [
                # Rust tooling for pnt-cli pyo3 extension
                cargo
                rustc
                clippy
                cargo-nextest
                maturin
              ]
            );

          env = {
            UV_NO_SYNC = "1";
            UV_PYTHON = "${virtualenv}/bin/python";
            UV_PYTHON_DOWNLOADS = "never";
          };

          shellHook = ''
            unset PYTHONPATH
            export REPO_ROOT=$(git rev-parse --show-toplevel)
            export GIT_REPO_NAME=$(basename -s .git "$(git config --get remote.origin.url 2>/dev/null || echo "unknown-repo")")
            export GIT_REF=$(git symbolic-ref -q --short HEAD 2>/dev/null || git rev-parse HEAD 2>/dev/null || echo "unknown-ref")
            export GIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo "unknown-sha")
            export GIT_SHA_SHORT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
            printf "\n%s %s %s %s\n\n" "$GIT_REPO_NAME" "$GIT_REF" "$GIT_SHA_SHORT" "$GIT_SHA"
          '';
        };
    in
    {
      devShells = rec {
        pythonNixTemplate312 = mkDevShell {
          name = "python-nix-template-3.12";
          pythonVersion = "py312";
        };

        pythonNixTemplate313 = mkDevShell {
          name = "python-nix-template-3.13";
          pythonVersion = "py313";
        };

        default = pythonNixTemplate313;
      };
    };
}
