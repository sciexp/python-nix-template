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
      pythonSets,
      editablePythonSets,
      pythonVersions,
      ...
    }:
    let
      # Merge deps from all independent package workspaces
      mergeWorkspaceDeps =
        selector:
        lib.foldlAttrs (
          acc: _: pkg:
          acc // (selector pkg.workspace.deps)
        ) { } packageWorkspaces;

      defaultDeps = mergeWorkspaceDeps (deps: deps.default);
    in
    {
      packages = rec {
        pythonNixTemplate311 = pythonSets.py311.mkVirtualEnv "python-nix-template-3.11" defaultDeps;
        pythonNixTemplate312 = pythonSets.py312.mkVirtualEnv "python-nix-template-3.12" defaultDeps;

        default = pythonNixTemplate312;
      };
    };
}
