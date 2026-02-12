#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
fi

echo "🚀 Comprehensive GitHub Secrets & Variables Setup"
echo "   Repository: $REPO"
echo
echo "This will:"
echo "  1. Upload GitHub variables (from environment or vars/shared.yaml)"
echo "  2. Upload GitHub secrets (from vars/shared.yaml)"
echo "  3. Skip SOPS_AGE_KEY (use sops-upload-github-key separately)"
echo
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 0
fi

# Check if SOPS_AGE_KEY is set
echo "Checking SOPS_AGE_KEY status..."
if gh secret list --repo="$REPO" 2>/dev/null | grep -q "SOPS_AGE_KEY"; then
  echo "✅ SOPS_AGE_KEY already set in GitHub"
else
  echo "⚠️  SOPS_AGE_KEY not set in GitHub"
  echo "   This is required for CI to decrypt secrets."
  echo
  read -p "Upload SOPS_AGE_KEY now? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    scripts/sops-upload-github-key.sh "$REPO"
  else
    echo "   Skipping SOPS_AGE_KEY upload."
    echo "   Run later: just sops-upload-github-key"
  fi
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 Uploading GitHub variables..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

just ghvars "$REPO"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 Uploading GitHub secrets (except SOPS_AGE_KEY)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Upload secrets from vars/shared.yaml
sops exec-env vars/shared.yaml "
  set -euo pipefail

  if [ -n \"\${CACHIX_AUTH_TOKEN:-}\" ] && [ \"\$CACHIX_AUTH_TOKEN\" != \"REPLACE_ME\" ]; then
    gh secret set CACHIX_AUTH_TOKEN --repo='$REPO' --body=\"\$CACHIX_AUTH_TOKEN\"
    echo '   ✅ CACHIX_AUTH_TOKEN'
  fi

  if [ -n \"\${GITGUARDIAN_API_KEY:-}\" ] && [ \"\$GITGUARDIAN_API_KEY\" != \"REPLACE_ME\" ]; then
    gh secret set GITGUARDIAN_API_KEY --repo='$REPO' --body=\"\$GITGUARDIAN_API_KEY\"
    echo '   ✅ GITGUARDIAN_API_KEY'
  fi

  if [ -n \"\${CLOUDFLARE_API_TOKEN:-}\" ] && [ \"\$CLOUDFLARE_API_TOKEN\" != \"REPLACE_ME\" ]; then
    gh secret set CLOUDFLARE_API_TOKEN --repo='$REPO' --body=\"\$CLOUDFLARE_API_TOKEN\"
    echo '   ✅ CLOUDFLARE_API_TOKEN'
  fi

  if [ -n \"\${CLOUDFLARE_ACCOUNT_ID:-}\" ] && [ \"\$CLOUDFLARE_ACCOUNT_ID\" != \"REPLACE_ME\" ]; then
    gh secret set CLOUDFLARE_ACCOUNT_ID --repo='$REPO' --body=\"\$CLOUDFLARE_ACCOUNT_ID\"
    echo '   ✅ CLOUDFLARE_ACCOUNT_ID'
  fi

  echo
  echo '   ℹ️  SOPS_AGE_KEY skipped (upload separately with: just sops-upload-github-key)'
"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ GitHub setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "Verification:"
echo "  gh secret list --repo=$REPO"
echo "  gh variable list --repo=$REPO"
echo
echo "Test CI:"
echo "  just gh-ci-run"
