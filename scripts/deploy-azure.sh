#!/usr/bin/env bash
#
# Azure deploy for the Telugu Pickles platform, in the correct order.
#
# Why the order matters:
#   1. The root module stores state in a Blob Storage account that the
#      bootstrap step creates, so bootstrap must run first.
#   2. The root module's kubernetes/helm providers read values from the AKS
#      cluster. Those values are unknown before the first apply, so a single
#      `terraform apply` fails. We split it in two:
#        stage 1 -> network, registry, AKS, ACR pull role
#        stage 2 -> ingress, Argo CD, Rollouts, monitoring, Azure OpenAI AIOps
#
# Every apply below asks you to review and type "yes". Nothing is auto-approved.
#
# Usage (Git Bash):
#   ./scripts/deploy-azure.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$REPO_ROOT/projects/AzureInfrastructure"
BOOTSTRAP_DIR="$INFRA_DIR/bootstrap"

info() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

command -v terraform >/dev/null || die "terraform is not on PATH."
command -v az        >/dev/null || die "Azure CLI (az) is not on PATH."
command -v kubelogin >/dev/null || die "kubelogin is not on PATH. Install Azure kubelogin first."

info "Checking Azure sign-in"
az account show >/dev/null 2>&1 || die "Not signed in. Run 'az login' first."
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
ok "Subscription: $SUBSCRIPTION_ID"

info "Step 1/4 - Bootstrap state storage and GitHub identity (local state)"
cd "$BOOTSTRAP_DIR"
terraform init -input=false -no-color >/dev/null
terraform plan -input=false -no-color \
  -var="subscription_id=$SUBSCRIPTION_ID" \
  -out=bootstrap.tfplan
terraform apply bootstrap.tfplan

STATE_RG="$(terraform output -raw state_resource_group)"
STATE_SA="$(terraform output -raw state_storage_account)"
OPERATOR_ID="$(terraform output -raw operator_object_id)"
ok "State resource group: $STATE_RG"
ok "State account:        $STATE_SA"

info "Bootstrap outputs (add the Azure ones to GitHub Actions secrets/variables)"
terraform output -no-color

info "Step 2/4 - Point the root module at the new Blob state"
cd "$INFRA_DIR"
terraform init -reconfigure -input=false -no-color \
  -backend-config="resource_group_name=$STATE_RG" \
  -backend-config="storage_account_name=$STATE_SA" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=telugu-pickles/azure.tfstate" \
  -backend-config="use_azuread_auth=true"
terraform validate -no-color

# Helm releases resolve charts from the local Helm cache.
if [[ -x "$REPO_ROOT/scripts/helm-repos.sh" ]]; then
  "$REPO_ROOT/scripts/helm-repos.sh" >/dev/null 2>&1 || true
fi

info "Step 3/4 - Stage 1: network, registry, AKS (10-20 min)"
terraform apply -no-color -lock-timeout=10m \
  -target=module.network \
  -target=module.registry \
  -target=module.aks \
  -target=azurerm_role_assignment.acr_pull \
  -target=azurerm_role_assignment.terraform_cluster_user \
  -target=azurerm_role_assignment.terraform_rbac_admin \
  -target=azurerm_role_assignment.release_cluster_user \
  -target=azurerm_role_assignment.release_rbac_writer \
  -target=azurerm_role_assignment.operator_cluster_user \
  -target=azurerm_role_assignment.operator_rbac_admin \
  -var="aks_admin_principal_ids=[\"$OPERATOR_ID\"]"

APP_RG="$(terraform output -raw resource_group_name)"
AKS_NAME="$(terraform output -raw cluster_name)"
az aks get-credentials \
  --resource-group "$APP_RG" \
  --name "$AKS_NAME" \
  --overwrite-existing
kubelogin convert-kubeconfig --login azurecli

for attempt in $(seq 1 20); do
  if kubectl auth can-i create namespaces >/dev/null 2>&1; then
    break
  fi
  [[ "$attempt" -eq 20 ]] && die "AKS RBAC did not propagate within five minutes."
  sleep 15
done

info "Step 4/4 - Stage 2: ingress, Argo CD, monitoring, AIOps (10-20 min)"
terraform apply -no-color -lock-timeout=10m \
  -var="aks_admin_principal_ids=[\"$OPERATOR_ID\"]"

info "Done. Useful next commands:"
echo "  az aks get-credentials --resource-group $APP_RG --name $AKS_NAME --overwrite-existing"
echo "  kubectl get nodes"
echo "  kubectl -n telugu-pickles get pods"
echo "  kubectl -n ingress-nginx get svc ingress-nginx-controller"
