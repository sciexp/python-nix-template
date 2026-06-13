# Check harvest via passthru.tests

This document records the rationale for the check architecture landing in PR #278 (`ci-flake-checks-and-toolchain`).
It explains why the pure-package flake checks that the branch already introduced are refactored onto a single canonical idiom shared with the maturin package, and it serves as the implementation record for the file-by-file changes.

The pure-package checks are not net-new in this PR.
The branch already wires `mkPurePytestCheck`, `pureChecks`, `ruffChecks`, and `basedpyrightCheck` in `modules/python.nix`, with `checks = rustChecks // pureChecks // ruffChecks // { basedpyright = basedpyrightCheck; }`.
What this work does is collapse those bespoke builders, plus the maturin package's separately-shaped `rustChecks` harvest, onto one mechanism: every package attaches its checks to its package node as `passthru.tests`, and a single fold harvests them into the flake's `checks` output.

## Core principles

The architecture rests on four principles.

One shared Python set per interpreter version.
`mkPythonSet python` is called exactly once per version and the result is threaded to every consumer via `_module.args`.
No check builder re-invokes `mkPythonSet`.
The single-fixpoint property becomes structural rather than disciplinary, because every test virtual environment is produced by `final.mkVirtualEnv` inside that one overlay.
Today `mkPurePytestCheck` and `basedpyrightCheck` each call `mkPythonSet` internally, re-deriving the overlay fixpoint; those internal re-derivations are removed.

Tests attach to package nodes via `passthru.tests`, built from dedicated dependency groups.
Each pure package's pytest and basedpyright derivations are attached to its package node inside an overlay composed into `mkPythonSet`, exactly as the uv2nix canonical testing example does (`~/projects/nix-workspace/uv2nix/doc/src/patterns/testing/flake.nix`).
The test venv is built from a single dedicated group spec `{ <pkg> = [ "test" ]; }` rather than from `workspace.deps.default`, which currently unions `lint`, `test`, and `types` because every pure pyproject sets `default-groups = ["lint", "test", "types"]`.

One uniform harvest mechanism across pure and maturin packages.
Both kinds expose `passthru.tests` on their package node: pure packages via the new overlay, and `pnt-cli` via crane-maturin.
A single fold over `pythonSets.py313.<pkg>.passthru.tests`, renaming each entry to `<pkg>-<check>`, produces the entire check set.
This replaces both the maturin-only `rustChecks` fold and the bespoke per-pure-package builders.

The editable set is reserved for the dev shell.
`editablePythonSets` backs only `devshell.nix`; checks and `packages` consume only the production `pythonSets`.
An editable venv must never back a check, because editable installs point at the mutable working tree and break hermeticity.
A production set must never back the dev shell, because it would force a rebuild on every edit.
The code already honors this; the design names it as an invariant and documents it at the top of `modules/python.nix`.

## The passthru.tests mechanism

The centerpiece is an overlay that attaches `passthru.tests` to each pure package node, adapted directly from the uv2nix canonical testing pattern.
The pytest venv is built from a dedicated `test` group spec.
The basedpyright venv is built from the `["typecheck" "test"]` group spec rather than `["typecheck"]` alone: basedpyright scans the whole `src/` tree including `src/<pkg>/tests`, whose modules import the test toolchain (pytest, hypothesis), so those imports must resolve for type-checking to succeed.
Each check still pulls exactly the dependencies it needs, with the test toolchain present only where the type-checker must see it.
For `pnt-functional`, a beartype claw `conftest.py` is injected before pytest so the runtime type-checking hook is active during tests.

