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
      packageOverrides ? (_: _: { }),
      sdistOverrides ? (_: _: { }),
      ...
    }:
    let
      pythonVersions = {
        py312 = pkgs.python312;
        py313 = pkgs.python313;
      };

      # Discover packages from packages/ directory. Each subdirectory is a
      # Python package. Packages containing Cargo.toml are maturin/pyo3
      # packages requiring a corresponding nix/packages/{name}/default.nix
      # module that exports { overlay, checks }.
      packageDirs = builtins.readDir ../packages;
      packageNames = builtins.filter (name: packageDirs.${name} == "directory") (
        builtins.attrNames packageDirs
      );

      isMaturin = name: builtins.pathExists (../packages + "/${name}/Cargo.toml");
      maturinPackageNames = builtins.filter isMaturin packageNames;
      purePackageNames = builtins.filter (name: !(isMaturin name)) packageNames;
      hasMaturinPackages = maturinPackageNames != [ ];

      # Load each Python package independently (no root workspace).
      # Each package directory contains its own pyproject.toml and uv.lock,
      # resolved independently following the LangChain federation model.
      loadPackage =
        name: path:
        let
          workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
            workspaceRoot = path;
          };
        in
        {
          inherit workspace;
          overlay = workspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          };
          editableOverlay = workspace.mkEditablePyprojectOverlay {
            root = "$REPO_ROOT/packages/${name}";
          };
        };

      packageWorkspaces = lib.genAttrs packageNames (name: loadPackage name (../packages + "/${name}"));

      # Per-package Nix modules with Rust overlays. Each maturin package
      # requires nix/packages/{name}/default.nix exporting { overlay, checks }.
      # Eval-time error when Cargo.toml exists but the module is missing.
      mkPackageModule =
        name: python:
        let
          modulePath = ../nix/packages + "/${name}/default.nix";
        in
        if builtins.pathExists modulePath then
          import modulePath {
            inherit pkgs lib python;
            crane = inputs.crane;
            inherit (inputs) crane-maturin pyproject-nix;
          }
        else
          throw "Maturin package ${name} requires nix/packages/${name}/default.nix";

      # Compose per-package uv2nix overlays with shared overrides.
      #
      # Invariant: all federated packages must resolve compatible versions for
      # shared dependencies. Per-package uv2nix overlays are composed sequentially
      # into a single package set — if two packages resolve different versions of
      # the same dependency, the later overlay silently wins. Enforce version
      # alignment across packages by running:
      #   uv lock --check
      # in each package directory after updating any shared dependency.
      mkPythonSet =
        python:
        (pkgs.callPackage inputs.pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (
            lib.composeManyExtensions (
              [
                inputs.pyproject-build-systems.overlays.default
              ]
              ++ map (name: packageWorkspaces.${name}.overlay) packageNames
              ++ map (name: (mkPackageModule name python).overlay) maturinPackageNames
              ++ [
                packageOverrides
                sdistOverrides
              ]
            )
          );

      # Editable set excludes maturin packages: maturin packages are
      # incompatible with uv2nix's editable overlay (pyprojectFixupEditableHook
      # expects EDITABLE_ROOT which maturin's build process does not set).
      # Maturin packages are built as regular wheels in the devshell; use
      # `maturin develop` for iterative Rust development.
      mkEditablePythonSet =
        python:
        (mkPythonSet python).overrideScope (
          lib.composeManyExtensions (
            map (name: packageWorkspaces.${name}.editableOverlay) purePackageNames
            ++ [
              (
                final: prev:
                lib.genAttrs purePackageNames (
                  name:
                  prev.${name}.overrideAttrs (old: {
                    nativeBuildInputs =
                      old.nativeBuildInputs
                      ++ final.resolveBuildSystem {
                        editables = [ ];
                      };
                  })
                )
              )
            ]
          )
        );

      pythonSets = lib.mapAttrs (_: mkPythonSet) pythonVersions;
      editablePythonSets = lib.mapAttrs (_: mkEditablePythonSet) pythonVersions;

      # Rust checks from per-package modules (using default Python version)
      rustChecks = lib.foldl' (
        acc: name: acc // (mkPackageModule name pythonVersions.py313).checks
      ) { } maturinPackageNames;
    in
    {
      checks = lib.optionalAttrs hasMaturinPackages rustChecks;

      _module.args = {
        inherit
          packageWorkspaces
          pythonSets
          editablePythonSets
          pythonVersions
          packageNames
          maturinPackageNames
          purePackageNames
          hasMaturinPackages
          ;
        defaultPython = pythonVersions.py313;
      };
    };
}
