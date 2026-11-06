"""Dude — a multi-agent AIOps assistant built on the Amazon Bedrock Converse API.

                    Dude (SUPERVISOR, Claude Sonnet)
       ask_logs_agent   ask_metrics_agent   ask_deployment_agent      <- Dude's "tools" are other agents
            │                  │                     │
     logs agent (Haiku)  metrics agent (Haiku)  deployment agent (Haiku)
     error_summary       service_health         rollout_status, analysis_runs,
     search_logs         pod_errors, ...        argocd_status, pod_status, recent_events

Every agent is the same loop: send the conversation + tool list to the model -> if the model asks for tools,
run them (in parallel) and send the results back -> repeat until the model answers in text.

One Lambda, two entry points:
  - chat (Streamlit):      {"question": "...", "history": [{"role": "user"|"assistant", "text": "..."}]}
  - incident (SNS alarm):  {"Records": [{"Sns": {"Message": "<CloudWatch alarm JSON>"}}]}
"""
import json
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor

import boto3
from botocore.config import Config

import deploy_tools
import logs_tools
import metrics_tools

log = logging.getLogger()
log.setLevel(logging.INFO)

REGION = os.environ.get("AWS_REGION", "us-east-1")
SUPERVISOR_MODEL = os.environ["SUPERVISOR_MODEL"]
SPECIALIST_MODEL = os.environ["SPECIALIST_MODEL"]
REPORT_TOPIC = os.environ.get("REPORT_TOPIC_ARN", "")

bedrock = boto3.client("bedrock-runtime", region_name=REGION,
                       config=Config(retries={"max_attempts": 5, "mode": "adaptive"}, read_timeout=120))
sns = boto3.client("sns", region_name=REGION)

MAX_TOOL_RESULT = 12000  # characters; keeps context (and cost) small


# =============================================================== the agent loop
def tool(name, description, properties=None, required=None):
    return {"toolSpec": {"name": name, "description": description, "inputSchema": {"json": {
        "type": "object", "properties": properties or {}, "required": required or []}}}}


def run_agent(name, model, system, tools, functions, messages, max_turns, max_tokens, trace):
    """Converse tool-use loop. `functions` maps tool name -> python callable(**input) -> JSON-able."""
    for turn in range(max_turns):
        resp = bedrock.converse(
            modelId=model,
            system=[{"text": system}],
            messages=messages,
            toolConfig={"tools": tools},
            inferenceConfig={"maxTokens": max_tokens},  # always explicit (quota reservation)
        )
        usage = resp.get("usage", {})
        trace["tokens_in"] += usage.get("inputTokens", 0)
        trace["tokens_out"] += usage.get("outputTokens", 0)
        message = resp["output"]["message"]
        messages.append(message)

        calls = [b["toolUse"] for b in message["content"] if "toolUse" in b]
        if resp["stopReason"] != "tool_use" or not calls:
            return "".join(b.get("text", "") for b in message["content"]).strip()

        def execute(call):
            trace["steps"].append(f"{name} → {call['name']}({json.dumps(call.get('input', {}), separators=(',', ':'))})")
            try:
                fn = functions[call["name"]]  # unknown names raise KeyError -> reported to the model
                result = json.dumps(fn(**(call.get("input") or {})), default=str)
                status = "success"
            except Exception as exc:
                log.exception("tool %s failed", call["name"])
                result, status = json.dumps({"error": f"{type(exc).__name__}: {exc}"}), "error"
            if len(result) > MAX_TOOL_RESULT:
                result = result[:MAX_TOOL_RESULT] + "...(truncated)"
            return {"toolResult": {"toolUseId": call["toolUseId"], "content": [{"text": result}], "status": status}}

        with ThreadPoolExecutor(max_workers=4) as pool:  # several tool calls in one turn run in parallel
            results = list(pool.map(execute, calls))
        messages.append({"role": "user", "content": results})

    return f"({name} stopped after {max_turns} steps without a final answer)"


# =============================================================== the three specialists
PLATFORM = ("The Telugu Pickles e-commerce shop runs on Amazon EKS, namespace telugu-pickles: React frontend (nginx) "
            "-> gateway -> auth-service, catalog-service, cart-service, order-service; order-service calls "
            "payment-service; PostgreSQL. frontend releases with BLUE-GREEN, catalog-service with CANARY "
            "(25% -> Prometheus 5xx check -> 50% -> check -> 100%, automatic rollback), others rolling updates.")

