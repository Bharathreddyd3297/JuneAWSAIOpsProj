# Telugu Pickles — AWS platform
#
#   vpc       public subnets in 3 AZs (no NAT gateway -> lower cost)
#   eks       control plane + managed node group + EBS CSI driver, API-mode access entries
#   ecr       one repository per service
#   platform  everything installed INTO the cluster: Argo CD (+ the app), Prometheus/Grafana,
#             AWS Load Balancer Controller, Fluent Bit -> CloudWatch, metrics-server,
#             app secrets, and (when domain_name is set) ACM + ExternalDNS + HTTPS ingresses.

data "aws_caller_identity" "current" {}

locals {
  # Role created by ./bootstrap. Always a cluster admin so the pipeline can manage Helm releases.
  github_actions_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.github_actions_role_name}"
  cluster_admin_arns      = distinct(concat([local.github_actions_role_arn], var.cluster_admin_arns))
}

module "vpc" {
  source = "./modules/vpc"

  vpc_name           = var.vpc_name
  cidr_block         = var.vpc_cidr
  subnet_cidrs       = [for s in var.subnets : s.cidr_block]
  availability_zones = [for s in var.subnets : s.availability_zone]
  cluster_name       = var.cluster_name
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  node_group_name    = var.node_group_name
  admin_arns         = local.cluster_admin_arns

  instance_types = var.instance_types
  capacity_type  = var.capacity_type
  disk_size      = var.disk_size
  min_size       = var.min_size
  desired_size   = var.desired_size
  max_size       = var.max_size

  subnet_ids = module.vpc.subnet_ids
}

module "ecr" {
  source = "./modules/ecr"

  repositories = var.repositories
}

module "platform" {
  source = "./modules/platform"

  region            = var.region
  cluster_name      = module.eks.cluster_name
  vpc_id            = module.vpc.vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.oidc_issuer_url

  gitops_repo_url    = var.gitops_repo_url
  gitops_revision    = var.gitops_revision
  domain_name        = var.domain_name
  log_retention_days = var.log_retention_days

  # Helm/Kubernetes resources need running nodes and admin access first.
  depends_on = [module.eks]
}
