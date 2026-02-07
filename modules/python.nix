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

      hasFunctional = builtins.pathExists ../packages/pnt-functional;
      hasCli = builtins.pathExists ../packages/pnt-cli;

      packageWorkspaces = {
        python-nix-template = loadPackage "python-nix-template" ../packages/python-nix-template;
      }
      // lib.optionalAttrs hasCli {
        pnt-cli = loadPackage "pnt-cli" ../packages/pnt-cli;
      }
      // lib.optionalAttrs hasFunctional {
        pnt-functional = loadPackage "pnt-functional" ../packages/pnt-functional;
      };

      # Per-package Nix modules with optional Rust overlays.
      # Packages with Rust extensions get a dedicated module in nix/packages/
      # that encapsulates crane configuration and exports an overlay + checks.
      # When pnt-cli is absent (pyo3-package: false), returns an inert module
      # with no-op overlay and empty checks to avoid import path errors.
      emptyModule = {
        overlay = _final: _prev: { };
        checks = { };
      };

      mkPackageModule =
        python:
        if hasCli then
          import ../nix/packages/pnt-cli {
            inherit pkgs lib python;
            crane = inputs.crane;
            inherit (inputs) crane-maturin pyproject-nix;
          }
        else
          emptyModule;

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
              ++ lib.optional hasCli packageWorkspaces.pnt-cli.overlay
              ++ lib.optional hasFunctional packageWorkspaces.pnt-functional.overlay
              ++ [
                packageWorkspaces.python-nix-template.overlay
                # Rust integration overlay for pnt-cli (crane + maturin)
                (mkPackageModule python).overlay
                packageOverrides
                sdistOverrides
              ]
            )
          );

      # Editable set excludes pnt-cli: maturin packages are incompatible with
      # uv2nix's editable overlay (pyprojectFixupEditableHook expects EDITABLE_ROOT
      # which maturin's build process does not set). pnt-cli is built as a regular
      # wheel in the devshell; use `maturin develop` for iterative Rust development.
      mkEditablePythonSet =
        python:
        (mkPythonSet python).overrideScope (
          lib.composeManyExtensions (
            lib.optional hasFunctional packageWorkspaces.pnt-functional.editableOverlay
            ++ [
              packageWorkspaces.python-nix-template.editableOverlay
              (
                final: prev:
                {
                  python-nix-template = prev.python-nix-template.overrideAttrs (old: {
                    nativeBuildInputs =
                      old.nativeBuildInputs
                      ++ final.resolveBuildSystem {
                        editables = [ ];
                      };
                  });
                }
                // lib.optionalAttrs hasFunctional {
                  pnt-functional = prev.pnt-functional.overrideAttrs (old: {
                    nativeBuildInputs =
                      old.nativeBuildInputs
                      ++ final.resolveBuildSystem {
                        editables = [ ];
                      };
                  });
                }
              )
            ]
          )
        );

      pythonSets = lib.mapAttrs (_: mkPythonSet) pythonVersions;
      editablePythonSets = lib.mapAttrs (_: mkEditablePythonSet) pythonVersions;

      # Rust checks from per-package modules (using default Python version)
      rustChecks = (mkPackageModule pythonVersions.py313).checks;
    in
    {
      checks = lib.optionalAttrs hasCli rustChecks;

      _module.args = {
        inherit
          packageWorkspaces
          pythonSets
          editablePythonSets
          pythonVersions
          ;
        defaultPython = pythonVersions.py313;
      };
    };
}
