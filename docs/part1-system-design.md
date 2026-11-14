# Part 1 — Azure system design

Telugu Pickles is a microservice application designed to run unchanged in local Docker Compose and Azure Kubernetes Service (AKS). Runtime configuration is supplied through environment variables and Kubernetes resources.

## Architecture

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
  -> PostgreSQL on Azure Disk
```

The Azure Virtual Network contains an AKS subnet. AKS uses Azure CNI Overlay so pods receive routable cluster addresses without consuming one VNet address per pod. Two worker nodes provide capacity for the application, GitOps controllers, monitoring, and system pods.

## Service boundaries

| Service | Responsibility | Persistent dependency |
|---|---|---|
| frontend | React UI and `/api` reverse proxy | none |
| gateway | API routing and request correlation | none |
| auth-service | users, login, JWTs | `auth_db` |
| catalog-service | products, categories, stock | `catalog_db` |
| cart-service | guest and signed-in carts | `cart_db` |
| order-service | checkout and order state | `orders_db` |
| payment-service | internal payment simulation | `payments_db` |

The lab uses one PostgreSQL server with database-per-service separation. A 10 GiB persistent volume is provisioned dynamically by the AKS `managed-csi` Azure Disk storage class.

## Delivery design

GitHub Actions authenticates to Azure with OIDC. It builds eight images, scans them, and pushes immutable commit-SHA tags to Azure Container Registry (ACR). The workflow commits those tags to the Azure Kustomize overlay. Argo CD sees the Git change and reconciles AKS.

Frontend uses a blue-green Rollout. Catalog uses a canary Rollout with Prometheus analysis. The other services use standard Kubernetes Deployments.

## Observability and AIOps

- Prometheus scrapes Kubernetes, HTTP, latency, error, order, and payment metrics.
- Grafana visualizes Prometheus data.
- Azure Monitor Container Insights sends container stdout/stderr to Log Analytics `ContainerLogV2`.
- The AIOps API runs in AKS and uses Azure OpenAI.
- Entra workload identity lets it query Log Analytics without an API key.
- Its Kubernetes RBAC is read-only and excludes Secrets and mutation verbs.

See [`AZURE-SERVICE-MAP.md`](AZURE-SERVICE-MAP.md) for the complete resource and data-flow inventory.
