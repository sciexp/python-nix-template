## 1. deploy-sites build+deploy app

- [x] 1.1 Add `modules/apps/deploy-sites.nix` defining `perSystem.apps.deploy-sites` as a `writeShellApplication` that bakes the source fileset (`.dvc/config`, `docs/`, `wrangler.jsonc`) plus the toolchain `runtimeInputs`: `quarto` (with `QUARTO_PYTHON` pointed at the uv2nix docs venv), the python env providing `quartodoc` + `pnt_core`, `dvc` + `dvc-s3`, `nodejs` + `wrangler`, `jq`, `git`, `coreutils`.
- [x] 1.2 Add `modules/apps/deploy-sites.sh` with `build`/`preview`/`production` subcommands: copy the baked source to a tmpdir -> `dvc pull --force --allow-missing` -> `quartodoc build` + `quartodoc interlinks` -> `quarto render docs` to produce `_site` -> then (preview/production only) the `node`-wrangler deploy. The `build` subcommand runs only the build half and performs no deploy, leaving `_site` in a tmpdir whose path is printed; it requires `AWS_*` (for `dvc pull`) but not `CLOUDFLARE_*`. Preview = `node "$WRANGLER" versions upload --preview-alias b-<safe-branch> --tag <sha12>`; production = promote the version whose `workers/tag` annotation matches the sha12 (`versions list --json` match -> `versions deploy <id>@100%`), else fresh-build fallback `node "$WRANGLER" deploy`. Derive git metadata env-first (`GIT_REV_SHORT12`) with a git fallback; read credentials from inherited `CLOUDFLARE_*`/`AWS_*` env; run wrangler under real `node`, not bun.
- [ ] 1.3 Verify acceptance: `nix build .#deploy-sites` builds the app (done), and `nix run .#deploy-sites -- preview <branch>` builds the site and deploys a working preview under `sops exec-env` (pending a live deploy).
- [x] 1.4 Fix the render toolchain: vendor upstream quarto-cli v1.9.37 whole as the first `pkgs/by-name` resident (retaining bundled pandoc 3.8.3), wire `config.packages.quarto` into the app `runtimeInputs` and the devshell, and isolate per-run `HOME`/`XDG_*` inside `build_site()`. Cures the nixpkgs pandoc-3.7.0.2 `Unknown option "syntax-highlighting"` Aeson error and the deno_kv SassCache RangeError at `quarto render`.

## 2. GHA rewire

- [ ] 2.1 Modify `.github/workflows/deploy-docs.yaml` to deploy via `nix run .#deploy-sites` (the app now builds AND deploys; there is no separate `.#pnt-docs` payload), with sops still supplying the env; keep the `docs-deploy-{preview,production}` justfile recipes as thin wrappers calling `nix run .#deploy-sites`.
- [ ] 2.2 Verify acceptance: a `workflow_dispatch` run produces a live preview URL.

## 3. DVC GCS/Drive to R2 (additive; retirement deferred)

- [x] 3.1 Confirm the R2 bucket `sciexp` exists on account 1ece4a9a8f092f8cbdd679d22b9ecb1f (created out-of-band).
- [x] 3.2 Add a `r2` remote to `.dvc/config` (`url = s3://sciexp/projects/python-nix-template/cas`, `endpointurl = https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com`, `region = auto`) and set it as default; keep the `gcs` and `drive` remotes.
- [x] 3.3 Add the R2 S3 keypair (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) to sops `vars/shared.yaml` (manual; owner-only, never automated).
- [x] 3.4 Retarget the justfile `data-sync`/`docs-sync` recipes to r2 (`sops exec-env vars/shared.yaml` + `dvc-s3`, dropping the GCP-SA decrypt dance); make `dvc-run` universal (SA decrypt + `sops exec-env` + `--with dvc-s3,dvc-gs,dvc-gdrive`).
- [x] 3.5 Verify: `dvc push -r r2` seeds R2 from the local cache and `just data-sync` pulls cleanly (run after the keypair is set).
- [ ] 3.6 Deferred / out of scope: retire the GCP service account (`vars/dvc-sa.json`, `gcp-sa-*` recipes) and the `gcs`/`drive` remotes in a future follow-up once R2 is proven; all three remotes are kept for now.

## 4. Deferred / out of scope (do not implement)

- [ ] 4.1 Document (do not implement) the buildbot-nix/hercules-ci effect that would run the `deploy-sites` build+deploy app as a CI effect, invoking it via an eval-time `/nix/store` path so the build happens IN the effect (the effect sandbox has full network + nix daemon + root, and the app bakes its own source so there is no no-working-tree obstacle): hercules-ci-effects input plus flakeModule; a `mkEffect` deploy-sites effect referencing the app via the store path; a `python-nix-template-effects-secrets` clan-vars generator in vanixiets wired via `services.buildbot-nix.master.effects.perRepoSecretFiles` and imported on magnetite; `buildbot-nix.toml` gating. Blocked by CAM-23 and vanixiets PR-A; tracked as a future follow-up, with no Linear issue created now. Full spec in design.md (Non-Goals) and brainstorm.md.
