{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:

{
  perSystem =
    { system, pkgs, ... }:
    {
      packages.fix-template-names = pkgs.writeShellApplication {
        name = "fix-template-names";
        runtimeInputs = with pkgs; [
          coreutils
          gnused
          gnugrep
          findutils
          file
        ];
        text = ''
          #!/usr/bin/env bash

          set -euo pipefail

          # Colors for output
          GREEN='\033[0;32m'
          YELLOW='\033[1;33m'
          RED='\033[0;31m'
          NC='\033[0m' # No Color

          # Default old names
          OLD_NAME="python-nix-template"
          OLD_UNDERSCORE="python_nix_template"

          # Get the current directory name as default new name
          DEFAULT_NEW_NAME=$(basename "$(pwd)")
          # Convert to underscore version
          DEFAULT_NEW_UNDERSCORE=$(echo "$DEFAULT_NEW_NAME" | tr '-' '_')

          # Use command line argument if provided, otherwise use defaults
          if [ $# -eq 1 ]; then
            NEW_NAME="$1"
            # Convert to underscore version
            NEW_UNDERSCORE=$(echo "$NEW_NAME" | tr '-' '_')
          elif [ $# -eq 0 ]; then
            NEW_NAME="$DEFAULT_NEW_NAME"
            NEW_UNDERSCORE="$DEFAULT_NEW_UNDERSCORE"
          else
            echo -e "''${RED}Error: Too many arguments.''${NC}"
            echo "Usage: fix-template-names [new-name]"
            echo "If no argument is provided, the current directory name ($DEFAULT_NEW_NAME) will be used."
            exit 1
          fi

          echo -e "''${YELLOW}Starting replacement of template names...''${NC}"
          echo -e "''${YELLOW}Replacing $OLD_NAME with $NEW_NAME''${NC}"
          echo -e "''${YELLOW}Replacing $OLD_UNDERSCORE with $NEW_UNDERSCORE''${NC}"

          # Find all text files in the project (excluding .git, node_modules, and other common directories to ignore)
          # and replace the strings in-place
          find . -type f \
              -not -path "*/\.*" \
              -not -path "*/node_modules/*" \
              -not -path "*/venv/*" \
              -not -path "*/build/*" \
              -not -path "*/dist/*" \
              -not -path "*/\__pycache__/*" \
              -exec grep -l "$OLD_NAME\|$OLD_UNDERSCORE" {} \; | while read -r file; do
              echo "Processing: $file"
              
              # Check if file is binary
              if file "$file" | grep -q "binary"; then
                  echo "  Skipping binary file"
                  continue
              fi
              
              # Make replacements
              sed -i.bak "s/$OLD_NAME/$NEW_NAME/g" "$file"
              sed -i.bak "s/$OLD_UNDERSCORE/$NEW_UNDERSCORE/g" "$file"
              
              # Remove backup files
              rm -f "''${file}.bak"
          done

          echo -e "''${GREEN}Replacement complete!''${NC}"
          echo -e "''${YELLOW}Note: You may need to rebuild or reinstall your package after these changes.''${NC}"
        '';
      };
    };
}
