output "kira_function" {
  value = aws_lambda_function.kira.function_name
}

output "report_topic_arn" {
  value = aws_sns_topic.reports.arn
}
