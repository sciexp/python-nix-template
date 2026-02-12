#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
fi

echo "🔐 Upload SOPS_AGE_KEY to GitHub Secrets"
echo "   Repository: $REPO"
echo
echo "This uploads the CI age private key so GitHub Actions can decrypt secrets."
echo
echo "You have two options:"
echo "  1. Paste the CI_AGE_KEY from Bitwarden (recommended for rotation)"
echo "  2. Extract from vars/shared.yaml (requires dev key to decrypt)"
echo
printf "Choose option (1/2): "
read -r OPTION

if [ "$OPTION" = "1" ]; then
  echo
  echo "Paste the AGE-SECRET-KEY (input will be hidden):"
  read -rs PRIVATE_KEY
  echo

  if [[ ! "$PRIVATE_KEY" =~ ^AGE-SECRET-KEY- ]]; then
    echo "❌ Invalid age private key format (must start with AGE-SECRET-KEY-)"
    exit 1
  fi
elif [ "$OPTION" = "2" ]; then
  if [ ! -f vars/shared.yaml ]; then
    echo "❌ vars/shared.yaml not found"
    exit 1
  fi

  echo "Extracting CI_AGE_KEY from vars/shared.yaml..."
  PRIVATE_KEY=$(sops -d vars/shared.yaml | grep "^CI_AGE_KEY:" | cut -d: -f2- | xargs)

  if [ -z "$PRIVATE_KEY" ] || [ "$PRIVATE_KEY" = "REPLACE_ME" ]; then
    echo "❌ CI_AGE_KEY not set in vars/shared.yaml"
    echo "   Run: just edit-secrets"
    exit 1
  fi
else
  echo "❌ Invalid option"
  exit 1
fi

echo "Uploading to GitHub..."
echo "$PRIVATE_KEY" | gh secret set SOPS_AGE_KEY --repo="$REPO"

echo "✅ SOPS_AGE_KEY uploaded successfully"
echo
echo "Verify with:"
echo "  gh secret list --repo=$REPO | grep SOPS_AGE_KEY"
echo
echo "Test with:"
echo "  just gh-ci-run --debug=true"
