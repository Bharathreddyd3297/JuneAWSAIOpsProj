"""Tool-using AIOps assistant backed by an Azure OpenAI-compatible deployment."""

import json
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI

import deploy_tools
import logs_tools
import metrics_tools

log = logging.getLogger(__name__)
MAX_TOOL_RESULT = 12000
PLATFORM = (
    "Telugu Pickles runs on Azure Kubernetes Service (AKS), namespace telugu-pickles: "
    "React frontend (nginx) -> gateway -> auth-service, catalog-service, cart-service, "
    "order-service; order-service calls payment-service; PostgreSQL. Frontend releases "
    "use Argo Rollouts blue-green and catalog-service uses canary analysis with Prometheus."
)


@lru_cache(maxsize=1)
def _client() -> AzureOpenAI:
    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT", "").strip()
    if not endpoint:
        raise RuntimeError("AZURE_OPENAI_ENDPOINT is not configured.")
    api_version = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21")
    credential = DefaultAzureCredential(
        managed_identity_client_id=os.environ.get("AZURE_CLIENT_ID") or None
    )
    token_provider = get_bearer_token_provider(
        credential,
        "https://cognitiveservices.azure.com/.default",
    )
    return AzureOpenAI(
        azure_endpoint=endpoint,
        api_version=api_version,
        azure_ad_token_provider=token_provider,
        timeout=120,
        max_retries=2,
    )


def _model() -> str:
    deployment = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "").strip()
    if not deployment:
        raise RuntimeError("AZURE_OPENAI_DEPLOYMENT is not configured.")
    return deployment


def configuration_status() -> dict:
    configured = bool(
        os.environ.get("AZURE_OPENAI_ENDPOINT", "").strip()
        and os.environ.get("AZURE_OPENAI_DEPLOYMENT", "").strip()
        and os.environ.get("CLUSTER_ENDPOINT", "").strip()
        and os.environ.get("LOG_ANALYTICS_WORKSPACE_ID", "").strip()
    )
    return {
        "ready": configured,
        "model": os.environ.get("AZURE_OPENAI_DEPLOYMENT", "not configured"),
        "platform": "AKS",
    }


def tool(name: str, description: str, properties: dict | None = None, required: list | None = None) -> dict:
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": description,
            "parameters": {
                "type": "object",
                "properties": properties or {},
                "required": required or [],
                "additionalProperties": False,
            },
        },
    }


def run_agent(name, system, tools, functions, messages, max_turns, max_tokens, trace):
    """Run one tool-calling loop; tool failures are logged and returned to the model."""
    history = [{"role": "system", "content": system}, *messages]
    for _ in range(max_turns):
        response = _client().chat.completions.create(
            model=_model(),
            messages=history,
            tools=tools,
            tool_choice="auto",
            max_tokens=max_tokens,
        )
        if response.usage:
            trace["tokens_in"] += response.usage.prompt_tokens or 0
            trace["tokens_out"] += response.usage.completion_tokens or 0

        message = response.choices[0].message
        if not message.tool_calls:
            return (message.content or "").strip()

        history.append(message.model_dump(exclude_none=True))

        def execute(call):
            try:
                arguments = json.loads(call.function.arguments or "{}")
                function = functions[call.function.name]
                result = json.dumps(function(**arguments), default=str)
                status = "success"
            except Exception as exc:
                log.exception("AIOps tool %s failed", call.function.name)
                result = json.dumps({"error": f"{type(exc).__name__}: {exc}"})
                status = "error"
            if len(result) > MAX_TOOL_RESULT:
                result = result[:MAX_TOOL_RESULT] + "...(truncated)"
            trace["steps"].append(f"{name} -> {call.function.name}({call.function.arguments})")
            return {
                "role": "tool",
                "tool_call_id": call.id,
                "content": result,
            }

        with ThreadPoolExecutor(max_workers=min(4, len(message.tool_calls))) as pool:
            history.extend(pool.map(execute, message.tool_calls))

    return f"({name} stopped after {max_turns} steps without a final answer)"


