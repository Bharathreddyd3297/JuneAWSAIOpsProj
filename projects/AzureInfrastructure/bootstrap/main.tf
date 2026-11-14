data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

resource "azurerm_resource_group" "state" {
  name     = var.state_resource_group_name
  location = var.location
}

resource "azurerm_resource_group" "app" {
  name     = var.app_resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "state" {
  name                            = "tptfstate${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  # AzureRM configures blob retention through the data plane during creation,
  # so shared-key access is disabled by AzAPI only after those properties and
  # the state container exist.
  shared_access_key_enabled = true
  local_user_enabled        = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [shared_access_key_enabled]
  }
}

resource "azurerm_management_lock" "state" {
  name       = "protect-terraform-state"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Protects Terraform state from accidental storage-account deletion."
}

resource "azapi_resource" "state_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01"
  name      = "tfstate"
  parent_id = "${azurerm_storage_account.state.id}/blobServices/default"

  body = {
    properties = {
      publicAccess = "None"
    }
  }
}

resource "azapi_update_resource" "disable_shared_key" {
  type        = "Microsoft.Storage/storageAccounts@2025-06-01"
  resource_id = azurerm_storage_account.state.id

  body = {
    properties = {
      allowSharedKeyAccess = false
    }
  }

  depends_on = [
    azapi_resource.state_container,
    azurerm_role_assignment.operator_state_blob,
    azurerm_role_assignment.state_blob,
  ]
}

resource "azurerm_user_assigned_identity" "github" {
  name                = "telugu-pickles-terraform"
  location            = azurerm_resource_group.state.location
  resource_group_name = azurerm_resource_group.state.name
}


resource "azurerm_user_assigned_identity" "github_ci" {
  name                = "telugu-pickles-image-ci"
  location            = azurerm_resource_group.state.location
  resource_group_name = azurerm_resource_group.state.name
}

resource "azurerm_user_assigned_identity" "github_release" {
  name                = "telugu-pickles-release"
  location            = azurerm_resource_group.state.location
  resource_group_name = azurerm_resource_group.state.name
}

locals {
  github_immutable_repository = join("/", [
    "${split("/", var.github_repository)[0]}@${var.github_owner_id}",
    "${split("/", var.github_repository)[1]}@${var.github_repository_id}",
  ])
  github_main_subject       = "repo:${local.github_immutable_repository}:ref:refs/heads/main"
  github_production_subject = "repo:${local.github_immutable_repository}:environment:production"
}

resource "azurerm_federated_identity_credential" "github" {
  name                      = "github-production"
  user_assigned_identity_id = azurerm_user_assigned_identity.github.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = local.github_production_subject
}

resource "azurerm_federated_identity_credential" "github_ci" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = local.github_main_subject
}

resource "azurerm_federated_identity_credential" "github_release" {
  name                      = "github-production"
  user_assigned_identity_id = azurerm_user_assigned_identity.github_release.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = local.github_production_subject
}

# Terraform may manage resources and narrowly scoped role assignments only in the app resource group.
resource "azurerm_role_assignment" "contributor" {
  scope                = azurerm_resource_group.app.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "access_admin" {
  scope                = azurerm_resource_group.app.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "state_reader" {
  scope                = azurerm_resource_group.state.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "state_blob" {
  scope                = azapi_resource.state_container.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

# The signed-in operator can also initialize/read the remote backend locally.
resource "azurerm_role_assignment" "operator_state_blob" {
  scope                = azapi_resource.state_container.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
