output "name" { value = azurerm_kubernetes_cluster.main.name }
output "id" { value = azurerm_kubernetes_cluster.main.id }
output "host" {
  value     = azurerm_kubernetes_cluster.main.kube_config[0].host
  sensitive = true
}
output "cluster_ca_certificate" {
  value     = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate
  sensitive = true
}
output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.main.name
}
output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}
output "log_analytics_customer_id" {
  value = azurerm_log_analytics_workspace.main.workspace_id
}
output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.main.oidc_issuer_url
}
