# Migration Status

| Phase | Status | Notes |
|-------|--------|-------|
| Assessment | ✅ Complete | Service mappings and target AKS architecture are documented in the assessment report. |
| Code Migration | ✅ Complete | Terraform, Azure Functions, AKS/GitOps, GitHub OIDC workflows, scripts, and deployment documentation converted and validated. No Azure resources were deployed. |

## Validation

- Terraform format and `validate` passed for both the main and bootstrap stacks.
- Backend unit tests (7/7) and frontend production build passed.
- Python 3.14 syntax check and Azure Function import/registration smoke test passed.
- PowerShell and Bash script syntax checks passed.
- All 24 YAML files parsed successfully.

## Operator configuration still required

Choose the Azure subscription/region and an available AKS VM SKU; apply bootstrap Terraform; configure
GitHub OIDC/state variables and an optional local AKS admin; then review and manually apply the main
Terraform stack. Deploy an Azure-hosted model before enabling AIOps requests. The conversion has not
created, modified, or deleted Azure resources.
