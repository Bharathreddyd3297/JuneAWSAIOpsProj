output "openai_endpoint" { value = azurerm_cognitive_account.openai.endpoint }
output "model_deployment" { value = azurerm_cognitive_deployment.model.name }
output "identity_client_id" { value = azurerm_user_assigned_identity.aiops.client_id }
