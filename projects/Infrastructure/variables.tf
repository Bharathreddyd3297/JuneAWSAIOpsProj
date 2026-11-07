variable "resource_group_name" {
  description = "Resource group created by the bootstrap stack"
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "telugu-pickles-aks"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version; empty selects the current Azure default"
  type        = string
  default     = ""
}

variable "node_vm_size" {
  description = "Azure VM SKU for the AKS system node pool; choose one available in the selected region"
  type        = string
}

variable "desired_nodes" {
  description = "Initial node count"
  type        = number
  default     = 2
}

variable "min_nodes" {
  description = "Minimum autoscaled node count"
  type        = number
  default     = 2
}

variable "max_nodes" {
  description = "Maximum autoscaled node count"
  type        = number
  default     = 3
}

variable "node_os_disk_size_gb" {
  description = "AKS node OS disk size in GiB"
  type        = number
  default     = 64
}

variable "name_prefix" {
  description = "Short prefix used for Azure resource names"
  type        = string
  default     = "telugu-pickles"
}

variable "vnet_address_space" {
  description = "Address space for the AKS virtual network"
  type        = string
  default     = "10.10.0.0/16"
}

variable "aks_subnet_prefix" {
  description = "Subnet prefix for AKS nodes"
  type        = string
  default     = "10.10.0.0/22"
}

variable "service_cidr" {
  description = "AKS Kubernetes service address range; must not overlap the VNet"
  type        = string
  default     = "10.20.0.0/16"
}

variable "dns_service_ip" {
  description = "DNS service IP inside service_cidr"
  type        = string
  default     = "10.20.0.10"
}

variable "github_actions_principal_id" {
  description = "Principal/object ID of the GitHub OIDC identity created by bootstrap"
  type        = string
}

variable "aks_admin_principal_ids" {
  description = "Entra object IDs of human operators who need kubectl cluster-admin access"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 30
}

variable "function_max_instances" {
  description = "Maximum Flex Consumption instances for the AIOps Function"
  type        = number
  default     = 5
}

variable "azure_openai_location" {
  description = "Region for the AIOps model endpoint"
  type        = string
  default     = "southindia"
}

variable "azure_openai_model_name" {
  description = "Azure OpenAI model used by the AIOps assistant"
  type        = string
  default     = "gpt-4o-mini"
}

variable "azure_openai_model_version" {
  description = "Version of the Azure OpenAI model"
  type        = string
  default     = "2024-07-18"
}

variable "azure_openai_deployment_name" {
  description = "Name assigned to the AIOps model deployment"
  type        = string
  default     = "gpt-4o-mini"
}

variable "azure_openai_model_capacity" {
  description = "Global Standard model throughput in thousands of tokens per minute"
  type        = number
  default     = 50

  validation {
    condition     = var.azure_openai_model_capacity >= 1
    error_message = "Azure OpenAI model capacity must be at least 1 (1,000 tokens per minute)."
  }
}

variable "azure_openai_api_version" {
  description = "Azure OpenAI API version supported by the selected endpoint"
  type        = string
  default     = "2024-10-21"
}

variable "alert_email" {
  description = "Optional email receiver for Azure Monitor alerts"
  type        = string
  default     = ""
}
