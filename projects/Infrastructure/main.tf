data "azurerm_client_config" "current" {}
data "azurerm_resource_group" "app" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 5
  lower   = true
  numeric = true
  special = false
  upper   = false
}

locals {
  acr_name          = "tppickles${random_string.suffix.result}"
  function_name     = "tp-kira-${random_string.suffix.result}"
  function_storage  = "tpfunc${random_string.suffix.result}"
  key_vault_name    = "tp-${random_string.suffix.result}-kv"
  azure_openai_name = "tpai${random_string.suffix.result}"
  common_tags = {
    project    = "telugu-pickles"
    managed_by = "terraform"
  }
}

resource "azurerm_virtual_network" "app" {
  name                = "${var.name_prefix}-vnet"
  location            = data.azurerm_resource_group.app.location
  resource_group_name = data.azurerm_resource_group.app.name
  address_space       = [var.vnet_address_space]
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.name_prefix}-aks"
  resource_group_name  = data.azurerm_resource_group.app.name
  virtual_network_name = azurerm_virtual_network.app.name
  address_prefixes     = [var.aks_subnet_prefix]
}

resource "azurerm_container_registry" "app" {
  name                = local.acr_name
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.common_tags
}

resource "azurerm_log_analytics_workspace" "app" {
  name                = "${var.name_prefix}-logs"
  location            = data.azurerm_resource_group.app.location
  resource_group_name = data.azurerm_resource_group.app.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}

resource "azurerm_application_insights" "aiops" {
  name                         = "${var.name_prefix}-aiops"
  location                     = data.azurerm_resource_group.app.location
  resource_group_name          = data.azurerm_resource_group.app.name
  application_type             = "web"
  workspace_id                 = azurerm_log_analytics_workspace.app.id
  local_authentication_enabled = false
  tags                         = local.common_tags
}

resource "azurerm_cognitive_account" "aiops" {
  name                          = local.azure_openai_name
  location                      = var.azure_openai_location
  resource_group_name           = data.azurerm_resource_group.app.name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = local.azure_openai_name
  local_auth_enabled            = false
  public_network_access_enabled = true
  tags                          = local.common_tags
}

resource "azurerm_cognitive_deployment" "aiops" {
  name                 = var.azure_openai_deployment_name
  cognitive_account_id = azurerm_cognitive_account.aiops.id

  model {
    format  = "OpenAI"
    name    = var.azure_openai_model_name
    version = var.azure_openai_model_version
  }

  sku {
    name     = "GlobalStandard"
    capacity = var.azure_openai_model_capacity
  }
}

resource "azurerm_key_vault" "app" {
  name                          = local.key_vault_name
  location                      = data.azurerm_resource_group.app.location
  resource_group_name           = data.azurerm_resource_group.app.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
  tags                          = local.common_tags
}

resource "azurerm_kubernetes_cluster" "app" {
  name                = var.cluster_name
  location            = data.azurerm_resource_group.app.location
  resource_group_name = data.azurerm_resource_group.app.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version == "" ? null : var.kubernetes_version
  node_resource_group = "${var.name_prefix}-nodes-${random_string.suffix.result}"

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_vm_size
    node_count                  = var.desired_nodes
    min_count                   = var.min_nodes
    max_count                   = var.max_nodes
    auto_scaling_enabled        = true
    vnet_subnet_id              = azurerm_subnet.aks.id
    os_disk_size_gb             = var.node_os_disk_size_gb
    temporary_name_for_rotation = "systemtmp"
    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control_enabled = true
  local_account_disabled            = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = var.service_cidr
    dns_service_ip    = var.dns_service_ip
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.app.id
  }

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = local.common_tags
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.app.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.app.kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "github_acr_push" {
  scope                = azurerm_container_registry.app.id
  role_definition_name = "AcrPush"
  principal_id         = var.github_actions_principal_id
}

resource "azurerm_role_assignment" "github_aks_admin" {
  scope                = azurerm_kubernetes_cluster.app.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.github_actions_principal_id
}

resource "azurerm_role_assignment" "aks_operator_admin" {
  for_each             = toset(var.aks_admin_principal_ids)
  scope                = azurerm_kubernetes_cluster.app.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

resource "azurerm_storage_account" "function" {
  name                            = local.function_storage
  resource_group_name             = data.azurerm_resource_group.app.name
  location                        = data.azurerm_resource_group.app.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  tags                            = local.common_tags
}

resource "azurerm_storage_container" "function" {
  name                  = "function-content"
  storage_account_id    = azurerm_storage_account.function.id
  container_access_type = "private"
  depends_on            = [azurerm_role_assignment.function_storage_deployer]
}

resource "azurerm_role_assignment" "function_storage_deployer" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_user_assigned_identity" "aiops" {
  name                = "${var.name_prefix}-aiops"
  location            = data.azurerm_resource_group.app.location
  resource_group_name = data.azurerm_resource_group.app.name
  tags                = local.common_tags
}

