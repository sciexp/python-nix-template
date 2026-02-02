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
    echo "Installing Nix via Determinate Systems installer..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
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
