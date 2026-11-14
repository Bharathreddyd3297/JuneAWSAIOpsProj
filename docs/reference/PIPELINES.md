# Azure pipelines reference

| Workflow | Responsibility |
|---|---|
| `azure-infra.yml` | Validate, plan, apply, or destroy Azure Terraform |
| `azure-ci.yml` | Test, scan, build eight images, push to ACR, update GitOps tags |
| `azure-release.yml` | Promote, abort, or undo Argo Rollouts in AKS |
| `security.yml` | Repository Gitleaks and Trivy filesystem scanning |

## Authentication

Each Azure workflow requests GitHub's OIDC token. `azure/login` exchanges it for a short-lived Entra token. Terraform, image CI, and release control use separate least-privilege identities. Required repository secrets are `AZURE_TERRAFORM_CLIENT_ID`, `AZURE_CI_CLIENT_ID`, `AZURE_RELEASE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`; none is a password.

The Terraform backend coordinates concurrent state access through Azure Blob Storage. GitHub variables supply the state resource group, storage account, container, Azure region, and deployment resource group.

## Application pipeline

The matrix builds `frontend`, `gateway`, `auth-service`, `catalog-service`, `cart-service`, `order-service`, `payment-service`, and `aiops-assistant`. Images are scanned before push and tagged with the full commit SHA. The deploy job verifies the images, edits only the Azure overlay image entries, and commits the tag change.

Argo CD, rather than the CI job, applies application manifests to AKS. This makes Git the deployment record and keeps drift visible.

## Infrastructure safety

- Pull requests run offline formatting and validation only and receive no Azure credential.
- First deployment uses a saved foundation plan followed by a saved platform plan.
- Terraform and release jobs always use the protected `production` environment.
- Destroy is manual and requires explicit confirmation.
- The pre-destroy script removes controller-owned cloud resources before Terraform removes AKS and the network.
