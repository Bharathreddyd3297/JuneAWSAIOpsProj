output "resource_group_name" {
  value = data.azurerm_resource_group.app.name
}

output "location" {
  value = data.azurerm_resource_group.app.location
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.app.name
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl after Azure CLI authentication"
  value       = "az aks get-credentials --resource-group ${data.azurerm_resource_group.app.name} --name ${azurerm_kubernetes_cluster.app.name}"
}

output "acr_name" {
  value = azurerm_container_registry.app.name
}

output "acr_login_server" {
  value = azurerm_container_registry.app.login_server
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.app.workspace_id
}

output "key_vault_name" {
  value = azurerm_key_vault.app.name
}

output "aiops_function_app_name" {
  value = azurerm_function_app_flex_consumption.aiops.name
}

output "aiops_function_url" {
  value = "https://${azurerm_function_app_flex_consumption.aiops.name}.azurewebsites.net/api/aiops/ask"
}

output "azure_openai_account_name" {
  value = azurerm_cognitive_account.aiops.name
}

output "azure_openai_endpoint" {
  value = azurerm_cognitive_account.aiops.endpoint
}

output "azure_openai_deployment_name" {
  value = azurerm_cognitive_deployment.aiops.name
}

output "application_insights_name" {
  value = azurerm_application_insights.aiops.name
}

output "monitor_action_group_id" {
  value = try(azurerm_monitor_action_group.alerts[0].id, null)
}
