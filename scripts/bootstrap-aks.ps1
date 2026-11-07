param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroup,

    [string] $ClusterName = "telugu-pickles-aks",

    [Parameter(Mandatory = $true)]
    [string] $GitRepository,

    [string] $GitBranch = "azure-migration"
)

$ErrorActionPreference = "Stop"

foreach ($tool in @("az", "kubectl", "kubelogin", "helm")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required command '$tool' was not found. Install Azure CLI, kubectl, kubelogin, and Helm 3."
    }
}

if ($GitRepository -notmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$') {
    throw "GitRepository must be a GitHub HTTPS URL such as https://github.com/owner/repository.git."
}
if ($GitBranch -notmatch '^[A-Za-z0-9_.\-/]+$') {
    throw "GitBranch contains unsupported characters."
}

az account show --output none
if ($LASTEXITCODE -ne 0) {
    throw "Sign in to Azure first by running 'az login'."
}

Write-Host "Connecting kubectl to AKS cluster '$ClusterName'..."
az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing
if ($LASTEXITCODE -ne 0) { throw "Could not obtain AKS credentials." }
kubelogin convert-kubeconfig -l azurecli
if ($LASTEXITCODE -ne 0) { throw "Could not configure kubelogin for Azure CLI authentication." }

Write-Host "Creating application namespace and generating Kubernetes secrets..."
kubectl get namespace telugu-pickles *> $null
if ($LASTEXITCODE -ne 0) {
    kubectl create namespace telugu-pickles
    if ($LASTEXITCODE -ne 0) { throw "Could not create the application namespace." }
}

function New-RandomSecret([int] $Length) {
    $bytes = [byte[]]::new($Length)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes).TrimEnd("=")
}

function ConvertTo-SecretValue([string] $Value) {
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Value))
}

$secret = @{
    apiVersion = "v1"
    kind       = "Secret"
    metadata   = @{ name = "telugu-pickles-secrets"; namespace = "telugu-pickles" }
    type       = "Opaque"
    data       = @{
        PGUSER     = ConvertTo-SecretValue "pickleuser"
        PGPASSWORD = ConvertTo-SecretValue (New-RandomSecret 36)
        JWT_SECRET = ConvertTo-SecretValue (New-RandomSecret 48)
    }
} | ConvertTo-Json -Depth 6 -Compress

$secret | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw "Could not create the application Secret." }

Write-Host "Installing ingress-nginx, Argo CD, Argo Rollouts, and Prometheus/Grafana..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
if ($LASTEXITCODE -ne 0) { throw "Could not add the ingress-nginx Helm repository." }
helm repo add argo https://argoproj.github.io/argo-helm --force-update
if ($LASTEXITCODE -ne 0) { throw "Could not add the Argo Helm repository." }
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
if ($LASTEXITCODE -ne 0) { throw "Could not add the Prometheus community Helm repository." }
helm repo update
if ($LASTEXITCODE -ne 0) { throw "Could not refresh Helm repositories." }

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
    --version 4.12.1 --namespace ingress-nginx --create-namespace `
    --set controller.service.type=LoadBalancer --wait --timeout 15m
if ($LASTEXITCODE -ne 0) { throw "Ingress controller installation failed." }

helm upgrade --install argocd argo/argo-cd `
    --version 10.14.0 --namespace argocd --create-namespace `
    --set dex.enabled=false --set notifications.enabled=false `
    --set server.insecure=true --wait --timeout 15m
if ($LASTEXITCODE -ne 0) { throw "Argo CD installation failed." }

helm upgrade --install argo-rollouts argo/argo-rollouts `
    --version 2.43.9 --namespace argocd --wait --timeout 10m
if ($LASTEXITCODE -ne 0) { throw "Argo Rollouts installation failed." }

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
    --version 92.20.0 --namespace monitoring --create-namespace `
    --set grafana.service.type=ClusterIP `
    --set grafana.sidecar.dashboards.enabled=true `
    --set grafana.sidecar.dashboards.searchNamespace=ALL `
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false `
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false `
    --set prometheus.prometheusSpec.retention=7d --wait --timeout 20m
if ($LASTEXITCODE -ne 0) { throw "Prometheus/Grafana installation failed." }

$appPath = Join-Path (Split-Path $PSScriptRoot -Parent) "gitops/argocd-application.yml"
$application = Get-Content -Raw $appPath
$application = $application.Replace("https://github.com/YOUR_ORG/YOUR_REPO.git", $GitRepository)
$application = $application.Replace("YOUR_BRANCH", $GitBranch)
$application | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { throw "Could not register the GitOps application in Argo CD." }

Write-Host ""
Write-Host "AKS platform bootstrap complete."
Write-Host "Run the App CI workflow on the $GitBranch branch to build/push the images and update gitops/."
Write-Host "Argo CD UI: kubectl port-forward svc/argocd-server 8081:443 -n argocd"
Write-Host "Grafana:    kubectl port-forward svc/kube-prometheus-stack-grafana 3001:80 -n monitoring"
Write-Host "Shop URL:   kubectl get ingress -n telugu-pickles"
