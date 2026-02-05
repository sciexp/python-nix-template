{ inputs, ... }:

{
  flake = rec {
    templates.default = {
      description = "A Python project template for Nix using uv2nix and flake-parts";
      path = builtins.path { path = inputs.self; };
      welcomeText = ''
        Welcome to the python-nix-template!

        NOTE: If you're reusing a preexisting directory for PROJECT_DIRECTORY you
        may need to run `direnv revoke $PROJECT_DIRECTORY` to unload the environment
        before proceeding.

        Otherwise, don't forget to `cd` into your new project directory.

        If you do not have nix and direnv installed, check

        ```bash
        make -n bootstrap
        ```

        and rerun without the `-n` if you are comfortable with the commands. Otherwise,
        manually install the nix package manager and direnv.

        In order to recognize the `flake.nix` and associated files, create a git 
        repository, stage the files, and run `direnv allow` to load the environment.
        You might need to run `direnv revoke` first if you're reusing a directory
        where you have previously run `direnv allow`.

        You can copy and paste

        ```bash
        git init && git commit --allow-empty -m "initial commit (empty)" && git add . && direnv allow
        ```

        or, if you prefer, run the commands manually to verify or modify them

        ```bash
        ❯ git init
        Initialized empty Git repository in ...

        ❯ git commit --allow-empty -m "initial commit (empty)"
        [main (root-commit) bba59e7] initial commit (empty)

        ❯ git add .

        ❯ direnv allow
        ```

        Each package maintains its own lock file. Generate them with:

        ```bash
        for pkg in packages/*/; do [ -f "$pkg/pyproject.toml" ] && (cd "$pkg" && nix run github:NixOS/nixpkgs/nixos-unstable#uv -- lock); done
        git add .
        ```

        You should then be able to run `just test-all` inside the nix devshell
        to verify all packages are working. See the README for more information.

        ┌─────────────────────────────────────────────────────────────────────┐
        │  ❄️  Nix binary cache notice                                       │
        │                                                                     │
        │  You may see a warning about an HTTP 401 error from cachix.org.    │
        │  This is expected and harmless — the template's binary cache name  │
        │  was replaced with your project name during instantiation, and     │
        │  that cache does not exist yet.                                     │
        │                                                                     │
        │  Nix will skip the missing cache and build from source. To set up  │
        │  your own binary cache later, see:                                  │
        │                                                                     │
        │    https://docs.cachix.org (hosted)                                │
        │    https://nix.dev/guides/recipes/sharing-dependencies (self-hosted)│
        │                                                                     │
        │  Update extra-substituters and extra-trusted-public-keys in your   │
        │  flake.nix once your cache is ready.                               │
        └─────────────────────────────────────────────────────────────────────┘
      '';
    };

    # https://omnix.page/om/init.html#spec
    om.templates.python-nix-template = {
      template = templates.default;
      params = [
        {
          name = "package-name-kebab-case";
          description = "Name of the Python package (kebab-case)";
          placeholder = "python-nix-template";
        }
        {
          name = "package-name-snake-case";
          description = "Name of the Python package (snake_case)";
          placeholder = "python_nix_template";
        }
        {
          name = "monorepo-package";
          description = "Include the functional programming monorepo package in the project";
          paths = [ "packages/pnt-functional" ];
          value = false;
        }
        {
          name = "git-org";
          description = "GitHub organization or user name";
          placeholder = "sciexp";
        }
        {
          name = "author";
          description = "Author name";
          placeholder = "Your Name";
        }
        {
          name = "author-email";
          description = "Author email";
          placeholder = "your.email@example.com";
        }
        {
          name = "project-description";
          description = "Project description for documentation";
          placeholder = "A Python project template for Nix using uv2nix and flake-parts";
        }
        {
          name = "vscode";
          description = "Include the VSCode settings folder (./.vscode)";
          paths = [ ".vscode" ];
          value = true;
        }
        {
          name = "github-ci";
          description = "Include GitHub Actions workflow configuration";
          paths = [ ".github" ];
          value = true;
        }
        {
          name = "docs";
          description = "Include documentation site infrastructure (MkDocs + Cloudflare deployment)";
          paths = [
            "docs"
            ".github/workflows/deploy-docs.yaml"
          ];
          value = true;
        }
        {
          name = "nix-template";
          description = "Keep the flake template in the project";
          paths = [
            "**/template.nix"
            ".github/workflows/template.yaml"
          ];
          value = false;
        }
      ];
      tests = {
        default = {
          params = {
            package-name = "awesome-package";
            author = "John Doe";
            author-email = "john@example.com";
          };
          asserts = {
            source = {
              "ruff.toml" = true;
              "flake.nix" = true;
              ".github/workflows/ci.yaml" = true;
              ".vscode" = true;
              "modules/template.nix" = false;
            };
            packages.default = { };
          };
        };
      };
    };
  };
}
