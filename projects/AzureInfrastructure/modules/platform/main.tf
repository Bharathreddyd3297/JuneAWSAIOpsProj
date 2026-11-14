resource "kubernetes_namespace_v1" "argocd" {
  metadata { name = "argocd" }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata { name = "monitoring" }
}

resource "kubernetes_namespace_v1" "ingress" {
  metadata { name = "ingress-nginx" }
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      "app.kubernetes.io/part-of"          = "telugu-pickles"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

ephemeral "random_password" "postgres" {
  length  = 24
  special = true
}

ephemeral "random_password" "jwt" {
  length  = 48
  special = true
}

ephemeral "random_password" "grafana" {
  length  = 20
  special = true
}

resource "kubernetes_secret_v1" "app" {
  metadata {
    name      = "telugu-pickles-secrets"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data_wo = {
    PGUSER     = "postgres"
    PGPASSWORD = ephemeral.random_password.postgres.result
    JWT_SECRET = ephemeral.random_password.jwt.result
  }
  data_wo_revision = 1
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  namespace  = kubernetes_namespace_v1.ingress.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  timeout    = 600
  atomic     = true

  values = [yamlencode({
    controller = {
      replicaCount = 2
      service      = { type = "LoadBalancer" }
      metrics      = { enabled = true }
    }
  })]
}

resource "helm_release" "monitoring" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "92.20.0"
  timeout    = 900
  atomic     = true

  values = [yamlencode({
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }
    grafana = {
      service = { type = "ClusterIP" }
      persistence = {
        enabled          = true
        storageClassName = "managed-csi"
        size             = "5Gi"
      }
      sidecar = {
        dashboards = {
          enabled         = true
          label           = "grafana_dashboard"
          labelValue      = "1"
          searchNamespace = "ALL"
        }
      }
    }
    prometheus = {
      prometheusSpec = {
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        retention                               = "7d"
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { memory = "1536Mi" }
        }
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = "managed-csi"
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = "20Gi" } }
            }
          }
        }
      }
    }
  })]

  set_wo = [{
    name  = "grafana.adminPassword"
    value = ephemeral.random_password.grafana.result
  }]
  set_wo_revision = 1
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.14.0"
  timeout    = 600
  atomic     = true

  values = [yamlencode({
    configs = {
      params = { "server.insecure" = true }
      cm     = { "timeout.reconciliation" = "60s" }
    }
    dex           = { enabled = false }
    notifications = { enabled = false }
  })]
}

resource "helm_release" "argo_rollouts" {
  name       = "argo-rollouts"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-rollouts"
  version    = "2.43.9"
  timeout    = 600
  atomic     = true

  values = [yamlencode({
    controller = { replicas = 1 }
    dashboard  = { enabled = true }
  })]
}

resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.7"
  atomic     = true

  values = [yamlencode({
    applications = {
      telugu-pickles = {
        namespace  = "argocd"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = var.gitops_path
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.app_namespace
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
          syncOptions = [
            "ServerSideApply=true",
            "RespectIgnoreDifferences=true",
          ]
          retry = { limit = 10, backoff = { duration = "15s", factor = 2, maxDuration = "3m" } }
        }
        ignoreDifferences = [
          { group = "apps", kind = "Deployment", jsonPointers = ["/spec/replicas"] },
          { group = "argoproj.io", kind = "Rollout", jsonPointers = ["/spec/replicas"] },
        ]
      }
    }
  })]

  depends_on = [
    helm_release.argocd,
    helm_release.argo_rollouts,
    helm_release.monitoring,
    helm_release.ingress_nginx,
    kubernetes_secret_v1.app,
  ]
}
