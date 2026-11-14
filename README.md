# DevOps + AIOps on Microsoft Azure

Telugu Pickles is a complete microservices, GitOps, observability, progressive-delivery, and AIOps project running on Microsoft Azure.

## Start here

- Local application: [`projects/telugu-pickles/LOCAL-SETUP.md`](projects/telugu-pickles/LOCAL-SETUP.md)
- Azure deployment: [`projects/AzureInfrastructure/README.md`](projects/AzureInfrastructure/README.md)
- Azure AIOps assistant: [`projects/aiops-assistant/README.md`](projects/aiops-assistant/README.md)
- Azure service inventory and flows: [`docs/AZURE-SERVICE-MAP.md`](docs/AZURE-SERVICE-MAP.md)

## Architecture

```text
Developer -> GitHub Actions (OIDC) -> Azure Container Registry
                                      |
                                      v
Git commit <- image tags <- Azure CI  AKS <- Argo CD watches Git
                                      |
            +-------------------------+-------------------------+
            |                         |                         |
      Telugu Pickles            Prometheus/Grafana       Azure Monitor
      7 app containers          app + business metrics   Log Analytics
            |                                                   |
      Azure Disk/Postgres                               Azure OpenAI AIOps
                                                              |
                                            logs + metrics + deployment agents
```

## Azure service mapping

| Capability | Azure service |
|---|---|
| Kubernetes | Azure Kubernetes Service (AKS) |
| Container images | Azure Container Registry (ACR) |
| Network | Azure Virtual Network and subnet |
| Public traffic | Azure Load Balancer through ingress-nginx |
| Persistent database disk | Azure Disk CSI (`managed-csi`) |
| Logs | Azure Monitor Container Insights + Log Analytics |
| Metrics and dashboards | Prometheus + Grafana in AKS |
| Identity | Microsoft Entra ID, managed identities, workload identity |
| CI/CD authentication | GitHub OIDC; no stored Azure password |
| GitOps | Argo CD |
| Progressive delivery | Argo Rollouts |
| AI models | Azure OpenAI |
| Terraform state | Azure Blob Storage |
| Alerts | Prometheus rules and Azure Monitor |

## Repository structure

```text
.
├── .github/workflows/
│   ├── azure-infra.yml       # Terraform plan/apply/destroy
│   ├── azure-ci.yml          # test, scan, build, push to ACR, update GitOps
│   ├── azure-release.yml     # promote/abort/undo blue-green and canary releases
│   └── security.yml          # Gitleaks and Trivy
├── projects/
│   ├── telugu-pickles/       # React + six Node.js services + local Docker Compose
│   ├── AzureInfrastructure/  # modular Terraform for Azure
│   └── aiops-assistant/      # Azure OpenAI multi-agent API and Streamlit UI
└── gitops/
    ├── k8s/                  # cloud-neutral Kubernetes application resources
    └── overlays/azure/       # AKS storage, ingress, images, and AIOps deployment
```

## Local run

```powershell
cd projects\telugu-pickles
docker compose up -d --build
```

Open http://localhost:3000. Demo login: `demo@telugupickles.in` / `Pickle@123`.

## Azure deployment flow

1. Run the one-time bootstrap to create recoverable Blob state and separate Terraform, image-CI, and release OIDC identities.
2. Add bootstrap outputs to GitHub Actions secrets/variables.
3. Run **Azure Infrastructure** to apply the Azure foundation first, then the Kubernetes/Helm platform.
4. Run **Azure App CI** to push eight images and update the Azure GitOps overlay.
5. Argo CD deploys the application automatically.

Destroy the Azure Infrastructure workflow when the lab is finished to stop AKS and related charges.
