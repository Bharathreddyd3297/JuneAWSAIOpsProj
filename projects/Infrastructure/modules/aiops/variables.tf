variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "cluster_ca" {
  description = "Base64 cluster CA (module.eks.cluster_certificate_authority_data)"
  type        = string
}

variable "log_group_name" {
  type = string
}

variable "log_group_arn" {
  type = string
}

variable "alarm_topic_arn" {
  description = "SNS topic the CloudWatch alarms publish to; the incident Lambda subscribes to it"
  type        = string
}

variable "supervisor_model" {
  description = "Bedrock model / inference profile for Kira (the supervisor that reasons and writes the report)"
  type        = string
}

variable "specialist_model" {
  description = "Bedrock model / inference profile for the 3 specialist agents (fast + cheap)"
  type        = string
}

variable "alert_email" {
  description = "Email that receives automatic incident reports (confirm the SNS mail). Empty = no email."
  type        = string
  default     = ""
}

variable "lambda_source_dir" {
  description = "Folder with the Lambda Python code"
  type        = string
}
