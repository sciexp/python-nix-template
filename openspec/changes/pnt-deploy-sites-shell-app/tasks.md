## 1. pnt-docs derivation

- [ ] 1.1 Add `modules/docs.nix` defining `perSystem.packages.pnt-docs` as a `stdenv.mkDerivation` taking `pkgs.quarto`, the uv2nix venv `config.packages.pntCore313`, and a `lib.fileset`-scoped `docs/` source; run `quartodoc build` then `quarto render docs` to produce `_site`. Keep it a direct perSystem module, not pkgs-by-name (see design.md D1).
- [ ] 1.2 Vendor the external Sphinx `objects.inv` interlink inventories (python.org/beartype/matplotlib/numpy) as fixed-output derivations (likely a `nix/` helper), or accept graceful offline interlinks degradation (design.md D5).
- [ ] 1.3 Verify acceptance: `nix build .#pnt-docs` yields a stable `_site` with a sane `index.html`, and `nix flake check` is green.

## 2. deploy-sites app

- [ ] 2.1 Add `modules/apps/deploy-sites.nix` (`perSystem.apps.deploy-sites` as a `writeShellApplication`) and `modules/apps/deploy-sites.sh` porting the justfile preview/production wrangler logic: preview = `wrangler versions upload --preview-alias b-<safe-branch> --tag <sha12>`; production = version-promotion by the `workers/tag` sha12 annotation, else `wrangler deploy`.
- [ ] 2.2 Run wrangler under real `node`, not bun; read credentials from inherited env `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID`.
- [ ] 2.3 Verify acceptance: `nix run .#deploy-sites -- preview <branch>` uploads a preview from a clean checkout.

## 3. GHA rewire

- [ ] 3.1 Modify `.github/workflows/deploy-docs.yaml` (and the justfile) to deploy via `nix run .#deploy-sites` against the nix-built `.#pnt-docs` payload, with sops still supplying the env.
- [ ] 3.2 Verify acceptance: a `workflow_dispatch` run produces a live preview URL.

## 4. DVC GCS to R2

- [ ] 4.1 Provision an R2 bucket and a dashboard-minted R2 S3 HMAC keypair (via wrangler/MCP/dashboard; no terranix).
- [ ] 4.2 Rewrite `.dvc/config` to an s3 remote (`url=s3://<bucket>/projects/python-nix-template/cas`, `endpointurl=https://<accountid>.r2.cloudflarestorage.com`, `region=auto`).
- [ ] 4.3 Add the R2 keypair to sops `vars/shared.yaml` (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`).
- [ ] 4.4 Swap the justfile DVC recipes from `uvx --with dvc-gdrive,dvc-gs` to `--with dvc-s3` and drop the `sops -d vars/dvc-sa.json` GCP-SA dance; retire `vars/dvc-sa.json` and the gdrive remote.
- [ ] 4.5 Verify acceptance: `just data-sync` pulls from R2 cleanly, a push round-trips, and the docs build is still green.

## 5. Deferred / out of scope (do not implement)

- [ ] 5.1 Document (do not implement) the buildbot-nix/hercules-ci effect that would run `deploy-sites` as a CI effect: hercules-ci-effects input plus flakeModule; a `mkEffect` deploy-sites effect referencing the app via an eval-time store path; a `python-nix-template-effects-secrets` clan-vars generator in vanixiets wired via `services.buildbot-nix.master.effects.perRepoSecretFiles` and imported on magnetite; `buildbot-nix.toml` gating. Blocked by CAM-23 and vanixiets PR-A; tracked as a future follow-up, with no Linear issue created now. Full spec in design.md (Non-Goals) and brainstorm.md.