```nix
pyprojectTestOverrides =
  python: final: prev:
  let
    inherit (final) mkVirtualEnv;
    beartypeTargets = { pnt-functional = "pnt_functional"; };

    mkPureTests =
      name:
      let
        beartypePkg = beartypeTargets.${name} or null;
        testVenv = mkVirtualEnv "${name}-pytest-env" { ${name} = [ "test" ]; };
        # The typecheck venv carries both `typecheck` and `test`: basedpyright
        # scans the whole src/ tree including src/<pkg>/tests, whose modules
        # import the test toolchain, so those imports must resolve.
        typecheckVenv = mkVirtualEnv "${name}-typecheck-env" {
          ${name} = [
            "typecheck"
            "test"
          ];
        };
        beartypeConftest = pkgs.writeText "beartype-conftest.py" ''
          from beartype.claw import beartype_package
          beartype_package("${beartypePkg}")
        '';
      in
      (prev.${name}.passthru.tests or { })
      // {
        pytest = pkgs.stdenv.mkDerivation (
          {
            name = "${final.${name}.name}-pytest";
            inherit (final.${name}) src;
            nativeBuildInputs = [ testVenv ];
            dontConfigure = true;
            buildPhase = ''
              runHook preBuild
              ${lib.optionalString (beartypePkg != null) "cp ${beartypeConftest} conftest.py"}
              pytest
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              touch $out
              runHook postInstall
            '';
          }
          // lib.optionalAttrs (beartypePkg != null) { BEARTYPE_HOOK_PACKAGE = beartypePkg; }
        );

        basedpyright =
          pkgs.runCommand "${final.${name}.name}-basedpyright"
            { nativeBuildInputs = [ pkgs.basedpyright typecheckVenv ]; }
            ''
              cd ${final.${name}.src}
              basedpyright --pythonpath "$(command -v python3)" src/
              touch "$out"
            '';
      };
  in
  lib.genAttrs purePackageNames (
    name:
    prev.${name}.overrideAttrs (old: {
      passthru = (old.passthru or { }) // { tests = mkPureTests name; };
    })
  );
```

The overlay is composed into `mkPythonSet`, after the package overlays and before — or alongside — `packageOverrides` and `sdistOverrides`:

```nix
mkPythonSet =
  python:
  (pkgs.callPackage inputs.pyproject-nix.build.packages { inherit python; }).overrideScope (
    lib.composeManyExtensions (
      [ inputs.pyproject-build-systems.overlays.default ]
      ++ map (name: packageWorkspaces.${name}.overlay) packageNames
      ++ map (name: (mkPackageModule name python).overlay) maturinPackageNames
      ++ [
        packageOverrides
        sdistOverrides
        (pyprojectTestOverrides python)
      ]
    )
  );
```

The ordering is deliberate.
Composing `pyprojectTestOverrides` after `packageOverrides` and `sdistOverrides` means the test venv inputs see the fully-overridden package set; if a downstream override instead needs to observe `passthru.tests`, the order flips.
`inherit (final.${name}) src` takes the package node's already-filtered source, so there is one source definition owned by the node.
Coverage flags live in each pyproject's `[tool.pytest.ini_options] addopts`, so a bare `pytest` invocation already produces coverage; basedpyright consumes a venv for import resolution via `--pythonpath`, while ruff (below) does not.

Ruff stays a venv-free top-level builder, since it is a standalone binary and lint is config-only against the shared `ruff.toml`.
It does not belong in `passthru.tests` because it is neither per-node nor venv-backed:

```nix
mkRuffCheck =
  name:
  pkgs.runCommand "${name}-ruff"
    {
      nativeBuildInputs = [ pkgs.ruff ];
      src = lib.cleanSource (../packages + "/${name}");
    }
    ''
      cd "$src"
      ruff check --no-cache --config ${../ruff.toml} src/
      touch "$out"
    '';
```

## The uniform harvest

Both package kinds now expose `passthru.tests` on their node: pure packages via the overlay above, `pnt-cli` via crane-maturin.
A single fold over the shared set produces the entire check set with a consistent `<pkg>-<check>` naming convention, replacing the separate `rustChecks`, `pureChecks`, and `basedpyright` assembly that the branch currently uses.
Maturin packages drop the coverage variants exactly as the `pnt-cli` module does today.

```nix
checkSet = pythonSets.py313;

harvest =
  drops: name:
  lib.mapAttrs' (
    checkName: drv: lib.nameValuePair "${name}-${checkName}" drv
  ) (builtins.removeAttrs (checkSet.${name}.passthru.tests or { }) drops);

packageChecks =
  lib.foldl' (acc: name: acc // harvest [ ] name) { } purePackageNames
  // lib.foldl' (acc: name: acc // harvest [ "test-coverage" "pytest-coverage" ] name) { } maturinPackageNames;

ruffChecks = lib.foldl' (acc: name: acc // { "${name}-ruff" = mkRuffCheck name; }) { } packageNames;

checks = packageChecks // ruffChecks;
```