def ask_specialist(kind: str, question: str, trace: dict) -> str:
    if kind == "logs":
        system = PLATFORM + """
You are the LOGS specialist. Application JSON logs are in Azure Monitor Logs (ContainerLogV2).
Start with error_summary, then search_logs for concrete lines. Report the time window, counts, exact top
messages, pods, and first/last seen. Never invent log lines; say clearly if nothing was found.
Be concise: a short factual summary, no recommendations."""
        tools = [
            tool("error_summary", "Counts ERROR and WARN log lines grouped by service and message.",
                 {"minutes": {"type": "integer"}}),
            tool("search_logs", "Recent application log lines, optionally filtered.", {
                "service": {"type": "string"},
                "level": {"type": "string"},
                "minutes": {"type": "integer"},
                "text": {"type": "string"},
                "limit": {"type": "integer"},
            }),
        ]
        functions = {"error_summary": logs_tools.error_summary, "search_logs": logs_tools.search_logs}
    elif kind == "metrics":
        system = PLATFORM + """
You are the METRICS specialist. Start with service_health and firing_alerts. If a service looks unhealthy,
call pod_errors for it. Report numbers with units and the time window. Never invent numbers.
Be concise: a short factual summary, no recommendations."""
        tool_names = (
            "service_health", "pod_errors", "business_metrics", "pod_resources", "firing_alerts"
        )
        tools = [
            tool(name, name.replace("_", " "), {
                "service": {"type": "string"},
                "minutes": {"type": "integer"},
            }, ["service"] if name == "pod_errors" else [])
            for name in tool_names
        ]
        functions = {name: getattr(metrics_tools, name) for name in tool_names}
    elif kind == "deployment":
        system = PLATFORM + """
You are the DEPLOYMENT specialist. Use rollout_status and analysis_runs for Argo Rollouts releases,
argocd_status for Git revision/sync/health, pod_status for crashes/restarts, and recent_events for warnings.
Report timestamps and image tags. Be concise: a short factual summary, no recommendations."""
        tool_names = (
            "rollout_status", "analysis_runs", "argocd_status", "pod_status", "recent_events"
        )
        tools = [
            tool(name, name.replace("_", " "), {
                "name": {"type": "string"},
                "rollout": {"type": "string"},
                "limit": {"type": "integer"},
                "service": {"type": "string"},
                "minutes": {"type": "integer"},
                "warnings_only": {"type": "boolean"},
            })
            for name in tool_names
        ]
        functions = {name: getattr(deploy_tools, name) for name in tool_names}
    else:
        raise ValueError(f"Unknown AIOps specialist: {kind}")

    return run_agent(
        f"{kind}-agent",
        system,
        tools,
        functions,
        [{"role": "user", "content": question}],
        max_turns=6,
        max_tokens=1500,
        trace=trace,
    )


KIRA_SYSTEM = PLATFORM + """
You are Dude, the read-only AIOps site-reliability assistant for Telugu Pickles. Delegate to the logs,
metrics, and deployment specialists instead of guessing. For incidents, ask all three in the same turn,
then correlate timestamps, failed pods, and releases.

For evidenced incidents, respond with Markdown sections: Summary, Impact, Root cause with confidence,
Evidence, Recommended actions, and Prevention. Otherwise answer briefly. Never claim to change anything.
Distinguish a real 5xx/restart/release problem from expected demo traffic, validation errors, 401s, and 404s."""

QUESTION = {"type": "string", "description": "A precise question for the specialist, including time window"}
KIRA_TOOLS = [
    tool("ask_logs_agent", "Ask the logs specialist about Azure Monitor Logs.", {"question": QUESTION}, ["question"]),
    tool("ask_metrics_agent", "Ask the Prometheus metrics specialist.", {"question": QUESTION}, ["question"]),
    tool("ask_deployment_agent", "Ask the AKS/Argo CD deployment specialist.", {"question": QUESTION}, ["question"]),
]


def ask_kira(question: str, history: list | None = None) -> dict:
    if not question or len(question) > 4000:
        raise ValueError("question must contain between 1 and 4000 characters")

    trace = {"steps": [], "tokens_in": 0, "tokens_out": 0}
    functions = {
        "ask_logs_agent": lambda question: {
            "answer": ask_specialist("logs", question, trace)
        },
        "ask_metrics_agent": lambda question: {
            "answer": ask_specialist("metrics", question, trace)
        },
        "ask_deployment_agent": lambda question: {
            "answer": ask_specialist("deployment", question, trace)
        },
    }

    messages = []
    for turn in (history or [])[-10:]:
        role = turn.get("role")
        content = turn.get("text") or turn.get("content")
        if role in {"user", "assistant"} and isinstance(content, str) and content:
            if messages and messages[-1]["role"] == role:
                continue
            messages.append({"role": role, "content": content[:4000]})
    if messages and messages[0]["role"] != "user":
        messages.pop(0)
    if messages and messages[-1]["role"] == "user":
        messages.pop()
    messages.append({"role": "user", "content": question})

    started = time.monotonic()
    answer = run_agent(
        "dude",
        KIRA_SYSTEM,
        KIRA_TOOLS,
        functions,
        messages,
        max_turns=6,
        max_tokens=3000,
        trace=trace,
    )
    trace["seconds"] = round(time.monotonic() - started, 1)
    log.info(json.dumps({"question": question[:300], **trace}))
    return {"answer": answer, **trace}


def handle_alert(payload: dict) -> dict:
    data = payload.get("data", {})
    essentials = data.get("essentials", {}) if isinstance(data, dict) else {}
    if not isinstance(essentials, dict):
        raise ValueError("Azure Monitor alert is missing data.essentials")
    if essentials.get("monitorCondition", "").lower() != "fired":
        return {"handled": False, "reason": "Alert is not in the Fired state."}

    name = essentials.get("alertRule", "unknown")
    when = essentials.get("firedDateTime", "unknown")
    description = essentials.get("description") or "No alert description was supplied."
    investigation = ask_kira(
        f"""AUTOMATIC INCIDENT INVESTIGATION.
Azure Monitor alert "{name}" fired at {when}.
Description: {description}
Investigate the last 30 minutes, including whether a blue-green or canary release is in progress.""",
    )
    log.info("Azure Monitor incident report for %s: %s", name, investigation["answer"])
    return {"handled": True, "alert": name, "investigation": investigation}
