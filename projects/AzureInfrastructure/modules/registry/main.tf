resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_container_registry" "main" {
  name                = "${var.name_prefix}${random_string.suffix.result}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  admin_enabled       = false
}

# GitHub Actions pushes images using OIDC; no registry password is stored.
resource "azurerm_role_assignment" "github_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = var.github_actions_principal
  principal_type       = "ServicePrincipal"
}

# AcrPush is a data-plane role and does not allow the workflow to discover the
# registry's login server through Azure Resource Manager.
resource "azurerm_role_assignment" "github_read" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "Reader"
  principal_id         = var.github_actions_principal
  principal_type       = "ServicePrincipal"
}
