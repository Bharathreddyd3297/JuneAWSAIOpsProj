# Azure reference

| Document | Purpose |
|---|---|
| [INFRASTRUCTURE.md](INFRASTRUCTURE.md) | Terraform modules and Azure resources |
| [PIPELINES.md](PIPELINES.md) | GitHub Actions, OIDC, build, scan, and deployment flow |
| [ARGOCD.md](ARGOCD.md) | GitOps reconciliation on AKS |
| [PROGRESSIVE-DELIVERY.md](PROGRESSIVE-DELIVERY.md) | Frontend blue-green and catalog canary operation |
| [../AZURE-SERVICE-MAP.md](../AZURE-SERVICE-MAP.md) | Complete service and runtime-flow inventory |

```text
GitHub Actions -> ACR -> GitOps tag commit -> Argo CD -> AKS
                                                   |-> Azure Monitor / Log Analytics
                                                   |-> Prometheus / Grafana
                                                   `-> Azure OpenAI AIOps
```
