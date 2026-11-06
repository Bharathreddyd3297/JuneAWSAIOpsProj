"""Glue between a Bedrock Agent action group (function schema) and plain Python functions.

Bedrock sends:   {"actionGroup": "...", "function": "search_logs", "parameters": [{"name","type","value"}], ...}
and expects:     {"messageVersion": "1.0", "response": {"actionGroup", "function", "functionResponse": {...}}}
"""
import json
import logging
import traceback

log = logging.getLogger()
log.setLevel(logging.INFO)

MAX_CHARS = 20000  # keep tool results small: cheaper and the model reads them better


def handle(event: dict, functions: dict) -> dict:
    name = event.get("function", "")
    params = {p["name"]: _cast(p.get("type"), p.get("value")) for p in event.get("parameters", [])}
    log.info(json.dumps({"tool": name, "params": params}))
    try:
        if name not in functions:
            raise ValueError(f"unknown function {name}; available: {sorted(functions)}")
        result = functions[name](**params)
        body, state = json.dumps(result, default=str), None
    except Exception as exc:  # report the error to the agent instead of failing the whole conversation
        log.error(traceback.format_exc())
        body, state = json.dumps({"error": f"{type(exc).__name__}: {exc}"}), "FAILURE"
    if len(body) > MAX_CHARS:
        body = body[:MAX_CHARS] + '..."(truncated)"'
    response = {
        "actionGroup": event.get("actionGroup"),
        "function": name,
        "functionResponse": {"responseBody": {"TEXT": {"body": body}}},
    }
    if state:
        response["functionResponse"]["responseState"] = state
    return {
        "messageVersion": "1.0",
        "response": response,
        "sessionAttributes": event.get("sessionAttributes", {}),
        "promptSessionAttributes": event.get("promptSessionAttributes", {}),
    }


def _cast(kind, value):
    if value is None:
        return None
    if kind == "integer":
        return int(value)
    if kind == "number":
        return float(value)
    if kind == "boolean":
        return str(value).lower() == "true"
    return value
