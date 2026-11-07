# Telugu Pickles: Deploy to AKS with GitHub Actions and Argo CD

This guide provisions Azure infrastructure, bootstraps the AKS add-ons, and deploys the shop.
Terraform `apply` and `destroy` are explicit workflow-dispatch actions; no cloud resources are
created merely by cloning the repository.

## Architecture

```text
Git push
  ├─ Infrastructure workflow -> Terraform -> Azure VNet, AKS, ACR, Key Vault, Monitor, Function
  └─ App CI -> tests + scans -> build 7 images -> ACR -> GitOps image-tag commit
                                                     |
                                   Argo CD in AKS <- Git
                                                     |
                         ingress-nginx -> Azure Load Balancer -> shop
                         Prometheus/Grafana and Azure Monitor observe the cluster
```

## Prerequisites

- Azure subscription with permission to create resource groups, storage, AKS, identity and RBAC.
- Azure CLI, Terraform 1.10+, Docker, kubectl, kubelogin, Helm 3, Git, and PowerShell 7.
- A GitHub repository where Actions are enabled. Argo CD can read it anonymously if public; private
  repositories need credentials configured in Argo CD after bootstrap.
- A supported AKS node VM SKU available in the chosen region. Check quota and availability before
  applying infrastructure.

## 1. Configure and apply the bootstrap stack

Sign in locally:

```powershell
az login
az account set --subscription <subscription-id>
Set-Location projects/Infrastructure/bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with the Azure region and your GitHub repository (`owner/repository`), then:

```powershell
terraform init
terraform plan
terraform apply
terraform output
```

Keep the bootstrap state file private and backed up. The stack creates the app and state resource
groups, an Azure Storage backend, the GitHub OIDC identity, and its federated credentials. Its
Contributor and User Access Administrator grants are scoped to the app resource group; the state
identity receives Storage Blob Data Contributor on the state account.

## 2. Configure GitHub repository variables

Copy the bootstrap outputs into **Settings → Secrets and variables → Actions → Variables**:

| Variable | Value |
|---|---|
| `AZURE_CLIENT_ID` | `github_actions_client_id` |
| `AZURE_GITHUB_PRINCIPAL_ID` | `github_actions_principal_id` |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID |
| `AZURE_RESOURCE_GROUP` | Bootstrap app resource group (default `telugu-pickles-azure`) |
| `TF_STATE_RESOURCE_GROUP` | `state_resource_group_name` |
| `TF_STATE_STORAGE_ACCOUNT` | `state_storage_account_name` |
| `TF_STATE_CONTAINER` | `state_container_name` (default `tfstate`) |
| `TF_STATE_KEY` | `telugu-pickles/infrastructure.tfstate` |
| `AKS_NODE_VM_SIZE` | Available Azure VM SKU, for example `Standard_D2s_v5` |
| `AKS_ADMIN_PRINCIPAL_IDS_JSON` | Optional JSON list of Entra object IDs for human kubectl admins, e.g. `["00000000-0000-0000-0000-000000000000"]` |
| `AKS_CLUSTER_NAME` | Optional; default `telugu-pickles-aks` |
| `ACR_NAME` | Set after infrastructure apply, from Terraform output `acr_name` |

Terraform also creates the Azure OpenAI-compatible `gpt-4o-mini` Global Standard deployment in
South India, grants the Function identity `Cognitive Services OpenAI User`, and wires the endpoint
and deployment into the Function app settings. Model inference is usage-billed. To change the
region, model, version, or capacity, edit the corresponding Terraform variables and review the plan.
Set only `ALERT_EMAIL` as a GitHub Actions variable if alert email notifications are desired. Do not
put model keys or Function keys in repository variables.

The bootstrap adds an OIDC subject for the `azure-migration` branch and the `production` GitHub environment.
Create the `production` environment in repository settings and add required reviewers before using
the apply, destroy, or release-control workflows.

## 3. Plan and apply Azure infrastructure

Dispatch **Azure Infrastructure** from GitHub Actions with `plan`, inspect the result, then dispatch
again with `apply`. The workflow configures the AzureRM remote backend using OIDC. It provisions the
AKS cluster, ACR, VNet, Key Vault, Log Analytics, Application Insights, Azure Functions hosting,
and the AIOps model account/deployment. The model endpoint is in South India; the shop and AKS
remain in Central India. It does not install application Helm charts or deploy application code.

After apply, set the `ACR_NAME` GitHub variable from the workflow summary or
`terraform output -raw acr_name`.
Also set `AIOPS_FUNCTION_APP_NAME` from `terraform output -raw aiops_function_app_name`.
For a local operator, include their Entra object ID in `AKS_ADMIN_PRINCIPAL_IDS_JSON` before apply;
otherwise only the GitHub deployment identity receives AKS cluster-admin access.

## 4. Bootstrap AKS add-ons

From the repository root in PowerShell 7:

```powershell
.\scripts\bootstrap-aks.ps1 `
  -ResourceGroup telugu-pickles-azure `
  -ClusterName telugu-pickles-aks `
  -GitRepository https://github.com/dnaveenkumar125/pickles.git `
  -GitBranch azure-migration
```

The script obtains AKS credentials, configures kubelogin, generates fresh PostgreSQL/JWT secrets in
the cluster, installs ingress-nginx, Argo CD, Argo Rollouts and kube-prometheus-stack, and registers
the Argo CD application for `gitops/`. Secrets are generated locally and are not written to Git.

For private repositories, configure Argo CD repository credentials before syncing the application.
Argo CD and Grafana are not exposed publicly; use `kubectl port-forward` as shown by the script.

## 5. Build and deploy the shop

Dispatch **App CI** on `azure-migration` after infrastructure and AKS bootstrap. It runs tests and security
scans, pushes the seven images to ACR, and commits the image tags in `gitops/kustomization.yml`.
Argo CD then syncs the manifests.

```powershell
az aks get-credentials --resource-group telugu-pickles-azure --name telugu-pickles-aks
kubelogin convert-kubeconfig -l azurecli
kubectl get ingress -n telugu-pickles
kubectl -n argocd get applications
```

The frontend is reached through the ingress address. The blue-green preview remains internal:

```powershell
kubectl port-forward svc/frontend-preview 8080:80 -n telugu-pickles
```

After checking the preview, use **Release control → frontend → promote**. See
[progressive delivery](reference/PROGRESSIVE-DELIVERY.md).

## AIOps Function

Terraform creates the Function app and managed identity, but the code package is deployed
separately. The **AIOps Function** workflow deploys it with OIDC and remote build whenever its
source changes. To deploy manually, install Azure Functions Core Tools v4 and follow
[the AIOps setup guide](../projects/aiops-assistant/README.md). Configure the Function URL and
Function key in a local `.env` file for the Streamlit client; do not commit them.

## Destroying the deployment

Destroying AKS removes application data, including PostgreSQL persistent volumes. Back up anything
you need first. Dispatch **Azure Infrastructure** with action `destroy`, type `destroy` in the
confirmation field, and approve the `production` environment. The workflow removes the Argo CD
application, app namespace, and ingress resources before Terraform destroys the cluster.

The bootstrap resource group and Terraform state account are intentionally separate; they are not
removed by the main infrastructure destroy.
