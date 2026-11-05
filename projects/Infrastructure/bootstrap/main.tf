# ---------------------------------------------------------------------------
# BOOTSTRAP: run ONCE from your laptop, before any GitHub Actions run.
#
# It creates the three things the pipelines need but cannot create themselves:
#   1. S3 bucket for Terraform remote state (shared by laptop + GitHub Actions)
#   2. IAM role that GitHub Actions assumes via OIDC (no AWS keys stored in GitHub)
#   3. (optional) Route 53 hosted zone for your domain, so you can point GoDaddy at it
#
# State for THIS folder stays local (terraform.tfstate here). It is tiny and
# rarely changes. Keep it, or re-import if you lose it.
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform-bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

# ---------------------------------------------------------------- 1. state bucket
resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled" # lets you roll back a corrupted state file
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# ---------------------------------------------------------------- 2. GitHub OIDC
# One OIDC provider per AWS account. If your account already has
# token.actions.githubusercontent.com, set create_github_oidc_provider = false.
resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_github_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  github_oidc_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # GitHub's token "sub" claim comes in two formats:
  #   classic:   repo:OWNER/REPO:ref:refs/heads/main
  #   immutable: repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:refs/heads/main   (newer repos/accounts)
  # The immutable form is pinned to the numeric IDs when they are given, so a deleted and
  # re-registered account or repo with the same name can NOT assume this role.
  gh_owner = split("/", var.github_repository)[0]
  gh_repo  = split("/", var.github_repository)[1]
  github_subjects = [
    "repo:${var.github_repository}:*",
    var.github_owner_id != "" && var.github_repository_id != ""
    ? "repo:${local.gh_owner}@${var.github_owner_id}/${local.gh_repo}@${var.github_repository_id}:*"
    : "repo:${local.gh_owner}@*/${local.gh_repo}@*:*",
  ]
}

resource "aws_iam_role" "github_actions" {
  name                 = "${var.project}-github-actions"
  description          = "Assumed by GitHub Actions in ${var.github_repository} via OIDC"
  max_session_duration = 7200 # EKS create + Helm installs can take ~35 min

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        # Only workflows from THIS repository (any branch / PR) can assume the role.
        StringLike = { "token.actions.githubusercontent.com:sub" = local.github_subjects }
      }
    }]
  })
}

# Terraform creates VPCs, EKS, IAM roles, Route 53 records, ... so the pipeline
# needs broad rights. DEMO trade-off: AdministratorAccess, limited to one repo.
# Production: a scoped policy + a separate read-only role for pull-request plans.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ---------------------------------------------------------------- 3. DNS (optional)
resource "aws_route53_zone" "domain" {
  count   = var.domain_name == "" ? 0 : 1
  name    = var.domain_name
  comment = "${var.project}: delegated from GoDaddy"
}
