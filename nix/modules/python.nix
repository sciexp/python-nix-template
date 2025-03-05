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
      # Define supported Python versions
      pythonVersions = {
        py311 = pkgs.python311;
        py312 = pkgs.python312;
      };

      # Create workspace once - this is our pure functional core
      baseWorkspace = inputs.uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./../..;
      };

      # Function to create overlay with fixed preferences
      makeOverlay =
        workspace:
        workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };

      # Function to create editable overlay
      makeEditableOverlay =
        workspace:
        workspace.mkEditablePyprojectOverlay {
          root = "$REPO_ROOT";
        };

      # Function to create Python package set
      mkPythonSet =
        python:
        (pkgs.callPackage inputs.pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (
            lib.composeManyExtensions [
              inputs.pyproject-build-systems.overlays.default
              (makeOverlay baseWorkspace)
              packageOverrides
              sdistOverrides
            ]
          );

      # Function to create editable Python package set
      mkEditablePythonSet =
        python:
        (mkPythonSet python).overrideScope (
          lib.composeManyExtensions [
            (makeEditableOverlay baseWorkspace)
            (final: prev: {
              python-nix-template = prev.python-nix-template.overrideAttrs (old: {
                src = lib.fileset.toSource {
                  root = old.src;
                  fileset = lib.fileset.unions [
                    (old.src + "/pyproject.toml")
                    (old.src + "/README.md")
                    (old.src + "/src/python_nix_template/__init__.py")
                  ];
                };
                nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem { editables = [ ]; };
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

      # Create package sets for each Python version
      pythonSets = lib.mapAttrs (_: mkPythonSet) pythonVersions;
      editablePythonSets = lib.mapAttrs (_: mkEditablePythonSet) pythonVersions;
    in
    {
      # Expose constructed package sets for use in other modules
      _module.args = {
        inherit
          baseWorkspace
          pythonSets
          editablePythonSets
          pythonVersions
          ;
        defaultPython = pythonVersions.py312;
      };
    };
}
