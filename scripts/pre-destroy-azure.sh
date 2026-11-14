#!/usr/bin/env bash
# Remove Kubernetes-owned Azure resources before Terraform destroys AKS.
set -uo pipefail

RESOURCE_GROUP="${1:-telugu-pickles-azure}"
CLUSTER="${2:-telugu-pickles-aks}"

if ! az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER" >/dev/null 2>&1; then
  echo "AKS cluster $CLUSTER not found in $RESOURCE_GROUP - nothing to clean up."
  exit 0
fi

az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER" --overwrite-existing >/dev/null
echo "1/3 Deleting the Argo CD application..."
kubectl -n argocd delete application telugu-pickles --wait=true --timeout=10m 2>/dev/null || true
echo "2/3 Deleting public ingress services..."
kubectl -n ingress-nginx delete service ingress-nginx-controller --wait=true --timeout=5m 2>/dev/null || true
echo "3/3 Deleting PostgreSQL claims and Azure disks..."
kubectl -n telugu-pickles delete statefulset --all --wait=true --timeout=3m 2>/dev/null || true
kubectl -n telugu-pickles delete pvc --all --wait=true --timeout=5m 2>/dev/null || true
echo "Azure Kubernetes-owned resources removed."
