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
  description = "Kira (Bedrock supervisor agent) - used by projects/aiops-assistant/app.py"
  value = var.aiops_enabled ? {
    agent_id         = module.aiops[0].kira_agent_id
    agent_alias_id   = module.aiops[0].kira_alias_id
    report_topic_arn = module.aiops[0].report_topic_arn
    incident_lambda  = module.aiops[0].incident_lambda
    chat_ui          = "cd projects/aiops-assistant && pip install -r requirements.txt && streamlit run app.py"
  } : null
}
