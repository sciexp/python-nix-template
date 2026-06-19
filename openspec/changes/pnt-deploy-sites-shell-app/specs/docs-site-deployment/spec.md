## ADDED Requirements

### Requirement: deploy-sites build+deploy application

The system SHALL provide a `perSystem.apps.deploy-sites` `writeShellApplication`, defined in `modules/apps/deploy-sites.nix` with logic in `modules/apps/deploy-sites.sh`, that bakes a `lib.fileset` source (`.dvc/config`, `docs/`, `wrangler.jsonc`) plus the toolchain into its closure and, at runtime, copies the baked source to a tmpdir, runs `dvc pull --force --allow-missing` then `quartodoc build` + `quartodoc interlinks` + `quarto render docs` to produce `_site`, then deploys it to Cloudflare Workers.
The application MUST support a preview path (`versions upload --preview-alias b-<safe-branch> --tag <sha12>`) and a production path (promotion of the version whose `workers/tag` annotation matches the sha12, otherwise `wrangler deploy`), MUST run wrangler under real `node` rather than bun, MUST derive git metadata env-first (`GIT_REV_SHORT12`) with a git fallback, and MUST read its credentials from the inherited environment (`CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` for deploy, `AWS_*` for the R2 `dvc pull`).

#### Scenario: nix build produces the app

- **WHEN** `nix build .#deploy-sites` is run
- **THEN** it builds the app

#### Scenario: preview build and deploy from a clean checkout

- **WHEN** `nix run .#deploy-sites -- preview <branch>` is run from a clean checkout with the Cloudflare and R2 credentials present in the environment
- **THEN** it builds the site and uploads a working preview

### Requirement: CI deploys via the nix app

The system SHALL build and deploy the documentation site in CI by invoking `nix run .#deploy-sites`, which builds the site at runtime then deploys it.
`.github/workflows/deploy-docs.yaml` and the justfile MUST be rewired to use this entrypoint, with sops continuing to supply the Cloudflare environment.

#### Scenario: workflow_dispatch produces a live preview URL

- **WHEN** the `deploy-docs` workflow is triggered via `workflow_dispatch`
- **THEN** the run produces a live preview URL

### Requirement: DVC data backing store on Cloudflare R2

The system SHALL add a Cloudflare R2 (s3-compatible) remote as the default DVC remote, keeping the existing `gcs` and `drive` remotes.
`.dvc/config` MUST define an s3 remote named `r2` with `endpointurl` of the form `https://<accountid>.r2.cloudflarestorage.com` and `region=auto`, and MUST set `r2` as the default remote while preserving the `gcs` and `drive` remotes; the R2 S3 keypair MUST be stored in sops `vars/shared.yaml`; the justfile `data-sync` and `docs-sync` recipes MUST use `uvx --with dvc-s3` under `sops exec-env vars/shared.yaml` and MUST drop the GCP service-account decrypt step, while `dvc-run` remains universal across all three remotes (`--with dvc-s3,dvc-gs,dvc-gdrive`).
Retirement of the GCP service account (`vars/dvc-sa.json`) and the `gcs`/`drive` remotes is deferred to a follow-up once R2 is proven, and is out of scope for this change.
The migration MUST NOT introduce terranix.

#### Scenario: data-sync pulls from R2 and a push round-trips

- **WHEN** `just data-sync` is run against the migrated R2 remote
- **THEN** it pulls cleanly from R2, a subsequent push round-trips, and the docs build remains green
