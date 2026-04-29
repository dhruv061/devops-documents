#!/bin/bash

# ========= CONFIG =========
GITLAB_URL="git-link-url"
PROJECT_ID="726"   # Replace with your project ID
PRIVATE_TOKEN="PAT-XXXXXXXXXXXXXXXXXXXXXXXX"  # Replace with your GitLab Personal Access Token

# Default settings
PROTECTED=false
MASKED=false        # Visible
RAW=false           # Expand variable reference = false

# ========= INPUT FILE =========
# Format: KEY=VALUE (one per line)
VAR_FILE="variables.env"

# ========= FUNCTION =========
create_variable() {
  local KEY=$1
  local VALUE=$2

  echo "Attempting to create variable: $KEY..."

  RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
    --request POST "$GITLAB_URL/api/v4/projects/$PROJECT_ID/variables" \
    --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" \
    --form "key=$KEY" \
    --form "value=$VALUE" \
    --form "protected=$PROTECTED" \
    --form "masked=$MASKED" \
    --form "raw=$RAW")

  BODY=$(echo "$RESPONSE" | sed -e 's/HTTP_STATUS\:.*//g')
  STATUS=$(echo "$RESPONSE" | tr -d '\n' | sed -e 's/.*HTTP_STATUS://')

  if [ "$STATUS" -eq 201 ]; then
    echo "✅ Created: $KEY"
  elif [ "$STATUS" -eq 409 ]; then
    echo "⚠️  Skipped: $KEY (Already exists)"
  else
    echo "❌ Failed: $KEY (HTTP $STATUS)"
    echo "Response: $BODY"
  fi
}

# ========= MAIN =========
if [ ! -f "$VAR_FILE" ]; then
  echo "Error: $VAR_FILE file not found"
  exit 1
fi

echo "Reading from $VAR_FILE..."
echo "Creating variables in project $PROJECT_ID..."

# Robust loop to handle missing trailing newlines and Windows line endings
while IFS='=' read -r KEY VALUE || [[ -n "$KEY" ]]
do
  # skip empty lines or comments
  [[ -z "$KEY" || "$KEY" =~ ^# ]] && continue

  # Trim whitespace and carriage returns
  KEY=$(echo "$KEY" | xargs | tr -d '\r')
  VALUE=$(echo "$VALUE" | xargs | tr -d '\r')

  if [[ -n "$KEY" ]]; then
    create_variable "$KEY" "$VALUE"
  fi
done < "$VAR_FILE"

echo "Done."