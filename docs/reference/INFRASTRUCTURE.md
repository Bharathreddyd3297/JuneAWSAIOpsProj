# Infrastructure Created by Terraform

All code is in [`projects/Infrastructure/`](../../projects/Infrastructure/). There are two separate Terraform stacks:

| Stack | Folder | Run by | State | How often |
|---|---|---|---|---|
| **Bootstrap** | `bootstrap/` | your laptop | local file in that folder | once per AWS account |
| **Main** | `.` (root) + `modules/` | GitHub Actions (or laptop) | S3 bucket from the bootstrap | every infra change |

```
AWS account (us-east-1)
├── [bootstrap]  S3 telugu-pickles-tfstate-<acct>   IAM role telugu-pickles-github-actions   (Route 53 zone)
└── [main]
    ├── VPC 10.1.0.0/16 ── 3 public subnets (a/b/c) ── Internet Gateway
    │     └── EKS "telugu-pickles-eks" (1.35)
    │           ├── node group: 2 × m7i-flex.large (min 2 / max 3, 30 GiB)
    │           ├── add-on: EBS CSI driver (IRSA)           → gp3 volumes for Postgres
    │           └── in-cluster (Helm):
    │                 argocd/             Argo CD + Application "telugu-pickles"
    │                 monitoring/         Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter
    │                 kube-system/        AWS Load Balancer Controller, metrics-server, (ExternalDNS)
    │                 amazon-cloudwatch/  Fluent Bit  ──► CloudWatch Logs /eks/telugu-pickles/pods
    │                 telugu-pickles/     namespace + Secret  (workloads come from Argo CD)
    ├── ECR: 7 repositories telugu-pickles/<service>
    └── CloudWatch: log group, metric filter, alarm   (ACM certificate when a domain is set)
```

---

## Bootstrap stack (`bootstrap/`)

Creates what the pipeline needs before it can run at all.

| Resource | Name | Why |
|---|---|---|
| S3 bucket + versioning + AES256 encryption + public-access block + TLS-only policy | `telugu-pickles-tfstate-<account-id>` | Remote Terraform state shared by laptop and GitHub. Versioning lets you recover a broken state. |
| IAM OIDC provider (only if `create_github_oidc_provider = true`) | `token.actions.githubusercontent.com` | Lets AWS trust GitHub's login tokens. One per account. |
| IAM role + AdministratorAccess | `telugu-pickles-github-actions` | Assumed by workflows of **this repo only**. Admin because Terraform creates IAM, VPC and EKS. This is a demo trade-off. |
| Route 53 hosted zone (only if `domain_name` is set) | `<your domain>` | Its 4 nameservers go into GoDaddy. Created here so DNS can propagate before the main stack needs it. |

Settings ([`bootstrap/terraform.tfvars`](../../projects/Infrastructure/bootstrap/terraform.tfvars)): `github_repository`, `github_owner_id`, `github_repository_id`, `create_github_oidc_provider`, `domain_name`.

---

## Main stack

### `modules/vpc`
| Resource | Details |
|---|---|
| VPC | `10.1.0.0/16`, DNS hostnames on |
| 3 public subnets | `10.1.1.0/24`, `10.1.2.0/24`, `10.1.3.0/24` in us-east-1a/b/c; tagged `kubernetes.io/role/elb=1` so the ALB controller can place load balancers |
| Internet Gateway + route table | default route `0.0.0.0/0` → IGW |

There are **no private subnets and no NAT gateway**. That saves about $32 per month, but nodes get public IPs. Their security groups still only allow traffic from the control plane and the load balancer.

