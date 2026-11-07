# Argo CD in This Project

Argo CD runs in AKS and continuously reconciles the manifests in `gitops/` with the
`telugu-pickles` namespace. CI publishes images to ACR and changes `gitops/kustomization.yml`;
Argo CD, not the CI runner, applies workload changes to Kubernetes.

## Application setup

`scripts/bootstrap-aks.ps1` installs Argo CD and applies `gitops/argocd-application.yml` with the
repository URL and branch supplied on the command line. The Application watches the `gitops/` path
and uses automated sync, pruning, and self-healing.

The repository must be public for anonymous Git access. For a private repository, add credentials
to Argo CD before syncing. The Argo CD API server is not exposed publicly.

## Observe the application

```powershell
kubectl -n argocd get applications
kubectl -n argocd describe application telugu-pickles
kubectl kustomize gitops/
kubectl -n argocd port-forward svc/argocd-server 8081:443
```

Open `https://localhost:8081` and retrieve the initial admin password from the `argocd-initial-admin-secret`
Secret. Rotate the password after first sign-in.

## Deployment and rollback

1. App CI builds and scans the service images, then pushes them to ACR.
2. CI updates the ACR image names and commit-SHA tags in `gitops/kustomization.yml`.
3. Argo CD observes Git changes, renders Kustomize, and applies the new desired state.
4. Kubernetes rolling updates or Argo Rollouts perform the configured release strategy.

Use `git revert` on the image-tag commit to roll back to the previous image. Keep the GitOps
repository as the source of truth; manual edits are reconciled away.

## Troubleshooting

| Symptom | Check |
|---|---|
| `Unknown` or comparison error | `kubectl -n argocd describe application telugu-pickles`; also run `kubectl kustomize gitops/` |
| Repository cannot be read | Verify repo URL/branch and configure credentials for a private repo |
| `ImagePullBackOff` | Confirm the image tag exists in ACR and the AKS kubelet identity has `AcrPull` |
| `CreateContainerConfigError` | Verify `telugu-pickles-secrets` exists in the app namespace |
| Application remains progressing | Inspect pod events, PVC state, and Argo CD sync conditions |
