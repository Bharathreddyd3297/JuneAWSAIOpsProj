# AIOps Assistant: Kira (multi-agent on Amazon Bedrock)

Kira is an AI site-reliability engineer for the Telugu Pickles shop on EKS. Ask her questions in a chat, or let a
CloudWatch alarm wake her up. She sends three **specialist agents** to collect evidence, then writes one incident
report: summary, impact, root cause, evidence, recommended actions and prevention.

```
 Streamlit chat (app.py) ──lambda:Invoke──┐        CloudWatch alarm "telugu-pickles-error-spike"
                                          │                 │ SNS telugu-pickles-alarms
                                          ▼                 ▼
                       ┌──────────── Lambda telugu-pickles-kira (kira.py) ─────────────┐
                       │  Kira = SUPERVISOR agent (Nova Pro / Claude Sonnet)           │
                       │  her tools:  ask_logs_agent  ask_metrics_agent  ask_deployment_agent
                       │                   │                │                  │       │  (run in parallel)
                       │            logs agent        metrics agent     deployment agent  (Nova Lite / Claude Haiku)
                       │            error_summary     service_health    rollout_status, analysis_runs,
                       │            search_logs       pod_errors, ...   argocd_status, pod_status, events
                       └──────────────────┼────────────────┼──────────────────┼────────────┘
                                CloudWatch Logs    Prometheus (EKS API proxy)  Kubernetes API (read-only)
                                          report ──► SNS telugu-pickles-aiops-reports ──► email
```

Every agent is the **same loop** ([`lambda/kira.py`](lambda/kira.py), `run_agent`):
1. send the conversation and the tool list to the model with the Bedrock **Converse API**;
2. if the model asks for tools, run them in parallel and send back the results;
3. repeat until the model answers in text.

Kira's "tools" are the three specialists, so asking one of them starts a whole agent.

Everything is **created by Terraform** ([`projects/Infrastructure/modules/aiops`](../Infrastructure/modules/aiops)) in the
Infrastructure pipeline, and **destroyed with it**. Kira is **read-only**: she recommends actions and never changes anything.

> **Why not "Bedrock Agents"?** Classic Bedrock Agents is in
> [maintenance mode](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-classic-maintenance-mode.html) and closed
> to new accounts. `CreateAgent` returns *AccessDenied … not available for accounts without prior service usage*.
> The Converse loop does the same job in about 150 visible lines, and it's easier to teach.
> AWS's managed successor is **AgentCore**, which is the next step if you want hosted agents.

## What's in this folder

| File | What |
|---|---|
| [`lambda/kira.py`](lambda/kira.py) | The agent loop, Kira's instructions, the 3 specialists, and the chat and alarm entry points |
| [`lambda/logs_tools.py`](lambda/logs_tools.py) | `error_summary`, `search_logs`: Logs Insights on `/eks/telugu-pickles/pods` |
| [`lambda/metrics_tools.py`](lambda/metrics_tools.py) | `service_health`, `pod_errors`, `business_metrics`, `pod_resources`, `firing_alerts` |
| [`lambda/deploy_tools.py`](lambda/deploy_tools.py) | `rollout_status`, `analysis_runs`, `argocd_status`, `pod_status`, `recent_events` |
| [`lambda/k8s.py`](lambda/k8s.py) | Minimal Kubernetes client: EKS token from the Lambda's IAM role, plus the Prometheus proxy |
| [`app.py`](app.py) | Streamlit chat. It invokes the Lambda and shows which agents and tools were used, the time and the tokens |

## Security

| Concern | How |
|---|---|
| Prometheus isn't public | Tools call `…/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query` through the EKS API |
| The Lambda logs in to Kubernetes | It signs an STS request with its IAM role (the same token as `aws eks get-token`). An **EKS access entry** maps role `telugu-pickles-aiops-kira` to group `aiops-readers` |
| What it can see in the cluster | ClusterRole `aiops-reader`: get and list on pods, events, services, workloads, Rollouts, AnalysisRuns and Applications, plus `services/proxy` on the Prometheus service only. **No secrets, no exec, no writes.** |
| What it can do in AWS | Query the app log group, invoke the two configured models, publish to the reports topic. Nothing else. |
| Model output is untrusted | Tool inputs are validated (allowed characters, numeric limits), and every tool is read-only |
| Who can ask Kira | Anyone allowed `lambda:InvokeFunction` on `telugu-pickles-kira`, plus the alarm topic |

## Models

