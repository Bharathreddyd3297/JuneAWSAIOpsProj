# Azure Infrastructure

Terraform is split into two stacks. The bootstrap stack is applied locally once; the main stack is
managed by GitHub Actions or by an operator with Azure CLI authentication.

## Bootstrap: `projects/Infrastructure/bootstrap/`

Creates:

- Application and Terraform-state resource groups.
- A private Azure Storage account/container for the main stack's remote state.
- A user-assigned managed identity with federated GitHub OIDC credentials for the `azure-migration` branch and the
  `production` environment.
- Scoped Contributor, User Access Administrator, and Storage Blob Data Contributor role grants.

The bootstrap Terraform state is local by design. Back it up securely; do not commit it.

## Main stack: `projects/Infrastructure/`

| Resource | Purpose |
|---|---|
| VNet and AKS subnet | Network isolation for the cluster |
| AKS with Entra ID/RBAC, OIDC issuer, workload identity, autoscaling, and Azure CNI | Runs application and platform pods |
| Azure Container Registry | Stores the seven app images; AKS kubelet identity receives `AcrPull` |
| Key Vault | Azure secret store, configured for RBAC |
| Log Analytics + Application Insights | Container logs, Function telemetry, and alert queries |
| Flex Consumption Function app + managed identity | Hosts the AIOps API |
| Function storage account/container | Function runtime content and state, accessed with managed identity |
| Azure Monitor scheduled query + Action Group | Alerts on application errors |

Terraform creates Azure resources only. `scripts/bootstrap-aks.ps1` installs ingress-nginx, Argo CD,
Argo Rollouts and Prometheus/Grafana, and creates the application Secret. GitOps deploys the
workloads after images have been pushed to ACR.

## Configure and validate

Copy `terraform.tfvars.example` to an untracked `terraform.tfvars` and set your values, or provide
them through `TF_VAR_*` variables. At minimum configure the app resource group, an available AKS
node VM SKU, and the bootstrap GitHub principal ID. The region is selected by the bootstrap stack.

```powershell
terraform fmt -recursive
terraform init -backend=false
terraform validate
```

For remote state, the main stack uses the `azurerm` backend with Entra authentication. The GitHub
identity needs `Storage Blob Data Contributor` on the state storage account. No storage account key
is used.

## Outputs

The main stack outputs the resource group, AKS cluster name, ACR name/login server, Key Vault name,
Log Analytics workspace ID, Function app name/URL, and Application Insights name.

## Operations and cost

AKS node pools, public load balancer, ACR, storage, and monitoring can incur charges while running.
Choose a supported VM SKU and region based on your quota and budget. Use the explicit destroy
workflow to remove the app stack; it does not delete the bootstrap state resources.

The Azure Monitor Action Group supports an optional email receiver. If you connect the Function as
a webhook, retrieve its key after code deployment and configure the Action Group in Azure; never
store the Function URL with a key in committed Terraform files.
