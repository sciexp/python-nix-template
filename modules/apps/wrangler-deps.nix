{
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      # bun2nix builds the wrangler node_modules tree hermetically from the
      # checked-in bun.lock + bun.nix, sidestepping the nixpkgs `wrangler`
      # source build (broken on aarch64-darwin: its `pnpm tsup` /
      # generate-json-schema phase fails with EBADF, and it is not cached for
      # darwin). The published wrangler npm package ships a prebuilt bin, so no
      # native compile happens here.
      bun2nix = inputs.bun2nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    in
    {
      packages.wrangler-deps = pkgs.stdenv.mkDerivation {
        pname = "wrangler-deps";
        version = "0.0.0";

        src = lib.fileset.toSource {
          root = ../..;
          fileset = lib.fileset.unions [
            ../../package.json
            ../../bun.lock
            ../../bun.nix
          ];
        };

        nativeBuildInputs = [ bun2nix.hook ];

        bunDeps = bun2nix.fetchBunDeps {
          bunNix = ../../bun.nix;
        };

        # wrangler and its @cloudflare/* tooling are consumed at runtime as pure
        # JS plus the prebuilt workerd binary; no postinstall lifecycle script
        # needs to run to materialise a usable node_modules/.bin/wrangler.
        dontRunLifecycleScripts = true;

        # The bun2nix hook materialises node_modules via
        # bunNodeModulesInstallPhase. Preserving its symlink layout with a plain
        # cp -R keeps Node module resolution intact for node_modules/.bin/wrangler.
        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          runHook preInstall
          if [ ! -e node_modules/.bin/wrangler ]; then
            echo "error: node_modules/.bin/wrangler not populated by bun install; aborting" >&2
            exit 1
          fi
          mkdir -p "$out"
          cp -R node_modules "$out/node_modules"
          runHook postInstall
        '';

        meta = {
          description = "Hermetic node_modules tree providing the wrangler CLI for deploy-sites.";
          license = lib.licenses.mit;
        };
      };
    };
}
