## Context

python-nix-template (pnt) renders its quarto documentation site but has no reproducible, nix-native path to build and deploy it.
Today the docs build and publish flow leans on the devshell-resident quarto plus ad hoc justfile/wrangler invocations, and the project's DVC data backing store points at Google Cloud Storage and Google Drive remotes that require a GCP service-account decrypt dance.

A key research finding constrains the design: pnt's `quarto render` executes no code.
There are zero `{python}`/`{r}` chunks across all 22 `.qmd`, no execution engine is declared, and `docs/_freeze` holds only `.keep` plus a static `clipboard.min.js`.
The docs build is therefore already hermetic, and DVC `_freeze` is vestigial to it: `dvc pull` feeds the render nothing, and the rendered HTML is identical whether `_freeze` is empty or absent.
Build and DVC are orthogonal, which lets the docs derivation be a pure nix build and lets the DVC remote migration proceed independently as a demonstrated template pattern.

Constraints and stakeholders: pnt has zero terranix today and a flat sops layout; the Cloudflare Workers worker is `python-nix-template` at `python-nix-template.scientistexperience.net` with workers.dev subdomain `sciexp`.
The structural reference is ironstar-docs (`pkgs/by-name/ironstar-docs/package.nix`): a hermetic `stdenv.mkDerivation` with a `lib.fileset`-scoped source.

## Goals / Non-Goals

**Goals:**

- A pure `perSystem.packages.pnt-docs` derivation that builds the quarto site reproducibly into `_site` from the uv2nix venv plus `docs/` source.
- A `perSystem.apps.deploy-sites` shell application that deploys the nix-built `_site` payload to Cloudflare Workers for both preview and production.
- CI (GitHub Actions plus justfile) that deploys via `nix run .#deploy-sites` against the nix-built `.#pnt-docs` payload, with sops supplying the secrets.
- Migration of the DVC remote from GCS/Google Drive to Cloudflare R2 (s3-compatible), as a demonstrated build-independent template pattern.

**Non-Goals:**

- The buildbot-nix/hercules-ci effect that would run `deploy-sites` as a CI effect. This is deferred to a follow-up issue (blocked by CAM-23 and vanixiets PR-A) and is documented but not implemented here.
- Adopting terranix. One R2 bucket does not justify the terranix ceremony, and the Cloudflare Terraform provider cannot mint R2 S3 keypairs regardless.
- pkgs-by-name packaging of the docs derivation (see D1).
- Removing DVC. DVC is retained; only its remote backend changes.

## Decisions

### D1: pnt-docs is a direct perSystem module, not pkgs-by-name

- **Choice**: Define `perSystem.packages.pnt-docs` in a new `modules/docs.nix` as a `stdenv.mkDerivation` taking `pkgs.quarto`, the uv2nix venv (`config.packages.pntCore313`, which provides pnt_core plus the `docs` dependency-group quartodoc 0.11.1), and a `lib.fileset`-scoped `docs/` source. Steps: `quartodoc build --config docs/_quarto.yml` then `quarto render docs` producing `_site`.
- **Rationale**: A direct perSystem module receives `config.packages.pntCore313` for free. The build genuinely depends on the uv2nix venv, so this is the natural wiring.
- **Alternatives considered**: pkgs-by-name. Rejected because by-name's callPackage scope is plain nixpkgs plus synthetic `inputs` plus sibling by-name packages only; feeding it the uv2nix venv requires a recursion-risky `_module.args.pkgs <- config.packages` overlay. The structural model remains ironstar-docs (hermetic mkDerivation, fileset-scoped src), just expressed as a perSystem module rather than a by-name package.

### D2: deploy-sites is a writeShellApplication app run under real node

- **Choice**: `perSystem.apps.deploy-sites` as a `writeShellApplication` (`modules/apps/deploy-sites.nix` plus `modules/apps/deploy-sites.sh`) that consumes the pnt-docs `_site` payload and ports the justfile preview/production wrangler logic. Preview uploads a versioned preview alias; production promotes a matching version or falls back to a direct deploy. Wrangler runs under real `node`, not bun. Secrets arrive via inherited env `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID`.
- **Rationale**: A nix app gives a reproducible deploy entrypoint usable identically from a clean checkout and from CI. Running wrangler under real node avoids the bun fetch hang against the Cloudflare API (the ironstar lesson).
- **Alternatives considered**: keeping the deploy logic inline in the justfile/CI only. Rejected because it is not reproducible and cannot later be lifted into a CI effect.

### D3: CI deploys through the nix app against the nix-built payload

- **Choice**: Modify `.github/workflows/deploy-docs.yaml` (and the justfile) to deploy via `nix run .#deploy-sites` against the nix-built `.#pnt-docs` payload, with sops still supplying the env.
- **Rationale**: Single deploy entrypoint shared by local and CI; the build is the nix derivation, not an ad hoc CI step.
- **Alternatives considered**: a bespoke CI deploy script. Rejected for the same reproducibility/duplication reasons as D2.

