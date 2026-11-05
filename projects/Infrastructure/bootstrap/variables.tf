variable "region" {
  description = "AWS region for the state bucket (use the same region as the main stack)"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix for the bucket and IAM role"
  type        = string
  default     = "telugu-pickles"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the CI role, as owner/name"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use the form owner/repository, e.g. octocat/devops-ai-playbook."
  }
}

variable "create_github_oidc_provider" {
  description = "false if the account already has the token.actions.githubusercontent.com OIDC provider"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain bought at GoDaddy (e.g. mypickles.in). Empty = no Route 53 zone."
  type        = string
  default     = ""
}
