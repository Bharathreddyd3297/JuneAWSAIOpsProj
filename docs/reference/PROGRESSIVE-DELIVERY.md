# Progressive delivery on AKS

Argo Rollouts controls two release strategies:

- `frontend`: blue-green with `frontend` as the active service and `frontend-preview` as the private preview service.
- `catalog-service`: canary steps evaluated with Prometheus before full promotion.

The public ingress always routes to the active frontend service. The preview service is ClusterIP-only; test it with port-forwarding:

```powershell
kubectl -n telugu-pickles port-forward svc/frontend-preview 8081:80
```

## Inspect releases

```powershell
kubectl -n telugu-pickles get rollouts,analysisruns
kubectl -n telugu-pickles describe rollout frontend
kubectl -n telugu-pickles describe rollout catalog-service
```

## Control releases

Use the manual `azure-release.yml` workflow for promote, abort, or undo. It authenticates to Azure with OIDC, obtains AKS credentials, and calls the Argo Rollouts kubectl plugin.

Prometheus provides the error-rate and health measurements used by catalog analysis. If a threshold fails, the rollout does not advance. Azure Monitor retains the associated container logs, and the read-only AIOps assistant can correlate logs, metrics, and rollout status.

## Recovery checks

| Problem | Check |
|---|---|
| Rollout paused | AnalysisRun result and Prometheus target health |
| Preview unavailable | `frontend-preview` endpoints and port-forward session |
| New pods unhealthy | readiness probes, container logs, image tag |
| Metrics missing | ServiceMonitor/PodMonitor selection and Prometheus targets |
