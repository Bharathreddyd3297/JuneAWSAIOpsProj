resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_cognitive_account" "openai" {
  name                          = "telugu-pickles-ai-${random_string.suffix.result}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = "telugu-pickles-ai-${random_string.suffix.result}"
  local_auth_enabled            = false
  public_network_access_enabled = true
}

resource "azurerm_cognitive_deployment" "model" {
  name                 = var.model_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.model_name
    version = var.model_version
  }

  sku {
    name     = "GlobalStandard"
    capacity = var.model_capacity
  }
}

resource "azurerm_user_assigned_identity" "aiops" {
  name                = "telugu-pickles-aiops"
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_federated_identity_credential" "aiops" {
  name      = "aks-aiops"
  parent_id = azurerm_user_assigned_identity.aiops.id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = var.aks_oidc_issuer_url
  subject   = "system:serviceaccount:${var.app_namespace}:aiops-assistant"
}

resource "azurerm_role_assignment" "openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.aiops.principal_id
}

resource "azurerm_role_assignment" "logs_reader" {
  scope                = var.log_analytics_workspace_id
  role_definition_name = "Log Analytics Data Reader"
  principal_id         = azurerm_user_assigned_identity.aiops.principal_id
  principal_type       = "ServicePrincipal"
}

ephemeral "random_password" "api_token" {
  length  = 48
  special = true
}

resource "kubernetes_service_account_v1" "aiops" {
  metadata {
    name      = "aiops-assistant"
    namespace = var.app_namespace
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.aiops.client_id
    }
    labels = {
      "azure.workload.identity/use" = "true"
    }
  }
}

resource "kubernetes_secret_v1" "aiops_api" {
  metadata {
    name      = "aiops-assistant-api"
    namespace = var.app_namespace
  }
  data_wo = {
    AIOPS_API_TOKEN = ephemeral.random_password.api_token.result
  }
  data_wo_revision = 1
}

resource "kubernetes_role_v1" "aiops_app" {
  metadata {
    name      = "aiops-app-reader"
    namespace = var.app_namespace
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["rollouts"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_v1" "aiops_argocd" {
  metadata {
    name      = "aiops-argocd-reader"
    namespace = "argocd"
  }
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding_v1" "aiops_app" {
  metadata {
    name      = "aiops-app-reader"
    namespace = var.app_namespace
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.aiops_app.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.aiops.metadata[0].name
    namespace = var.app_namespace
  }
}

resource "kubernetes_role_binding_v1" "aiops_argocd" {
  metadata {
    name      = "aiops-argocd-reader"
    namespace = "argocd"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.aiops_argocd.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.aiops.metadata[0].name
    namespace = var.app_namespace
  }
}

resource "kubernetes_config_map_v1" "aiops" {
  metadata {
    name      = "aiops-assistant-config"
    namespace = var.app_namespace
  }
  data = {
    AZURE_CLIENT_ID                    = azurerm_user_assigned_identity.aiops.client_id
    AZURE_OPENAI_ENDPOINT              = azurerm_cognitive_account.openai.endpoint
    AZURE_OPENAI_SUPERVISOR_DEPLOYMENT = azurerm_cognitive_deployment.model.name
    AZURE_OPENAI_SPECIALIST_DEPLOYMENT = azurerm_cognitive_deployment.model.name
    AZURE_OPENAI_API_VERSION           = "2024-10-21"
    LOG_ANALYTICS_WORKSPACE_ID         = var.log_analytics_customer_id
  }
}
