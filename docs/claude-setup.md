# Developer Tooling for Azure

This project uses Azure CLI authentication locally and GitHub OIDC in CI. No long-lived Azure
credentials belong in source control or GitHub Actions variables.

## Local workstation

Install the tools needed for the task:

| Tool | Purpose |
|---|---|
| Azure CLI | Sign in, inspect Azure resources, obtain AKS credentials |
| Terraform | Validate and manage Azure infrastructure |
| kubectl + kubelogin | Operate AKS with Microsoft Entra authentication |
| Helm 3 | Install AKS platform components |
| Docker | Build and test the application containers |
| PowerShell 7 | Run `scripts/bootstrap-aks.ps1` |

Sign in and select the intended subscription:

```powershell
az login
az account set --subscription <subscription-id>
az account show
```

Use the [AKS deployment guide](AKS-GUIDE.md) for bootstrap, GitHub variables, infrastructure
deployment, and application rollout steps.

## GitHub Actions identity

The Terraform bootstrap creates a user-assigned managed identity with federated credentials scoped
to the configured GitHub repository. Workflows request short-lived tokens using GitHub OIDC and
`azure/login`; do not add a client secret or service-principal password.

For local tooling that supports MCP, prefer Azure/Microsoft documentation and resource tools scoped
to the active subscription. Review any proposed `apply`, deletion, or production command before
running it.
