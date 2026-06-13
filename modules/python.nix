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

      # Pinned Rust toolchain via oxalica/rust-overlay, applied to the perSystem
      # pkgs with `.extend` (the canonical flake-parts overlay pattern; a sibling
      # module cannot override perSystem `_module.args.pkgs` past flake-parts'
      # default). Tracks this template's own rust-toolchain.toml as the source of
      # truth: rustToolchainVersion is a nix constant kept in lockstep with
      # rust-toolchain.toml `channel` at 1.94.1; extensions mirror that file's
      # `components` plus the crane-needed llvm-tools-preview. Threaded into the
      # pnt-cli crane call via mkPackageModule and exported through _module.args
      # for devshell.nix.
      rustPkgs = pkgs.extend (import inputs.rust-overlay);
      rustToolchainVersion = "1.94.1";
      rustToolchain = rustPkgs.rust-bin.stable.${rustToolchainVersion}.default.override {
        extensions = [
          "rust-src"
          "rust-analyzer"
          "clippy"
          "rustfmt"
          "llvm-tools-preview"
        ];
      };

      # Discover packages from packages/ directory. Each subdirectory is a
      # Python package. Packages containing Cargo.toml are maturin/pyo3
      # packages requiring a corresponding nix/packages/{name}/default.nix
      # module that exports { overlay }.
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
      # requires nix/packages/{name}/default.nix exporting { overlay }.
      # Eval-time error when Cargo.toml exists but the module is missing.
      mkPackageModule =
        name: python:
        let
          modulePath = ../nix/packages + "/${name}/default.nix";
        in
        if builtins.pathExists modulePath then
          import modulePath {
            inherit
              pkgs
              lib
              python
              rustToolchain
              ;
            crane = inputs.crane;
            inherit (inputs) crane-maturin pyproject-nix;
          }
        else
          throw "Maturin package ${name} requires nix/packages/${name}/default.nix";

      # Per-package import path for beartype's package-wide claw hook. When a
      # pure package is listed here, its pytest derivation injects a conftest.py
      # calling beartype.claw.beartype_package so all callables are runtime
      # type-checked, not only those carrying an explicit @beartype decorator.
      beartypeTargets = {
        pnt-functional = "pnt_functional";
      };

      # Overlay factory attaching passthru.tests to each pure package node,
      # composed LAST into mkPythonSet's overrideScope chain. The test venvs are
      # built by `final.mkVirtualEnv` against the same fixpoint that produced the
      # package, so the single-set property is structural rather than
      # disciplinary: no check re-derives the package set. Each venv is built from
      # a single dedicated dependency group (`{ <pkg> = [ "<group>" ]; }`) rather
      # than deps.default, isolating the tools each check needs.
      #
      #   pytest     -> built from the package's `test` group; bare `pytest` picks
      #                 up coverage flags from [tool.pytest.ini_options] addopts.
      #   basedpyright-> built from the package's `typecheck` group; run per-package
      #                 against that package's src so a missing dependency in one
      #                 package is not masked by another package's closure.
      pyprojectTestOverrides =
        _python: final: prev:
        let
          inherit (final) mkVirtualEnv;

          mkPureTests =
            name:
            let
              beartypePkg = beartypeTargets.${name} or null;
              testVenv = mkVirtualEnv "${name}-pytest-env" { ${name} = [ "test" ]; };
              # The typecheck venv carries both `typecheck` (basedpyright) and
              # `test`: basedpyright scans the whole src/ tree including
              # src/<pkg>/tests, whose modules import the test toolchain, so those
              # imports must resolve for type-checking to succeed.
              typecheckVenv = mkVirtualEnv "${name}-typecheck-env" {
                ${name} = [
                  "typecheck"
                  "test"
                ];
              };
              beartypeConftest = pkgs.writeText "beartype-conftest.py" ''
                from beartype.claw import beartype_package
                beartype_package("${beartypePkg}")
              '';
            in
            (prev.${name}.passthru.tests or { })
            // {
              pytest = pkgs.stdenv.mkDerivation (
                {
                  name = "${final.${name}.name}-pytest";
                  inherit (final.${name}) src;
                  nativeBuildInputs = [ testVenv ];
                  dontConfigure = true;
                  buildPhase = ''
                    runHook preBuild
                    ${lib.optionalString (beartypePkg != null) "cp ${beartypeConftest} conftest.py"}
                    pytest
                    runHook postBuild
                  '';
                  installPhase = ''
                    runHook preInstall
                    touch $out
                    runHook postInstall
                  '';
                }
                // lib.optionalAttrs (beartypePkg != null) {
                  BEARTYPE_HOOK_PACKAGE = beartypePkg;
                }
              );

              basedpyright =
                pkgs.runCommand "${final.${name}.name}-basedpyright"
                  {
                    nativeBuildInputs = [
                      pkgs.basedpyright
                      typecheckVenv
                    ];
                  }
                  ''
                    cd ${final.${name}.src}
                    basedpyright --pythonpath "$(command -v python3)" src/
                    touch "$out"
                  '';
            };
        in
        lib.genAttrs purePackageNames (
          name:
          prev.${name}.overrideAttrs (old: {
            passthru = (old.passthru or { }) // {
              tests = mkPureTests name;
            };
          })
        );

      # Compose per-package uv2nix overlays with shared overrides.
      #
      # Invariant: all federated packages must resolve compatible versions for
      # shared dependencies. Per-package uv2nix overlays are composed sequentially
      # into a single package set — if two packages resolve different versions of
      # the same dependency, the later overlay silently wins. Enforce version
      # alignment across packages by running:
      #   uv lock --check
      # in each package directory after updating any shared dependency.
      #
      # pyprojectTestOverrides is composed last so user packageOverrides/
      # sdistOverrides remain visible to the test venv inputs.
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
                (pyprojectTestOverrides python)
              ]
            )
          );

      # Editable set excludes maturin packages: maturin packages are
      # incompatible with uv2nix's editable overlay (pyprojectFixupEditableHook
      # expects EDITABLE_ROOT which maturin's build process does not set).
      # Maturin packages are built as regular wheels in the devshell; use
      # `maturin develop` for iterative Rust development.
      #
      # The editable set backs only the dev shell. Checks and the packages output
      # consume the production pythonSets exclusively; an editable venv must never
      # back a check (editable installs point at the mutable tree, breaking
      # hermeticity).
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
    in
    {
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
          rustToolchain
          ;
        defaultPython = pythonVersions.py313;
      };
    };
}
