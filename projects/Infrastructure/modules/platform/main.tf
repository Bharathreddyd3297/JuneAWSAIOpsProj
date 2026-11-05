terraform {
  required_providers {
    aws        = { source = "hashicorp/aws" }
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
    random     = { source = "hashicorp/random" }
  }
}

# =============================================================== namespaces
resource "kubernetes_namespace_v1" "argocd" {
  metadata { name = "argocd" }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata { name = "monitoring" }
}

resource "kubernetes_namespace_v1" "cloudwatch" {
  metadata { name = "amazon-cloudwatch" }
}

# The app namespace is owned by Terraform (not Argo CD) because the secret below lives in it.
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
    labels = {
      "app.kubernetes.io/part-of"          = "telugu-pickles"
      "pod-security.kubernetes.io/enforce" = "baseline" # reject privileged pods
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

# =============================================================== app secrets
# Generated here, stored only in the (encrypted) Terraform state and in the cluster —
# never in Git. The workloads in gitops/ reference this Secret by name.
resource "random_password" "postgres" {
  length  = 24
  special = false
}

resource "random_password" "jwt" {
  length  = 48
  special = false
}

resource "kubernetes_secret_v1" "app" {
  metadata {
    name      = "telugu-pickles-secrets"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    PGUSER     = "postgres"
    PGPASSWORD = random_password.postgres.result
    JWT_SECRET = random_password.jwt.result
  }
}

resource "random_password" "grafana" {
  length  = 20
  special = false
}

# =============================================================== cluster add-ons
# metrics-server: CPU/memory metrics for the HorizontalPodAutoscalers and `kubectl top`
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
}

# AWS Load Balancer Controller: turns Kubernetes Ingress objects into an AWS ALB
resource "helm_release" "load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.2"

  values = [yamlencode({
    clusterName  = var.cluster_name
    region       = var.region
    vpcId        = var.vpc_id
    replicaCount = 1
    # We only use Ingress (ALB). Leave Service objects alone so nothing
    # depends on this webhook being up.
    enableServiceMutatorWebhook = false
    serviceAccount = {
      name        = "aws-load-balancer-controller"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.irsa["load-balancer-controller"].arn }
    }
  })]

  depends_on = [aws_iam_role_policy_attachment.load_balancer_controller]
}

# =============================================================== CloudWatch
# Pod logs of the telugu-pickles namespace -> this log group (used by the Bedrock AIOps agent).
resource "aws_cloudwatch_log_group" "app" {
  name              = "/eks/telugu-pickles/pods"
  retention_in_days = var.log_retention_days
}

resource "helm_release" "fluent_bit" {
  name       = "aws-for-fluent-bit"
  namespace  = kubernetes_namespace_v1.cloudwatch.metadata[0].name
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  version    = "0.2.0"

  values = [yamlencode({
    # Only our application's containers (keeps CloudWatch cost and noise low)
    input = { path = "/var/log/containers/*_${var.app_namespace}_*.log" }
    cloudWatchLogs = {
      enabled         = true
      region          = var.region
      logGroupName    = aws_cloudwatch_log_group.app.name
      logStreamPrefix = "pod-"
      autoCreateGroup = false
    }
    serviceAccount = {
      name        = "aws-for-fluent-bit"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.irsa["fluent-bit"].arn }
    }
    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { memory = "256Mi" }
    }
  })]

  depends_on = [aws_iam_role_policy.fluent_bit]
}

