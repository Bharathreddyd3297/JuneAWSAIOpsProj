# Telugu Pickles — Azure DevOps + AIOps

This copy migrates the original AWS project to Microsoft Azure. The source folder is kept unchanged.
It contains a six-service React/Node.js store, Azure Kubernetes Service (AKS) GitOps deployment,
Terraform infrastructure, and a multi-agent AIOps assistant using Azure Functions and an
Azure-hosted tool-calling model.

## Azure architecture

| Concern | Azure implementation |
|---|---|
| Kubernetes | AKS with Entra ID/RBAC, Azure CNI, autoscaling |
| Container registry | Azure Container Registry (ACR), AKS pulls through managed identity |
| Ingress | ingress-nginx backed by an Azure Standard Load Balancer |
| Infrastructure | Terraform AzureRM provider; separate bootstrap and app stacks |
| CI/CD | GitHub Actions with federated OIDC; no cloud credentials stored in GitHub |
| GitOps / delivery | Argo CD, Kustomize, Argo Rollouts |
| Metrics | Prometheus + Grafana |
| Logs and alerts | Azure Monitor / Log Analytics and Application Insights |
| AIOps | Python Azure Functions, Azure Monitor Logs, AKS read-only API, Prometheus, Azure OpenAI-compatible endpoint |
| Local development | Docker Compose, Node.js, React, PostgreSQL |

## Start here

- **Deploy on Azure:** [AKS deployment guide](docs/AKS-GUIDE.md)
- **Visual quick start:** [student guide](student-guide.html)
- **Infrastructure details:** [Terraform reference](docs/reference/INFRASTRUCTURE.md)
- **CI/CD details:** [GitHub Actions reference](docs/reference/PIPELINES.md)
- **GitOps and progressive releases:** [Argo CD](docs/reference/ARGOCD.md) · [Argo Rollouts](docs/reference/PROGRESSIVE-DELIVERY.md)
- **Run the shop locally:** [Local setup](projects/telugu-pickles/LOCAL-SETUP.md)
- **AIOps assistant:** [Function and Streamlit setup](projects/aiops-assistant/README.md)
- **Migration mapping and assumptions:** [Assessment report](migration-assessment-report.md)

## Run locally

Install Docker Desktop, then from `projects/telugu-pickles/`:

```bash
docker compose up -d --build
./scripts/smoke-test.sh
```

The store is at `http://localhost:3000`; the gateway health endpoint is
`http://localhost:8080/api/health`. Local development does not require an Azure subscription.

## Azure deployment overview

1. Configure and apply the one-time Terraform bootstrap in `projects/Infrastructure/bootstrap/`.
2. Add the Azure OIDC, Terraform state, node SKU, bootstrap identity, and ACR values described in
   [AKS deployment guide](docs/AKS-GUIDE.md) to GitHub repository variables.
3. Run **Azure Infrastructure** with `plan`, review it, then explicitly dispatch `apply`.
4. Run `scripts/bootstrap-aks.ps1` to install ingress-nginx, Argo CD, Argo Rollouts,
   Prometheus/Grafana, the app namespace, and generated Kubernetes secrets.
5. Run **App CI** on `azure-migration`. It tests, scans and pushes images to ACR, updates `gitops/`, and Argo
   CD deploys the app to AKS.
6. Set `AIOPS_FUNCTION_APP_NAME` from Terraform output; **AIOps Function** deploys the Python
   Function code on changes to `projects/aiops-assistant/function/`.

No Azure resources are deployed by this repository copy automatically. Set your Azure subscription,
resource group, and VM SKU before applying Terraform. The Terraform defaults deploy the AIOps
`gpt-4o-mini` endpoint to South India and the shop to Central India; model usage incurs additional
charges. Review the [assessment report](migration-assessment-report.md) for mappings, assumptions,
and limitations.
