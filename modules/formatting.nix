{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.git-hooks.flakeModule
  ];

  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";
        # Expose treefmt as a flake check (checks.treefmt = build.check projectRoot)
        # so the formatting regulator participates in `nix flake check`, not only
        # the optional pre-commit hook. This is the flakeModule's default; set
        # explicitly to keep it from silently regressing.
        flakeCheck = true;
        programs.nixfmt.enable = true;
        programs.ruff-format.enable = true;
        programs.ruff-check.enable = true;
        programs.taplo.enable = true;
      };

      pre-commit.check.enable = false;
      pre-commit.settings = {
        package = pkgs.prek;
        hooks.treefmt.enable = true;
        hooks.gitleaks = {
          enable = true;
          name = "gitleaks";
          entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged --verbose --redact";
          language = "system";
          pass_filenames = false;
        };
      };

      # Full-tree gitleaks secret scan against the pinned flake source snapshot.
      # Uses --no-git because the Nix store path has no .git directory; covers
      # file contents only (not commit history).
      checks.gitleaks =
        pkgs.runCommand "gitleaks"
          {
            nativeBuildInputs = [ pkgs.gitleaks ];
            src = inputs.self;
          }
          ''
            cd "$src"
            gitleaks detect --no-git --verbose --redact --source .
            touch "$out"
          '';
    };
}