# Count ERROR log lines -> CloudWatch metric -> alarm. Fluent Bit nests the app's
# JSON log under "data" (mergeLogKey), so the filter reads $.data.level.
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "telugu-pickles-error-logs"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.data.level = \"ERROR\" }"

  metric_transformation {
    name          = "AppErrorCount"
    namespace     = "TeluguPickles"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "telugu-pickles-error-spike"
  alarm_description   = "More than 5 ERROR log lines in 5 minutes across Telugu Pickles services"
  namespace           = "TeluguPickles"
  metric_name         = aws_cloudwatch_log_metric_filter.app_errors.metric_transformation[0].name
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

# =============================================================== Prometheus + Grafana
resource "helm_release" "monitoring" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "92.20.0"
  timeout    = 900

  values = [yamlencode({
    # EKS hides these control-plane components; scraping them only produces false alerts
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }

    grafana = {
      service = { type = "ClusterIP" }
      sidecar = {
        dashboards = {
          enabled         = true
          label           = "grafana_dashboard"
          labelValue      = "1"
          searchNamespace = "ALL" # picks up the Telugu Pickles dashboard ConfigMap synced by Argo CD
        }
      }
    }

    prometheus = {
      prometheusSpec = {
        # discover ServiceMonitors / PrometheusRules in every namespace
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        retention                               = "7d"
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { memory = "1536Mi" }
        }
      }
    }
  })]

  set_sensitive = [{
    name  = "grafana.adminPassword"
    value = random_password.grafana.result
  }]
}

# =============================================================== Argo CD
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.14.0"
  timeout    = 600

  values = [yamlencode({
    global = local.use_domain ? { domain = local.argocd_host } : {}
    configs = {
      params = {
        "server.insecure" = true # TLS ends at the ALB (or you use port-forward)
      }
      cm = {
        "timeout.reconciliation" = "60s" # poll Git every minute (default 3 min)
      }
    }
    dex           = { enabled = false } # no SSO in this demo
    notifications = { enabled = false }
  })]
}

# The Application that makes Argo CD deploy gitops/ — created via the argocd-apps chart
# so Terraform can plan it before the Argo CD CRDs exist.
locals {
  # With a domain: give the shop Ingress its hostname + HTTPS, without editing Git.
  frontend_domain_patch = <<-EOT
    - op: add
      path: /spec/rules/0/host
      value: ${local.shop_host}
    - op: replace
      path: /metadata/annotations/alb.ingress.kubernetes.io~1listen-ports
      value: '[{"HTTP":80},{"HTTPS":443}]'
    - op: add
      path: /metadata/annotations/alb.ingress.kubernetes.io~1ssl-redirect
      value: "443"
    - op: add
      path: /metadata/annotations/alb.ingress.kubernetes.io~1certificate-arn
      value: ${local.use_domain ? aws_acm_certificate_validation.wildcard[0].certificate_arn : ""}
  EOT

  app_source = merge(
    {
      repoURL        = var.gitops_repo_url
      targetRevision = var.gitops_revision
      path           = "gitops"
    },
    local.use_domain ? {
      kustomize = {
        patches = [{
          target = { kind = "Ingress", name = "frontend" }
          patch  = local.frontend_domain_patch
        }]
      }
    } : {}
  )
}

resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.7"

  values = [yamlencode({
    applications = {
      telugu-pickles = {
        namespace  = "argocd"
        finalizers = ["resources-finalizer.argocd.argoproj.io"] # deleting the app deletes its resources
        project    = "default"
        source     = local.app_source
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.app_namespace
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
          syncOptions = [
            "ServerSideApply=true",          # large Grafana dashboard ConfigMap
            "RespectIgnoreDifferences=true", # let the HPAs own replica counts
          ]
          retry = { limit = 10, backoff = { duration = "15s", factor = 2, maxDuration = "3m" } }
        }
        ignoreDifferences = [{
          group        = "apps"
          kind         = "Deployment"
          jsonPointers = ["/spec/replicas"]
        }]
      }
    }
  })]

  # Everything the app needs must exist before the first sync:
  # its Secret, ServiceMonitor CRDs, the IngressClass "alb", and Argo CD itself.
  depends_on = [
    helm_release.argocd,
    helm_release.monitoring,
    helm_release.load_balancer_controller,
    kubernetes_secret_v1.app,
  ]
}
