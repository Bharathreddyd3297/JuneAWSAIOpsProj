output "azure_terraform_client_id" {
  value = azurerm_user_assigned_identity.github.client_id
}

output "azure_ci_client_id" {
  value = azurerm_user_assigned_identity.github_ci.client_id
}

output "azure_release_client_id" {
  value = azurerm_user_assigned_identity.github_release.client_id
}

output "azure_tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "azure_subscription_id" {
  value = var.subscription_id
}

output "operator_object_id" {
  description = "Signed-in operator to grant AKS administration during local deployments"
  value       = data.azurerm_client_config.current.object_id
}

output "state_resource_group" {
  value = azurerm_resource_group.state.name
}

output "state_storage_account" {
  value = azurerm_storage_account.state.name
}

output "state_container" {
  value = azapi_resource.state_container.name
}

output "app_resource_group" {
  value = azurerm_resource_group.app.name
}

output "terraform_identity_name" {
  value = azurerm_user_assigned_identity.github.name
}

output "ci_identity_name" {
  value = azurerm_user_assigned_identity.github_ci.name
}

output "release_identity_name" {
  value = azurerm_user_assigned_identity.github_release.name
}
