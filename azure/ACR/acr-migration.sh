#!/bin/bash

SOURCE_ACR="source-account-acr-name"
DEST_ACR="destination-account-acr-namehadev"
SRC_USER="source-acr-username"
SRC_PASS="destination-acr-user-password"

#Repo of ACR that have to migrate
REPOS=(
"dev-arthaadmin"
"dev-arthanode"
"dev-arthaweb"
)

echo "🚀 Starting direct ACR migration..."
echo "Running in DESTINATION subscription context"

for REPO in "${REPOS[@]}"; do
    echo "📦 Checking tags: $REPO"
    TAGS=$(az acr repository show-tags -n $SOURCE_ACR --repository "$REPO" --username "$SRC_USER" --password "$SRC_PASS" -o tsv)

    for TAG in $TAGS; do
        echo "➡️ Importing $REPO:$TAG ..."
        az acr import \
            -n $DEST_ACR \
            --source "${SOURCE_ACR}.azurecr.io/$REPO:$TAG" \
            --image "$REPO:$TAG" \
            --username "$SRC_USER" \
            --password "$SRC_PASS" \
            --force
            
        echo "✔ Done $REPO:$TAG"
    done
    echo "---------------------------------"
done

echo "🎯 All Migrations Completed!"
