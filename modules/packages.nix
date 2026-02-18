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
      # Merge deps from all independent package workspaces, unioning extras lists
      # for shared dependency names rather than silently dropping via //
      mergeWorkspaceDeps =
        selector:
        lib.foldlAttrs (
          acc: _: pkg:
          lib.zipAttrsWith (_: values: lib.unique (lib.flatten values)) [
            acc
            (selector pkg.workspace.deps)
          ]
        ) { } packageWorkspaces;

      defaultDeps = mergeWorkspaceDeps (deps: deps.default);
    in
    {
      packages = rec {
        pntCore312 = pythonSets.py312.mkVirtualEnv "pnt-core-3.12" defaultDeps;
        pntCore313 = pythonSets.py313.mkVirtualEnv "pnt-core-3.13" defaultDeps;

        default = pntCore313;
      };
    };
}