### `modules/eks`
| Resource | Details |
|---|---|
| IAM role for the control plane | `AmazonEKSClusterPolicy` |
| EKS cluster | version from `kubernetes_version` (1.35), public API endpoint, **authentication mode `API`** |
| EKS access entries | `AmazonEKSClusterAdminPolicy` for the GitHub Actions role + every ARN in `cluster_admin_arns` (your laptop user). The creator gets no hidden admin, so access is the same whoever created the cluster. |
| IAM OIDC provider for the cluster | enables IRSA (pod-level IAM roles) |
| IAM role for nodes | worker, CNI and ECR read-only policies |
| Managed node group | `m7i-flex.large` (2 vCPU / 8 GiB, max 29 pods), ON_DEMAND, desired 2, min 2, max 3, 30 GiB disk |
| EBS CSI driver add-on + IRSA role | lets the Postgres StatefulSet get a gp3 volume |

### `modules/ecr`
7 repositories `telugu-pickles/{frontend,gateway,auth-service,catalog-service,cart-service,order-service,payment-service}`:
- **scan on push**, AES256 encryption;
- a **lifecycle policy that keeps the last 15 images**;
- `force_delete` enabled, so `destroy` works even when images exist.

### `modules/platform` (inside the cluster + supporting AWS resources)

| Resource | Namespace | Version | What it does |
|---|---|---|---|
| Namespaces `argocd`, `monitoring`, `amazon-cloudwatch`, `telugu-pickles` | — | — | `telugu-pickles` has Pod Security `baseline` enforced |
| `random_password` ×3 + Secret `telugu-pickles-secrets` | telugu-pickles | — | `PGUSER`, `PGPASSWORD`, `JWT_SECRET`, generated at apply time and never in Git |
| Helm **metrics-server** | kube-system | 3.14.0 | CPU/memory metrics for the HPAs and `kubectl top` |
| Helm **aws-load-balancer-controller** + IRSA role + official IAM policy | kube-system | 3.6.2 | Turns the shop's `Ingress` into an internet-facing **ALB** |
| CloudWatch log group `/eks/telugu-pickles/pods` | — | — | 7-day retention (`log_retention_days`) |
| Helm **aws-for-fluent-bit** + IRSA role (write to that log group only) | amazon-cloudwatch | 0.2.0 | Ships logs of `telugu-pickles` pods only |
| CloudWatch metric filter + alarm | — | — | Counts `$.data.level = "ERROR"` → `TeluguPickles/AppErrorCount`; alarm `telugu-pickles-error-spike` when > 5 in 5 min |
| Helm **kube-prometheus-stack** | monitoring | 92.20.0 | Prometheus (7-day retention), Grafana (admin password generated), Alertmanager, node-exporter, kube-state-metrics. Discovers ServiceMonitors and dashboards in all namespaces. |
| Helm **argo-cd** | argocd | 10.14.0 | Argo CD server/controller/repo-server/redis; Dex and notifications off; polls Git every 60 s |
| Helm **argo-rollouts** | argocd | 2.43.9 | Argo Rollouts controller + dashboard. The `Rollout` kind for **blue-green** and **canary** releases (see [PROGRESSIVE-DELIVERY.md](PROGRESSIVE-DELIVERY.md)) |
| Helm **argocd-apps** | argocd | 2.0.7 | The `telugu-pickles` **Application** (see [ARGOCD.md](ARGOCD.md)) |

**Only when `domain_name` is set** (see `modules/platform/dns.tf`):

| Resource | What it does |
|---|---|
| ACM certificate `<domain>` + `*.<domain>`, DNS-validated through Route 53 | HTTPS |
| Helm **external-dns** 1.23.0 + IRSA (this zone only) | Creates `shop.`, `argocd.`, `grafana.` records pointing at the ALB |
| Ingresses `argocd` and `grafana` | HTTPS on the same shared ALB (`group.name: telugu-pickles`) |
| Argo CD patch on the shop Ingress | Adds host `shop.<domain>`, port 443, HTTP→HTTPS redirect, certificate |

### `modules/aiops` (multi-agent AIOps on Bedrock, when `aiops_enabled = true`)

Details and demo: [`projects/aiops-assistant/README.md`](../../projects/aiops-assistant/README.md).

