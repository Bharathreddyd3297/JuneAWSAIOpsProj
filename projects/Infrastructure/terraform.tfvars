# Telugu Pickles — AWS infrastructure inputs
region   = "us-east-1" # us-east-1 has the widest Amazon Bedrock model + Agents coverage (AIOps phase)
vpc_name = "telugu-pickles-vpc"
vpc_cidr = "10.1.0.0/16"

subnets = [
  { name = "subnet-1", cidr_block = "10.1.1.0/24", availability_zone = "us-east-1a" },
  { name = "subnet-2", cidr_block = "10.1.2.0/24", availability_zone = "us-east-1b" },
  { name = "subnet-3", cidr_block = "10.1.3.0/24", availability_zone = "us-east-1c" },
]

cluster_name       = "telugu-pickles-eks"
kubernetes_version = "1.35"
node_group_name    = "telugu-pickles-nodes"

# m7i-flex.large = 2 vCPU / 8 GiB, max 29 pods per node.
# App (10) + ArgoCD (7) + monitoring (7) + kube-system (~11) = ~35 pods -> needs 2 nodes.
instance_types = ["m7i-flex.large"]
capacity_type  = "ON_DEMAND"
desired_size   = 2
min_size       = 2
max_size       = 3
disk_size      = 30

repositories = [
  "telugu-pickles/frontend",
  "telugu-pickles/gateway",
  "telugu-pickles/auth-service",
  "telugu-pickles/catalog-service",
  "telugu-pickles/cart-service",
  "telugu-pickles/order-service",
  "telugu-pickles/payment-service",
]

# ---- Access -------------------------------------------------------------------
# The GitHub Actions role (from ./bootstrap) is always a cluster admin.
# EDIT: add YOUR IAM user/role so kubectl works from your laptop.
#   Find it with:  aws sts get-caller-identity --query Arn --output text
cluster_admin_arns = [
  "arn:aws:iam::123456789012:user/your-iam-user",
]

# ---- GitOps -------------------------------------------------------------------
# EDIT for your fork: Argo CD deploys gitops/ from this repository + branch.
gitops_repo_url = "https://github.com/YOUR-GITHUB-USER/YOUR-REPO.git"
gitops_revision = "main"

# ---- DNS (optional) -----------------------------------------------------------
# "" = shop served on the AWS load balancer hostname (HTTP), Argo CD/Grafana via port-forward.
# Set to your GoDaddy domain AFTER the bootstrap created the Route 53 zone and GoDaddy
# nameservers point to it -> https://shop.<domain>, https://argocd.<domain>, https://grafana.<domain>
domain_name = ""

# ---- CloudWatch ---------------------------------------------------------------
log_retention_days = 7

# ---- AIOps (Bedrock) ----------------------------------------------------------
# Any Bedrock model with tool use works. Test access first:
#   aws bedrock-runtime converse --region us-east-1 --model-id <id> --messages '[{"role":"user","content":[{"text":"hi"}]}]'
# Amazon Nova needs no extra approval. Claude needs the one-time Anthropic "use case details" form
# (Bedrock console -> Model catalog -> any Claude model). After that, better reports:
#   aiops_supervisor_model = "us.anthropic.claude-sonnet-4-6"
#   aiops_specialist_model = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
aiops_enabled          = true
aiops_supervisor_model = "us.amazon.nova-pro-v1:0"
aiops_specialist_model = "us.amazon.nova-lite-v1:0"
aiops_alert_email      = "" # your email -> incident reports by mail (confirm the AWS subscription mail)
