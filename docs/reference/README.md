# Reference Docs

Short, factual explanations of each moving part. Use them as reference. For the step-by-step walkthrough, follow [../CICD-EKS-GUIDE.md](../CICD-EKS-GUIDE.md).

| Doc | Answers |
|---|---|
| [PIPELINES.md](PIPELINES.md) | What each GitHub Actions workflow does, when it runs, which secrets it needs, and what can fail |
| [INFRASTRUCTURE.md](INFRASTRUCTURE.md) | Every AWS and Kubernetes resource Terraform creates, why, and what it costs |
| [ARGOCD.md](ARGOCD.md) | What Argo CD is, how it deploys this app, and how to operate it |
| [PROGRESSIVE-DELIVERY.md](PROGRESSIVE-DELIVERY.md) | Blue-green (frontend) and canary (catalog-service) with Argo Rollouts, plus a demo script that includes an automatic rollback |

```
 git push ──► GitHub Actions ──► AWS (Terraform)        PIPELINES.md + INFRASTRUCTURE.md
                    │
                    └──► ECR images + gitops/ tag bump ──► Argo CD ──► EKS pods        ARGOCD.md
```
