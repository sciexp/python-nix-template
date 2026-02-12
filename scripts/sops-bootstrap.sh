#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-dev}"  # 'dev' or 'ci'
METHOD="${2:-ssh}"  # 'ssh' or 'age'

echo "🔐 SOPS Key Bootstrap/Rotation"
echo "   Role: $ROLE"
echo "   Method: $METHOD"
echo

# Verify .sops.yaml exists
if [ ! -f .sops.yaml ]; then
  echo "❌ .sops.yaml not found. Cannot proceed."
  exit 1
fi

# Check if this is rotation (key already exists) or bootstrap (placeholder)
CURRENT_KEY=$(grep "^  - &${ROLE} " .sops.yaml | awk '{print $3}')

# Placeholder keys indicate this is a fresh bootstrap
# gitleaks:allow - age public keys used as placeholders
if [ "$CURRENT_KEY" = "age1dn8w7y4t4h23fmeenr3dghfz5qh53jcjq9qfv26km3mnv8l44g0sghptu3" ] || \
   [ "$CURRENT_KEY" = "age1m9m8h5vqr7dqlmvnzcwshmm4uk8umcllazum6eaulkdp3qc88ugs22j3p8" ]; then
  IS_ROTATION=false
  echo "🆕 Placeholder key detected - this is BOOTSTRAP"
else
  IS_ROTATION=true
  echo "🔄 Real key detected - this is a ROTATION"
fi

# Generate new key
if [ "$METHOD" = "ssh" ]; then
  echo "🔑 Generating SSH key pair..."
  KEY_FILE=$(mktemp)
  trap "rm -f $KEY_FILE ${KEY_FILE}.pub" EXIT

  ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -C "${ROLE}@python-nix-template"
  PUBLIC_KEY=$(ssh-to-age < "${KEY_FILE}.pub")
  PRIVATE_KEY=$(cat "$KEY_FILE")
  PRIVATE_AGE_KEY=$(ssh-to-age -private-key -i "$KEY_FILE")

  echo "   SSH public key: $(cat ${KEY_FILE}.pub)"
  echo "   Age public key: $PUBLIC_KEY"
else
  echo "🔑 Generating age key pair..."
  KEY_FILE=$(mktemp)
  rm -f "$KEY_FILE"  # age-keygen expects to create the file itself
  trap "rm -f $KEY_FILE" EXIT

  age-keygen -o "$KEY_FILE" 2>&1 | tee /tmp/keygen-output.txt
  PUBLIC_KEY=$(grep -i "public key:" /tmp/keygen-output.txt | cut -d: -f2 | xargs)
  PRIVATE_KEY=$(cat "$KEY_FILE")
  rm -f /tmp/keygen-output.txt
fi

echo
echo "📋 Generated key:"
echo "   Public:  $PUBLIC_KEY"
echo

# Check if key already exists in .sops.yaml
if grep -q "$PUBLIC_KEY" .sops.yaml; then
  echo "⚠️  This public key already exists in .sops.yaml"
  exit 1
fi

# Update .sops.yaml based on rotation or bootstrap
cp .sops.yaml .sops.yaml.backup

if [ "$IS_ROTATION" = true ]; then
  echo "📝 Adding new key as ${ROLE}-next for rotation..."

  # Add new key anchor after current key
  sed -i.tmp "/^  - &${ROLE} /a\\
  - \&${ROLE}-next ${PUBLIC_KEY}" .sops.yaml

  # Add to creation_rules (both yaml and json)
  sed -i.tmp "/- \*${ROLE}$/a\\
          - \*${ROLE}-next" .sops.yaml

  rm .sops.yaml.tmp
  echo "✅ Added ${ROLE}-next to .sops.yaml"
else
  echo "📝 Replacing ${ROLE} key in .sops.yaml..."
  sed -i.tmp "s|^  - \&${ROLE} .*|  - \&${ROLE} ${PUBLIC_KEY}|" .sops.yaml
  rm .sops.yaml.tmp
  echo "✅ Updated ${ROLE} key in .sops.yaml"
fi

# Create or update encrypted files
if [ ! -f vars/shared.yaml ]; then
  echo
  echo "📝 Creating vars/shared.yaml template..."
  mkdir -p vars
  cat > /tmp/shared-template.yaml << 'EOF'
