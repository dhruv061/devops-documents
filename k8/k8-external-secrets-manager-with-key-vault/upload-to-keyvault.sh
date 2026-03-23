#!/usr/bin/env bash
# ============================================================================
# upload-to-keyvault.sh
# Reads a .env file and uploads/updates secrets in Azure Key Vault.
# Includes logic to skip secrets with the same value and update changed ones.
# ────────────────────────────────────────────────────────────────────────────
# Updated: Better input isolation and error handling for 200+ secrets.
# ============================================================================
set -euo pipefail

# ─── Configuration ───
ENV_FILE="${1:-}"                       # Pass .env file as 1st arg
KEYVAULT_NAME="${2:-}"                  # Pass KV name as 2nd arg
DRY_RUN="${DRY_RUN:-false}"             # Set DRY_RUN=true to preview without uploading

# ─── Colors ───
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ─── Usage ───
usage() {
  echo "Usage: $0 <env-file> <keyvault-name>"
  echo "Example: $0 .env my-app-kv"
  echo ""
  echo "Prerequisites:"
  echo "  1. Install Azure CLI (az)"
  echo "  2. Run 'az login' to authenticate"
  echo "  3. Set DRY_RUN=true for a preview"
  exit 1
}

# ─── Validate ───
if [[ -z "$ENV_FILE" || -z "$KEYVAULT_NAME" ]]; then
  usage
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${RED}ERROR: File '$ENV_FILE' not found.${NC}"
  exit 1
fi

# ─── Check Login ───
echo -n "Checking Azure login status... "
if ! az account show &>/dev/null; then
  echo -e "${RED}FAILED${NC}"
  echo -e "${YELLOW}Please run 'az login' first to authenticate with Azure.${NC}"
  exit 1
fi
echo -e "${GREEN}LOGGED IN${NC}"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Source:    $ENV_FILE${NC}"
echo -e "${CYAN}  Target:    $KEYVAULT_NAME${NC}"
echo -e "${CYAN}  Dry Run:   $DRY_RUN${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

SUCCESS=0
FAILED=0
SKIPPED=0
UPDATED=0
CREATED=0

# Clean up whitespace function (uses bash built-ins)
trim_whitespace() {
  local var="$*"
  # remove leading whitespace characters
  var="${var#"${var%%[![:space:]]*}"}"
  # remove trailing whitespace characters
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}

# ─── Process File ───
# Use FD 3 for reading to prevent 'az' commands from stealing from FD 0 (stdin)
exec 3< "$ENV_FILE"
while IFS= read -u 3 -r line || [[ -n "$line" ]]; do
  # Skip empty lines and comments
  if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  # Extract key and value (handling lines without '=')
  if [[ "$line" != *"="* ]]; then
    continue
  fi

  KEY="${line%%=*}"
  VALUE="${line#*=}"

  # Trim leading/trailing whitespace from key and value
  KEY="$(trim_whitespace "$KEY")"
  VALUE="$(trim_whitespace "$VALUE")"

  # Remove surrounding quotes from value if present
  if [[ "$VALUE" =~ ^\".*\"$ ]] || [[ "$VALUE" =~ ^\'.*\'$ ]]; then
    VALUE="${VALUE:1:-1}"
  fi

  # Skip if key is empty
  if [[ -z "$KEY" ]]; then
    continue
  fi

  # Convert underscores to hyphens for Azure Key Vault (only hyphens and alphanumeric allowed)
  KV_SECRET_NAME="${KEY//_/-}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY RUN]${NC} Would process: ${KEY} → ${KV_SECRET_NAME}"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo -n "  Processing: ${KEY} → ${KV_SECRET_NAME} ... "

  # Check if secret exists and get its current value
  # We redirect /dev/null to stdin to be 100% sure 'az' doesn't touch FD 3
  CURRENT_VALUE=$(az keyvault secret show \
    --vault-name "$KEYVAULT_NAME" \
    --name "$KV_SECRET_NAME" \
    --query "value" -o tsv < /dev/null 2>/dev/null || echo "__NOT_FOUND__")

  if [[ "$CURRENT_VALUE" == "$VALUE" ]]; then
    echo -e "${YELLOW}EXISTING (No change)${NC}"
    SKIPPED=$((SKIPPED + 1))
  elif [[ "$CURRENT_VALUE" == "__NOT_FOUND__" ]]; then
    # Create new secret
    if az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "$KV_SECRET_NAME" \
        --value "$VALUE" \
        --output none < /dev/null; then
      echo -e "${GREEN}CREATED${NC}"
      CREATED=$((CREATED + 1))
    else
      echo -e "${RED}ERROR (Create)${NC}"
      FAILED=$((FAILED + 1))
    fi
  else
    # Update existing secret value (new version)
    if az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "$KV_SECRET_NAME" \
        --value "$VALUE" \
        --output none < /dev/null; then
      echo -e "${CYAN}UPDATED${NC}"
      UPDATED=$((UPDATED + 1))
    else
      echo -e "${RED}ERROR (Update)${NC}"
      FAILED=$((FAILED + 1))
    fi
  fi
done
exec 3<&-

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ✅ Created: $CREATED  |  🔄 Updated: $UPDATED  |  ⏭️ Skipped: $SKIPPED  |  ❌ Failed: $FAILED"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ $FAILED -gt 0 ]]; then
  echo -e "${RED}Warning: $FAILED secrets failed to upload.${NC}"
  echo "Please check your RBAC permissions (Key Vault Secrets Officer role required)."
  exit 1
fi
echo -e "${GREEN}Task completed successfully!${NC}"
