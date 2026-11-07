# Blue-Green and Canary Releases with Argo Rollouts

| Strategy | Service | Behavior |
|---|---|---|
| Blue-green | `frontend` | New pods are tested behind an internal preview Service; a human promotes them |
| Canary | `catalog-service` | Gradually shifts pod capacity and checks Prometheus error rates |
| Rolling update | Other services | Standard Kubernetes rollout |

Argo Rollouts is installed in AKS by `scripts/bootstrap-aks.ps1`. The relevant resources are
`gitops/k8s/apps/frontend.yml`, `catalog-service.yml`, and `analysis.yml`.

## Frontend blue-green

The public ingress routes to the active `frontend` Service. The `frontend-preview` Service remains
cluster-internal so new pods can be checked before promotion:

```powershell
kubectl port-forward svc/frontend-preview 8080:80 -n telugu-pickles
```

When a new image arrives, Argo Rollouts runs the pre-promotion health analysis and pauses. Inspect
the preview, then use **Actions → Release control → frontend → promote** or:

```powershell
kubectl argo rollouts -n telugu-pickles promote frontend
```

Promotion switches the active Service to the green pods; the previous version remains briefly for
rollback. Abort instead of promoting to keep the current version active.

## Catalog canary

The catalog Rollout gradually increases the new ReplicaSet's share of pods. Prometheus evaluates
the canary error rate; a failed analysis aborts the rollout and returns traffic to the stable
ReplicaSet. Generate traffic while testing so the metric has enough samples.

```powershell
kubectl argo rollouts -n telugu-pickles get rollout catalog-service --watch
kubectl -n telugu-pickles get analysisrun
kubectl -n telugu-pickles describe analysisrun <name>
```

The configured weight is based on pod counts, not a separate ingress traffic-splitting layer.

## Release commands

The protected **Release control** GitHub workflow supports status, promote, full, abort, retry,
and undo. Local equivalents:

```powershell
kubectl argo rollouts -n telugu-pickles list rollouts
kubectl argo rollouts -n telugu-pickles get rollout frontend
kubectl argo rollouts -n telugu-pickles promote frontend --full
kubectl argo rollouts -n telugu-pickles abort catalog-service
kubectl -n telugu-pickles get analysisrun
```

The first rollout has no prior version to stage against; blue-green and canary behavior is visible
after a later image update.
