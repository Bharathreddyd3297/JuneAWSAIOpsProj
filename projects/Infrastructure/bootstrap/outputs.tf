output "state_resource_group_name" {
  value = azurerm_resource_group.state.name
}

output "state_storage_account_name" {
  value = azurerm_storage_account.state.name
}

output "state_container_name" {
  value = azurerm_storage_container.state.name
}

output "app_resource_group_name" {
  value = azurerm_resource_group.app.name
}

output "github_actions_client_id" {
  value = azurerm_user_assigned_identity.github.client_id
}

output "github_actions_principal_id" {
  value = azurerm_user_assigned_identity.github.principal_id
}
