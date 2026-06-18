# pnt deploy-sites Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Build and deploy the pnt quarto docs site reproducibly via nix, and migrate the DVC backing store from GCS/Drive to Cloudflare R2.

**Architecture:** A pure `perSystem.packages.pnt-docs` derivation renders the site into `_site` from the uv2nix venv and `docs/` source; a `perSystem.apps.deploy-sites` shell application deploys that payload to Cloudflare Workers under real node; CI invokes the app against the nix-built payload with sops-supplied secrets. DVC is retained but repointed at an s3-compatible R2 remote.

**Tech Stack:** nix/flake-parts, uv2nix, quarto + quartodoc, Cloudflare Workers + wrangler (node), Cloudflare R2 (s3) + DVC, sops, GitHub Actions, just.

---

## Task 1: pnt-docs derivation

- [ ] **Step 1:** Create `modules/docs.nix` with a `perSystem` block defining `packages.pnt-docs` as a `stdenv.mkDerivation`; wire its `src` to a `lib.fileset` scoped over `docs/`.
- [ ] **Step 2:** Add `pkgs.quarto` and the uv2nix venv `config.packages.pntCore313` to `nativeBuildInputs`/`buildInputs`; set the build phase to `quartodoc build --config docs/_quarto.yml` then `quarto render docs`, installing `_site` to `$out`.
- [ ] **Step 3:** Handle the `quartodoc interlinks` network impurity: add a `nix/` FOD helper that vendors the external `objects.inv` inventories (python.org/beartype/matplotlib/numpy), or configure graceful offline interlinks degradation.
- [ ] **Step 4:** Verify `nix build .#pnt-docs` yields a stable `_site` with a sane `index.html`, and `nix flake check` is green. Commit.

## Task 2: deploy-sites app

- [ ] **Step 1:** Create `modules/apps/deploy-sites.sh` porting the justfile wrangler logic: a `preview <branch>` path running `wrangler versions upload --preview-alias b-<safe-branch> --tag <sha12>`, and a `production` path that promotes the version whose `workers/tag` annotation matches the sha12 (else `wrangler deploy`).
- [ ] **Step 2:** Create `modules/apps/deploy-sites.nix` defining `perSystem.apps.deploy-sites` as a `writeShellApplication` that runs the script with wrangler invoked under real `node` (not bun) and reads `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` from the environment; point it at the `.#pnt-docs` `_site` payload.
- [ ] **Step 3:** Verify `nix run .#deploy-sites -- preview <branch>` uploads a preview from a clean checkout. Commit.

## Task 3: GHA rewire

- [ ] **Step 1:** Edit `.github/workflows/deploy-docs.yaml` to build `.#pnt-docs` and deploy via `nix run .#deploy-sites`, keeping the sops step that supplies the Cloudflare env.
- [ ] **Step 2:** Update the corresponding justfile recipe to call `nix run .#deploy-sites` against the nix-built payload.
- [ ] **Step 3:** Verify a `workflow_dispatch` run produces a live preview URL. Commit.

## Task 4: DVC GCS to R2

- [ ] **Step 1:** Provision an R2 bucket and a dashboard-minted R2 S3 HMAC keypair via wrangler/MCP/dashboard (no terranix).
- [ ] **Step 2:** Rewrite `.dvc/config` to an s3 remote: `url=s3://<bucket>/projects/python-nix-template/cas`, `endpointurl=https://<accountid>.r2.cloudflarestorage.com`, `region=auto`.
- [ ] **Step 3:** Add `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` (the R2 keypair) to sops `vars/shared.yaml`.
- [ ] **Step 4:** Swap the justfile DVC recipes from `uvx --with dvc-gdrive,dvc-gs` to `--with dvc-s3`; drop the `sops -d vars/dvc-sa.json` GCP-SA dance; retire `vars/dvc-sa.json` and the gdrive remote.
- [ ] **Step 5:** Verify `just data-sync` pulls from R2 cleanly, a push round-trips, and the docs build is still green. Commit.

## Deferred (do not implement)

The buildbot-nix/hercules-ci effect that runs `deploy-sites` as a CI effect is out of scope for this change (blocked by CAM-23 and vanixiets PR-A). It is documented in design.md (Non-Goals), brainstorm.md, and tasks.md §5; no Linear issue is created for it now.
