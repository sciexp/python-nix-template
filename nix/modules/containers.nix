{
  inputs,
  ...
}:
{
  perSystem =
    {
      config,
      self',
      inputs',
      pkgs,
      lib,
      system,
      baseWorkspace,
      pythonSets,
      editablePythonSets,
      pythonVersions,
      ...
    }:
    let
      isLinux = pkgs.stdenv.isLinux;

      defaultPythonVersion = "py312";
      defaultPythonSet = pythonSets.${defaultPythonVersion};
      defaultEditablePythonSet = editablePythonSets.${defaultPythonVersion};

      defaultPythonEnv = defaultPythonSet.mkVirtualEnv "mypackage-env" baseWorkspace.deps.default;
      defaultEditablePythonEnv = defaultEditablePythonSet.mkVirtualEnv "mypackage-editable-env" baseWorkspace.deps.all;

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
          ] ++ extraContents;

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
          ] ++ extraEnv;

          extraConfig = {
            ExposedPorts."8888/tcp" = { };
          } // extraConfig;
        };

      gitHubOrg = "cameronraysmith";
      packageName = "python-nix-template";
      version = builtins.getEnv "VERSION";

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
    in
    {
      packages = lib.optionalAttrs isLinux {
        devcontainerImage = mkBaseContainer {
          name = "mypackage-dev";
          pythonPackageEnv = defaultEditablePythonEnv;
          extraPkgs = containerDevPackages;
        };

        containerImage = mkBaseContainer {
          name = "mypackage";
          pythonPackageEnv = defaultPythonEnv;
        };
      };

      legacyPackages = lib.optionalAttrs isLinux {
        containerManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
          inherit version;
          github = {
            enable = true;
            enableRegistry = true;
            token = "$GH_TOKEN";
          };
          autoTags.branch = false;
          registries = {
            "ghcr.io" = {
              repo = lib.mkForce "${gitHubOrg}/${packageName}";
            };
          };
          imageFiles = map (sys: inputs.self.packages.${sys}.containerImage) includedSystems;
          tags = [
            (builtins.getEnv "GIT_SHA_SHORT")
            (builtins.getEnv "GIT_SHA")
            (builtins.getEnv "GIT_REF")
            "dev"
          ];
        };

        devcontainerManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
          inherit version;
          github = {
            enable = true;
            enableRegistry = true;
            token = "$GH_TOKEN";
          };
          autoTags.branch = false;
          registries = {
            "ghcr.io" = {
              repo = lib.mkForce "${gitHubOrg}/${packageName}-dev";
            };
          };
          imageFiles = map (sys: inputs.self.packages.${sys}.devcontainerImage) includedSystems;
          tags = [
            (builtins.getEnv "GIT_SHA_SHORT")
            (builtins.getEnv "GIT_SHA")
            (builtins.getEnv "GIT_REF")
            "dev"
          ];
        };
      };
    };
}
