## Context

python-nix-template (pnt) renders its quarto documentation site but has no reproducible, nix-native path to build and deploy it.
Today the docs build and publish flow leans on the devshell-resident quarto plus ad hoc justfile/wrangler invocations, and the project's DVC data backing store points at Google Cloud Storage and Google Drive remotes that require a GCP service-account decrypt dance.

A key research finding shapes the design: the template's docs are designed to host expensive, networked quarto notebooks whose execution is out-of-band.
A developer runs the notebooks, then `dvc add`/`dvc push` the resulting freeze; the freeze cache is per-document (`freeze: true`) and DVC-tracked precisely so that execution happens once, out of band, not on every build.
The build path therefore only `dvc pull`s the freeze and `quarto render`s against it, never re-executing notebooks.
This makes a nix-build sandbox the wrong fit: it has no network and no data, so a stale-freeze render would fail inside a derivation with no recourse, whereas an imperative path has the network to re-execute if needed.
Build and DVC are not orthogonal here: the build depends on the DVC-pulled freeze, which is why the deploy app pulls before rendering.

Constraints and stakeholders: pnt has zero terranix today and a flat sops layout; the Cloudflare Workers worker is `python-nix-template` at `python-nix-template.scientistexperience.net` with workers.dev subdomain `sciexp`.
The structural reference is the vanixiets `deploy-docs` / ironstar `deploy-sites` shell-application pattern (a hercules-CI-style effect invoked by eval-time `/nix/store` path), with pyrovelocity confirming the toolchain-only (no docs derivation) build pattern.

## Goals / Non-Goals

**Goals:**

- A single `perSystem.apps.deploy-sites` build+deploy shell application that bakes the source fileset plus the toolchain into its closure, builds the quarto site at runtime (`dvc pull` -> `quartodoc build`/`interlinks` -> `quarto render`) into `_site`, and deploys it to Cloudflare Workers for both preview and production.
- CI (GitHub Actions plus justfile) that builds and deploys via `nix run .#deploy-sites`, with sops supplying the secrets.
- Migration of the DVC remote from GCS/Google Drive to Cloudflare R2 (s3-compatible), as a demonstrated template pattern.

**Non-Goals:**

- The buildbot-nix/hercules-ci effect that would run the `deploy-sites` build+deploy app as a CI effect. This is deferred to a follow-up issue (blocked by CAM-23 and vanixiets PR-A) and is documented but not implemented here.
- Adopting terranix. One R2 bucket does not justify the terranix ceremony, and the Cloudflare Terraform provider cannot mint R2 S3 keypairs regardless.
- A hermetic docs derivation (see D1). Nix bakes the toolchain, not the site.
- Removing DVC. DVC is retained; only its remote backend changes.

## Decisions

### D1: a single deploy-sites build+deploy app, not a hermetic docs derivation

