# Azure Blob state is configured at init time because the bootstrap creates it:
# terraform init \
#   -backend-config="resource_group_name=<state-rg>" \
#   -backend-config="storage_account_name=<state-account>" \
#   -backend-config="container_name=tfstate" \
#   -backend-config="key=telugu-pickles/azure.tfstate" \
#   -backend-config="use_azuread_auth=true"
terraform {
  backend "azurerm" {}
}
