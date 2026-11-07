#!/usr/bin/env bash
# Remove controller-managed AKS resources before Terraform destroys the cluster.
# Usage: scripts/pre-destroy.sh <resource-group> <cluster-name> [--confirm]
set -euo pipefail

RESOURCE_GROUP="${1:-}"
CLUSTER="${2:-telugu-pickles-aks}"
CONFIRM="${3:-}"

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "Usage: $0 <resource-group> <cluster-name> [--confirm]" >&2
  exit 2
fi

if [[ "$CONFIRM" != "--confirm" ]]; then
  read -r -p "This deletes application workloads and PostgreSQL data in AKS '$CLUSTER'. Type 'destroy' to continue: " answer
  [[ "$answer" == "destroy" ]] || { echo "Cancelled."; exit 1; }
fi

az account show --output none
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER" --overwrite-existing
az aks install-cli
kubelogin convert-kubeconfig -l azurecli

echo "Deleting the Argo CD application and its managed workloads..."
kubectl -n argocd delete application telugu-pickles --wait=true --timeout=10m \
  --ignore-not-found

echo "Deleting the app namespace (including PostgreSQL claims and data)..."
kubectl delete namespace telugu-pickles --wait=true --timeout=10m --ignore-not-found

echo "Deleting ingress-nginx resources to release its Azure Load Balancer..."
kubectl delete namespace ingress-nginx --wait=true --timeout=5m --ignore-not-found

echo "Cleanup complete. It is now safe to run Terraform destroy for the AKS stack."
