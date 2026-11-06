output "app_log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "app_log_group_arn" {
  value = aws_cloudwatch_log_group.app.arn
}

output "alarm_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "grafana_admin_password" {
  value     = random_password.grafana.result
  sensitive = true
}

output "urls" {
  value = local.use_domain ? {
    shop    = "https://${local.shop_host}"
    argocd  = "https://${local.argocd_host}"
    grafana = "https://${local.grafana_host}"
    } : {
    shop    = "kubectl -n ${var.app_namespace} get ingress frontend   (ADDRESS column, open with http://)"
    argocd  = "kubectl -n argocd port-forward svc/argocd-server 8081:80   -> http://localhost:8081"
    grafana = "kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80   -> http://localhost:3001"
  }
}
