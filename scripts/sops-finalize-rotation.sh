#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-dev}"

echo "🧹 Finalize SOPS key rotation for role: $ROLE"
echo
echo "This will:"
echo "  1. Remove old ${ROLE} key from .sops.yaml"
echo "  2. Rename ${ROLE}-next to ${ROLE}"
echo "  3. Update all encrypted files"
echo
echo "⚠️  Only proceed if you have verified the new key works!"
echo
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  exit 0
fi

# Check if -next key exists
if ! grep -q "\&${ROLE}-next" .sops.yaml; then
  echo "❌ No ${ROLE}-next key found in .sops.yaml"
  echo "   Nothing to finalize. Run rotation first: just sops-bootstrap $ROLE"
  exit 1
fi

# Backup
cp .sops.yaml .sops.yaml.pre-finalize

# Get old and new keys
OLD_KEY=$(grep "^  - &${ROLE} " .sops.yaml | awk '{print $3}')
NEW_KEY=$(grep "^  - &${ROLE}-next " .sops.yaml | awk '{print $3}')

echo "Old ${ROLE} key: $OLD_KEY"
echo "New ${ROLE} key: $NEW_KEY"
echo

# Remove old key line
sed -i.tmp "/^  - &${ROLE} ${OLD_KEY}/d" .sops.yaml

# Rename anchor definition, delete reference lines (original *dev now points to new key)
sed -i.tmp "s/&${ROLE}-next/\&${ROLE}/g" .sops.yaml
sed -i.tmp "/- \*${ROLE}-next/d" .sops.yaml

rm .sops.yaml.tmp

echo "📝 Updated .sops.yaml"
echo
echo "🔄 Updating encrypted files to remove old key..."
just updatekeys

echo
echo "✅ Rotation finalized!"
echo "   Old key: $OLD_KEY (REMOVED)"
echo "   New key: $NEW_KEY (now $ROLE)"
echo
echo "💾 Backup saved: .sops.yaml.pre-finalize"
echo
echo "⚠️  Update Bitwarden/key storage:"
echo "   - Mark old $ROLE key as 'revoked' or delete"
echo "   - Ensure new key is saved"
