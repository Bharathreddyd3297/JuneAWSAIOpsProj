# Terraform remediation note

Date: 2026-11-14

## What was fixed

### Reliable AKS creation

- The AKS control plane now uses a user-assigned identity created before AKS.
- Terraform grants that identity `Network Contributor` on the AKS subnet before cluster creation.
- AKS uses Entra integration with Azure RBAC and disables local certificate accounts.
- Kubernetes and Helm authenticate through `kubelogin` and the active Azure CLI identity; client certificate/private-key outputs were removed.
- The node pool now uses Standard AKS tier, cluster autoscaling, patch upgrades, and node-image upgrades.

### Safe deployment ordering

The Azure Infrastructure workflow now runs in two saved-plan stages:

1. Foundation: VNet, ACR, AKS, subnet access, image-pull access, and AKS RBAC.
2. Platform: namespaces, Kubernetes Secrets, ingress, monitoring, Argo CD/Rollouts, and optional AIOps resources.

The workflow waits until the Terraform identity can authorize against AKS before running the platform plan. Destroy skips the normal create plans and uses the configured cluster name rather than a hard-coded value.

### Least-privilege GitHub OIDC

Bootstrap creates three identities:

| Identity | OIDC context | Permissions |
|---|---|---|
| Terraform | protected `production` environment | application resource-group management, role assignments, state, AKS admin |
| Image CI | `main` branch | ACR Reader and AcrPush only |
| Release | protected `production` environment | AKS cluster-user and Kubernetes writer only |

This prevents an ordinary image-build job from reading Terraform state or administering Azure infrastructure.

### State and secret protection

- State storage has shared keys disabled, blob versioning, 30-day blob/container soft deletion, `prevent_destroy`, and an Azure `CanNotDelete` lock.
- PostgreSQL, JWT, Grafana, and AIOps tokens use ephemeral random values and provider write-only fields. They are sent to Kubernetes/Helm during apply but omitted from Terraform plans and state.
- Local `*.tfvars` files are ignored; a safe `terraform.tfvars.example` is checked in.
- Bootstrap remains a local-state operation because it creates the remote backend. Its state must be copied to encrypted private storage after apply.

### Functional corrections

- `location` now controls the module resource locations instead of being ignored.
- `aiops_enabled = false` selects `gitops/overlays/azure-no-aiops`, so Terraform and GitOps disable AIOps together.
- Both Azure overlays are updated by image CI.
- Generated credentials are no longer exported as Terraform outputs.
- Important identifiers, node counts, capacity, repository URL, namespace, and subscription ID now have validation.
- ACR was moved from Basic to Standard and explicitly grants the image identity only Reader/AcrPush.
- Prometheus and Grafana now request persistent Azure Disk storage.
- Helm platform releases use atomic installation so failed installs are rolled back.

## How authentication works internally

1. GitHub requests an OIDC token whose subject contains the immutable repository IDs and either `main` or `environment:production`.
2. Azure matches that subject to exactly one managed identity.
3. `azure/login` exchanges the OIDC token for a temporary Azure token; no client secret is stored.
4. Terraform uses the production identity for AzureRM and Blob state operations.
5. For Kubernetes resources, the provider runs `kubelogin get-token --login azurecli` and presents the short-lived Entra token to AKS.
6. AKS Azure RBAC authorizes Terraform as cluster admin and the release identity as writer. The image identity receives no AKS permission.

## Required GitHub configuration

Create/update repository secrets from bootstrap outputs:

- `AZURE_TERRAFORM_CLIENT_ID`
- `AZURE_CI_CLIENT_ID`
- `AZURE_RELEASE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Create/update repository variables:

- `AZURE_TFSTATE_RESOURCE_GROUP`
- `AZURE_TFSTATE_STORAGE_ACCOUNT`
- `AZURE_TFSTATE_CONTAINER`
- `AZURE_LOCATION`
- `AZURE_RESOURCE_GROUP`
- `AZURE_AKS_CLUSTER`
- `AZURE_AKS_ADMIN_PRINCIPAL_IDS` as a JSON list, using bootstrap output `operator_object_id`

The GitHub environment named `production` must exist and should require reviewers.

## Deployment sequence

1. Re-run bootstrap plan/apply.
2. Immediately back up `bootstrap/terraform.tfstate` to encrypted private storage.
3. Replace the old `AZURE_CLIENT_ID` setting with the three client-ID secrets above.
4. Add the repository variables above.
5. Run `foundation-plan` for a read-only first-stage review, or run `apply` to execute both stages.
6. Run Azure App CI after infrastructure is ready so real ACR image names replace the bootstrap placeholders.

No Azure apply or destroy was executed while making these code changes. A read-only check confirmed that the target AKS cluster did not exist, so no live Kubernetes credential was rotated.

## Verification performed

- `terraform fmt -check -recursive`: passed.
- Root `terraform validate`: passed with AzureRM 4.81.0, Kubernetes 3.5.0, Helm 3.3.0, and Random 3.9.1.
- Bootstrap `terraform validate`: passed.
- `kubectl kustomize gitops/overlays/azure`: passed.
- `kubectl kustomize gitops/overlays/azure-no-aiops`: passed and contains no AIOps workload.
- Azure workflow YAML parsing: passed.
- Bash syntax checks for deploy and pre-destroy scripts: passed.

`actionlint`, `shellcheck`, TFLint, and Checkov were not installed locally, so those optional linters were not run.

## Intentional remaining tradeoffs

- AKS, ACR, and Azure OpenAI retain public endpoints because the project uses GitHub-hosted runners. Authentication is keyless/Entra-based, but a private-endpoint design would require private DNS and a self-hosted runner inside the VNet.
- PostgreSQL remains a single in-cluster training database. Production should use Azure Database for PostgreSQL with backups and high availability.
- The two-stage workflow uses targeted foundation planning to break the provider bootstrap dependency. A future larger platform should use separate foundation and platform root states instead.
- Standard AKS, Standard ACR, autoscaling, and persistent monitoring disks improve reliability but cost more than the original lab configuration.
