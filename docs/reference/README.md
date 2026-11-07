# Reference Docs

Short explanations of each Azure deployment component. For the step-by-step walkthrough, follow
[the AKS deployment guide](../AKS-GUIDE.md).

| Doc | Answers |
|---|---|
| [PIPELINES.md](PIPELINES.md) | What each GitHub Actions workflow does, when it runs, which secrets it needs, and what can fail |
| [INFRASTRUCTURE.md](INFRASTRUCTURE.md) | Azure and Kubernetes resources created by Terraform and their roles |
| [ARGOCD.md](ARGOCD.md) | What Argo CD is, how it deploys this app, and how to operate it |
| [PROGRESSIVE-DELIVERY.md](PROGRESSIVE-DELIVERY.md) | Blue-green (frontend) and canary (catalog-service) with Argo Rollouts, plus a demo script that includes an automatic rollback |

```
 git push ──► GitHub Actions ──► Azure (Terraform) PIPELINES.md + INFRASTRUCTURE.md
                    │
                    └──► ACR images + gitops/ tag bump ──► Argo CD ──► AKS pods        ARGOCD.md
```