| Resource | Details |
|---|---|
| Lambda **`telugu-pickles-kira`** | Python 3.12 arm64, 300 s, code from `projects/aiops-assistant/lambda/`. Kira (supervisor) plus 3 specialist agents, run as a Bedrock **Converse** tool-use loop |
| IAM role `telugu-pickles-aiops-kira` | Query the app log group, invoke `aiops_supervisor_model` and `aiops_specialist_model`, publish reports |
| EKS access entry + ClusterRole/Binding **`aiops-reader`** | Role → group `aiops-readers`: get/list on pods, events, workloads, Rollouts, AnalysisRuns and Applications, plus the Prometheus service proxy. No secrets, no writes. |
| SNS `telugu-pickles-alarms` (in `modules/platform`) | The error alarm's action. Kira subscribes to it. |
| SNS `telugu-pickles-aiops-reports` (+ email subscription if `aiops_alert_email` is set) | Incident reports |
| CloudWatch log group `/aws/lambda/telugu-pickles-kira` | 7-day retention |

Classic Bedrock Agents isn't used: it's in maintenance mode and closed to new accounts.
Cost when idle: $0. A question costs under $0.02 on Nova, or about $0.05–0.20 on Claude.

### Created by Kubernetes, not Terraform
| Resource | Created by | Removed by |
|---|---|---|
| Application Load Balancer + target groups + security groups | AWS Load Balancer Controller (from the Ingress) | `scripts/pre-destroy.sh` |
| 10 GiB gp3 EBS volume for Postgres | EBS CSI driver (from the StatefulSet's PVC) | `scripts/pre-destroy.sh` |
| Route 53 `A` / `TXT` records | ExternalDNS | ExternalDNS (`policy: sync`) |

That's why **destroy must run `pre-destroy.sh` first**. The Infrastructure workflow does this automatically.

---

## Inputs (`terraform.tfvars`)

| Variable | Value here | Change it when |
|---|---|---|
| `region` | `us-east-1` | different region (Bedrock model availability is best in us-east-1) |
| `cluster_name`, `node_group_name`, `vpc_name` | `telugu-pickles-*` | — |
| `kubernetes_version` | `1.35` | upgrading (one minor version at a time) |
| `instance_types`, `desired/min/max_size`, `disk_size` | m7i-flex.large, 2/2/3, 30 | more or fewer pods |
| `repositories` | 7 ECR repos | adding a service |
| `cluster_admin_arns` | your IAM user | others need kubectl |
| `gitops_repo_url`, `gitops_revision` | this repo, `main` | fork or another branch |
| `domain_name` | `""` | after GoDaddy points to Route 53 |
| `log_retention_days` | 7 | longer log history |
| `aiops_enabled` | `true` | `false` skips the AIOps Lambda entirely |
| `aiops_supervisor_model`, `aiops_specialist_model` | Nova Pro, Nova Lite (`us.` inference profiles) | Claude after the Anthropic use-case form (better reports) |
| `aiops_alert_email` | `""` | you want incident reports by email |

## Outputs

```bash
terraform output                       # cluster_name, region, kubeconfig_command, ecr_urls, app_log_group, urls
terraform output -raw grafana_admin_password
```

## Cost (us-east-1, approximate)

| Item | Per hour | Per day |
|---|---|---|
| EKS control plane | $0.10 | $2.40 |
| 2 × m7i-flex.large | $0.19 | $4.60 |
| ALB | $0.03 | $0.55 |
| EBS (70 GiB gp3), CloudWatch, ECR | < $0.02 | $0.30 |
| **Total** | **≈ $0.35** | **≈ $8** |
| Bootstrap (S3 state, IAM role) | ~$0 | ~$0 |
| Route 53 zone (if used) | — | $0.50 per month |

## Commands

```bash
cd projects/Infrastructure
../../scripts/helm-repos.sh                                                # once per machine
terraform init -backend-config="bucket=telugu-pickles-tfstate-<account-id>"
terraform plan
terraform apply
../../scripts/pre-destroy.sh telugu-pickles-eks us-east-1 && terraform destroy
```
