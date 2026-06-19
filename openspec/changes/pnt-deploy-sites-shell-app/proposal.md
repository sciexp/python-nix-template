---
linear_story_id: "CAM-23"
linear_story_identifier: "CAM-23"
linear_story_title: "Create python-nix-template shell application to deploy quarto docs"
linear_story_url: "https://linear.app/cameronraysmith/issue/CAM-23"
linear_story_state: "In Progress"
linear_team: "CAM"
last_synced_state: "In Progress"
last_synced_at: "2026-06-18T16:42:19Z"
review_round: 0
attempt_log:
  - { at: "2026-06-18T16:42:19Z", transition: "bind->todo", outcome: "dropped", note: "issue already In Progress (manually set pre-proposal); Todo is strictly-behind, state transition skipped as no-op per strictly-behind rule" }
  - { at: "2026-06-18T16:42:19Z", transition: "bind->describe", outcome: "posted", note: "Linear description seeded from proposal business content" }
---

## Why

pnt renders its quarto docs site but has no reproducible, nix-native way to build and deploy it, and its DVC data store still depends on GCS and Google Drive remotes gated behind a GCP service-account decrypt dance. A single `deploy-sites` build+deploy app, into which nix bakes the toolchain and the source, gives one reproducible build-and-deploy entrypoint shared by local and CI, and migrating the DVC remote to Cloudflare R2 removes the GCP dependency and demonstrates a clean s3-compatible template pattern.

## What Changes

**Docs build and deploy**
- From: docs rendered ad hoc via the devshell quarto and justfile invocations, with deploy logic inline in the justfile/CI calling wrangler directly.
- To: a single `perSystem.apps.deploy-sites` build+deploy `writeShellApplication` into which nix bakes the toolchain and the source fileset (`.dvc/config`, `docs/`, `wrangler.jsonc`); the app does the imperative quarto build (`dvc pull` -> `quartodoc build`/`interlinks` -> `quarto render docs`) then the wrangler deploy (preview/production) under real node.
- Reason: notebook execution is out-of-band and the freeze cache is DVC-tracked, so a derivation's no-network sandbox cannot recover from a stale freeze while the imperative path can re-execute; pre-merge build validation comes from PR-mode effects (which fail the merge gate on a broken preview build), not from a derivation.
- Impact: non-breaking; adds `modules/apps/deploy-sites.{nix,sh}`.

**CI deploy wiring**
- From: `.github/workflows/deploy-docs.yaml` builds and deploys docs with bespoke steps.
- To: CI builds and deploys via `nix run .#deploy-sites` (the app builds the site at runtime then deploys it), sops supplying the env.
- Reason: single entrypoint; the build is the app's runtime quarto render.
- Impact: non-breaking workflow change.

**DVC data backend**
- From: DVC default remote on GCS, with a Google Drive remote alongside, decrypted via a GCP service account (`vars/dvc-sa.json`).
- To: a Cloudflare R2 (s3-compatible) remote added as the new default with an R2 S3 keypair in sops `vars/shared.yaml`; the `gcs` and `drive` remotes are kept, and GCP-SA/gdrive retirement is deferred to a follow-up once R2 is proven.
- Reason: removes the GCP dependency from the default data path and demonstrates a clean s3-compatible template pattern; DVC is retained.
- Impact: additive and non-destructive (all three remotes kept); the deferred follow-up that retires the GCP SA and old remotes is the one-way step, gated behind a verified push round-trip.

## Capabilities

### New Capabilities

- `docs-site-deployment`: a single nix-native `deploy-sites` app that builds and deploys the pnt quarto documentation site (nix bakes the toolchain and source; the app renders at runtime then deploys), plus the CI wiring and the migration of the DVC data backing store to Cloudflare R2.

### Modified Capabilities

<!-- None: this is a new capability for pnt; openspec/specs/ has no existing specs. -->

## Impact

- New nix modules: `modules/apps/deploy-sites.nix`, `modules/apps/deploy-sites.sh`.
- Modified: `.github/workflows/deploy-docs.yaml`, `justfile`, `.dvc/config`, sops `vars/shared.yaml`.
- Deferred retirement (follow-up, not this change): `vars/dvc-sa.json` (GCP SA) and the DVC `gcs`/`drive` remotes; all three remotes are kept for now.
- Dependencies (baked toolchain): `quarto` (with `QUARTO_PYTHON` -> the uv2nix docs venv), the uv2nix docs venv providing `quartodoc` + `pnt_core`, `dvc` + `dvc-s3`, `nodejs` + `wrangler`, `jq`, `git`, `coreutils`; Cloudflare Workers (worker `python-nix-template`) and R2; wrangler run under real node.
- Secrets: `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` for deploy, R2 S3 `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for the DVC pull.
- Out of scope / deferred follow-up: the buildbot-nix/hercules-ci effect that would run the `deploy-sites` build+deploy app as a CI effect, invoking it via an eval-time store path so the build happens in-effect (blocked by CAM-23 and vanixiets PR-A); documented in design.md, not implemented, and no Linear issue is created for it now.
