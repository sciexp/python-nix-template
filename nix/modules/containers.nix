{
  inputs,
  lib,
  ...
}:
let
  gitHubOrg = "sciexp";
  repoName = "python-nix-template";

  # Production container definitions (nix2container)
  # Add new containers here; containerMatrix auto-discovers them.
  productionContainerDefs = {
    pnt-cli = {
      name = "pnt-cli";
      entrypoint = "pnt-cli";
      description = "pnt-cli with pyo3 native bindings";
    };
  };

  # Dev container image attribute names for manifest generation
  devContainerDefs = {
    ${repoName} = {
      imageAttr = "containerImage";
    };
    "${repoName}-dev" = {
      imageAttr = "devcontainerImage";
    };
  };
in
{
  perSystem =
    {
      config,
      self',
      inputs',
      pkgs,
      lib,
      system,
      packageWorkspaces,
      pythonSets,
      editablePythonSets,
      pythonVersions,
      ...
    }:
    let
      isLinux = pkgs.stdenv.isLinux;

      # --- Python environments ---

      defaultPythonVersion = "py312";
      defaultPythonSet = pythonSets.${defaultPythonVersion};
      defaultEditablePythonSet = editablePythonSets.${defaultPythonVersion};

      # Merge deps from all independent package workspaces, unioning extras lists
      # for shared dependency names rather than silently dropping via //
      defaultDeps = lib.foldlAttrs (
        acc: _: pkg:
        lib.zipAttrsWith (_: values: lib.unique (lib.flatten values)) [
          acc
          pkg.workspace.deps.default
        ]
      ) { } packageWorkspaces;
      allDeps = lib.foldlAttrs (
        acc: _: pkg:
        lib.zipAttrsWith (_: values: lib.unique (lib.flatten values)) [
          acc
          pkg.workspace.deps.all
        ]
      ) { } packageWorkspaces;

      defaultPythonEnv = defaultPythonSet.mkVirtualEnv "${repoName}-env" defaultDeps;
      defaultEditablePythonEnv = defaultEditablePythonSet.mkVirtualEnv "${repoName}-editable-env" allDeps;

      # --- Dev container infrastructure (nixpod/dockerTools, unchanged) ---

      buildMultiUserNixImage = import "${inputs.nixpod.outPath}/containers/nix.nix";

      containerUsername = "jovyan";
      containerUserInfo = {
        uid = 1000;
        gid = 0;
        uname = containerUsername;
        gname = "wheel";
      };

      containerSysPackages = with pkgs; [
        bashInteractive
        cacert
        coreutils
        direnv
        gnutar
        gzip
        less
        nix
        procps
        sudo
        zsh
      ];

      containerDevPackages = with pkgs; [
        git
        helix
        lazygit
        neovim
        starship
      ];

      mkBaseContainer =
        {
          name,
          tag ? "latest",
          pythonPackageEnv,
          extraContents ? [ ],
          extraPkgs ? [ ],
          extraEnv ? [ ],
          extraConfig ? { },
        }:
        buildMultiUserNixImage {
          inherit pkgs name tag;
          storeOwner = containerUserInfo;
          maxLayers = 121;
          fromImage = inputs'.nixpod.packages.sudoImage;
          compressor = "zstd";

          extraPkgs = containerSysPackages ++ extraPkgs ++ [ pythonPackageEnv ];
          extraContents = [
            inputs'.nixpod.legacyPackages.homeConfigurations.${containerUsername}.activationPackage
          ]
          ++ extraContents;

          extraFakeRootCommands = ''
            chown -R ${containerUsername}:wheel /nix
          '';

          nixConf = {
            allowed-users = [ "*" ];
            experimental-features = [
              "nix-command"
              "flakes"
            ];
            max-jobs = [ "auto" ];
            sandbox = "false";
            trusted-users = [
              "root"
              "${containerUsername}"
              "runner"
            ];
          };

          extraEnv = [
            "NB_USER=${containerUsername}"
            "NB_UID=1000"
            "NB_PREFIX=/"
            "LD_LIBRARY_PATH=${pythonPackageEnv}/lib:/usr/local/nvidia/lib64"
            "NVIDIA_DRIVER_CAPABILITIES='compute,utility'"
            "NVIDIA_VISIBLE_DEVICES=all"
            "QUARTO_PYTHON=${pythonPackageEnv}/bin/python"
          ]
          ++ extraEnv;

          extraConfig = {
            ExposedPorts."8888/tcp" = { };
          }
          // extraConfig;
        };

      # --- Production container infrastructure (nix2container) ---
      # Built natively per-system. Cross-compilation via pkgsCross for the
      # Python + maturin + Cargo stack is orthogonal and tracked separately.

      nix2container = inputs'.nix2container.packages.nix2container;
      skopeo-nix2container = inputs'.nix2container.packages.skopeo-nix2container;

      mkMultiArchManifest = pkgs.callPackage ../lib/mk-multi-arch-manifest.nix { };

      productionBaseLayer = nix2container.buildLayer {
        deps = [
          pkgs.bashInteractive
          pkgs.coreutils
          pkgs.cacert
        ];
      };

      mkProductionContainer =
        {
          name,
          entrypoint,
          pythonEnv ? defaultPythonEnv,
          tag ? "latest",
          description ? "",
        }:
        nix2container.buildImage {
          inherit name tag;
          layers = [ productionBaseLayer ];
          copyToRoot = pkgs.buildEnv {
            name = "${name}-root";
            paths = [
              pythonEnv
              pkgs.cacert
            ];
            pathsToLink = [
              "/bin"
              "/lib"
              "/etc"
            ];
          };
          config = {
            entrypoint = [ "${pythonEnv}/bin/${entrypoint}" ];
            Env = [
              "PATH=${pythonEnv}/bin:${pkgs.coreutils}/bin:${pkgs.bashInteractive}/bin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            Labels = {
              "org.opencontainers.image.description" = description;
              "org.opencontainers.image.source" = "https://github.com/${gitHubOrg}/${repoName}";
            };
          };
          maxLayers = 2;
        };

      productionContainerPackages = lib.mapAttrs' (
        containerName: def:
        lib.nameValuePair "${containerName}ProductionImage" (mkProductionContainer {
          inherit (def) name entrypoint description;
        })
      ) productionContainerDefs;

      # --- Manifest generation (crane-based, replaces flocken) ---
      # Env vars (require --impure): VERSION, TAGS, GITHUB_REF_NAME, GITHUB_ACTOR, GITHUB_TOKEN

      getEnvOr =
        var: default:
        let
          val = builtins.getEnv var;
        in
        if val == "" then default else val;

      getEnvList =
        var:
        let
          val = builtins.getEnv var;
        in
        if val == "" then [ ] else lib.splitString "," val;

      # Systems to include in multi-arch manifests
      includedSystems =
        let
          envVar = builtins.getEnv "NIX_IMAGE_SYSTEMS";
        in
        if envVar == "" then
          [
            "x86_64-linux"
            "aarch64-linux"
          ]
        else
          builtins.filter (sys: sys != "") (builtins.split " " envVar);

      manifestVersion = getEnvOr "VERSION" "0.0.0";
      manifestTags = getEnvList "TAGS";
      manifestBranch = getEnvOr "GITHUB_REF_NAME" "main";
      manifestUsername = getEnvOr "GITHUB_ACTOR" "cameronraysmith";

      # Production manifests use nix: transport (skopeo-nix2container)
      productionManifestPackages = lib.mapAttrs' (
        containerName: _def:
        lib.nameValuePair "${containerName}Manifest" (mkMultiArchManifest {
          name = containerName;
          images = lib.listToAttrs (
            map (sys: {
              name = sys;
              value = inputs.self.packages.${sys}."${containerName}ProductionImage";
            }) includedSystems
          );
          registry = {
            name = "ghcr.io";
            repo = "${gitHubOrg}/${repoName}/${containerName}";
            username = manifestUsername;
            password = "$GITHUB_TOKEN";
          };
          version = manifestVersion;
          tags = manifestTags;
          branch = manifestBranch;
          skopeo = skopeo-nix2container;
        })
      ) productionContainerDefs;

      # Dev manifests use docker-archive: transport (regular skopeo)
      devManifestPackages = lib.mapAttrs' (
        manifestName: def:
        lib.nameValuePair "${manifestName}Manifest" (mkMultiArchManifest {
          name = manifestName;
          images = lib.listToAttrs (
            map (sys: {
              name = sys;
              value = inputs.self.packages.${sys}.${def.imageAttr};
            }) includedSystems
          );
          registry = {
            name = "ghcr.io";
            repo = "${gitHubOrg}/${manifestName}";
            username = manifestUsername;
            password = "$GITHUB_TOKEN";
          };
          version = manifestVersion;
          tags = manifestTags;
          branch = manifestBranch;
          skopeo = pkgs.skopeo;
          mkSourceUri = image: "docker-archive:${image}";
        })
      ) devContainerDefs;

    in
    {
      packages = lib.optionalAttrs isLinux (
        {
          # Dev containers (nixpod/dockerTools, unchanged)
          containerImage = mkBaseContainer {
            name = repoName;
            pythonPackageEnv = defaultPythonEnv;
          };

          devcontainerImage = mkBaseContainer {
            name = "${repoName}-dev";
            pythonPackageEnv = defaultEditablePythonEnv;
            extraPkgs = containerDevPackages;
          };
        }
        // productionContainerPackages
        // productionManifestPackages
        // devManifestPackages
      );
    };

  # CI matrix data (pure evaluation): nix eval .#containerMatrix --json
  flake.containerMatrix = {
    build =
      (lib.mapAttrsToList (containerName: _: {
        package = "${containerName}ProductionImage";
        type = "production";
      }) productionContainerDefs)
      ++ (lib.mapAttrsToList (_: def: {
        package = def.imageAttr;
        type = "dev";
      }) devContainerDefs);
    manifest =
      (lib.mapAttrsToList (containerName: _: {
        name = containerName;
        type = "production";
      }) productionContainerDefs)
      ++ (lib.mapAttrsToList (manifestName: _: {
        name = manifestName;
        type = "dev";
      }) devContainerDefs);
  };
}
