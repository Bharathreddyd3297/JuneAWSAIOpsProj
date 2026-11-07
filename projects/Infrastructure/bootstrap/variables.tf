variable "location" {
  description = "Azure region selected for the deployment"
  type        = string
}

variable "name_prefix" {
  description = "Short prefix for resources created by bootstrap"
  type        = string
  default     = "telugu-pickles"
}

variable "github_repository" {
  description = "GitHub repository allowed to authenticate with Azure OIDC, as owner/name"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository)) && !startswith(var.github_repository, "YOUR-")
    error_message = "Use the form owner/repository, e.g. octocat/devops-ai-playbook."
  }
}

variable "github_branch" {
  description = "Azure migration branch allowed to authenticate with Azure OIDC"
  type        = string
  default     = "azure-migration"
}

variable "app_resource_group_name" {
  description = "Resource group for the application stack"
  type        = string
  default     = "telugu-pickles-azure"
}

variable "state_resource_group_name" {
  description = "Resource group for Terraform remote state"
  type        = string
  default     = "telugu-pickles-state"
}
