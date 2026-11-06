# AIOps Assistant: Kira (Amazon Bedrock multi-agent)

Kira is an AI site-reliability engineer for the Telugu Pickles shop on EKS. Ask her questions in a chat, or let a
CloudWatch alarm wake her up. She sends three **specialist agents** to collect evidence, then writes one incident
report: summary, impact, root cause, evidence, recommended actions and prevention.

```
 Streamlit chat (app.py) ─┐                          CloudWatch alarm "telugu-pickles-error-spike"
                          │                                   │ SNS telugu-pickles-alarms
                          ▼                                   ▼
                 ┌─────────────────────┐  ◄────────  Lambda telugu-pickles-aiops-incident ──► SNS telugu-pickles-aiops-reports ──► email
                 │ Kira  (SUPERVISOR)  │
                 │ Claude Sonnet 4.6   │
                 └──┬────────┬──────┬──┘
        ┌───────────┘        │      └──────────────┐
        ▼                    ▼                     ▼
  logs-agent           metrics-agent         deployment-agent        (COLLABORATORS, Claude Haiku 4.5)
  Lambda logs-tools    Lambda metrics-tools  Lambda deploy-tools
  CloudWatch Logs      Prometheus            Argo CD, Argo Rollouts, pods, events
  Insights             (via EKS API proxy)   (Kubernetes API, read-only)
```

Everything is **created by Terraform** ([`projects/Infrastructure/modules/aiops`](../Infrastructure/modules/aiops)) in the
Infrastructure pipeline, and **destroyed with it**. The agents are **read-only**: they recommend actions, they never change anything.

## What's in this folder

| File | What |
|---|---|
| [`lambda/logs_tools.py`](lambda/logs_tools.py) | `error_summary`, `search_logs`: Logs Insights on `/eks/telugu-pickles/pods` |
| [`lambda/metrics_tools.py`](lambda/metrics_tools.py) | `service_health`, `pod_errors`, `business_metrics`, `pod_resources`, `firing_alerts` |
| [`lambda/deploy_tools.py`](lambda/deploy_tools.py) | `rollout_status`, `analysis_runs`, `argocd_status`, `pod_status`, `recent_events` |
| [`lambda/incident.py`](lambda/incident.py) | Alarm → ask Kira → publish the report to SNS (email) and its log |
| [`lambda/k8s.py`](lambda/k8s.py) | Minimal Kubernetes client: EKS token from the Lambda's IAM role and the Prometheus proxy |
| [`lambda/agent_io.py`](lambda/agent_io.py) | Converts between the Bedrock action-group event and plain Python functions |
| [`app.py`](app.py) | Streamlit chat UI. It finds Kira by name and shows which specialists she consulted |

## How the pieces connect, and why it's secure

| Concern | How |
|---|---|
| Prometheus isn't public | Tools call `…/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query` through the EKS API |
| Lambdas log in to Kubernetes | They sign an STS request with their IAM role (the same token as `aws eks get-token`). An **EKS access entry** maps role `telugu-pickles-aiops-k8s` to group `aiops-readers` |
| What they can see | ClusterRole `aiops-reader`: get and list on pods, events, services, workloads, Rollouts, AnalysisRuns and Applications, plus `services/proxy` on the Prometheus service only. **No secrets, no exec, no writes.** |
| Logs | Role `telugu-pickles-aiops-logs` may only query the app log group |
| Who can call the tools | `aws_lambda_permission` allows only the specific Bedrock agent ARN |
| Models | Inference profiles `us.anthropic.claude-sonnet-4-6` (Kira) and `us.anthropic.claude-haiku-4-5…` (specialists). Change them in `terraform.tfvars` |

## Setup

1. **Model access.** Check that your account can call the models (each call costs a fraction of a cent):
   ```bash
   aws bedrock-runtime converse --region us-east-1 --model-id us.anthropic.claude-sonnet-4-6 \
     --messages '[{"role":"user","content":[{"text":"hi"}]}]'
   ```
   `AccessDeniedException` means you should pick another model from `aws bedrock list-inference-profiles` and set
   `aiops_supervisor_model` / `aiops_specialist_model` in `projects/Infrastructure/terraform.tfvars`.
