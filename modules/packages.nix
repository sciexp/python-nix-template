{
  perSystem =
    {
      lib,
      packageWorkspaces,
      pythonSets,
      packageNames,
      maturinPackageNames,
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

      # Per-package production output: a pure package resolves to a minimal venv
      # containing only that package and its runtime closure (no dev groups); a
      # maturin package resolves to its installed wheel node. Every discovered
      # package is exposed so the structural-traceability invariant can assert
      # packages.<system> coverage by name.
      perPackageOutput =
        name:
        if builtins.elem name maturinPackageNames then
          pythonSets.py313.${name}
        else
          pythonSets.py313.mkVirtualEnv name { ${name} = [ ]; };

      packageOutputs = lib.genAttrs packageNames perPackageOutput;
    in
    {
      packages = packageOutputs // {
        pntCore312 = pythonSets.py312.mkVirtualEnv "pnt-core-3.12" defaultDeps;
        pntCore313 = pythonSets.py313.mkVirtualEnv "pnt-core-3.13" defaultDeps;

        default = pythonSets.py313.mkVirtualEnv "pnt-core-3.13" defaultDeps;
      };
    };
}
