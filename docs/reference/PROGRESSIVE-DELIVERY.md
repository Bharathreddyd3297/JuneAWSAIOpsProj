# Blue-Green and Canary Releases (Argo Rollouts)

A normal Kubernetes **rolling update** swaps pods one by one. Every shopper can hit the new version before
anyone has checked it. **Progressive delivery** releases more carefully:

| Strategy | Used for | Idea | Rollback |
|---|---|---|---|
| **Blue-green** | `frontend` | Run the new version (**green**) next to the old (**blue**). Test green privately, then switch **all** traffic at once. | Switch back instantly (blue keeps running 2 min) |
| **Canary** | `catalog-service` | Give the new version a **small share** of traffic, measure errors, then increase step by step. | **Automatic**: a failed check sends 100% back to the old version |
| Rolling update | other services | Kubernetes default | `git revert` |

The tool is **[Argo Rollouts](https://argoproj.github.io/rollouts/)**. Terraform installs it (`modules/platform`, chart
`argo-rollouts` 2.43.9) in the `argocd` namespace. It adds a `Rollout` kind, which is a Deployment with a release strategy.

```
CI pushes image ─► bot commits tag to gitops/ ─► Argo CD syncs the Rollout ─► Argo Rollouts runs the strategy
                                                                              ├─ frontend:  blue-green, waits for "promote"
                                                                              └─ catalog:   canary + Prometheus checks
```

Files:

| File | What |
|---|---|
| [`gitops/k8s/apps/frontend.yml`](../../gitops/k8s/apps/frontend.yml) | Rollout (blue-green), Services `frontend` (active) + `frontend-preview`, Ingresses on ALB ports **80** and **8080** |
| [`gitops/k8s/apps/catalog-service.yml`](../../gitops/k8s/apps/catalog-service.yml) | Rollout (canary) with steps 25% → check → 50% → check → 100% |
| [`gitops/k8s/apps/analysis.yml`](../../gitops/k8s/apps/analysis.yml) | AnalysisTemplates: `http-health` (blue-green) and `canary-error-rate` (Prometheus) |
| [`gitops/k8s/apps/autoscaling.yml`](../../gitops/k8s/apps/autoscaling.yml) | HPA for catalog targets the Rollout, minimum 4 pods |
| [`.github/workflows/release.yml`](../../.github/workflows/release.yml) | **Release control**: status, promote, full, abort, retry and undo from GitHub |

> The **first** deployment of a Rollout is never staged. There's nothing to compare it to yet.
> Blue-green and canary start from the **second** image onwards.

---

## Blue-green: `frontend`

```
                 ALB :80   ──► Service frontend          ──► BLUE pods  (current version, shoppers)
                 ALB :8080 ──► Service frontend-preview  ──► GREEN pods (new version, testers)
promote:         ALB :80   ──► GREEN pods                    BLUE pods removed after 120 s
```

1. A new frontend image is committed to Git, and Argo CD syncs it.
2. Argo Rollouts starts **2 green pods**. Shoppers still get blue.
3. **Pre-promotion check** (`http-health`): green calls `/api/health` through its own Service 3 times. It must return `"status":"ok"`, which proves green reaches the gateway and all backend services.
4. The Rollout **pauses**. Argo CD shows health **Suspended**, which is normal.
5. Open **`http://<ALB>:8080`** and test the new version.
6. Promote with **Actions → Release control → `frontend` → `promote`**, after you approve the `production` environment. On a laptop, run `kubectl argo rollouts -n telugu-pickles promote frontend`.
7. The `frontend` Service switches to green in a single step. Blue is deleted 2 minutes later.

To reject green, run **Release control → `abort`**. Green is scaled down, and shoppers never saw it.

## Canary: `catalog-service`

| Step | Pods (of 4) | Duration |
|---|---|---|
| `setWeight: 25` | 1 new, 3 old | — |
| pause | | 1 min (metrics build up) |
| analysis `canary-error-rate` | | 4 checks × 30 s |
| `setWeight: 50` | 2 new, 2 old | — |
| pause + analysis | | 3 min |
| `setWeight: 100` | 4 new | done, about 7 min in total |

The check runs this Prometheus query against **the new pods only**, found by their pod-template hash:

