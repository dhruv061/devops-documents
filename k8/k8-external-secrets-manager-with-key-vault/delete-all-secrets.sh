#!/usr/bin/env bash
set -euo pipefail

VAULT_NAME="${1:-}"

if [[ -z "$VAULT_NAME" ]]; then
  echo "Error: Missing Vault Name"
  echo "Usage: ./delete-all-secrets.sh <vault-name>"
  echo "Example: ./delete-all-secrets.sh artha-backend-kv"
  exit 1
fi

echo "Fetching all secrets from Key Vault: $VAULT_NAME..."

# Get a list of all secret names
SECRETS=$(az keyvault secret list --vault-name "$VAULT_NAME" --query "[].id" -o tsv | awk -F'/' '{print $NF}')

if [[ -z "$SECRETS" ]]; then
  echo "No secrets found in $VAULT_NAME."
  exit 0
fi

# Count the secrets
TOTAL=$(echo "$SECRETS" | wc -w)
echo "Found $TOTAL secrets to delete."

# 🔴 SAFETY CHECK 🔴
echo "⚠️ WARNING: This will delete $TOTAL secrets from $VAULT_NAME!"
read -p "Are you absolutely sure? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 1
fi

# Loop through and delete each secret
COUNT=0
for SECRET_NAME in $SECRETS; do
  COUNT=$((COUNT + 1))
  echo "[$COUNT/$TOTAL] Deleting secret: $SECRET_NAME..."
  
  # Delete the secret
  az keyvault secret delete \
    --vault-name "$VAULT_NAME" \
    --name "$SECRET_NAME" \
    --output none || echo "Warning: Failed to delete $SECRET_NAME (It might already be soft-deleted)"
    
  # Uncomment the line below if you also want to PURGE the secret entirely 
  # (Requires Key Vault to have purge protection disabled and you to have purge permissions)
  # az keyvault secret purge --vault-name "$VAULT_NAME" --name "$SECRET_NAME" --output none
done

echo ""
echo "✅ Finished deleting $TOTAL secrets from $VAULT_NAME."