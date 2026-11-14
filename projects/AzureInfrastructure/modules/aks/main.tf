data "azurerm_client_config" "current" {}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "telugu-pickles-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${var.cluster_name}-control-plane"
  location            = var.location
  resource_group_name = var.resource_group_name
}

# AKS must be able to join and manage the customer-owned node subnet before
# cluster creation. A user-assigned identity makes that ordering deterministic.
resource "azurerm_role_assignment" "subnet_network_contributor" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "telugu-pickles"
  sku_tier            = "Standard"

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"
  local_account_disabled    = true

  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  default_node_pool {
    name                 = "system"
    node_count           = var.node_count
    vm_size              = var.node_vm_size
    vnet_subnet_id       = var.subnet_id
    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count
    os_disk_size_gb      = 64
    type                 = "VirtualMachineScaleSets"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    load_balancer_sku   = "standard"
    service_cidr        = "10.30.0.0/16"
    dns_service_ip      = "10.30.0.10"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  tags = {
    Project   = "telugu-pickles"
    ManagedBy = "terraform"
  }

  depends_on = [azurerm_role_assignment.subnet_network_contributor]
}
