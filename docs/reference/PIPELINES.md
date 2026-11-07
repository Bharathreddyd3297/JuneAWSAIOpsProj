# GitHub Actions Pipelines

| Workflow | Purpose |
|---|---|
| `security.yml` | Gitleaks history scan and Trivy dependency, image, and IaC scans |
| `infra.yml` | Terraform format/validation, Azure plan, explicit apply, and confirmed destroy |
| `ci.yml` | Node tests, frontend build, container build/scans, ACR push, GitOps tag update |
| `function.yml` | Deploy the Azure Functions Python package using OIDC and remote build |
| `release.yml` | Operate AKS Argo Rollouts for frontend blue-green and catalog canary releases |

## Authentication

Azure login uses GitHub OIDC (`azure/login@v2`); there are no client secrets or access keys in
workflow configuration. Bootstrap must create the federated identity and grant it the required Azure
roles. See [AKS-GUIDE.md](../AKS-GUIDE.md) for the repository variables.

## Infrastructure workflow

- Pull requests run Terraform formatting, initialization without a remote backend, and validation.
- Pushes and manual `plan` runs initialize the AzureRM backend and create a plan.
- `apply` and `destroy` are manual dispatch options gated by the `production` environment.
- Destroy requires the explicit text `destroy`; the job first removes the Argo CD app, application
  namespace, PostgreSQL claim, and ingress controller resources.

No plan file is uploaded as a workflow artifact. Apply generates a fresh plan in the protected job.

## App CI workflow

- Runs backend tests and the frontend production build.
- Builds seven Linux/amd64 container images and scans them with Trivy.
- Pushes images to ACR only when Azure OIDC variables and the registry are available.
- Commits new full-SHA image tags to `gitops/kustomization.yml`; Argo CD performs the AKS deployment.

Without Azure configuration, unit tests, frontend build, and security scans still run; image push
and deployment are skipped. The workflow does not use `kubectl` for application deploys.

## Release control

The protected workflow uses Azure OIDC to obtain AKS credentials, converts kubeconfig for
`kubelogin`, and installs the Argo Rollouts kubectl plugin. Actions are status, promote, full,
abort, retry, and undo. The frontend preview is internal; use `kubectl port-forward` before
promoting.
