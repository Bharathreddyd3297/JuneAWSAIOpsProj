# Part 2 — Azure DevOps workflow

## 1. Run locally

```powershell
cd projects\telugu-pickles
docker compose up -d --build
```

The local stack runs the frontend, gateway, six backend services, PostgreSQL, Prometheus, and Grafana. Use `scripts/smoke-test.sh` to verify the public API.

## 2. Bootstrap Azure once

From `projects/AzureInfrastructure/bootstrap`, Terraform creates:

- an Azure resource group, storage account, and Blob container for Terraform state;
- separate user-assigned identities for Terraform, image CI, and release control;
- GitHub OIDC federation and the RBAC needed by the training project.

Bootstrap keeps local state, which must be backed up to encrypted private storage. The main Azure stack uses the protected Blob backend.

## 3. Provision the platform

The `azure-infra.yml` workflow validates Terraform, applies the Azure foundation, waits for AKS RBAC propagation, and then applies the Kubernetes/Helm platform. This avoids configuring in-cluster providers before AKS exists.

## 4. Build and deploy

```text
push to main
  -> tests and secret/filesystem scans
  -> build 8 Linux images
  -> image vulnerability scans
  -> push SHA tags to ACR
  -> update gitops/overlays/azure/kustomization.yml
  -> Argo CD syncs AKS
```

The application workflow never stores an Azure password. GitHub exchanges its repository OIDC token for a short-lived Entra token.

## 5. Observe and investigate

Prometheus and Grafana provide fast operational metrics. Azure Monitor stores AKS container logs in Log Analytics. The AIOps assistant combines read-only evidence from logs, Prometheus, Kubernetes, and Argo APIs, then uses Azure OpenAI to return an incident report.

## 6. Release control

Use `azure-release.yml` to promote, abort, or undo the frontend blue-green rollout and catalog canary. Release actions target AKS after Azure OIDC login.

## 7. Tear down

Run the Azure Infrastructure workflow with the destroy action. It first runs `scripts/pre-destroy-azure.sh` to remove controller-created load balancers and persistent claims, then destroys Terraform-managed resources.

Detailed commands and required GitHub settings are in [`../projects/AzureInfrastructure/README.md`](../projects/AzureInfrastructure/README.md).
