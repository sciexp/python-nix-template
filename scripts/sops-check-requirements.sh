#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Analyzing required secrets for GitHub workflows"
echo

# Find all secrets and vars referenced in workflows
if [ ! -d .github/workflows ]; then
  echo "❌ .github/workflows not found"
  exit 1
fi

WORKFLOW_SECRETS=$(grep -rh '\${{ secrets\.' .github/workflows/*.yaml 2>/dev/null | \
  grep -oP 'secrets\.\K[A-Z_]+' | sort -u || true)

WORKFLOW_VARS=$(grep -rh '\${{ vars\.' .github/workflows/*.yaml 2>/dev/null | \
  grep -oP 'vars\.\K[A-Z_]+' | sort -u || true)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 REQUIRED GITHUB SECRETS (set via gh secret set)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for secret in $WORKFLOW_SECRETS; do
  if [ "$secret" = "GITHUB_TOKEN" ]; then
    echo "   ✓ $secret (automatic, provided by GitHub)"
  elif [ "$secret" = "SOPS_AGE_KEY" ]; then
    echo "   ! $secret (CI age key - upload with: just sops-upload-github-key)"
  else
    echo "   → $secret (can be in vars/shared.yaml and uploaded via just ghsecrets)"
  fi
done

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 REQUIRED GITHUB VARIABLES (set via gh variable set)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -z "$WORKFLOW_VARS" ]; then
  echo "   (none found)"
else
  for var in $WORKFLOW_VARS; do
    echo "   → $var (upload with: just ghvars)"
  done
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 SOPS-MANAGED SECRETS (in vars/shared.yaml)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -f vars/shared.yaml ]; then
  echo "   ❌ vars/shared.yaml not found"
  echo "   Run: just sops-bootstrap dev"
else
  # Try to decrypt and check contents
  if ! SOPS_SECRETS=$(sops -d vars/shared.yaml 2>/dev/null); then
    echo "   ❌ Cannot decrypt vars/shared.yaml"
    echo "   Ensure you have the dev key installed: just sops-add-key"
  else
    # Check each secret
    SECRET_KEYS=$(echo "$SOPS_SECRETS" | grep -E '^[A-Z_]+:' | cut -d: -f1 || true)

    for key in $SECRET_KEYS; do
      VALUE=$(echo "$SOPS_SECRETS" | grep "^$key:" | cut -d: -f2- | xargs)
      if [ "$VALUE" = "REPLACE_ME" ] || [ -z "$VALUE" ]; then
        echo "   ❌ $key (NOT SET - edit with: just edit-secrets)"
      else
        # Show first/last few chars for verification
        DISPLAY="${VALUE:0:4}...${VALUE: -4}"
        echo "   ✓ $key ($DISPLAY)"
      fi
    done

    # Check for missing secrets that workflows need
    echo
    echo "   Missing from vars/shared.yaml but found in workflows:"
    FOUND_MISSING=false
    for secret in $WORKFLOW_SECRETS; do
      if [ "$secret" != "GITHUB_TOKEN" ] && [ "$secret" != "SOPS_AGE_KEY" ]; then
        if ! echo "$SECRET_KEYS" | grep -q "^$secret$"; then
          echo "   ❌ $secret"
          FOUND_MISSING=true
        fi
      fi
    done
    if [ "$FOUND_MISSING" = false ]; then
      echo "   ✓ All workflow secrets present in vars/shared.yaml"
    fi
  fi
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 NEXT STEPS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
echo "1. Ensure dev key is installed:"
echo "   just sops-add-key"
echo
echo "2. Edit secrets to add missing values:"
echo "   just edit-secrets"
echo
echo "3. Upload SOPS_AGE_KEY to GitHub:"
echo "   just sops-upload-github-key"
echo
echo "4. Upload other secrets and variables to GitHub:"
echo "   just sops-setup-github"
echo
echo "5. Verify GitHub secrets are set:"
echo "   gh secret list"
echo "   gh variable list"
