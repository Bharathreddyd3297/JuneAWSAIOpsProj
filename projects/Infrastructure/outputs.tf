output "cluster_name" {
  value = module.eks.cluster_name
}

output "region" {
  value = var.region
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "ecr_urls" {
  value = module.ecr.repository_urls
}

output "app_log_group" {
  description = "CloudWatch log group that receives the Telugu Pickles pod logs"
  value       = module.platform.app_log_group
}

output "urls" {
  description = "Where to open things"
  value       = module.platform.urls
}

output "grafana_admin_password" {
  description = "terraform output -raw grafana_admin_password"
  value       = module.platform.grafana_admin_password
  sensitive   = true
}

output "aiops" {
  description = "Kira (Bedrock multi-agent Lambda) - used by projects/aiops-assistant/app.py"
  value = var.aiops_enabled ? {
    kira_function    = module.aiops[0].kira_function
    report_topic_arn = module.aiops[0].report_topic_arn
    ask_from_cli     = "aws lambda invoke --region ${var.region} --function-name ${module.aiops[0].kira_function} --cli-read-timeout 300 --payload '{\"question\":\"Is everything healthy?\"}' --cli-binary-format raw-in-base64-out out.json"
    chat_ui          = "cd projects/aiops-assistant && pip install -r requirements.txt && streamlit run app.py"
  } : null
}