resource "azurerm_service_plan" "aiops" {
  name                = "${var.name_prefix}-aiops-flex"
  location            = data.azurerm_resource_group.app.location
  resource_group_name = data.azurerm_resource_group.app.name
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = local.common_tags
}

resource "azurerm_function_app_flex_consumption" "aiops" {
  name                = local.function_name
  resource_group_name = data.azurerm_resource_group.app.name
  location            = data.azurerm_resource_group.app.location
  service_plan_id     = azurerm_service_plan.aiops.id

  storage_container_type            = "blobContainer"
  storage_container_endpoint        = "${azurerm_storage_account.function.primary_blob_endpoint}${azurerm_storage_container.function.name}"
  storage_authentication_type       = "UserAssignedIdentity"
  storage_user_assigned_identity_id = azurerm_user_assigned_identity.aiops.id

  runtime_name           = "python"
  runtime_version        = "3.14"
  maximum_instance_count = var.function_max_instances
  instance_memory_in_mb  = 2048
  https_only             = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aiops.id]
  }

  site_config {}

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME                  = "python"
    FUNCTIONS_EXTENSION_VERSION               = "~4"
    AzureWebJobsStorage__accountName          = azurerm_storage_account.function.name
    AzureWebJobsStorage__credential           = "managedidentity"
    AzureWebJobsStorage__clientId             = azurerm_user_assigned_identity.aiops.client_id
    AZURE_CLIENT_ID                           = azurerm_user_assigned_identity.aiops.client_id
    AZURE_OPENAI_ENDPOINT                     = azurerm_cognitive_account.aiops.endpoint
    AZURE_OPENAI_DEPLOYMENT                   = azurerm_cognitive_deployment.aiops.name
    AZURE_OPENAI_API_VERSION                  = var.azure_openai_api_version
    LOG_ANALYTICS_WORKSPACE_ID                = azurerm_log_analytics_workspace.app.workspace_id
    CLUSTER_ENDPOINT                          = azurerm_kubernetes_cluster.app.kube_config[0].host
    PROMETHEUS_SERVICE_PROXY                  = "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy"
    APPLICATIONINSIGHTS_CONNECTION_STRING     = azurerm_application_insights.aiops.connection_string
    APPLICATIONINSIGHTS_AUTHENTICATION_STRING = "ClientId=${azurerm_user_assigned_identity.aiops.client_id};Authorization=AAD"
  }

  tags = local.common_tags
}

resource "azurerm_role_assignment" "function_storage_blob" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_user_assigned_identity.aiops.principal_id
}

resource "azurerm_role_assignment" "function_storage_queue" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.aiops.principal_id
}

resource "azurerm_role_assignment" "function_storage_table" {
  scope                = azurerm_storage_account.function.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_user_assigned_identity.aiops.principal_id
}

resource "azurerm_role_assignment" "function_log_reader" {
  scope                = azurerm_log_analytics_workspace.app.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_user_assigned_identity.aiops.principal_id
}

resource "azurerm_role_assignment" "function_aks_reader" {
  scope                = azurerm_kubernetes_cluster.app.id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = azurerm_user_assigned_identity.aiops.principal_id
}

resource "azurerm_role_assignment" "function_app_insights" {
  scope                = azurerm_application_insights.aiops.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_user_assigned_identity.aiops.principal_id
}

resource "azurerm_role_assignment" "function_openai" {
  scope                = azurerm_cognitive_account.aiops.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.aiops.principal_id
}

resource "azurerm_monitor_action_group" "alerts" {
  count               = var.alert_email == "" ? 0 : 1
  name                = "${var.name_prefix}-alerts"
  resource_group_name = data.azurerm_resource_group.app.name
  short_name          = "tpalerts"

  email_receiver {
    name                    = "operations"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }

  tags = local.common_tags
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "app_errors" {
  count                = var.alert_email == "" ? 0 : 1
  name                 = "${var.name_prefix}-app-errors"
  resource_group_name  = data.azurerm_resource_group.app.name
  location             = data.azurerm_resource_group.app.location
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.app.id]
  severity             = 2
  enabled              = true
  display_name         = "Telugu Pickles application error spike"
  description          = "More than five ERROR logs for Telugu Pickles in five minutes."

  criteria {
    query                   = <<-KQL
      ContainerLogV2
      | where PodNamespace == "telugu-pickles"
      | extend event = parse_json(LogMessage)
      | where tostring(event.level) == "ERROR"
      | summarize ErrorCount = count()
    KQL
    time_aggregation_method = "Maximum"
    threshold               = 5
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.alerts[0].id]
  }

  tags = local.common_tags
}
