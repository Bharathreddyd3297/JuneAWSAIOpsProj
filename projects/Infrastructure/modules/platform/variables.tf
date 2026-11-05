variable "region" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (IRSA)"
  type        = string
}

variable "oidc_issuer_url" {
  description = "EKS OIDC issuer URL (IRSA)"
  type        = string
}

variable "gitops_repo_url" {
  type = string
}

variable "gitops_revision" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "log_retention_days" {
  type = number
}

variable "app_namespace" {
  type    = string
  default = "telugu-pickles"
}
