# Azure AIOps Assistant: Dude

Dude is a multi-agent site-reliability assistant for Telugu Pickles on AKS.

```text
Streamlit UI -> AKS aiops-assistant API -> Azure OpenAI supervisor
                                          |-> logs specialist -> Azure Monitor / Log Analytics
                                          |-> metrics specialist -> Prometheus
                                          `-> deployment specialist -> AKS / Argo CD / Argo Rollouts
```

## Azure services

| Service | Purpose |
|---|---|
| Azure OpenAI | Supervisor and specialist model inference |
| Microsoft Entra Workload ID | Passwordless pod authentication |
| Azure Monitor Container Insights | Collect AKS container logs |
| Log Analytics | Query application errors and warnings with KQL |
| AKS | Hosts the API and application workloads |
| Prometheus/Grafana | Application, business, pod, and rollout metrics |
| Argo CD/Rollouts | GitOps, blue-green frontend, canary catalog releases |

No model keys, registry passwords, or Azure access keys are stored in files. Terraform creates a user-assigned identity, federates it to the `aiops-assistant` Kubernetes service account, and grants only Azure OpenAI User plus Log Analytics Data Reader access. `/ask` also requires a generated bearer token.

## Runtime

| Path | Purpose |
|---|---|
| `agent/api.py` | FastAPI `/healthz` and `/ask` endpoints |
| `agent/kira.py` | Azure OpenAI multi-agent tool loop |
| `agent/logs_tools.py` | Log Analytics queries |
| `agent/metrics_tools.py` | Prometheus queries |
| `agent/deploy_tools.py` | Read-only AKS/Argo status |
| `app.py` | Local Streamlit chat UI |
| `requirements-api.txt` | Minimal dependencies baked into the AKS API image |

## Use it

After Azure Infrastructure and Azure App CI complete:

```powershell
kubectl -n telugu-pickles port-forward service/aiops-assistant 8000:8000
```

In another terminal:

```powershell
cd projects\aiops-assistant
Copy-Item .env.example .env
$encoded = kubectl -n telugu-pickles get secret aiops-assistant-api -o jsonpath="{.data.AIOPS_API_TOKEN}"
$token = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
(Get-Content .env) -replace 'replace-with-kubernetes-secret', $token | Set-Content .env
pip install -r requirements.txt
streamlit run app.py
```

Open http://localhost:8501 and ask:

- Is the platform healthy?
- Why did the catalog canary roll back?
- Are checkout payments failing?
- Which pods have restarted?

## Configuration

The Terraform module creates a `gpt-4o` Global Standard deployment in `eastus2` by default. Override these inputs if your subscription has quota in a different supported region:

```hcl
aiops_location       = "eastus2"
aiops_model_name     = "gpt-4o"
aiops_model_version  = "2024-11-20"
aiops_model_capacity = 10
```

Set `aiops_enabled = false` only when the subscription does not have Azure OpenAI access. The shop, GitOps, monitoring, and dashboards work independently.
