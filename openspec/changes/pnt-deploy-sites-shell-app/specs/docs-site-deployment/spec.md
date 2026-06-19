## ADDED Requirements

### Requirement: pnt-docs build derivation

The system SHALL provide a `perSystem.packages.pnt-docs` derivation, defined in `modules/docs.nix`, that builds the quarto documentation site reproducibly into `_site` from the uv2nix venv (`config.packages.pntCore313`, providing pnt_core and the `docs` dependency-group quartodoc) and a `lib.fileset`-scoped `docs/` source, by running `quartodoc build` followed by `quarto render docs`.
The derivation MUST be a direct perSystem module rather than a pkgs-by-name package, and MUST vendor external Sphinx `objects.inv` interlink inventories as fixed-output derivations or otherwise degrade interlinks gracefully when offline.

#### Scenario: nix build produces a stable site

- **WHEN** `nix build .#pnt-docs` is run
- **THEN** it yields a stable `_site` with a sane `index.html`

#### Scenario: flake check passes with the docs derivation present

- **WHEN** `nix flake check` is run after `modules/docs.nix` is added
- **THEN** the check is green

### Requirement: deploy-sites application

The system SHALL provide a `perSystem.apps.deploy-sites` application, defined as a `writeShellApplication` in `modules/apps/deploy-sites.nix` with logic in `modules/apps/deploy-sites.sh`, that consumes the pnt-docs `_site` payload and deploys it to Cloudflare Workers.
The application MUST support a preview path (`wrangler versions upload --preview-alias b-<safe-branch> --tag <sha12>`) and a production path (promotion of the version whose `workers/tag` annotation matches the sha12, otherwise `wrangler deploy`), MUST run wrangler under real `node` rather than bun, and MUST read its credentials from the inherited environment variables `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.

#### Scenario: preview deploy from a clean checkout

- **WHEN** `nix run .#deploy-sites -- preview <branch>` is run from a clean checkout with the Cloudflare credentials present in the environment
- **THEN** it uploads a preview of the docs site

### Requirement: CI deploys via the nix app

The system SHALL deploy the documentation site in CI by invoking `nix run .#deploy-sites` against the nix-built `.#pnt-docs` payload.
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