| Setting (`projects/Infrastructure/terraform.tfvars`) | Default | Better, after Anthropic approval |
|---|---|---|
| `aiops_supervisor_model` (Kira) | `us.amazon.nova-pro-v1:0` | `us.anthropic.claude-sonnet-4-6` |
| `aiops_specialist_model` (3 specialists) | `us.amazon.nova-lite-v1:0` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |

Amazon **Nova** works without approval. **Claude** writes noticeably better reports, but each AWS account must first
submit Anthropic's one-time **use case details** form. To do that, open the Bedrock console → **Model catalog** → any Claude model, then follow the prompt. Approval takes about 15 minutes.

Test a model before switching. Each call costs a fraction of a cent:

```bash
aws bedrock-runtime converse --region us-east-1 --model-id us.anthropic.claude-sonnet-4-6 \
  --messages '[{"role":"user","content":[{"text":"hi"}]}]' --inference-config maxTokens=10
```

## Setup

1. **Optional email reports.** Set `aiops_alert_email = "you@example.com"` in `terraform.tfvars`, then click the confirmation link AWS emails you.
2. **Push.** The Infrastructure workflow creates the Lambda, its IAM role, the Kubernetes RBAC and the SNS wiring.
3. **Check it:**
   ```bash
   cd projects/Infrastructure && terraform output aiops
   aws lambda invoke --region us-east-1 --function-name telugu-pickles-kira --cli-read-timeout 300 \
     --cli-binary-format raw-in-base64-out --payload '{"question":"Is everything healthy?"}' out.json && cat out.json
   ```

## Chat with Kira

```bash
cd projects/aiops-assistant
pip install -r requirements.txt
streamlit run app.py               # http://localhost:8501
```

Your AWS CLI login is used, so there are no keys in files. If your CLI's default region isn't us-east-1, put `AWS_REGION=us-east-1` in `.env`.

Try the buttons, or ask:
- *Is everything healthy?*
- *Why did the last catalog-service canary roll back?*
- *Are payments failing? Since when?*

The **"How Kira investigated"** box lists every agent and tool call. That's the multi-agent collaboration made visible.

## Demo: failed canary → automatic rollback → automatic AI incident report

1. Generate traffic: `while true; do curl -s -o /dev/null http://<ALB>/api/products; sleep 0.2; done`.
2. Ship a bad catalog version: add `CHAOS_ERROR_RATE: "0.5"` to the env of `gitops/k8s/apps/catalog-service.yml`, then commit and push.
   See [PROGRESSIVE-DELIVERY.md](../../docs/reference/PROGRESSIVE-DELIVERY.md).
3. **Argo Rollouts** sees more than 5% errors on the canary pod and **aborts**. Traffic goes back to the stable pods.
4. The canary's ERROR logs push the CloudWatch alarm over 5 errors in 5 minutes. **SNS** then invokes **Kira**.
5. A minute later the **report arrives by email**, and it's also in the log of `/aws/lambda/telugu-pickles-kira`. It should
   name the canary, the failed analysis, the 503 *chaos* log lines and recommend a `git revert`.
6. Ask in the chat: *"Explain the incident from the last 15 minutes"*.

Test the alarm path without breaking anything:

```bash
aws cloudwatch set-alarm-state --region us-east-1 --alarm-name telugu-pickles-error-spike \
  --state-value ALARM --state-reason "Manual test of the AIOps pipeline"
aws logs tail /aws/lambda/telugu-pickles-kira --region us-east-1 --follow
```

## Cost

| Item | Cost |
|---|---|
| Lambda, SNS when idle | $0 |
| One question on Nova Pro + Lite (~15k tokens) | under $0.02 |
| One question on Claude Sonnet + Haiku (~15–40k tokens) | about $0.05–0.20 |

## Troubleshooting

| Symptom | Fix |
|---|---|
| Chat: *not reachable* | Run `aws sts get-caller-identity` (same account?) and check the region (`AWS_REGION=us-east-1` in `.env`) |
| `Model use case details have not been submitted` | Claude needs the Anthropic form (see Models), or use Nova |
| `AccessDeniedException` on a model | The model isn't enabled for the account, or isn't in the IAM policy (it must be the configured model) |
| Tool error `403 Forbidden` from Kubernetes | `kubectl get clusterrolebinding aiops-reader`, `aws eks list-access-entries --cluster-name telugu-pickles-eks` |
| Metrics tools return empty lists | No traffic yet. Check that `up{namespace="telugu-pickles"}` shows targets in Grafana → Explore. |
| Lambda log | `aws logs tail /aws/lambda/telugu-pickles-kira --region us-east-1 --since 15m` |
