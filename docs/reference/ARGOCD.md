# Argo CD on AKS

Argo CD is installed by the Terraform platform module. Its Application watches `gitops/overlays/azure` on the repository's `main` branch and deploys into the `telugu-pickles` namespace.

## Reconciliation flow

```text
Azure App CI -> commit ACR image tags -> Git
                                         |
                                         v
                                    Argo CD
                                         |
                                         v
                           Kustomize Azure overlay -> AKS
```

The base contains cloud-neutral application objects. The Azure overlay supplies ACR image names, the `managed-csi` storage class, ingress-nginx behavior, and the AIOps deployment.

## Check status

```powershell
kubectl -n argocd get applications
kubectl -n argocd get application telugu-pickles -o wide
kubectl -n telugu-pickles get pods,svc,ingress,rollout
```

To access the Argo UI without making it public:

```powershell
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

## Common failures

| Symptom | Check |
|---|---|
| `ImagePullBackOff` | ACR image/tag exists and AKS kubelet has `AcrPull` |
| Application `OutOfSync` | Render `kubectl kustomize gitops/overlays/azure` and inspect Argo events |
| Ingress has no address | ingress-nginx controller service and Azure public IP allocation |
| PVC pending | AKS Azure Disk CSI driver and `managed-csi` storage class |
