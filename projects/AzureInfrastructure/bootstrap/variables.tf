variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid Azure subscription UUID."
  }
}

variable "location" {
  type    = string
  default = "centralindia"

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "github_repository" {
  description = "GitHub owner/repository name used in the immutable OIDC subject"
  type        = string
  default     = "ramakrishnaredd95-stack/JuneAWSAIOpsProj"

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repository))
    error_message = "github_repository must use the owner/repository format."
  }
}

variable "github_owner_id" {
  description = "Immutable numeric GitHub owner ID"
  type        = string
  default     = "241236789"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be the immutable numeric GitHub owner ID."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID"
  type        = string
  default     = "1449175040"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be the immutable numeric GitHub repository ID."
  }
}

variable "state_resource_group_name" {
  type    = string
  default = "telugu-pickles-tfstate"
}

variable "app_resource_group_name" {
  description = "Resource group that the GitHub deployment identity may manage"
  type        = string
  default     = "telugu-pickles-azure"
}
