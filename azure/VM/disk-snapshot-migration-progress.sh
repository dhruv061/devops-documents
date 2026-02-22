#!/bin/bash

echo "Monitoring copy progress... Press CTRL+C to stop"
echo ""

while true; do
  data=$(az storage blob show \
    --account-name $DEST_SA \
    --account-key "$STORAGE_KEY" \
    --container $DEST_CONTAINER \
    --name $DEST_BLOB \
    --query "properties.copy.progress" \
    -o tsv)

  copied=$(echo $data | cut -d'/' -f1)
  total=$(echo $data | cut -d'/' -f2)

  if [ "$copied" == "" ] || [ "$total" == "" ]; then
    echo "Waiting for progress data..."
    sleep 5
    continue
  fi

  percent=$(echo "$copied * 100 / $total" | bc)

  printf "\rProgress: %d%% (%d / %d bytes)" "$percent" "$copied" "$total"

  if [ "$percent" -ge 100 ]; then
    echo -e "\nCopy Finished! 🎉"
    break
  fi

  sleep 5
done
