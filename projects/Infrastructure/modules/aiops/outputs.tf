output "kira_agent_id" {
  value = aws_bedrockagent_agent.kira.agent_id
}

output "kira_alias_id" {
  value = aws_bedrockagent_agent_alias.kira.agent_alias_id
}

output "report_topic_arn" {
  value = aws_sns_topic.reports.arn
}

output "incident_lambda" {
  value = aws_lambda_function.incident.function_name
}