This yields `pnt-core-pytest`, `pnt-core-basedpyright`, `pnt-functional-pytest`, `pnt-functional-basedpyright`, `pnt-cli-pytest`, `pnt-cli-clippy`, `pnt-cli-doc`, `pnt-cli-fmt`, `pnt-cli-test`, plus the `pnt-*-ruff` checks, with `gitleaks` and `treefmt` contributed separately by `formatting.nix`.
One mechanism, one naming convention, for both package kinds.

The harvest is taken at `py313` only, matching `defaultPython`, even though both `pythonSets.py312` and `pythonSets.py313` are built.
Fanning every check across both interpreters doubles CI cost for marginal coverage at template altitude; downstream repos that need matrix coverage change the fold to a `concatMapAttrs` over `pythonSets` with a `<ver>-<pkg>-<check>` naming scheme.

The `pnt-cli` module's own `checks` attribute, which currently performs the rename and coverage-drop locally, becomes redundant once the central harvest exists.
The module is reduced to exporting its overlay; the crane-maturin test construction (venv-from-`cargoArtifacts`) is unchanged, and only the harvest and naming unify.
The construction of the maturin tests still differs from the pure tests — crane-maturin builds from cargo artifacts, the pure tests from `mkVirtualEnv` — so "one mechanism" holds for harvest and naming, which is the part that matters for maintainability, not for test-derivation construction.

## Dependency-group conventions

The dedicated-group venv idiom requires each group to exist and to be minimal, so each check pulls exactly one group.
Current pyprojects bundle `lint`, `test`, and `types` and set `default-groups = ["lint", "test", "types"]`.
The design splits responsibilities so the per-check venvs name their group explicitly while `default-groups` continues to govern only `deps.default`.

```toml
[dependency-groups]
test = [
  "hypothesis>=6.125.1",
  "pytest-cov>=6.0.0",
  "pytest>=8.3.4",
  "xdoctest>=1.2.0",
]
typecheck = [
  "basedpyright>=1.21",
]
lint = [ "ruff>=0.9.4" ]
dev = [
  { include-group = "test" },
  { include-group = "typecheck" },
  { include-group = "lint" },
  { include-group = "interactive" },
]

[tool.uv]
default-groups = ["lint", "test", "typecheck"]
```

Two semantic pyproject changes are part of this work.
The existing `types` dependency group is renamed to `typecheck`, and the pinned `pyright` is replaced with `basedpyright`, so the Nix check tool and the pixi/uv parity path agree on the type engine that CLAUDE.md and the project skills already standardize on.
Each affected package's `uv.lock` is regenerated afterward, and basedpyright is confirmed to resolve into the lock.

The same "type-check needs the test toolchain visible" rationale that drives the Nix venv's `["typecheck" "test"]` group spec also governs the conda/uv parity paths, because basedpyright scans `src/<pkg>/tests` regardless of which path invokes it.
The pixi `typecheck` environment therefore carries both features, `{ features = ["test", "typecheck"], ... }`, and each package's `pixi.lock` is regenerated so the conda parity path resolves `basedpyright`, `pytest`, and the rest of the test toolchain under that environment.
The `just ci-typecheck` recipe likewise runs `uv sync` before `uv run --no-sync basedpyright src/`: the dev shell exports `UV_NO_SYNC=1`, so without an explicit sync the project venv is empty and basedpyright cannot resolve any import.
After the sync the recipe type-checks all three packages — including `pnt-cli`, which now carries `basedpyright` in its `typecheck` group even though no Nix basedpyright check is emitted for it.

