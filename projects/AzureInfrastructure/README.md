# Deploy Telugu Pickles to Microsoft Azure

This is the active cloud platform for the application:

| AWS component | Azure component |
|---|---|
| EKS | AKS |
| ECR | Azure Container Registry |
| AWS Load Balancer Controller | ingress-nginx + Azure Load Balancer |
| EBS gp3 | Azure Disk `managed-csi` |
| CloudWatch | Azure Monitor + Log Analytics |
| S3 Terraform state | Azure Blob Storage |
| GitHub AWS OIDC role | GitHub OIDC user-assigned managed identity |

Argo CD, Argo Rollouts, Prometheus, Grafana, PostgreSQL, and all seven application images remain the same.
The stack also creates the Azure OpenAI multi-agent AIOps runtime with AKS workload identity and Log Analytics access.

## Simple module layout

```text
AzureInfrastructure/
├── main.tf                 # connects the modules
├── modules/
│   ├── network/            # VNet and AKS subnet
│   ├── registry/           # ACR and GitHub push access
│   ├── aks/                # AKS, node pool, Azure Monitor/Log Analytics
│   ├── platform/           # ingress, Argo CD/Rollouts, Prometheus/Grafana, secrets
│   └── aiops/              # Azure OpenAI, workload identity, Log Analytics RBAC
└── bootstrap/              # Blob state and GitHub OIDC identity (one time)
```

This separation lets you plan, test, or replace a cloud concern without mixing it with application services.

## Prerequisites

- An Azure subscription where you can create role assignments.
- Azure CLI, Terraform >= 1.10, Git, kubectl, and Azure kubelogin.
- The public GitHub repository `ramakrishnaredd95-stack/JuneAWSAIOpsProj`.

Sign in from your own PowerShell window:

```powershell
az login
az account list --output table
az account set --subscription "<subscription name or ID>"
az account show --output table
```

Do not paste Azure passwords, tokens, or access keys into project files or chat.

## 1. Bootstrap state and GitHub OIDC

This is the only Terraform run that uses local state. It creates the Blob state store, the application resource group, and three passwordless GitHub identities. The OIDC credentials use this repository's immutable GitHub owner/repository IDs.

The identities are intentionally separate:

- Terraform identity: protected `production` environment; manages the application resource group and remote state.
- Image CI identity: `main` branch; can read and push only to ACR.
- Release identity: protected `production` environment; can operate AKS rollouts but cannot manage Azure infrastructure or state.

```powershell
cd projects\AzureInfrastructure\bootstrap
terraform init
$subscriptionId = az account show --query id -o tsv
terraform plan -var="subscription_id=$subscriptionId" -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output
```

After a successful bootstrap, copy `terraform.tfstate` to encrypted private storage. Never commit it. It is required to update or recover the bootstrap resources; `terraform import` is the fallback if the file is lost.

Bootstrap grants only the Terraform identity `Contributor` and `Role Based Access Control Administrator` on the application resource group. State access is scoped to the `tfstate` Blob container. Blob versioning and 30-day soft deletion are enabled, and a `CanNotDelete` lock protects the storage account. Pull requests receive no Azure credential.

## 2. Add GitHub Actions settings

In GitHub, open **Settings -> Secrets and variables -> Actions**.

Add these repository **secrets** from bootstrap outputs:

| Secret | Terraform output |
|---|---|
| `AZURE_TERRAFORM_CLIENT_ID` | `azure_terraform_client_id` |
| `AZURE_CI_CLIENT_ID` | `azure_ci_client_id` |
| `AZURE_RELEASE_CLIENT_ID` | `azure_release_client_id` |
| `AZURE_TENANT_ID` | `azure_tenant_id` |
| `AZURE_SUBSCRIPTION_ID` | `azure_subscription_id` |

Add these repository **variables**:

