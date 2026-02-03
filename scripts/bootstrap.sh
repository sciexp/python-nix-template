#!/usr/bin/env bash
# Self-contained bootstrap script for python-nix-template.
# Intended for curl one-liner pre-clone onboarding:
#   curl -sSf https://raw.githubusercontent.com/sciexp/python-nix-template/main/scripts/bootstrap.sh | bash
#
# This script must be kept in sync with the Makefile bootstrap targets
# manually (discipline-based, not DRY import) since it must remain
# self-contained for the curl use case.
set -euo pipefail

echo "python-nix-template bootstrap"
echo "=============================="
echo

# Install Nix
echo "Checking Nix installation..."
if command -v nix >/dev/null 2>&1; then
    echo "Nix is already installed."
    nix --version
else
    echo "Installing Nix via NixOS community installer..."
    NIX_INSTALLER_VERSION="2.33.0"
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64)  PLATFORM="x86_64-linux" ;;
        Linux-aarch64) PLATFORM="aarch64-linux" ;;
        Darwin-x86_64) PLATFORM="x86_64-darwin" ;;
        Darwin-arm64)  PLATFORM="aarch64-darwin" ;;
        *) echo "Unsupported platform: $(uname -s)-$(uname -m)"; exit 1 ;;
    esac
    INSTALLER_URL="https://github.com/NixOS/nix-installer/releases/download/${NIX_INSTALLER_VERSION}/nix-installer-${PLATFORM}"
    echo "Platform: ${PLATFORM}"
    echo "Downloading from: ${INSTALLER_URL}"
    curl --proto '=https' --tlsv1.2 -sSf -L --retry 3 --retry-delay 5 \
        "${INSTALLER_URL}" -o /tmp/nix-installer && chmod +x /tmp/nix-installer
    /tmp/nix-installer install --no-confirm \
        --extra-conf "trusted-users = root @admin @wheel"
fi
echo

# Install direnv
echo "Checking direnv installation..."
if command -v direnv >/dev/null 2>&1; then
    echo "direnv is already installed."
else
    echo "Installing direnv..."
    curl -sfL https://direnv.net/install.sh | bash
fi
echo

# Verify
echo "Verifying installation..."
echo

if ! command -v nix >/dev/null 2>&1; then
    echo "Nix not found after installation. Start a new shell session and re-run."
    exit 1
fi

if ! nix flake --help >/dev/null 2>&1; then
    echo "Nix flakes not enabled."
    exit 1
fi

echo "Nix and flakes verified."
echo

echo "Bootstrap complete."
echo
echo "Next steps:"
echo "  1. Start a new shell session"
echo "  2. Clone the repository"
echo "  3. cd into the project directory"
echo "  4. Run 'nix develop' to enter the development environment"
echo "  5. Run 'make verify' for full environment verification"
echo "  6. Run 'make setup-user' to generate your age key for secrets"
echo "  7. Use 'just ...' to run tasks"
echo
echo "See https://direnv.net/docs/hook.html to set up automatic environment activation."
