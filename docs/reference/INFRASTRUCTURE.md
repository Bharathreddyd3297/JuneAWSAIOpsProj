# Azure infrastructure reference

## Bootstrap

The one-time `projects/AzureInfrastructure/bootstrap` stack creates recoverable Azure Blob state and separate Terraform, image-CI, and release OIDC identities. Shared-key access is disabled; operators and automation use Entra RBAC.

## Main Terraform modules

| Module | Azure resources | Purpose |
|---|---|---|
| `network` | VNet and AKS subnet | Isolated address space for cluster nodes and pods |
| `registry` | ACR and role assignments | Private image storage; GitHub pushes and AKS pulls |
| `aks` | AKS, node pool, Log Analytics, Container Insights | Compute, orchestration, and container-log collection |
| `platform` | Helm releases and Kubernetes resources | ingress-nginx, Argo CD/Rollouts, Prometheus, Grafana, namespaces, secrets |
| `aiops` | Azure OpenAI, deployment, managed identity, federation, RBAC | Passwordless AI inference and read-only operations evidence |

The root module connects these modules and passes the AKS and identity outputs between them.

## Important security properties

- GitHub OIDC uses short-lived tokens; there is no Azure client secret.
- Terraform/state, image push, and release permissions are isolated on separate identities.
- AKS has workload identity, OIDC issuer, Entra/Azure RBAC, and disabled local accounts.
- ACR grants pull only to the AKS kubelet identity.
- The AIOps pod uses a federated service account and read-only roles.
- Kubernetes Secrets are not included in AIOps RBAC.
- Generated application credentials use ephemeral and write-only Terraform fields and are omitted from plan/state.
- Terraform state uses Entra data-plane roles, blob versioning, soft delete, and a delete lock.

## Cost-bearing resources

AKS worker VMs, Azure OpenAI usage, ACR storage, Log Analytics ingestion, public IP/load balancing, and managed disks can incur charges. Use the destroy workflow after the lab. Confirm current pricing in Azure before provisioning.

## Validation

```powershell
cd projects\AzureInfrastructure
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
kubectl kustomize ..\..\gitops
```
