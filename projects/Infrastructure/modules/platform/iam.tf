# IRSA (IAM Roles for Service Accounts): each add-on gets its OWN IAM role,
# usable only by its own Kubernetes service account. No AWS keys in the cluster.

locals {
  oidc_host = replace(var.oidc_issuer_url, "https://", "")

  # key => "namespace:serviceaccount"
  irsa_accounts = merge(
    {
      load-balancer-controller = "kube-system:aws-load-balancer-controller"
      fluent-bit               = "amazon-cloudwatch:aws-for-fluent-bit"
    },
    local.use_domain ? { external-dns = "kube-system:external-dns" } : {}
  )
}

data "aws_iam_policy_document" "irsa_trust" {
  for_each = local.irsa_accounts

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:${each.value}"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each           = local.irsa_accounts
  name               = "${var.cluster_name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust[each.key].json
}

# --- AWS Load Balancer Controller: official policy for the chart version in use
resource "aws_iam_policy" "load_balancer_controller" {
  name   = "${var.cluster_name}-load-balancer-controller"
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.irsa["load-balancer-controller"].name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

# --- Fluent Bit: write to ONE log group only
resource "aws_iam_role_policy" "fluent_bit" {
  name = "cloudwatch-logs"
  role = aws_iam_role.irsa["fluent-bit"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = ["${aws_cloudwatch_log_group.app.arn}", "${aws_cloudwatch_log_group.app.arn}:*"]
      }, {
      Effect   = "Allow"
      Action   = ["logs:DescribeLogGroups"]
      Resource = "*"
    }]
  })
}

# --- ExternalDNS: manage records in OUR hosted zone only
resource "aws_iam_role_policy" "external_dns" {
  count = local.use_domain ? 1 : 0
  name  = "route53"
  role  = aws_iam_role.irsa["external-dns"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["route53:ChangeResourceRecordSets"]
      Resource = [data.aws_route53_zone.domain[0].arn]
      }, {
      Effect   = "Allow"
      Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResources"]
      Resource = "*"
    }]
  })
}