- **Choice**: Build and deploy from a single `perSystem.apps.deploy-sites` `writeShellApplication`; there is no docs derivation. Nix bakes the source fileset (`.dvc/config`, `docs/`, `wrangler.jsonc`) plus the toolchain into the app's closure; the app builds the site imperatively at runtime (copy baked source -> `dvc pull` -> `quartodoc build`/`interlinks` -> `quarto render`) before deploying.
- **Rationale**: A hermetic docs derivation is the wrong tool because the template's docs are designed to host notebooks whose execution is expensive and networked. Quarto's `_freeze` cache (DVC-tracked, per-document `freeze: true`) exists precisely so execution happens out-of-band: a developer runs the notebooks, then `dvc add`/`dvc push` the freeze, and the build path only `dvc pull`s the freeze and `quarto render`s against it, never re-executing. A nix-build sandbox has no network and no data, so a stale-freeze render would fail inside a derivation with no recourse; the imperative path degrades gracefully because it has network to re-execute if needed. Pre-merge build validation does not require a derivation either: with `effects_on_pull_requests = true` the deploy effect runs on PRs in preview mode, so a broken build fails the `buildbot/nix-effects` merge gate pre-merge (today's GHA `preview-docs-deploy` already does the same), making the derivation's only remaining justification moot. pyrovelocity, a real expensive-notebook quarto project, confirms the pattern: it has no docs derivation; nix supplies only the toolchain (the `quarto` CLI plus a python env, with `QUARTO_PYTHON` exported to the venv), and a `just docs-build` recipe runs `dvc pull --force --allow-missing` -> `quartodoc build` -> `quartodoc interlinks` -> `quarto render` imperatively. Nix's correct role is to bake the toolchain into the app's closure, not to build the site.
- **Alternatives considered**: a hermetic `pnt-docs` `stdenv.mkDerivation` (optionally as a pkgs-by-name package). Rejected because a nix-build sandbox has no network and no data, so a stale-freeze render is unrecoverable inside the derivation, and the only remaining justification (pre-merge validation) is moot under PR-mode effects that already fail the merge gate on a broken preview build.

### D2: deploy-sites is a writeShellApplication app that builds then deploys under real node

- **Choice**: `perSystem.apps.deploy-sites` as a `writeShellApplication` (`modules/apps/deploy-sites.nix` plus `modules/apps/deploy-sites.sh`) that builds the site at runtime before deploying: copy the baked source to a tmpdir -> `dvc pull --force --allow-missing` (R2; `AWS_*` from env) -> `quartodoc build` + `quartodoc interlinks` -> `quarto render docs` to produce `_site` -> then the preview/production wrangler deploy. Preview uploads a versioned preview alias (`versions upload --preview-alias b-<safe-branch> --tag <sha12>`); production promotes the version whose `workers/tag` matches the sha12 (`versions list --json` -> `versions deploy <id>@100%`) or falls back to a direct `deploy`. Wrangler runs under real `node`, not bun. Secrets arrive via inherited env (`CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` for deploy, `AWS_*` for the R2 pull).
- **Rationale**: A nix app gives a reproducible build-and-deploy entrypoint usable identically from a clean checkout and from CI. Running wrangler under real node avoids the bun fetch hang against the Cloudflare API (the ironstar lesson).
- **Deliberate divergence**: vanixiets `deploy-docs` and ironstar `deploy-sites` bake a pre-built site payload and only deploy. pnt instead bakes the source (a `lib.fileset` of `.dvc/config`, `docs/`, `wrangler.jsonc`) plus the toolchain and builds at runtime. This is effect-safe: the buildbot-nix effect sandbox has full network plus nix daemon plus root, and baking the source removes the no-working-tree obstacle.
- **Alternatives considered**: keeping the deploy logic inline in the justfile/CI only. Rejected because it is not reproducible and cannot later be lifted into a CI effect.

### D3: CI builds and deploys through the nix app

- **Choice**: Modify `.github/workflows/deploy-docs.yaml` (and the justfile) to build and deploy via `nix run .#deploy-sites`, which now builds the site at runtime and deploys it, with sops still supplying the env. There is no separate `.#pnt-docs` payload.
- **Rationale**: Single build-and-deploy entrypoint shared by local and CI; the build is the app's runtime quarto render, not an ad hoc CI step.
- **Alternatives considered**: a bespoke CI deploy script. Rejected for the same reproducibility/duplication reasons as D2.

### D4: DVC adds R2 as the default remote via sops, without terranix; GCS/Drive retirement deferred

- **Choice**: Keep DVC; add an s3 remote `r2` to `.dvc/config` (`url=s3://sciexp/projects/python-nix-template/cas`, `endpointurl=https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com`, `region=auto`) and make it the default, keeping the existing `gcs` and `drive` remotes. Provision an R2 bucket plus a dashboard-minted R2 S3 HMAC keypair (split from the Workers bearer token). Land the keypair in sops `vars/shared.yaml` (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for native dvc-s3 pickup via `sops exec-env`). Retarget the justfile `data-sync`/`docs-sync` recipes to r2 via `sops exec-env vars/shared.yaml` plus `--with dvc-s3`, dropping the `sops -d vars/dvc-sa.json` GCP-SA dance; make `dvc-run` universal (`--with dvc-s3,dvc-gs,dvc-gdrive`). Defer retiring the GCP SA and the `gcs`/`drive` remotes to a follow-up once R2 is proven.
- **Rationale**: R2 is a clean s3-compatible target and a useful demonstrated template pattern; DVC and the docs build are orthogonal, so this is build-independent. The keypair is dashboard-minted because the Cloudflare TF provider cannot mint R2 S3 keypairs (dashboard-only); vanixiets captures its R2 keypair manually via a clan-vars placeholder.
- **Alternatives considered**: terranix-managed provisioning (rejected: one bucket is not worth the ceremony given pnt has zero terranix and flat sops, and the provider cannot mint the keypair anyway) and dropping DVC entirely (rejected: DVC is retained as the demonstrated pattern).

### D5: interlinks needs no FOD vendoring under the runtime-build model

- **Choice**: `quartodoc interlinks` runs at app runtime over the live network (the effect sandbox and the GHA runner both have network), so no fixed-output derivation vendoring of external Sphinx `objects.inv` is needed.
- **Rationale**: The prior design's FOD-vendoring decision existed only to keep a hermetic build-time fetch pure. Under B there is no build-time hermeticity constraint to satisfy, so the FOD machinery is moot and dropped.

### D6: notebook execution is out-of-band; the build only pulls and renders the freeze

- **Choice**: Notebooks execute out-of-band; the freeze is per-document `freeze: true` and DVC-tracked; the build path only `dvc pull`s the freeze and `quarto render`s against it, never executing.
- **Rationale**: Expensive, networked notebook execution must happen once, out of band, with its result captured in the DVC-tracked freeze cache. Coupling execution into the build path (as a hermetic derivation would) is both expensive and impossible in a no-network sandbox; pulling the freeze and rendering against it keeps the build path cheap and deterministic while leaving re-execution available to the imperative path when the freeze is stale.

## Risks / Trade-offs

- [Risk] wrangler under bun hangs against the Cloudflare API. -> Mitigation: run wrangler under real node, not bun (D2).
- [Risk] The R2 S3 keypair cannot be provisioned as code. -> Mitigation: mint it via the Cloudflare dashboard and land it in sops `vars/shared.yaml` manually, mirroring vanixiets' clan-vars placeholder approach (D4).
- [Trade-off] No terranix for the single R2 bucket. -> Accepted: the ceremony is not justified for one bucket, and the provider cannot mint the keypair regardless.
- [Trade-off] All three remotes (r2 default, gcs, drive) are kept for now; retiring the GCP SA and gcs/drive remotes is a deferred one-way migration of the DVC backing store. -> Accepted: a push round-trip against R2 is part of the acceptance criteria before that follow-up retirement is undertaken.

## Migration Plan

1. Land `modules/apps/deploy-sites.{nix,sh}` (bake the source fileset plus the toolchain; build at runtime then deploy) and verify `nix build .#deploy-sites` builds and `nix run .#deploy-sites -- preview <branch>` builds the site and deploys a working preview from a clean checkout.
2. Rewire `.github/workflows/deploy-docs.yaml` and the justfile to build and deploy via `nix run .#deploy-sites`; verify a `workflow_dispatch` run yields a live preview URL.
3. Provision the R2 bucket and keypair, add the `r2` remote to `.dvc/config` as default (keeping `gcs` and `drive`), add the keypair to sops, and retarget the justfile DVC recipes; verify `just data-sync` pulls and a push round-trips and docs still build. Defer retiring the GCP SA and the `gcs`/`drive` remotes to a follow-up once R2 is proven.

Rollback: each work item is independent. Adding the R2 remote is non-destructive (all three remotes are kept). The deferred follow-up that retires the GCP SA and old remotes is the only step with a one-way characteristic, and it is gated behind a verified push round-trip before any old remote is removed.

## Open Questions

- The exact R2 bucket name and account-id-derived endpoint values, which are provisioned out of band via dashboard/wrangler/MCP and then referenced in `.dvc/config` and sops.
