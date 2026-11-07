"""Azure Monitor Logs tools for application container logs in Log Analytics."""

import json
import os
import re
from datetime import timedelta
from functools import lru_cache

from azure.identity import DefaultAzureCredential
from azure.monitor.query import LogsQueryClient, LogsQueryStatus

WORKSPACE_ID = os.environ["LOG_ANALYTICS_WORKSPACE_ID"]
SAFE_TEXT = re.compile(r"^[A-Za-z0-9 _.:/\-]*$")


@lru_cache(maxsize=1)
def _client() -> LogsQueryClient:
    credential = DefaultAzureCredential(
        managed_identity_client_id=os.environ.get("AZURE_CLIENT_ID") or None
    )
    return LogsQueryClient(credential)


def _query(query: str, minutes: int) -> list[dict]:
    bounded_minutes = max(1, min(int(minutes), 24 * 60))
    result = _client().query_workspace(
        WORKSPACE_ID,
        query,
        timespan=timedelta(minutes=bounded_minutes),
    )
    if result.status != LogsQueryStatus.SUCCESS:
        raise RuntimeError(f"Log Analytics query did not complete successfully: {result.status}")
    if not result.tables:
        return []

    table = result.tables[0]
    columns = [column.name for column in table.columns]
    return [dict(zip(columns, row)) for row in table.rows]


def _check(name: str, value: str) -> str:
    if value and not SAFE_TEXT.fullmatch(value):
        raise ValueError(f"{name} contains unsupported characters")
    return value


def search_logs(
    service: str = "",
    level: str = "ERROR",
    minutes: int = 30,
    text: str = "",
    limit: int = 30,
) -> dict:
    """Return recent structured application log records, newest first."""
    service = _check("service", service)
    text = _check("text", text)
    level = _check("level", level).upper()
    if level not in {"ERROR", "WARN", "INFO", "ALL"}:
        raise ValueError("level must be ERROR, WARN, INFO, or ALL")

    filters = ['PodNamespace == "telugu-pickles"']
    if level != "ALL":
        filters.append(f'tostring(event.level) == "{level}"')
    if service:
        filters.append(f'tostring(event.service) == "{service}"')
    if text:
        filters.append(f'tostring(event.msg) contains "{text}"')

    query = f"""
        ContainerLogV2
        | extend event = parse_json(LogMessage)
        | where {' and '.join(filters)}
        | project TimeGenerated, PodName, ContainerName,
                  service=tostring(event.service), level=tostring(event.level),
                  message=tostring(event.msg), path=tostring(event.path),
                  status=tostring(event.status), error=tostring(event.err.message)
        | order by TimeGenerated desc
        | take {max(1, min(int(limit), 100))}
    """
    rows = _query(query, minutes)
    return {"minutes": max(1, min(int(minutes), 24 * 60)), "count": len(rows), "lines": rows}


def error_summary(minutes: int = 60) -> dict:
    """Summarize ERROR and WARN logs by service and message."""
    query = """
        ContainerLogV2
        | where PodNamespace == "telugu-pickles"
        | extend event = parse_json(LogMessage)
        | where tostring(event.level) in ("ERROR", "WARN")
        | summarize count=count(), last_seen=max(TimeGenerated), example_pod=take_any(PodName)
            by service=tostring(event.service), level=tostring(event.level), message=tostring(event.msg)
        | order by count desc
        | take 25
    """
    rows = _query(query, minutes)
    return {"minutes": max(1, min(int(minutes), 24 * 60)), "groups": json.loads(json.dumps(rows, default=str))}
