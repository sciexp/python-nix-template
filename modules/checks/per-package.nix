# Uniform per-package check harvest.
#
# Both pure and maturin packages expose passthru.tests on their package node:
# pure packages via modules/python.nix pyprojectTestOverrides, pnt-cli via
# crane-maturin (nix/packages/pnt-cli/default.nix). A single fold over
# pythonSets.py313.<pkg>.passthru.tests, renaming each entry to <pkg>-<check>,
# produces the entire per-package check set with one naming convention.
#
# Harvest is at py313 only (matching defaultPython). Fanning every check across
# py312+py313 is a one-line change (concatMapAttrs over pythonSets) for
# downstream repos that need matrix coverage.
{
  perSystem =
    {
      pkgs,
      lib,
      pythonSets,
      packageNames,
      purePackageNames,
      maturinPackageNames,
      ...
    }:
    let
      checkSet = pythonSets.py313;

      harvest =
        drops: name:
        lib.mapAttrs' (checkName: drv: lib.nameValuePair "${name}-${checkName}" drv) (
          builtins.removeAttrs (checkSet.${name}.passthru.tests or { }) drops
        );

      packageChecks =
        lib.foldl' (acc: name: acc // harvest [ ] name) { } purePackageNames
        // lib.foldl' (
          acc: name:
          acc
          // harvest [
            "test-coverage"
            "pytest-coverage"
          ] name
        ) { } maturinPackageNames;

      # Per-package ruff lint check. Runs ruff against the package's src/
      # directory using the repository-root ruff.toml via --config, keeping lint
      # configuration centralized. No virtual environment is required since ruff
      # is a standalone binary, so it is a thin top-level builder rather than a
      # passthru.tests entry.
      mkRuffCheck =
        name:
        pkgs.runCommand "${name}-ruff"
          {
            nativeBuildInputs = [ pkgs.ruff ];
            src = lib.cleanSource (../../packages + "/${name}");
          }
          ''
            cd "$src"
            ruff check --no-cache --config ${../../ruff.toml} src/
            touch "$out"
          '';

      ruffChecks = lib.foldl' (
        acc: name:
        acc
        // {
          "${name}-ruff" = mkRuffCheck name;
        }
      ) { } packageNames;
    in
    {
      checks = packageChecks // ruffChecks;
    };
}
