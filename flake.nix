{
  description = "python-nix-template integrating uv2nix with flake-parts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flocken = {
      url = "github:mirkolenz/flocken/v2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpod = {
      url = "github:cameronraysmith/nixpod/00-lock";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.flocken.follows = "flocken";
    };

    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.flake = false;
  };

  nixConfig = {
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "pyproject-nix.cachix.org-1:UNzugsOlQIu2iOz0VyZNBQm2JSrL/kwxeCcFGw+jMe0="
      "sciexp.cachix.org-1:HaliIGqJrFN7CDrzYVHqWS4uSISorWAY1bWNmNl8T08="
    ];
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://pyproject-nix.cachix.org"
      "https://sciexp.cachix.org"
    ];
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # https://github.com/NixOS/nixpkgs/blob/24.05/lib/systems/flake-systems.nix
      # systems = nixpkgs.lib.systems.flakeExposed; # tiered list of feasible systems
      # https://github.com/nix-systems/default # plausible systems
      # systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux" ];
      systems = import inputs.systems;

      imports = with builtins; map (fn: ./nix/modules/${fn}) (attrNames (readDir ./nix/modules));
    };
}