| Variable | Value |
|---|---|
| `AZURE_TFSTATE_RESOURCE_GROUP` | output `state_resource_group` |
| `AZURE_TFSTATE_STORAGE_ACCOUNT` | output `state_storage_account` |
| `AZURE_TFSTATE_CONTAINER` | output `state_container` (normally `tfstate`) |
| `AZURE_LOCATION` | `centralindia` |
| `AZURE_RESOURCE_GROUP` | `telugu-pickles-azure` |
| `AZURE_AKS_CLUSTER` | `telugu-pickles-aks` |
| `AZURE_AKS_ADMIN_PRINCIPAL_IDS` | JSON list containing `operator_object_id`, for example `["00000000-..."]` |

Create a GitHub environment named **`production`** and add required reviewers. Infrastructure plan/apply/destroy and all rollout operations use this protected environment. Its immutable OIDC subject is created by bootstrap.

Under **Settings -> Actions -> General**, set **Workflow permissions** to **Read and write permissions** so Azure App CI can commit new image tags.

## 3. Create AKS and the platform

Commit and push the Azure files. Open **Actions -> Azure Infrastructure**. The push to `main` first plans/applies the Azure foundation (network, ACR, AKS and RBAC), waits for AKS authorization, then plans/applies the in-cluster platform. This two-stage sequence is required because the Kubernetes and Helm providers cannot connect until AKS exists. The first deployment normally takes 20-35 minutes.

For a manual review before the first deployment, choose `foundation-plan`. Choose `plan` only after the foundation already exists.

The stack creates:

- the bootstrap-owned application resource group, VNet, Standard-tier AKS cluster with autoscaling `Standard_D2s_v5` nodes, and a Standard ACR;
- Azure Monitor Container Insights and a Log Analytics workspace;
- ingress-nginx, Argo CD, Argo Rollouts, Prometheus, and Grafana;
- generated PostgreSQL/JWT/Grafana/AIOps API credentials passed through ephemeral values and write-only provider fields, so they are stored in Kubernetes Secrets but not Terraform plan/state;
- an Argo CD Application watching `gitops/overlays/azure`;
- Azure OpenAI plus a keyless, read-only AIOps workload identity.

Set `aiops_enabled = false` to select `gitops/overlays/azure-no-aiops`; this omits the AIOps Deployment and its Terraform resources together.

## 4. Build and deploy the application

After Azure Infrastructure is green, open **Actions -> Azure App CI -> Run workflow** on `main`.

It tests the code, builds and scans eight images (seven application images plus AIOps), pushes them to ACR with the Git commit SHA, and commits those ACR image names into `gitops/overlays/azure/kustomization.yml`. Argo CD then deploys them to AKS.

## 5. Connect and open the shop

```powershell
az aks get-credentials --resource-group telugu-pickles-azure --name telugu-pickles-aks --overwrite-existing
kubectl get nodes
kubectl -n argocd get application telugu-pickles
kubectl -n telugu-pickles get pods
kubectl -n ingress-nginx get service ingress-nginx-controller
```

Open `http://<EXTERNAL-IP>` from the ingress service. Azure may take several minutes to allocate the first public IP.

Demo login: `demo@telugupickles.in` / `Pickle@123`.

### Grafana

```powershell
kubectl -n monitoring port-forward service/kube-prometheus-stack-grafana 3001:80
```

Open http://localhost:3001 as `admin`. Retrieve the generated password:

```powershell
$encoded = kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}"
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

### Argo CD

```powershell
kubectl -n argocd port-forward service/argocd-server 8081:80
```

Open http://localhost:8081 as `admin`. Retrieve its password:

```powershell
$encoded = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

The blue-green preview service is private on Azure. Inspect it with:

```powershell
kubectl -n telugu-pickles port-forward service/frontend-preview 8080:80
```

Use **Actions -> Azure Release Control** to view, promote, abort, or undo a frontend/catalog rollout.

## Destroy to stop charges

Open **Actions -> Azure Infrastructure -> Run workflow**, choose `destroy`, and enter `destroy` in the confirmation field.

The bootstrap state account and GitHub identities remain. Delete them only when you no longer need this project. Before deleting the state account, explicitly remove its `CanNotDelete` lock and the Terraform `prevent_destroy` protection after confirming that no managed platform remains.