SPECIALISTS = {
    "logs": {
        "system": PLATFORM + """
You are the LOGS specialist. Services write JSON logs (level, service, msg, path, status, err) to CloudWatch.
Start with error_summary, then search_logs for concrete lines. Report the time window, counts, exact top messages
(quoted), the pods they came from, first/last seen. Never invent log lines; say clearly if nothing was found.
Be concise: a short factual summary, no recommendations.""",
        "tools": [
            tool("error_summary", "Counts ERROR and WARN log lines grouped by service and message, biggest first.",
                 {"minutes": {"type": "integer", "description": "Minutes back (default 60)"}}),
            tool("search_logs", "Most recent log lines, newest first, optionally filtered.", {
                "service": {"type": "string", "description": "e.g. catalog-service; empty = all"},
                "level": {"type": "string", "description": "ERROR (default), WARN, INFO or ALL"},
                "minutes": {"type": "integer", "description": "Minutes back (default 30)"},
                "text": {"type": "string", "description": "Only messages containing this text"},
                "limit": {"type": "integer", "description": "Max lines (default 30, max 100)"}}),
        ],
        "functions": {"error_summary": logs_tools.error_summary, "search_logs": logs_tools.search_logs},
    },
    "metrics": {
        "system": PLATFORM + """
You are the METRICS specialist (Prometheus). Start with service_health and firing_alerts. If a service looks bad,
call pod_errors for it: if only some pods fail, they are probably NEW pods of a canary/blue-green release.
Report numbers with units and the window. Normal: error_pct_5xx near 0, p95 below 0.5 s. Never invent numbers.
Be concise: a short factual summary, no recommendations.""",
        "tools": [
            tool("service_health", "Requests/s, 5xx error % and p95 latency for every service.",
                 {"minutes": {"type": "integer", "description": "Rate window in minutes (default 5)"}}),
            tool("pod_errors", "Request rate and 5xx % for EACH POD of one service (finds a bad canary pod).", {
                "service": {"type": "string", "description": "e.g. catalog-service"},
                "minutes": {"type": "integer", "description": "Rate window in minutes (default 10)"}}, ["service"]),
            tool("business_metrics", "Orders placed by status and payment method (PAYMENT_FAILED = checkout problems).",
                 {"minutes": {"type": "integer", "description": "Window in minutes (default 30)"}}),
            tool("pod_resources", "CPU cores, memory MiB and restarts in the last hour for every app pod."),
            tool("firing_alerts", "Prometheus alerts currently firing or pending."),
        ],
        "functions": {f: getattr(metrics_tools, f) for f in
                      ("service_health", "pod_errors", "business_metrics", "pod_resources", "firing_alerts")},
    },
    "deployment": {
        "system": PLATFORM + """
You are the DEPLOYMENT specialist (GitOps: GitHub Actions -> ECR -> Git commit -> Argo CD; Argo Rollouts for
blue-green/canary). Use rollout_status and analysis_runs to tell whether a release is progressing, paused, aborted
or rolled back and which metric failed with which values; argocd_status for Git revision and sync/health;
pod_status for CrashLoopBackOff/ImagePullBackOff/OOMKilled/restarts; recent_events for warnings.
Report timestamps and image tags. Be concise: a short factual summary, no recommendations.""",
        "tools": [
            tool("rollout_status", "Argo Rollouts state (frontend blue-green, catalog-service canary).",
                 {"name": {"type": "string", "description": "frontend or catalog-service; empty = all"}}),
            tool("analysis_runs", "Recent automatic release checks with measured values and result.", {
                "rollout": {"type": "string", "description": "Rollout name; empty = all"},
                "limit": {"type": "integer", "description": "How many (default 5)"}}),
            tool("argocd_status", "Argo CD sync/health, deployed Git revision, last sync result, unhealthy resources."),
            tool("pod_status", "Pods: ready, restarts, waiting reason, last termination reason, image.",
                 {"service": {"type": "string", "description": "Only this service (label app); empty = all"}}),
            tool("recent_events", "Kubernetes events in the app namespace.", {
                "minutes": {"type": "integer", "description": "Minutes back (default 30)"},
                "warnings_only": {"type": "boolean", "description": "Only warnings (default true)"}}),
        ],
        "functions": {f: getattr(deploy_tools, f) for f in
                      ("rollout_status", "analysis_runs", "argocd_status", "pod_status", "recent_events")},
    },
}


def ask_specialist(kind, question, trace):
    spec = SPECIALISTS[kind]
    return run_agent(f"{kind}-agent", SPECIALIST_MODEL, spec["system"], spec["tools"], spec["functions"],
                     [{"role": "user", "content": [{"text": question}]}], max_turns=6, max_tokens=1500, trace=trace)


