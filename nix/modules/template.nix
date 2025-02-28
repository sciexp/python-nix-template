{ inputs, ... }:

{
  flake = rec {
    templates.default = {
      description = "A Python project template for Nix using uv2nix and flake-parts";
      path = builtins.path { path = inputs.self; };
    };

    # https://omnix.page/om/init.html#spec
    om.templates.default = {
      template = templates.default;
      params = [
        {
          name = "package-name";
          description = "Name of the Python package";
          placeholder = "python-nix-template";
        }
        {
          name = "git-org";
          description = "GitHub organization or user name";
          placeholder = "cameronraysmith";
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
          name = "nix-template";
          description = "Keep the flake template in the project";
          paths = [ "**/template.nix" ];
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
              "pyproject.toml" = true;
              "flake.nix" = true;
              ".github/workflows/ci.yaml" = true;
              ".vscode" = true;
              "nix/modules/template.nix" = false;
            };
            packages.default = { };
          };
        };
      };
    };
  };
}
