# Structural-traceability invariant.
#
# A pure-eval runCommand asserting two coverage properties over the assembled
# flake outputs: every discovered package emits the required regulators
# {ruff, basedpyright, pytest} as <pkg>-<regulator> checks (with audited
# exemptions), and every package name appears in packages.<system>. Because this
# template is instantiated downstream, the invariant is the forcing function that
# keeps coverage uniform: a downstream author who adds packages/foo/ and forgets
# its checks gets a red `nix flake check` rather than silent invisibility.
#
# This is traceability plus a minimal exemption audit (each exemption carries a
# reason). Adequacy (regulators saturating each envelope) and mutation-kill
# integrity are out of scope at template altitude.
{
  perSystem =
    {
      self',
      pkgs,
      lib,
      packageNames,
      ...
    }:
    let
      required = [
        "ruff"
        "basedpyright"
        "pytest"
      ];

      exemptions = {
        # pnt-cli is a pyo3 native module: its type surface is the Rust crate,
        # regulated by pnt-cli-clippy and pnt-cli-doc, and its pytest comes from
        # the crane-maturin harvest rather than a uv2nix typecheck venv.
        pnt-cli = {
          basedpyright = "type surface is the Rust crate; clippy/doc regulate it";
        };
      };

      checkNames = builtins.attrNames self'.checks;

      missing = lib.flatten (
        map (
          pkg:
          map (reg: { inherit pkg reg; }) (
            builtins.filter (
              reg:
              !(builtins.elem "${pkg}-${reg}" checkNames) && !(exemptions ? ${pkg} && exemptions.${pkg} ? ${reg})
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
            touch "$out"
          '';
    };
}