# =============================================================== Dude, the supervisor (display name; code names keep "kira")
KIRA_SYSTEM = PLATFORM + """
You are Dude, the AIOps site-reliability engineer for Telugu Pickles. You lead three specialist agents and
delegate to them instead of guessing:
  - ask_logs_agent: error messages and when they started (CloudWatch Logs)
  - ask_metrics_agent: error %, latency, traffic, per-pod comparison, orders/payments, alerts (Prometheus)
  - ask_deployment_agent: releases, blue-green/canary state, failed release checks, Argo CD, pod crashes, events
Give each specialist a precise question. For an incident, ask ALL THREE in the same turn (they run in parallel),
then correlate: did errors start right after a release? Are only new pods failing? Was a canary aborted?
Is it one service or a dependency (database, payment)?

For an incident answer in this format (Markdown):
**Summary** - one or two sentences a manager understands.
**Impact** - which services, how many errors / which checkouts affected, since when.
**Root cause** - most likely cause, with confidence (high / medium / low).
**Evidence** - bullets of concrete facts from the specialists (numbers, quoted log messages, timestamps, versions).
**Recommended actions** - numbered, safest first, with exact commands or GitHub Actions steps
  (e.g. "Actions -> Release control -> catalog-service -> abort", "git revert <deploy commit>").
**Prevention** - one or two improvements.
Use the incident format ONLY when the evidence shows a real problem. Otherwise answer briefly (a few bullets).
What is NORMAL here (not an incident): little or no traffic (it is a demo shop); 4xx answers (400 validation,
401 failed login, 404) - those are client mistakes or tests, only 5xx are server errors; Rollouts phase Healthy.
Real problems: 5xx error % above ~1-5%, p95 latency above 1 s, pods restarting/not ready, a Degraded or aborted
rollout, a failed analysis run, firing alerts, PAYMENT_FAILED orders.
You are READ-ONLY: never claim you changed anything. Say what data is missing."""

ASK = {"type": "string", "description": "A precise question for this specialist, including the time window"}
KIRA_TOOLS = [
    tool("ask_logs_agent", "Ask the logs specialist (CloudWatch Logs).", {"question": ASK}, ["question"]),
    tool("ask_metrics_agent", "Ask the metrics specialist (Prometheus).", {"question": ASK}, ["question"]),
    tool("ask_deployment_agent", "Ask the deployment specialist (Argo CD, Rollouts, pods).", {"question": ASK}, ["question"]),
]


def ask_kira(question, history=None):
    trace = {"steps": [], "tokens_in": 0, "tokens_out": 0}
    functions = {
        "ask_logs_agent": lambda question: {"answer": ask_specialist("logs", question, trace)},
        "ask_metrics_agent": lambda question: {"answer": ask_specialist("metrics", question, trace)},
        "ask_deployment_agent": lambda question: {"answer": ask_specialist("deployment", question, trace)},
    }
    messages = []
    for turn in (history or [])[-10:]:  # earlier chat turns, text only
        if turn.get("text") and turn.get("role") in ("user", "assistant"):
            if messages and messages[-1]["role"] == turn["role"]:
                continue  # Converse requires alternating roles
            messages.append({"role": turn["role"], "content": [{"text": turn["text"]}]})
    if messages and messages[-1]["role"] == "user":
        messages.pop()
    if messages and messages[0]["role"] != "user":
        messages.pop(0)
    messages.append({"role": "user", "content": [{"text": question}]})

    started = time.time()
    answer = run_agent("dude", SUPERVISOR_MODEL, KIRA_SYSTEM, KIRA_TOOLS, functions, messages,
                       max_turns=6, max_tokens=3000, trace=trace)
    trace["seconds"] = round(time.time() - started, 1)
    log.info(json.dumps({"question": question[:300], **trace}))
    return {"answer": answer, **trace}


# =============================================================== entry points
INCIDENT_PROMPT = """AUTOMATIC INCIDENT INVESTIGATION.
CloudWatch alarm "{name}" changed to ALARM at {time}.
Reason: {reason}
Description: {description}
Investigate the last 30 minutes with all three specialists (check whether a blue-green or canary release is in
progress or was just rolled back), then write the full incident report."""


def handle_alarm(record):
    alarm = json.loads(record["Sns"]["Message"])
    if alarm.get("NewStateValue") != "ALARM":
        return None
    name = alarm.get("AlarmName", "unknown")
    try:
        result = ask_kira(INCIDENT_PROMPT.format(name=name, time=alarm.get("StateChangeTime"),
                                                 reason=alarm.get("NewStateReason"),
                                                 description=alarm.get("AlarmDescription") or "-"))
        report = result["answer"]
        footer = f"\n\n---\nInvestigated in {result['seconds']} s, {len(result['steps'])} tool calls."
    except Exception as exc:  # humans must still hear about the alarm
        log.exception("investigation failed")
        report, footer = f"Dude could not investigate ({type(exc).__name__}: {exc}). Check Grafana and Argo CD.", ""
    log.info(json.dumps({"alarm": name, "report": report}))
    if REPORT_TOPIC:
        sns.publish(TopicArn=REPORT_TOPIC, Subject=f"[AIOps] {name}: incident report"[:100],
                    Message=f"Alarm: {name}\nTime: {alarm.get('StateChangeTime')}\n\n{report}{footer}")
    return name


def handler(event, _context):
    if "Records" in event:  # SNS (CloudWatch alarm)
        return {"handled": [n for n in (handle_alarm(r) for r in event["Records"]) if n]}
    question = str(event.get("question", "")).strip()[:4000]
    if not question:
        return {"error": "send {\"question\": \"...\"}"}
    return ask_kira(question, event.get("history"))
