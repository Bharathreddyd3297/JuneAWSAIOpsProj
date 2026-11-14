# AI coding assistant setup for Azure

This project can be operated with any coding assistant that can use a terminal. The assistant does not need cloud passwords in its configuration.

## Required local tools

- Azure CLI (`az`)
- Terraform 1.10 or newer
- Docker Desktop
- `kubectl`
- Git

Authenticate interactively and select the intended subscription:

```powershell
az login
az account list --output table
az account set --subscription "<subscription name or ID>"
az account show --output table
```

Never paste passwords, access tokens, storage keys, or kubeconfig content into chat or repository files.

## Useful Azure checks

```powershell
az account show --output table
az aks list --output table
az acr list --output table
az monitor log-analytics workspace list --output table
```

After Terraform creates AKS:

```powershell
az aks get-credentials --resource-group telugu-pickles-azure --name telugu-pickles-aks --overwrite-existing
kubectl get nodes
kubectl get pods -A
```

## Safe operating pattern

1. Inspect and validate before changing infrastructure.
2. Run `terraform plan` and review the exact add/change/destroy counts.
3. Apply only an approved saved plan.
4. Use GitHub OIDC and Entra workload identity instead of client secrets.
5. Run the Azure pre-destroy script before destroying the cluster.

The deployment guide is in [`../projects/AzureInfrastructure/README.md`](../projects/AzureInfrastructure/README.md).
