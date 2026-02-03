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
        py311 = pkgs.python311;
        py312 = pkgs.python312;
      };

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
            root = "$REPO_ROOT";
          };
        };

      packageWorkspaces = {
        pnt-cli = loadPackage "pnt-cli" ../../packages/pnt-cli;
        pnt-functional = loadPackage "pnt-functional" ../../packages/pnt-functional;
        python-nix-template = loadPackage "python-nix-template" ../../packages/python-nix-template;
      };

      # Per-package Nix modules with optional Rust overlays.
      # Packages with Rust extensions get a dedicated module in nix/packages/
      # that encapsulates crane configuration and exports an overlay + checks.
      mkPackageModule =
        python:
        import ../packages/pnt-cli {
          inherit pkgs lib python;
          crane = inputs.crane;
        };

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
            lib.composeManyExtensions [
              inputs.pyproject-build-systems.overlays.default
              packageWorkspaces.pnt-cli.overlay
              packageWorkspaces.pnt-functional.overlay
              packageWorkspaces.python-nix-template.overlay
              # Rust integration overlay for pnt-cli (crane + maturin)
              (mkPackageModule python).overlay
              packageOverrides
              sdistOverrides
            ]
          );

      mkEditablePythonSet =
        python:
        (mkPythonSet python).overrideScope (
          lib.composeManyExtensions [
            packageWorkspaces.pnt-cli.editableOverlay
            packageWorkspaces.pnt-functional.editableOverlay
            packageWorkspaces.python-nix-template.editableOverlay
            (final: prev: {
              pnt-cli = prev.pnt-cli.overrideAttrs (old: {
                nativeBuildInputs =
                  old.nativeBuildInputs
                  ++ final.resolveBuildSystem {
                    editables = [ ];
                  };
              });
              python-nix-template = prev.python-nix-template.overrideAttrs (old: {
                nativeBuildInputs =
                  old.nativeBuildInputs
                  ++ final.resolveBuildSystem {
                    editables = [ ];
                  };
              });
              pnt-functional = prev.pnt-functional.overrideAttrs (old: {
                nativeBuildInputs =
                  old.nativeBuildInputs
                  ++ final.resolveBuildSystem {
                    editables = [ ];
                  };
              });
            })
          ]
        );

      pythonSets = lib.mapAttrs (_: mkPythonSet) pythonVersions;
      editablePythonSets = lib.mapAttrs (_: mkEditablePythonSet) pythonVersions;

      # Rust checks from per-package modules (using default Python version)
      rustChecks = (mkPackageModule pythonVersions.py312).checks;
    in
    {
      checks = rustChecks;

      _module.args = {
        inherit
          packageWorkspaces
          pythonSets
          editablePythonSets
          pythonVersions
          ;
        defaultPython = pythonVersions.py312;
      };
    };
}