### D4: DVC adds R2 as the default remote via sops, without terranix; GCS/Drive retirement deferred

- **Choice**: Keep DVC; add an s3 remote `r2` to `.dvc/config` (`url=s3://sciexp/projects/python-nix-template/cas`, `endpointurl=https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com`, `region=auto`) and make it the default, keeping the existing `gcs` and `drive` remotes. Provision an R2 bucket plus a dashboard-minted R2 S3 HMAC keypair (split from the Workers bearer token). Land the keypair in sops `vars/shared.yaml` (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for native dvc-s3 pickup via `sops exec-env`). Retarget the justfile `data-sync`/`docs-sync` recipes to r2 via `sops exec-env vars/shared.yaml` plus `--with dvc-s3`, dropping the `sops -d vars/dvc-sa.json` GCP-SA dance; make `dvc-run` universal (`--with dvc-s3,dvc-gs,dvc-gdrive`). Defer retiring the GCP SA and the `gcs`/`drive` remotes to a follow-up once R2 is proven.
- **Rationale**: R2 is a clean s3-compatible target and a useful demonstrated template pattern; DVC and the docs build are orthogonal, so this is build-independent. The keypair is dashboard-minted because the Cloudflare TF provider cannot mint R2 S3 keypairs (dashboard-only); vanixiets captures its R2 keypair manually via a clan-vars placeholder.
- **Alternatives considered**: terranix-managed provisioning (rejected: one bucket is not worth the ceremony given pnt has zero terranix and flat sops, and the provider cannot mint the keypair anyway) and dropping DVC entirely (rejected: DVC is retained as the demonstrated pattern).

### D5: interlinks objects.inv as fixed-output derivations

- **Choice**: The one build-time network impurity is `quartodoc interlinks` fetching external Sphinx `objects.inv` (python.org/beartype/matplotlib/numpy). Vendor these as fixed-output derivations (likely via a `nix/` helper), or accept offline interlinks degradation.
- **Rationale**: A hermetic nix build cannot fetch at build time outside an FOD. Vendoring the inventories as FODs preserves cross-project interlinks while keeping the build pure.
- **Alternatives considered**: leaving the fetch unpinned (rejected: breaks hermeticity) versus simply degrading interlinks offline (acceptable fallback if FOD vendoring proves heavy).

## Risks / Trade-offs

- [Risk] `quartodoc interlinks` network fetch breaks a hermetic build. -> Mitigation: vendor `objects.inv` as FODs, or accept offline interlinks degradation (D5).
- [Risk] wrangler under bun hangs against the Cloudflare API. -> Mitigation: run wrangler under real node, not bun (D2).
- [Risk] The R2 S3 keypair cannot be provisioned as code. -> Mitigation: mint it via the Cloudflare dashboard and land it in sops `vars/shared.yaml` manually, mirroring vanixiets' clan-vars placeholder approach (D4).
- [Trade-off] No terranix for the single R2 bucket. -> Accepted: the ceremony is not justified for one bucket, and the provider cannot mint the keypair regardless.
- [Trade-off] All three remotes (r2 default, gcs, drive) are kept for now; retiring the GCP SA and gcs/drive remotes is a deferred one-way migration of the DVC backing store. -> Accepted: a push round-trip against R2 is part of the acceptance criteria before that follow-up retirement is undertaken.

## Migration Plan

1. Land `modules/docs.nix` and verify `nix build .#pnt-docs` plus `nix flake check`.
2. Land `modules/apps/deploy-sites.{nix,sh}` and verify `nix run .#deploy-sites -- preview <branch>` from a clean checkout.
3. Rewire `.github/workflows/deploy-docs.yaml` and the justfile to deploy via the nix app against the nix-built payload; verify a `workflow_dispatch` run yields a live preview URL.
4. Provision the R2 bucket and keypair, add the `r2` remote to `.dvc/config` as default (keeping `gcs` and `drive`), add the keypair to sops, and retarget the justfile DVC recipes; verify `just data-sync` pulls and a push round-trips and docs still build. Defer retiring the GCP SA and the `gcs`/`drive` remotes to a follow-up once R2 is proven.

Rollback: each work item is independent. Adding the R2 remote is non-destructive (all three remotes are kept). The deferred follow-up that retires the GCP SA and old remotes is the only step with a one-way characteristic, and it is gated behind a verified push round-trip before any old remote is removed.

## Open Questions

- Whether to vendor all four `objects.inv` inventories as FODs immediately or ship with offline interlinks degradation first and add FODs incrementally (D5).
- The exact R2 bucket name and account-id-derived endpoint values, which are provisioned out of band via dashboard/wrangler/MCP and then referenced in `.dvc/config` and sops.