CACHIX_AUTH_TOKEN: REPLACE_ME
CACHIX_CACHE_NAME: REPLACE_ME
GITGUARDIAN_API_KEY: REPLACE_ME
CLOUDFLARE_API_TOKEN: REPLACE_ME
CLOUDFLARE_ACCOUNT_ID: REPLACE_ME
CI_AGE_KEY: REPLACE_ME
EOF

  # For bootstrap, we can encrypt immediately
  if [ "$ROLE" = "dev" ]; then
    # Move template to vars/ first so path regex matches
    mv /tmp/shared-template.yaml vars/shared-template.yaml

    # Create temporary .sops.yaml with only dev key to avoid encrypting for placeholder CI key
    cat > /tmp/sops-bootstrap.yaml << SOPSEOF
keys:
  - &dev ${PUBLIC_KEY}

creation_rules:
  - path_regex: vars/.*\.yaml$
    key_groups:
      - age:
          - *dev
SOPSEOF

    echo "$PRIVATE_KEY" > /tmp/bootstrap-key.txt
    SOPS_AGE_KEY_FILE=/tmp/bootstrap-key.txt sops --config /tmp/sops-bootstrap.yaml -e vars/shared-template.yaml > vars/shared.yaml
    rm /tmp/bootstrap-key.txt /tmp/sops-bootstrap.yaml vars/shared-template.yaml
    echo "✅ Created vars/shared.yaml (edit with: just edit-secrets)"
    echo "   Note: After generating CI key, run 'just updatekeys' to add it"
  else
    echo "⚠️  Cannot encrypt without dev key. Create dev key first."
    echo "   Unencrypted template at: /tmp/shared-template.yaml"
    echo "   Run: just sops-bootstrap dev"
    rm -f /tmp/shared-template.yaml
  fi
else
  echo
  echo "🔄 Updating keys for existing encrypted files..."
  just updatekeys
  echo "✅ Keys updated"
fi

# Display private key and next steps
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 SAVE THIS PRIVATE KEY SECURELY!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$METHOD" = "ssh" ]; then
  echo
  echo "SSH Private Key:"
  echo "$PRIVATE_KEY"
  echo
  echo "Age Private Key (for SOPS):"
  echo "$PRIVATE_AGE_KEY"
else
  echo
  echo "Age Private Key:"
  echo "$PRIVATE_KEY"
fi

echo
echo "Public Key (safe to share):"
echo "$PUBLIC_KEY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Role-specific instructions
if [ "$ROLE" = "dev" ]; then
  echo "📥 To install this dev key locally:"
  echo
  echo "   Option 1: Use sops-add-key recipe (interactive)"
  echo "   just sops-add-key"
  echo
  echo "   Option 2: Manual installation"
  echo "   mkdir -p ~/.config/sops/age"
  echo "   cat >> ~/.config/sops/age/keys.txt << KEYEOF"
  echo "   # python-nix-template dev key"
  echo "   # public key: ${PUBLIC_KEY}"
  echo "   ${PRIVATE_KEY}"
  echo "   KEYEOF"
  echo
  echo "   Then test: just show-secrets"
elif [ "$ROLE" = "ci" ]; then
  echo "📤 To use this CI key:"
  echo
  echo "   1. Save private key to Bitwarden (for backup/recovery)"
  echo
  echo "   2. Add to vars/shared.yaml as CI_AGE_KEY:"
  echo "   just edit-secrets"
  echo "   # Add line: CI_AGE_KEY: ${PRIVATE_KEY}"
  echo
  echo "   3. Upload to GitHub secrets:"
  echo "   just sops-upload-github-key"
  echo "   # Paste the private key when prompted"
fi

echo
echo "📋 Next steps:"
if [ "$IS_ROTATION" = true ]; then
  echo "   1. Install/upload the new key (see instructions above)"
  echo "   2. Test decryption works: just show-secrets"
  echo "   3. Test CI workflow: just gh-ci-run"
  echo "   4. After verification, remove old key: just sops-finalize-rotation ${ROLE}"
else
  echo "   1. Install/upload the key (see instructions above)"
  echo "   2. If bootstrapping dev key, generate CI key: just sops-bootstrap ci"
  echo "   3. Edit secrets: just edit-secrets"
  echo "   4. Check requirements: just sops-check-requirements"
  echo "   5. Upload to GitHub: just sops-setup-github"
fi

echo
echo "💾 Backup saved: .sops.yaml.backup"