```promql
sum(rate(http_requests_total{pod=~"catalog-service-<new-hash>-.*", status_code=~"5.."}[2m]))
  / sum(rate(http_requests_total{pod=~"catalog-service-<new-hash>-.*"}[2m]))      # must be <= 0.05
```

If it fails twice, the Rollout is **Degraded/Aborted** and all pods go back to the old version, with no human involved.

There's no traffic splitter here. The weight is the **share of pods**: with 1 new pod out of 4, the Service sends about 25% of requests to it.

---

## Demo script (about 20 minutes)

Before you start: the cluster is running, App CI has deployed at least once, and the shop opens on `http://<ALB>`.

**Watch it live** (optional, laptop):

```bash
# CLI plugin: https://argoproj.github.io/argo-rollouts/installation/#kubectl-plugin-installation
kubectl argo rollouts -n telugu-pickles get rollout frontend --watch
kubectl -n argocd port-forward svc/argo-rollouts-dashboard 3100:3100      # UI: http://localhost:3100
```

### 1. Blue-green
1. Make a visible change, for example the hero title in `projects/telugu-pickles/frontend/src/pages/Home.jsx`. Commit and push.
2. App CI builds all images, and the bot commits the tags. The run summary lists what happens to each service.
3. Within about a minute, `http://<ALB>` still shows the **old** page and `http://<ALB>:8080` shows the **new** page.
4. Run **Actions → Release control → frontend → status**: *Paused, BlueGreenPause*.
5. Run **Release control → frontend → promote** and approve it. Reload `http://<ALB>`: the new page is live.

### 2. Canary that succeeds
The same push also gave catalog-service a new image, so its canary runs on its own. Generate traffic so the check has data:

```bash
ALB=<alb-hostname>
while true; do curl -s -o /dev/null "http://$ALB/api/products"; sleep 0.2; done
```

Watch 1 → 2 → 4 new pods in `kubectl argo rollouts -n telugu-pickles get rollout catalog-service --watch`.

### 3. Canary that fails, with automatic rollback (an AIOps hook)
1. Ship a "bad" version: in `gitops/k8s/apps/catalog-service.yml`, add this to the container `env:`
   ```yaml
   - name: CHAOS_ERROR_RATE
     value: "0.5"        # the new pods fail 50% of requests
   ```
   Commit and push. This is a Git-only change, so no CI build is needed.
2. Keep the traffic loop running. After the 1-minute pause, the analysis measures about 50% errors on the canary pod and the Rollout becomes **Degraded**, with *RolloutAborted: Metric "canary-5xx-ratio" assessed Failed*.
3. All traffic is back on the old pods automatically. Shoppers saw errors for about 2 minutes, and only on 25% of requests.
4. Clean up: remove the env lines, commit and push. A new canary runs and passes.

Later the **Bedrock AIOps agent** gets these facts: Rollout status, AnalysisRun results, the error logs in CloudWatch and the `HighServerErrorRate` alert. It can explain why the release was rolled back.

---

## Commands

```bash
kubectl argo rollouts -n telugu-pickles list rollouts
kubectl argo rollouts -n telugu-pickles get rollout catalog-service
kubectl argo rollouts -n telugu-pickles promote frontend          # next step / switch blue-green
kubectl argo rollouts -n telugu-pickles promote frontend --full   # skip all remaining steps
kubectl argo rollouts -n telugu-pickles abort catalog-service
kubectl argo rollouts -n telugu-pickles retry rollout catalog-service
kubectl -n telugu-pickles get analysisrun                          # results of every check
kubectl -n telugu-pickles describe analysisrun <name>
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Argo CD health **Suspended** | Normal while blue-green waits for `promote` |
| Blue-green never pauses | It was the first deployment of the Rollout. That's expected; try again with the next image. |
| `http://<ALB>:8080` doesn't load | `kubectl -n telugu-pickles get ingress frontend-preview`. The ALB listener on 8080 takes 1–2 minutes the first time. |
| Analysis **Error** (not Failed) | Prometheus unreachable: `kubectl -n monitoring get svc kube-prometheus-stack-prometheus` |
| Canary passed although it was bad | No traffic reached it. Run the curl loop **during** the analysis steps. |
| After `undo`, Argo CD brings the bad image back | Git is the truth. Also `git revert` the deploy commit. |
