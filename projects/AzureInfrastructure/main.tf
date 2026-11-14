# Root module: wire the small Azure modules together.

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_user_assigned_identity" "github_terraform" {
  name                = var.github_identity_name
  resource_group_name = var.github_identity_resource_group
}

data "azurerm_user_assigned_identity" "github_ci" {
  name                = var.github_ci_identity_name
  resource_group_name = var.github_identity_resource_group
}

data "azurerm_user_assigned_identity" "github_release" {
  name                = var.github_release_identity_name
  resource_group_name = var.github_identity_resource_group
}

module "network" {
  source = "./modules/network"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
}

module "registry" {
  source = "./modules/registry"

  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = var.location
  github_actions_principal = data.azurerm_user_assigned_identity.github_ci.principal_id
}

module "aks" {
  source = "./modules/aks"

  resource_group_name = data.azurerm_resource_group.main.name
  location            = var.location
  cluster_name        = var.cluster_name
  subnet_id           = module.network.aks_subnet_id
  node_vm_size        = var.node_vm_size
  node_count          = var.node_count
  node_min_count      = var.node_min_count
  node_max_count      = var.node_max_count
}

# The AKS kubelet identity pulls private images without registry passwords.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = module.registry.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity_object_id
}

# Terraform has cluster-admin data-plane access only through the protected
# production environment. The image CI identity deliberately has no AKS role.
resource "azurerm_role_assignment" "terraform_cluster_user" {
  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = data.azurerm_user_assigned_identity.github_terraform.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "terraform_rbac_admin" {
  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_user_assigned_identity.github_terraform.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "release_cluster_user" {
  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = data.azurerm_user_assigned_identity.github_release.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "release_rbac_writer" {
  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = data.azurerm_user_assigned_identity.github_release.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_cluster_user" {
  for_each = var.aks_admin_principal_ids

  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = each.value
}

resource "azurerm_role_assignment" "operator_rbac_admin" {
  for_each = var.aks_admin_principal_ids

  scope                = module.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

module "platform" {
  source = "./modules/platform"

  providers = {
    kubernetes = kubernetes
    helm       = helm
    random     = random
  }

  app_namespace   = var.app_namespace
  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision
  gitops_path     = var.aiops_enabled ? "gitops/overlays/azure" : "gitops/overlays/azure-no-aiops"

  depends_on = [
    module.aks,
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.terraform_cluster_user,
    azurerm_role_assignment.terraform_rbac_admin,
  ]
}

module "aiops" {
  source = "./modules/aiops"
  count  = var.aiops_enabled ? 1 : 0

  providers = {
    azurerm    = azurerm
    kubernetes = kubernetes
    random     = random
  }

  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = var.aiops_location
  aks_oidc_issuer_url        = module.aks.oidc_issuer_url
  log_analytics_workspace_id = module.aks.log_analytics_workspace_id
  log_analytics_customer_id  = module.aks.log_analytics_customer_id
  model_name                 = var.aiops_model_name
  model_version              = var.aiops_model_version
  model_capacity             = var.aiops_model_capacity
  app_namespace              = var.app_namespace

  depends_on = [module.platform]
}
