# Argo CD in This Project

## What Argo CD is

Argo CD is a **GitOps controller** that runs inside the Kubernetes cluster. It continuously compares:

- **desired state:** the YAML in a Git repository (here `gitops/` on `main`), with
- **live state:** what is actually running in the cluster,

and makes the cluster match Git.

```
          Git (gitops/ on main)                    EKS cluster
   ┌───────────────────────────────┐        ┌──────────────────────────┐
   │ kustomization.yml (image tags)│        │ Deployments, Services,   │
   │ k8s/apps/*.yml                │  sync  │ StatefulSet, Ingress,    │
   │ k8s/database/postgres.yml     │ ─────► │ HPAs, ServiceMonitor,    │
   │ k8s/monitoring/...            │        │ Grafana dashboard        │
   └───────────────▲───────────────┘        └────────────┬─────────────┘
                   │ every 60 s: "has Git changed?"      │ "has someone changed the cluster?"
                   └──────────────── Argo CD ◄───────────┘
```

### Push model vs pull model

| | Push (classic CI/CD) | Pull (GitOps with Argo CD) |
|---|---|---|
| Who changes the cluster | the CI pipeline runs `kubectl apply` | Argo CD, from inside the cluster |
| Cluster credentials in CI | needed | **not needed** for deploys |
| Someone edits the cluster by hand | drift goes unnoticed | detected, and **reverted** automatically |
| Rollback | re-run an old pipeline | `git revert` |
| Audit trail | pipeline logs | **Git history** = deployment history |

In this project CI never runs `kubectl`. It only **commits new image tags to Git**, and Argo CD does the rest.

---

## How it is set up here

**Installed by Terraform** ([`modules/platform/main.tf`](../../projects/Infrastructure/modules/platform/main.tf)):

| Piece | Setting | Why |
|---|---|---|
| Helm chart `argo-cd` 10.14.0 | namespace `argocd` | the Argo CD components |
| `server.insecure: true` | TLS ends at the ALB, or you use port-forward | avoids double TLS |
| `timeout.reconciliation: 60s` | poll Git every minute (default 3 min) | faster demos |
| Dex, notifications | off | not needed; fewer pods |
| Helm chart `argocd-apps` 2.0.7 | creates the **Application** | Terraform can plan it before Argo CD's CRDs exist |

### The `telugu-pickles` Application

| Field | Value | Meaning |
|---|---|---|
| `source.repoURL` | `gitops_repo_url` (this GitHub repo, public) | where to read |
| `source.targetRevision` | `main` | which branch |
| `source.path` | `gitops` | folder with `kustomization.yml`, rendered with Kustomize |
| `source.kustomize.patches` | only when a domain is set | adds `shop.<domain>` + HTTPS to the Ingress **without editing Git** |
| `destination` | in-cluster, namespace `telugu-pickles` | where to deploy |
| `syncPolicy.automated.prune` | `true` | something deleted from Git is deleted from the cluster |
| `syncPolicy.automated.selfHeal` | `true` | manual `kubectl` edits are reverted |
| `ServerSideApply=true` | — | the Grafana dashboard ConfigMap is too large for client-side apply |
| `ignoreDifferences` `/spec/replicas` + `RespectIgnoreDifferences=true` | — | the HPAs own replica counts; Argo CD doesn't fight them |
| `retry` | 10 tries, 15 s → 3 min backoff | survives temporary errors (for example images still being pushed) |
| finalizer `resources-finalizer.argocd.argoproj.io` | — | deleting the Application deletes everything it created |

### Division of work

| Owned by Terraform | Owned by Argo CD (from `gitops/`) |
|---|---|
| Namespace `telugu-pickles` (PSA labels) | 6 service Deployments + Services, frontend Deployment |
| Secret `telugu-pickles-secrets` (generated passwords) | Postgres StatefulSet + headless Service |
| Argo CD itself, Prometheus/Grafana, ALB controller, Fluent Bit | Ingress `frontend` (→ ALB) |
| The Application object | ConfigMap `telugu-pickles-config` (service URLs, chaos knobs) |
| | HPAs (gateway, catalog), StorageClass `gp3` |
| | ServiceMonitor + PrometheusRule, Grafana dashboard ConfigMap (in `monitoring`) |

