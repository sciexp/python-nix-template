#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-dev}"
METHOD="${2:-ssh}"  # 'ssh' or 'age'

echo "🔄 Quick rotation workflow for $ROLE key (method: $METHOD)"
echo
echo "Step 1/3: Bootstrap new key..."
scripts/sops-bootstrap.sh "$ROLE" "$METHOD"
echo
read -p "Install/upload the new key, then press Enter to continue..." _
echo
echo "Step 2/3: Verify new key works..."
echo "Testing decryption..."
if just show-secrets > /dev/null 2>&1; then
  echo "✅ Decryption works!"
else
  echo "❌ Decryption failed. Fix the issue before finalizing."
  exit 1
fi
echo
read -p "Step 3/3: Finalize rotation? This removes the old key. (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  scripts/sops-finalize-rotation.sh "$ROLE"
else
  echo "Rotation not finalized. Run manually when ready:"
  echo "  just sops-finalize-rotation $ROLE"
fi
