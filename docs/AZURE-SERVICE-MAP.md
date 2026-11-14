# Azure service map and runtime flow

## Azure resources

| Layer | Service | Created by | How it works |
|---|---|---|---|
| State | Azure Blob Storage | `bootstrap` | Stores Terraform state with lease locking, versioning, soft deletion, a delete lock, and Entra RBAC instead of storage keys. |
| Automation identities | Three user-assigned identities + GitHub OIDC | `bootstrap` | Terraform, image CI, and release control have separate immutable subjects and least-privilege roles; pull requests have no Azure credential. |
| Resource grouping | Azure Resource Group | `bootstrap` | Contains AKS, ACR, network, monitoring, identity, and AI resources and bounds CI management permissions. |
| Network | Azure Virtual Network + AKS subnet | `modules/network` | Provides private pod/node address space; AKS uses Azure CNI Overlay. |
| Containers | Azure Container Registry | `modules/registry` | Stores eight private images tagged with the Git commit SHA. GitHub has `AcrPush`; the AKS kubelet has `AcrPull`. |
| Compute | Azure Kubernetes Service | `modules/aks` | Runs the platform on an autoscaling Standard-tier node pool with Entra/Azure RBAC and no local certificate accounts. |
| Public entry | Azure Load Balancer + ingress-nginx | `modules/platform` | Allocates one external IP and routes `/` to the active frontend service. |
| Persistent data | Azure Disk CSI (`managed-csi`) | AKS + GitOps | Dynamically provisions disks for PostgreSQL, Prometheus, and Grafana. |
| Logs | Azure Monitor Container Insights | `modules/aks` | Collects AKS container stdout/stderr into Log Analytics `ContainerLogV2`. |
| Log queries | Log Analytics | `modules/aks` | The logs specialist uses workload identity and the scoped Log Analytics Data Reader role. |
| Metrics | Prometheus | `modules/platform` | Scrapes application `/metrics`, Kubernetes resources, request rates, 5xx rates, latency, orders, and payments. |
| Dashboards | Grafana | `modules/platform` | Visualizes Prometheus metrics and imports the Telugu Pickles dashboard from Git. |
| GitOps | Argo CD | `modules/platform` | Polls `gitops/overlays/azure`, detects image-tag commits, and reconciles AKS to Git. |
| Releases | Argo Rollouts | `modules/platform` | Runs frontend blue-green releases and catalog canaries with Prometheus analysis. |
| AI | Azure OpenAI | `modules/aiops` | Runs the Dude supervisor and three specialists through tool calling. |
| AI identity | Entra Workload ID | `modules/aiops` | Federates the AKS service account to an Azure managed identity; no model key is stored. |
| AI API | `aiops-assistant` AKS Deployment | Azure GitOps overlay | Exposes private `/healthz`; `/ask` requires a generated bearer token and limits concurrent investigations. |

## Application services

| Service | Replicas | Role | Dependencies |
|---|---:|---|---|
| `frontend` | 2 | React application served by NGINX; proxies `/api` to gateway | gateway |
| `gateway` | 2 | Public API entry and request routing | auth, catalog, cart, order |
| `auth-service` | 1 | Registration, login, JWT identity | PostgreSQL `auth_db` |
| `catalog-service` | 4 | Products, categories, search, stock; canary release | PostgreSQL `catalog_db` |
| `cart-service` | 1 | Authenticated and guest cart operations | PostgreSQL `cart_db`, catalog |
| `order-service` | 1 | Checkout, orders, cancellation, stock coordination | PostgreSQL `orders_db`, catalog, cart, payment |
| `payment-service` | 1 | Internal payment simulation | PostgreSQL `payments_db` |
| `postgres` | 1 | One server with database-per-service isolation | Azure Disk |
| `aiops-assistant` | 1 | Multi-agent investigation API | Azure OpenAI, Log Analytics, Prometheus, Kubernetes API |

## Request flow

```text
Internet
  -> Azure Load Balancer
  -> ingress-nginx
  -> frontend
  -> gateway
     -> auth-service
     -> catalog-service
     -> cart-service
     -> order-service -> payment-service
  -> PostgreSQL databases
```

## Deployment flow

```text
git push
  -> GitHub OIDC login to Azure
  -> test + Gitleaks + Trivy
  -> build eight images
  -> push commit-SHA tags to ACR
  -> commit ACR tags to gitops/overlays/azure/kustomization.yml
  -> Argo CD sync
  -> Argo Rollouts blue-green/canary checks
  -> AKS serves the new version
```

## Observability and AIOps flow

```text
Application stdout -> Azure Monitor -> Log Analytics -> logs specialist
Application /metrics -> Prometheus -> Grafana + metrics specialist
AKS/Argo APIs -> deployment specialist
logs + metrics + deployment evidence -> Azure OpenAI supervisor -> incident report
```

The AIOps identity is read-only: it can query logs and inspect Kubernetes objects, but it cannot modify deployments, execute inside pods, or read Kubernetes Secrets.
