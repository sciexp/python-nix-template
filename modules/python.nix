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

      # Pytest check for a pure Python package using the uv2nix-resolved venv.
      # The virtual env includes the package itself plus its default dependency
      # groups (test, lint, types per pyproject.toml [tool.uv] default-groups),
      # providing pytest, pytest-cov, hypothesis, xdoctest, and beartype for
      # packages that list it as a runtime dependency.
      #
      # When beartypePackage is set to the Python import path (e.g. "pnt_functional"),
      # activates beartype's package-wide import hook by injecting a conftest.py with
      # beartype.claw.beartype_package so all callables are runtime type-checked, not
      # only those carrying an explicit @beartype decorator. BEARTYPE_HOOK_PACKAGE in
      # the derivation environment records the activation target for inspection via
      # nix derivation show.
      mkPurePytestCheck =
        {
          name,
          python,
          beartypePackage ? null,
        }:
        let
          pythonSet = mkPythonSet python;
          workspace = packageWorkspaces.${name}.workspace;
          testEnv = pythonSet.mkVirtualEnv "${name}-test-env" workspace.deps.default;
          beartypeConftestFile =
            if beartypePackage != null then
              pkgs.writeText "beartype-conftest.py" ''
                from beartype.claw import beartype_package
                beartype_package("${beartypePackage}")
              ''
            else
              null;
        in
        pkgs.stdenv.mkDerivation (
          {
            name = "${name}-pytest";
            src = lib.cleanSource (../packages + "/${name}");
            nativeBuildInputs = [ testEnv ];
            buildPhase = ''
              runHook preBuild
              ${if beartypeConftestFile != null then "cp ${beartypeConftestFile} conftest.py" else ""}
              pytest
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              touch $out
              runHook postInstall
            '';
          }
          // lib.optionalAttrs (beartypePackage != null) {
            BEARTYPE_HOOK_PACKAGE = beartypePackage;
          }
        );

      pureChecks = lib.foldl' (
        acc: name:
        acc
        // {
          "${name}-pytest" = mkPurePytestCheck {
            inherit name;
            python = pythonVersions.py313;
            beartypePackage = if name == "pnt-functional" then "pnt_functional" else null;
          };
        }
      ) { } purePackageNames;

      # Per-package ruff lint check. Runs ruff check against the package's
      # src/ directory using the repository-root ruff.toml via --config,
      # keeping lint configuration centralized. No Python virtual environment
      # is required since ruff is a standalone binary. Applied to all packages
      # (pure and maturin) that contain Python source under src/.
      mkRuffCheck =
        name:
        pkgs.runCommand "${name}-ruff"
          {
            nativeBuildInputs = [ pkgs.ruff ];
            src = lib.cleanSource (../packages + "/${name}");
          }
          ''
            cd "$src"
            ruff check --no-cache --config ${../ruff.toml} src/
            touch "$out"
          '';

      ruffChecks = lib.foldl' (
        acc: name:
        acc
        // {
          "${name}-ruff" = mkRuffCheck name;
        }
      ) { } packageNames;

      # Net-new basedpyright type-checking derivation covering the full pure-Python
      # source tree. Merges default dependency groups from all pure packages into a
      # single virtual environment so basedpyright resolves beartype, expression, and
      # other runtime imports. The --pythonpath flag points at the venv Python wrapper
      # so basedpyright discovers the correct sys.path including installed package stubs.
      basedpyrightCheck =
        let
          pythonSet = mkPythonSet pythonVersions.py313;
          mergedDeps = lib.foldl' (
            acc: name: acc // packageWorkspaces.${name}.workspace.deps.default
          ) { } purePackageNames;
          typeEnv = pythonSet.mkVirtualEnv "basedpyright-env" mergedDeps;
        in
        pkgs.runCommand "basedpyright"
          {
            nativeBuildInputs = [
              pkgs.basedpyright
              typeEnv
            ];
            src = inputs.self;
          }
          ''
            cd "$src"
            basedpyright \
              --pythonpath "$(command -v python3)" \
              ${lib.concatMapStrings (name: "packages/${name}/src ") purePackageNames}
            touch "$out"
          '';
    in
    {
      checks = rustChecks // pureChecks // ruffChecks // { basedpyright = basedpyrightCheck; };

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
