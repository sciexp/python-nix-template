{
  perSystem =
    {
      config,
      pkgs,
      lib,
      pythonSets,
      ...
    }:
    let
      # Docs venv: pnt_core plus its `docs` dependency group (quartodoc, jupyter,
      # jupyter-cache). Built from the same production pythonSet that backs
      # modules/packages.nix, so the single-set property holds — no check or app
      # re-derives the package set. The plain pntCore313 venv carries runtime
      # deps only and lacks quartodoc; this dedicated venv adds the docs group.
      docsVenv = pythonSets.py313.mkVirtualEnv "pnt-docs-env" {
        pnt-core = [ "docs" ];
      };

      # Hermetic dvc with the s3 remote plugin baked in. The top-level `dvc`
      # derivation does not expose an `enableS3` knob, so the s3 backend is
      # supplied by co-installing dvc-s3 into a python env; the resulting
      # `bin/dvc` runs with `dvc_s3` importable, matching `uvx --with dvc-s3 dvc`
      # without fetching anything at runtime.
      dvcWithS3 = pkgs.python3.withPackages (ps: [
        ps.dvc
        ps.dvc-s3
      ]);

      # Bake the docs source needed for a runtime build+deploy. Restricted to
      # git-tracked files so generated artifacts excluded by docs/.gitignore
      # (_site, _inv, reference/, _freeze/, objects.txt) never leak into the
      # closure; docs/_freeze.dvc IS tracked and is the DVC pointer pulled at
      # runtime.
      docsSrc = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.intersection (lib.fileset.gitTracked ../..) (
          lib.fileset.unions [
            ../../.dvc/config
            ../../wrangler.jsonc
            ../../docs
          ]
        );
      };

      deploySites = pkgs.writeShellApplication {
        name = "deploy-sites";
        # Secrets flow via inherited env (CLOUDFLARE_*/AWS_*), never via
        # `sops exec-env` inside the script. sed/awk/grep/find are declared
        # explicitly because a hercules-ci-effects bwrap sandbox PATH does not
        # include them by default, and writeShellApplication pins PATH to
        # runtimeInputs at runtime.
        runtimeInputs = [
          config.packages.quarto
          docsVenv
          dvcWithS3
          pkgs.nodejs
          pkgs.jq
          pkgs.git
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.gawk
          pkgs.findutils
        ];
        runtimeEnv = {
          DOCS_SRC = "${docsSrc}";
          # quarto's wrapper sets QUARTO_PYTHON only with --set-default, so this
          # value (the docs venv carrying quartodoc + pnt_core) wins at runtime
          # without needing a python3=null quarto override (which would force
          # `null.withPackages` and break evaluation).
          QUARTO_PYTHON = "${docsVenv}/bin/python3";
          # wrangler comes from the bun2nix-built deps tree, not nixpkgs
          # `wrangler` (whose source build is broken and uncached on
          # aarch64-darwin); the .sh runs it as `node "$WRANGLER"`.
          WRANGLER = "${config.packages.wrangler-deps}/node_modules/.bin/wrangler";
        };
        text = builtins.readFile ./deploy-sites.sh;
      };
    in
    {
      # Exposed as both a package and an app: `nix build .#deploy-sites` builds
      # the closure (the acceptance check) and `nix run .#deploy-sites` invokes
      # it, both backed by the single writeShellApplication derivation.
      packages.deploy-sites = deploySites;
      apps.deploy-sites = {
        type = "app";
        meta.description = "Build the python-nix-template quarto docs site at runtime and deploy it to Cloudflare Workers (preview or production).";
        program = lib.getExe deploySites;
      };
    };
}