Secrets stay out of Git. Everything else about the app is in Git.

---

## A deployment, step by step

1. Developer pushes app code → **App CI** builds `…/gateway:9f3c2e1…` and pushes it to ECR.
2. The CI bot commits to `gitops/kustomization.yml`:
   ```yaml
   - name: telugu-pickles/gateway
     newName: 229378727493.dkr.ecr.us-east-1.amazonaws.com/telugu-pickles/gateway
     newTag: "9f3c2e1…"
   ```
3. Within 60 s Argo CD sees a new commit → renders `gitops/` with Kustomize → the Deployment's image differs → **OutOfSync**.
4. Auto-sync applies the change → Kubernetes does a **rolling update** (`maxUnavailable: 0`, readiness probes on `/health/ready`).
5. All pods ready → **Synced / Healthy**.

**Rollback:** `git revert <deploy commit> && git push`. Argo CD deploys the previous tag. You can also use **History and rollback** in the UI, but the next Git change will win again, because Git stays the source of truth.

---

## Sync and health states

| Sync status | Meaning |
|---|---|
| **Synced** | the cluster matches Git |
| **OutOfSync** | Git and cluster differ (new commit, or a manual change about to be healed) |
| **Unknown** | Argo CD can't read Git or render the manifests (for example a YAML error) |

| Health status | Meaning |
|---|---|
| **Healthy** | all resources ready |
| **Progressing** | rolling out (pods starting, ALB being created) |
| **Degraded** | something is failing, for example `ImagePullBackOff` or `CrashLoopBackOff` |
| **Missing** | in Git but not yet in the cluster |

---

## Operating it

```bash
aws eks update-kubeconfig --name telugu-pickles-eks --region us-east-1

# status
kubectl -n argocd get applications
kubectl -n argocd describe application telugu-pickles      # conditions, last sync result

# UI  (user: admin)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward svc/argocd-server 8081:80   # http://localhost:8081

# force an immediate refresh instead of waiting up to 60 s
kubectl -n argocd annotate application telugu-pickles argocd.argoproj.io/refresh=hard --overwrite

# preview exactly what Argo CD will apply
kubectl kustomize gitops/
```

With a domain configured, the UI is at **https://argocd.<domain>**.

### In the UI
- **Application tree:** Application → Deployment → ReplicaSet → Pod; click a pod for **logs** and **events**.
- **App diff:** the exact YAML difference between Git and the cluster.
- **Sync:** manual sync, for example with *Prune* or *Replace*.
- **History and rollback:** every revision Argo CD deployed (Git SHA + time).

### Demo: self-healing
```bash
kubectl -n telugu-pickles scale deploy cart-service --replicas=0
kubectl -n argocd get application telugu-pickles -w     # OutOfSync -> Synced, pods come back
```

### Demo: config change through Git only
Edit `gitops/k8s/platform/config.yml` (for example `PAYMENT_DECLINE_RATE: "0.5"`), commit and push. Argo CD updates the ConfigMap. Pods read env vars at start, so roll them:
`kubectl -n telugu-pickles rollout restart deploy payment-service`.

---

## Troubleshooting

| Symptom | Check |
|---|---|
| `Unknown` / `ComparisonError` | `kubectl -n argocd describe application telugu-pickles`. Usually a YAML or Kustomize error; reproduce with `kubectl kustomize gitops/`. |
| Repo can't be read | The repo must be public, or add credentials: Settings → Repositories in the UI. |
| `Degraded`, pods `ImagePullBackOff` | The tag in `kustomization.yml` isn't in ECR. Run App CI on `main`. |
| Pods `CreateContainerConfigError` | Secret `telugu-pickles-secrets` missing. It's created by Terraform; re-run Infrastructure apply. |
| Sync fails on `ServiceMonitor` | Prometheus CRDs missing. kube-prometheus-stack must be installed first (Terraform orders this). |
| App stuck deleting | The finalizer is waiting for resources. `kubectl -n argocd get application telugu-pickles -o yaml` → `status.operationState`. |