Runtime `[project.dependencies]` (for example `pnt-functional`'s `beartype` and `expression`) are in every venv unconditionally because the package node depends on them.
Check-specific tools live in named groups, pulled per-check via `{ <pkg> = ["<group>"]; }`, never via `deps.default`.
After this design, `deps.default` is consumed only by the dev shell and the `packages` aggregate venv, not by any check.
The `lint` group is retained solely for the pixi/uv non-Nix parity path, since ruff in the Nix check comes from nixpkgs rather than from a venv.
For `pnt-cli`, the maturin path owns its own pytest and type surface through crane-maturin, so no Nix basedpyright check is emitted for it (the structural invariant exempts it, since its type surface is the Rust crate).
Its dependency groups are nonetheless renamed to the uniform `typecheck`/`basedpyright` naming and its `uv.lock` regenerated, so the dependency-group vocabulary is consistent across all three packages even though the maturin path, not a uv2nix typecheck venv, regulates its types.

## Per-package basedpyright

Type-checking is performed per package, one derivation per package's own `typecheck` venv, replacing the single merged `basedpyright-env`.
The merged-venv approach unions `deps.default` across all pure packages into one environment, which can mask a missing dependency in one package that another package's dependencies happen to provide.
That is a false negative, and a severe one in the validation-assurance sense, because it fails precisely under the plausible bug where a package under-declares a dependency.

Per-package isolation makes each package's venv reflect exactly that package's resolved dependency closure, reuses the harvest fold verbatim, and makes the regulator-to-artifact relation one-to-one so the structural invariant below can assert type coverage by name (`pnt-functional-basedpyright`) rather than against a single global `basedpyright`.
The extra venvs are cheap: the underlying wheels are shared and the venvs are symlink farms, not independent compilations.
basedpyright still consumes a venv for import resolution, which is why it is venv-backed while ruff is not.

## Structural traceability invariant

The check set is the compositional-continuous-verification closure operator for the repository, and the traceability obligation is that every package that requires regulation has at least one regulator targeting it.
A small nix-unit-style meta-check makes this mechanical: it asserts that every package emits its required regulators (`ruff`, `basedpyright`, `pytest`) and that every package is exposed in the `packages` output, with explicit, reason-carrying exemptions.

The invariant is the forcing function that keeps coverage uniform as the template is instantiated downstream (hodosome, sciexp/data).
A downstream author who adds `packages/foo/` and forgets its tests gets a red `nix flake check` rather than silent invisibility.

```nix
{ ... }:
{
  perSystem =
    { self', lib, pkgs, packageNames, ... }:
    let
      required = [ "ruff" "basedpyright" "pytest" ];
      exemptions = {
        pnt-cli = { basedpyright = "type surface is the Rust crate; clippy regulates it"; };
      };
      checkNames = builtins.attrNames self'.checks;
      missing = lib.flatten (
        map (
          pkg:
          map (reg: { inherit pkg reg; }) (
            builtins.filter (
              reg:
              !(builtins.elem "${pkg}-${reg}" checkNames)
              && !(exemptions ? ${pkg} && exemptions.${pkg} ? ${reg})
            ) required
          )
        ) packageNames
      );
      packagesMissingFromOutput = builtins.filter (n: !(self'.packages ? ${n})) packageNames;
    in
    {
      checks.invariant-traceability =
        pkgs.runCommand "invariant-traceability"
          {
            missingRegulators = builtins.toJSON missing;
            missingFromOutput = builtins.toJSON packagesMissingFromOutput;
          }
          ''
            if [ "$missingRegulators" != "[]" ]; then
              echo "traceability: packages missing required regulators: $missingRegulators" >&2
              exit 1
            fi
            if [ "$missingFromOutput" != "[]" ]; then
              echo "traceability: packages absent from packages.<system>: $missingFromOutput" >&2
              exit 1
            fi
            touch $out
          '';
    };
}
```

The invariant has a precondition currently unmet: `pnt-cli` is absent from the `packages` output, which exposes only the aggregate `pntCore312`/`pntCore313`/`default` venvs.
The invariant cannot enumerate a package that is not in `packages`, so each package is also exposed as a buildable `packages.<name>` entry — a per-package production venv for the pure packages, and the wheel for `pnt-cli`.
The per-package basedpyright decision and the by-name invariant are coupled: adopting the invariant while keeping a merged basedpyright would force exempting type-check for every package and defeat it, so the per-package split satisfies the coupling.

Scope, per the CCV taxonomy, is traceability plus a minimal exemption audit where every exemption carries a reason.
Adequacy (whether the regulators saturate each operating envelope) and integrity (mutation-kill) are out of scope at template altitude and are recorded as not-applicable-for-now.
The invariant uses `runCommand` rather than a true nix-unit derivation to avoid adding a flake input for a single invariant; downstream repos that grow more invariants graduate to nix-unit proper.

## File-by-file delta

The implementation record below maps each change to its file.

| File | Change |
|------|--------|
| `modules/python.nix` | Remove the internal `mkPythonSet` re-derivations in the old check builders; add `pyprojectTestOverrides` (pytest, basedpyright, beartype conftest) and compose it into `mkPythonSet`; keep `mkRuffCheck`; remove the bespoke `mkPurePytestCheck`, `pureChecks`, and `basedpyrightCheck` builders and the standalone `rustChecks` fold; document the editable-vs-production rule. |
| `modules/checks/per-package.nix` (new) | The uniform harvest fold producing `<pkg>-<check>` for pure and maturin packages, plus the `ruffChecks` fold; assembles `checks`. |
| `modules/checks/invariants.nix` (new) | The traceability meta-check asserting required regulators and `packages`-output exposure, with reason-carrying exemptions. |
| `modules/formatting.nix` | Set `treefmt.flakeCheck = true` so the treefmt formatting regulator participates in `nix flake check` rather than only the optional pre-commit hook; the full-tree `checks.gitleaks` scan is unchanged. |
| `modules/packages.nix` | Expose each package as a `packages.<name>` entry (per-package production venv; for `pnt-cli` the wheel) alongside the existing aggregates, satisfying the invariant precondition; the `perSystem` destructure drops unused arguments (`config`, `self'`, `pkgs`, `editablePythonSets`, `pythonVersions`, `purePackageNames`) and the top-level `inputs`. |
| `nix/packages/pnt-cli/default.nix` | Reduce the module to exporting its overlay; remove the local `checks` rename and coverage-drop, which the central harvest now performs; crane-maturin construction is unchanged. |
| `packages/pnt-core/pyproject.toml` | Rename `types` group to `typecheck`; replace `pyright` with `basedpyright`; keep `lint` and `test` minimal; adjust `default-groups`. |
| `packages/pnt-functional/pyproject.toml` | Same group and engine changes as `pnt-core`. |
| `packages/pnt-functional/src/pnt_functional/tests/test_main.py` | Convert the absolute `from pnt_functional.main import ...` to a relative `from ..main import ...` (mirroring `pnt-core` and carrying the omnix#425 rationale) so `--cov=src/pnt_functional/` instruments the in-tree src rather than the installed wheel; without this the check emits a no-data-collected warning and reports 0% coverage. |
| `packages/pnt-functional/src/pnt_functional/tests/__init__.py` (new) | Add the empty package marker that `pnt-core` already carries. The relative import requires the `tests` directory to be a package so pytest imports the test module as `pnt_functional.tests.test_main` with a known parent package; without it the relative import raises `ImportError: attempted relative import with no known parent package`. |
| `packages/pnt-core/uv.lock`, `packages/pnt-functional/uv.lock`, `packages/pnt-cli/uv.lock` | Regenerate after the group and engine changes; confirm basedpyright resolves into each lock and bare `pyright` is gone. |
| `packages/pnt-core/pixi.lock`, `packages/pnt-functional/pixi.lock` | Regenerate so the conda parity path resolves `basedpyright` under the `typecheck` environment; the old `types` environment and `pyright` are gone. `pnt-cli` has no `[tool.pixi]` configuration and so has no pixi.lock. |
| `packages/pnt-cli/pyproject.toml` | Rename the `types` group to `typecheck` and replace `pyright` with `basedpyright>=1.21`, matching the pure-package vocabulary, and regenerate `uv.lock`. No Nix basedpyright check is emitted for `pnt-cli`; the structural invariant continues to exempt it because its type surface is the Rust crate, and the rename is for dependency-group consistency only. |

The end state is a green `nix flake check` on the local system for the affected checks.
The traceability invariant is intended to be observed failing under the current `packages`-output gap and then to turn green once each package is exposed, which is a small demonstration of the CCV integrity property the template is otherwise too small to assert via mutation testing.
