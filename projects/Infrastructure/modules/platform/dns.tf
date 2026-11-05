# Only used when var.domain_name is set.
#   Route 53 zone  -> created by ./bootstrap (so GoDaddy can be pointed at it BEFORE this runs)
#   ACM cert       -> <domain> + *.<domain>, validated through Route 53 automatically
#   ExternalDNS    -> creates shop./argocd./grafana. records pointing at the load balancer

locals {
  use_domain   = var.domain_name != ""
  shop_host    = "shop.${var.domain_name}"
  argocd_host  = "argocd.${var.domain_name}"
  grafana_host = "grafana.${var.domain_name}"
}

data "aws_route53_zone" "domain" {
  count = local.use_domain ? 1 : 0
  name  = var.domain_name
}

resource "aws_acm_certificate" "wildcard" {
  count                     = local.use_domain ? 1 : 0
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.use_domain ? {
    for o in aws_acm_certificate.wildcard[0].domain_validation_options : o.domain_name => o
  } : {}

  zone_id         = data.aws_route53_zone.domain[0].zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true # apex + wildcard share one validation record
}

resource "aws_acm_certificate_validation" "wildcard" {
  count                   = local.use_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.wildcard[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  timeouts {
    create = "30m" # fails here if GoDaddy nameservers are not pointing at Route 53 yet
  }
}

resource "helm_release" "external_dns" {
  count      = local.use_domain ? 1 : 0
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.23.0"

  values = [yamlencode({
    provider      = { name = "aws" }
    sources       = ["ingress"]
    domainFilters = [var.domain_name]
    policy        = "sync" # also deletes records when an Ingress is removed
    registry      = "txt"
    txtOwnerId    = var.cluster_name
    env           = [{ name = "AWS_DEFAULT_REGION", value = var.region }]
    serviceAccount = {
      name        = "external-dns"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.irsa["external-dns"].arn }
    }
  })]

  depends_on = [aws_iam_role_policy.external_dns]
}

# ALB settings shared by every HTTPS ingress. Same group.name => ONE load balancer for all hosts.
locals {
  https_ingress_annotations = local.use_domain ? {
    "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
    "alb.ingress.kubernetes.io/target-type"     = "ip"
    "alb.ingress.kubernetes.io/group.name"      = "telugu-pickles"
    "alb.ingress.kubernetes.io/listen-ports"    = jsonencode([{ HTTP = 80 }, { HTTPS = 443 }])
    "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
    "alb.ingress.kubernetes.io/certificate-arn" = aws_acm_certificate_validation.wildcard[0].certificate_arn
  } : {}
}

resource "kubernetes_ingress_v1" "argocd" {
  count = local.use_domain ? 1 : 0
  metadata {
    name      = "argocd"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    annotations = merge(local.https_ingress_annotations, {
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
    })
  }
  spec {
    ingress_class_name = "alb"
    rule {
      host = local.argocd_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port { number = 80 }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.argocd, helm_release.load_balancer_controller]
}

resource "kubernetes_ingress_v1" "grafana" {
  count = local.use_domain ? 1 : 0
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
    annotations = merge(local.https_ingress_annotations, {
      "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
    })
  }
  spec {
    ingress_class_name = "alb"
    rule {
      host = local.grafana_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kube-prometheus-stack-grafana"
              port { number = 80 }
            }
          }
        }
      }
    }
  }
  depends_on = [helm_release.monitoring, helm_release.load_balancer_controller]
}
