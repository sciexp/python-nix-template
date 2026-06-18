<!--
Raw capture of the locked CAM-23 deploy-sites design (HIL/OpenSpec).

This file captures the validated design decisions verbatim; it does not impose any structure.
design.md is extracted from this file and reorganized into a structured design document.
Do not copy this file's content into design.md — design.md is an independent, reorganized artifact.
-->

# CAM-23 deploy-sites: locked design capture

Locked design for CAM-23 (cameronraysmith Linear, "Create python-nix-template shell application to deploy quarto docs"), covering the pnt quarto-docs deploy-sites shell application plus the DVC GCS to R2 migration.
Execution mode: HIL/OpenSpec.
Decided 2026-06-18.

## Key research finding (non-obvious, expensive to rederive)

pnt's `quarto render` executes NO code: zero `{python}`/`{r}` chunks across all 22 `.qmd`, no execution engine declared, and `docs/_freeze` (dvc md5 481f00b1...) holds only `.keep` plus a static `clipboard.min.js`.
So the docs build is already hermetic and DVC `_freeze` is vestigial to it: `dvc pull` feeds the render nothing; identical HTML with `_freeze` empty or absent.
Build and DVC are orthogonal.

## Decision chain

### pnt-docs derivation (direct perSystem module, not pkgs-by-name)

A pure `perSystem.packages.pnt-docs` in a new `modules/docs.nix` — NOT pkgs-by-name.
by-name's callPackage scope is plain nixpkgs plus synthetic `inputs` plus sibling by-name packages only; feeding it the uv2nix venv needs a recursion-risky `_module.args.pkgs <- config.packages` overlay, whereas a direct perSystem module gets `config.packages.pntCore313` for free.
Structurally models ironstar-docs (`pkgs/by-name/ironstar-docs/package.nix`, stdenv.mkDerivation plus bun2nix, hermetic, lib.fileset-scoped src).
Inputs: `pkgs.quarto` (1.9.37, already in the devshell) plus the uv2nix venv (pnt_core plus the `docs` dependency-group -> quartodoc 0.11.1, `dynamic: true` live import) plus `docs/` source.
Steps: `quartodoc build --config docs/_quarto.yml` then `quarto render docs` -> `_site`.
The ONE build-time network impurity is `quartodoc interlinks` fetching external Sphinx `objects.inv` (python.org/beartype/matplotlib/numpy) — vendor as FODs (likely a `nix/` helper) or accept offline interlinks degradation.

### deploy-sites shell application

`perSystem.apps.deploy-sites` writeShellApplication consuming the pnt-docs `_site` payload, porting the justfile preview/production wrangler logic.
preview = `wrangler versions upload --preview-alias b-<safe-branch> --tag <sha12>`.
production = version-promotion by `workers/tag` sha12 annotation, else `wrangler deploy`.
Run wrangler under real `node`, not bun (bun fetch hangs against the cloudflare API — ironstar lesson).
Secrets via inherited env `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID`.
Worker `python-nix-template`, domain `python-nix-template.scientistexperience.net`, workers.dev subdomain `sciexp`.
GHA `deploy-docs.yaml`/justfile then call `nix run .#deploy-sites` against the nix-built payload (sops still provides the env).

### DVC GCS to R2 migration

Keep DVC, migrate to R2 as a demonstrated template pattern (build-independent).
`.dvc/config` -> s3 remote, `url=s3://<bucket>/projects/python-nix-template/cas`, `endpointurl=https://<accountid>.r2.cloudflarestorage.com`, `region=auto`.
Creds: a dedicated R2 S3 HMAC keypair (split from the Workers bearer token), dashboard-minted, landed in sops `vars/shared.yaml` (e.g. `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for dvc-s3 native pickup via `sops exec-env`).
NO terranix: the Cloudflare TF provider cannot mint R2 S3 keypairs (dashboard-only; vanixiets captures its R2 keypair manually via clan-vars placeholder), and one bucket is not worth the terranix ceremony given pnt has zero terranix today plus flat sops.
Swap justfile `uvx --with dvc-gdrive,dvc-gs` -> `--with dvc-s3`, drop the `sops -d vars/dvc-sa.json` GCP-SA dance; retire GCP SA plus gdrive remote.
Bucket created via wrangler/MCP/dashboard.

## Deferred to a follow-up issue (out of scope here)

Blocked by CAM-23 plus vanixiets PR-A (effects-secrets live on magnetite): the buildbot-nix/hercules-ci effect.
Effects run INSIDE buildbot-nix (Hercules-compatible runtime): it reads `herculesCI.onPush.default.outputs.effects.<name>`, instantiates `.run`, executes under bwrap with `HERCULES_CI_SECRETS_JSON=/run/secrets.json`.
Follow-up needs: hercules-ci-effects input plus flakeModule; a `mkEffect` deploy-sites effect referencing the app via an eval-time store path (eval is agent-system-scoped, single `onPush.default`, no per-system fanout); a `python-nix-template-effects-secrets` clan-vars generator in vanixiets (`{NAME:{data:{value}}}` envelope, read via `readSecretString NAME .value`) wired via `services.buildbot-nix.master.effects.perRepoSecretFiles."github:cameronraysmith/python-nix-template"` plus imported on magnetite; `buildbot-nix.toml` gating (main runs effects by default; `effects_on_pull_requests`/`effects_branches` for PR/branch).
Secret keys: CLOUDFLARE_API_TOKEN/ACCOUNT_ID plus the R2 S3 pair.

This is exactly the "docs-site build" adopt-trigger that prior memory anticipated, but it routes to a direct perSystem module rather than by-name because of the uv2nix-env build dependence.
