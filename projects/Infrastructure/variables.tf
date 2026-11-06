variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_name" {
  description = "VPC name"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "subnets" {
  description = "Public subnets, one per availability zone"
  type = list(object({
    name              = string
    cidr_block        = string
    availability_zone = string
  }))
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "node_group_name" {
  description = "EKS managed node group name"
  type        = string
}

variable "instance_types" {
  description = "Instance types for worker nodes"
  type        = list(string)
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
}

variable "desired_size" {
  description = "Desired number of worker nodes"
  type        = number
}

variable "min_size" {
  description = "Minimum number of worker nodes"
  type        = number
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
}

variable "disk_size" {
  description = "Worker node disk size (GiB)"
  type        = number
}

variable "repositories" {
  description = "ECR repositories to create"
  type        = list(string)
}

variable "github_actions_role_name" {
  description = "IAM role created by ./bootstrap for GitHub Actions (always made a cluster admin)"
  type        = string
  default     = "telugu-pickles-github-actions"
}

variable "cluster_admin_arns" {
  description = "Extra IAM users/roles that get kubectl admin access (e.g. your laptop IAM user)"
  type        = list(string)
  default     = []
}

variable "gitops_repo_url" {
  description = "Git repository Argo CD watches (must contain gitops/)"
  type        = string
}

variable "gitops_revision" {
  description = "Branch Argo CD follows"
  type        = string
  default     = "main"
}

variable "domain_name" {
  description = "Domain with a Route 53 hosted zone (created by ./bootstrap). Empty = no DNS/HTTPS; the shop is served on the load balancer's AWS hostname."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch retention for application logs"
  type        = number
  default     = 7
}

# ---- AIOps (Bedrock multi-agent) ----
variable "aiops_enabled" {
  description = "Create Kira (Bedrock multi-agent Lambda), its read-only cluster access and the alarm -> report flow"
  type        = bool
  default     = true
}

variable "aiops_supervisor_model" {
  description = "Bedrock inference profile for Kira, the supervisor agent"
  type        = string
  default     = "us.amazon.nova-pro-v1:0"
}

variable "aiops_specialist_model" {
  description = "Bedrock inference profile for the logs / metrics / deployment agents"
  type        = string
  default     = "us.amazon.nova-lite-v1:0"
}

variable "aiops_alert_email" {
  description = "Email for automatic incident reports (AWS sends a confirmation mail first). Empty = no email."
  type        = string
  default     = ""
}
