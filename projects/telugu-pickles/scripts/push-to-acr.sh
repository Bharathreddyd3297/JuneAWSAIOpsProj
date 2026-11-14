#!/usr/bin/env bash
# Build all application images for linux/amd64 and push them to Azure Container Registry.
set -euo pipefail

TAG="${1:-1.0.0}"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-telugu-pickles-azure}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACR_NAME="$(az acr list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv)"

if [ -z "$ACR_NAME" ]; then
  echo "No ACR found in $RESOURCE_GROUP. Apply Azure Infrastructure first." >&2
  exit 1
fi

REGISTRY="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)"
az acr login --name "$ACR_NAME"
echo "Registry: $REGISTRY   Tag: $TAG"

for svc in frontend gateway auth-service catalog-service cart-service order-service payment-service aiops-assistant; do
  if [ "$svc" = frontend ]; then
    ctx="$ROOT/frontend"
  elif [ "$svc" = aiops-assistant ]; then
    ctx="$ROOT/../aiops-assistant"
  else
    ctx="$ROOT/services"
  fi
  image="$REGISTRY/telugu-pickles/$svc:$TAG"
  echo "==> $svc"
  docker build --platform linux/amd64 --build-arg SERVICE="$svc" -t "$image" "$ctx" >/dev/null
  docker push "$image" | tail -1
done

echo "Images pushed to Azure Container Registry."
