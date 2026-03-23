#!/usr/bin/env bash
# ============================================================================
# generate-external-secret.sh
#
# Generates an ExternalSecret YAML from a .env file.
# Automatically converts underscores (_) to hyphens (-) for Key Vault names.
#
# Usage:
#   ./generate-external-secret.sh <env-file> <app-name> <namespace> <store-name>
#
# Examples:
#   ./generate-external-secret.sh admin.env    admin    artha admin-kv-store
#   ./generate-external-secret.sh frontend.env frontend artha frontend-kv-store
#   ./generate-external-secret.sh backend.env  backend  artha backend-kv-store
# ============================================================================
set -euo pipefail

ENV_FILE="${1:-}"
APP_NAME="${2:-}"
NAMESPACE="${3:-default}"
STORE_NAME="${4:-azure-keyvault-store}"
OUTPUT_FILE="external-secret-${APP_NAME}.yaml"

# ─── Colors ───
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ─── Validate ───
if [[ -z "$ENV_FILE" || -z "$APP_NAME" ]]; then
  echo "Usage: $0 <env-file> <app-name> <namespace> <store-name>"
  echo ""
  echo "Example: $0 backend.env backend artha backend-kv-store"
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo -e "${RED}ERROR: File '$ENV_FILE' not found.${NC}"
  exit 1
fi

# Clean up whitespace function (bash built-ins only)
trim_whitespace() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "$var"
}

# ─── Generate YAML Header ───
cat > "$OUTPUT_FILE" <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ${APP_NAME}-secrets
  namespace: ${NAMESPACE}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: ${STORE_NAME}
    kind: ClusterSecretStore
  target:
    name: ${APP_NAME}-env-secrets
    creationPolicy: Owner
  data:
EOF

# ─── Generate Data Entries ───
COUNT=0
DUPLICATES=0
declare -A SEEN_KEYS  # Track seen keys to avoid duplicates

exec 3< "$ENV_FILE"
while IFS= read -u 3 -r line || [[ -n "$line" ]]; do
  # Skip empty lines, comments, and lines without '='
  if [[ -z "$line" || "$line" =~ ^[[:space:]]*# || "$line" != *"="* ]]; then
    continue
  fi

  KEY="${line%%=*}"
  KEY="$(trim_whitespace "$KEY")"

  if [[ -z "$KEY" ]]; then
    continue
  fi

  # Skip duplicate keys (use only the first occurrence)
  if [[ -n "${SEEN_KEYS[$KEY]:-}" ]]; then
    DUPLICATES=$((DUPLICATES + 1))
    continue
  fi
  SEEN_KEYS[$KEY]=1

  # Convert underscores to hyphens for Key Vault name
  KV_NAME="${KEY//_/-}"

  cat >> "$OUTPUT_FILE" <<EOF
    - secretKey: ${KEY}
      remoteRef:
        key: ${KV_NAME}
EOF
  COUNT=$((COUNT + 1))
done
exec 3<&-

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✅ Generated: ${OUTPUT_FILE}${NC}"
echo -e "  ${CYAN}   Secrets:    ${COUNT}${NC}"
echo -e "  ${YELLOW}   Duplicates: ${DUPLICATES} (skipped)${NC}"
echo -e "  ${CYAN}   Namespace:  ${NAMESPACE}${NC}"
echo -e "  ${CYAN}   Store:      ${STORE_NAME}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Review:  ${YELLOW}cat ${OUTPUT_FILE}${NC}"
echo -e "  Apply:   ${YELLOW}kubectl apply -f ${OUTPUT_FILE}${NC}"
