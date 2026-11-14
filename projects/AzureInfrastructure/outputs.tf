output "resource_group_name" {
  value = data.azurerm_resource_group.main.name
}

output "cluster_name" {
  value = module.aks.name
}

output "acr_name" {
  value = module.registry.name
}

output "acr_login_server" {
  value = module.registry.login_server
}

output "kubeconfig_command" {
  value = "az aks get-credentials --resource-group ${data.azurerm_resource_group.main.name} --name ${module.aks.name} --overwrite-existing"
}

output "shop_address_command" {
  value = "kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

output "log_analytics_workspace" {
  value = module.aks.log_analytics_workspace_name
}

output "aiops" {
  value = var.aiops_enabled ? {
    openai_endpoint = module.aiops[0].openai_endpoint
    model           = module.aiops[0].model_deployment
    service         = "kubectl -n ${var.app_namespace} port-forward service/aiops-assistant 8000:8000"
  } : null
}
