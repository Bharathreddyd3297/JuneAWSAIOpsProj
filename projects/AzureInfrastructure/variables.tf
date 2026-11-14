variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid Azure subscription UUID."
  }
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralindia"

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location must not be empty."
  }
}

variable "resource_group_name" {
  description = "Resource group for the application platform"
  type        = string
  default     = "telugu-pickles-azure"
}

variable "cluster_name" {
  type    = string
  default = "telugu-pickles-aks"
}

variable "node_vm_size" {
  description = "AKS node VM size"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "node_count" {
  description = "Number of AKS worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= var.node_min_count && var.node_count <= var.node_max_count
    error_message = "node_count must be between node_min_count and node_max_count."
  }
}

variable "node_min_count" {
  description = "Minimum node count used by the AKS cluster autoscaler"
  type        = number
  default     = 2

  validation {
    condition     = var.node_min_count >= 2
    error_message = "node_min_count must be at least 2."
  }
}

variable "node_max_count" {
  description = "Maximum node count used by the AKS cluster autoscaler"
  type        = number
  default     = 5

  validation {
    condition     = var.node_max_count >= var.node_min_count
    error_message = "node_max_count must be greater than or equal to node_min_count."
  }
}

variable "gitops_repo_url" {
  description = "Public Git repository Argo CD watches"
  type        = string
  default     = "https://github.com/ramakrishnaredd95-stack/JuneAWSAIOpsProj.git"

  validation {
    condition     = can(regex("^https://", var.gitops_repo_url))
    error_message = "gitops_repo_url must be an HTTPS URL."
  }
}

variable "gitops_revision" {
  type    = string
  default = "main"
}

variable "app_namespace" {
  type    = string
  default = "telugu-pickles"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.app_namespace))
    error_message = "app_namespace must be a valid lowercase Kubernetes namespace."
  }
}

variable "github_identity_resource_group" {
  description = "Resource group created by bootstrap for the GitHub Actions identity"
  type        = string
  default     = "telugu-pickles-tfstate"
}

variable "github_identity_name" {
  description = "Protected user-assigned identity used only by Terraform"
  type        = string
  default     = "telugu-pickles-terraform"
}

variable "github_ci_identity_name" {
  description = "Least-privilege identity used by main-branch image builds"
  type        = string
  default     = "telugu-pickles-image-ci"
}

variable "github_release_identity_name" {
  description = "Protected identity used for Argo Rollouts operations"
  type        = string
  default     = "telugu-pickles-release"
}

variable "aks_admin_principal_ids" {
  description = "Entra user or group object IDs that may administer AKS"
  type        = set(string)
  default     = []
}

variable "aiops_enabled" {
  description = "Create the Azure OpenAI multi-agent AIOps runtime"
  type        = bool
  default     = true
}

variable "aiops_location" {
  description = "Azure OpenAI region; may differ from the AKS region"
  type        = string
  default     = "eastus2"
}

variable "aiops_model_name" {
  type    = string
  default = "gpt-4o"
}

variable "aiops_model_version" {
  type    = string
  default = "2024-11-20"
}

variable "aiops_model_capacity" {
  description = "Azure OpenAI thousands of tokens per minute"
  type        = number
  default     = 10

  validation {
    condition     = var.aiops_model_capacity > 0
    error_message = "aiops_model_capacity must be greater than zero."
  }
}