2. **Optional email reports.** Set `aiops_alert_email = "you@example.com"` in the same tfvars file, then click the
   confirmation link AWS emails you.
3. **Push.** The Infrastructure workflow creates 42 AIOps resources: 4 agents, 4 Lambdas, IAM, RBAC and SNS.
   ```bash
   cd projects/Infrastructure && terraform output aiops
   ```

## Chat with Kira

```bash
cd projects/aiops-assistant
pip install -r requirements.txt
streamlit run app.py               # http://localhost:8501
```

Your AWS CLI login is used, so there are no keys in files. Try the buttons, or ask:
- *Is everything healthy?*
- *Why did the last catalog-service canary roll back?*
- *Are payments failing? Since when?*

The first answer takes 30–90 seconds because Kira waits for her specialists.

You can also test from the AWS console: **Bedrock → Agents → telugu-pickles-kira → Test**. Choose alias `live` and open the **trace** to watch the delegation.

## Demo: failed canary → automatic rollback → automatic AI incident report

1. Generate traffic: `while true; do curl -s -o /dev/null http://<ALB>/api/products; sleep 0.2; done`.
2. Ship a bad catalog version: add `CHAOS_ERROR_RATE: "0.5"` to the env of `gitops/k8s/apps/catalog-service.yml`, then commit and push.
   See [PROGRESSIVE-DELIVERY.md](../../docs/reference/PROGRESSIVE-DELIVERY.md).
3. **Argo Rollouts** sees more than 5% errors on the canary pod and **aborts**. Traffic goes back to the stable pods.
4. The canary's ERROR logs push the CloudWatch alarm over 5 errors in 5 minutes. **SNS** then wakes the **incident Lambda**, which asks **Kira**.
5. A few minutes later the **report arrives by email**, and it's also in CloudWatch log group `/aws/lambda/telugu-pickles-aiops-incident`.
   It should name the canary, the failed analysis, the 503 *chaos* log lines and the recommended `git revert`.
6. Ask in the chat UI: *"Explain the incident from the last 15 minutes"*.

Test the alarm path without breaking anything:

```bash
aws cloudwatch set-alarm-state --alarm-name telugu-pickles-error-spike \
  --state-value ALARM --state-reason "Manual test of the AIOps pipeline"
aws logs tail /aws/lambda/telugu-pickles-aiops-incident --follow
```

## Cost

| Item | Cost |
|---|---|
| Bedrock agents, aliases, Lambdas, SNS when idle | $0 |
| One investigation (Kira + 3 specialists, ~30–60k tokens) | about $0.10–0.30 |
| Lambda invocations | free tier |

## Troubleshooting

| Symptom | Fix |
|---|---|
| Chat: *agent not found* | Run `aws sts get-caller-identity` (same account?), then `terraform output aiops` |
| `accessDeniedException` on the model | The model isn't enabled for the account. See Setup step 1. |
| Tool error `403 Forbidden` from Kubernetes | Access entry or RBAC missing: `kubectl get clusterrolebinding aiops-reader`, `aws eks list-access-entries --cluster-name telugu-pickles-eks` |
| Tool error `Unauthorized` | The Lambda role isn't in the access entries. Re-run Infrastructure apply. |
| Metrics tools return empty lists | No traffic yet, or Prometheus isn't scraping: Grafana → Explore → `up{namespace="telugu-pickles"}` |
| Changed a specialist's instruction but nothing changed | Specialist aliases pin a version. Run `terraform apply -replace='module.aiops[0].aws_bedrockagent_agent_alias.specialist["logs"]'` |
| Lambda logs | `aws logs tail /aws/lambda/telugu-pickles-aiops-<logs\|metrics\|deploy>-tools --since 15m` |
