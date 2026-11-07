#!/usr/bin/env bash
# Build the seven application images and push them to Azure Container Registry.
# Usage: ACR_NAME=<registry-name> ./scripts/push-to-acr.sh [tag]
# Requires Azure CLI logged into the subscription that owns the ACR and Docker.
set -euo pipefail

TAG="${1:-latest}"
ACR_NAME="${ACR_NAME:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$ACR_NAME" ]]; then
  echo "Set ACR_NAME to the registry name (without .azurecr.io)." >&2
  exit 1
fi

REGISTRY="$(az acr show --name "$ACR_NAME" --query loginServer --output tsv)"
if [[ -z "$REGISTRY" ]]; then
  echo "Could not find Azure Container Registry '$ACR_NAME' in the active subscription." >&2
  exit 1
fi

echo "Registry: $REGISTRY   Tag: $TAG"
az acr login --name "$ACR_NAME"

for svc in frontend gateway auth-service catalog-service cart-service order-service payment-service; do
  if [[ "$svc" == frontend ]]; then ctx="$ROOT/frontend"; else ctx="$ROOT/services"; fi
  image="$REGISTRY/telugu-pickles/$svc:$TAG"
  echo "==> $svc"
  docker build --platform linux/amd64 --build-arg SERVICE="$svc" -t "$image" "$ctx"
  docker push "$image"
done

echo
echo "All images pushed to $REGISTRY with tag $TAG."
