"""Azure Monitor / Log Analytics tools for the logs specialist."""

import os
import re
from datetime import timedelta

from azure.identity import DefaultAzureCredential
from azure.monitor.query import LogsQueryClient, LogsQueryStatus

WORKSPACE_ID = os.environ["LOG_ANALYTICS_WORKSPACE_ID"]
_SAFE = re.compile(r"^[A-Za-z0-9 _.:/\-]*$")
_client = LogsQueryClient(DefaultAzureCredential())


def _check(name: str, value: str) -> str:
    if value and not _SAFE.match(value):
        raise ValueError(f"{name} contains unsupported characters")
    return value or ""


def _query(kql: str, minutes: int) -> list[dict]:
    minutes = max(1, min(int(minutes), 1440))
    result = _client.query_workspace(WORKSPACE_ID, kql, timespan=timedelta(minutes=minutes))
    tables = result.tables if result.status == LogsQueryStatus.SUCCESS else result.partial_data
    rows = []
    for table in tables:
        columns = [column.name for column in table.columns]
        rows.extend(dict(zip(columns, row)) for row in table.rows)
    return rows


def search_logs(service: str = "", level: str = "ERROR", minutes: int = 30, text: str = "", limit: int = 30):
    service = _check("service", service)
    text = _check("text", text)
    level = _check("level", level).upper()
    filters = ['PodNamespace == "telugu-pickles"']
    if service:
        filters.append(f'service == "{service}"')
    if level and level != "ALL":
        filters.append(f'level == "{level}"')
    if text:
        filters.append(f'message contains "{text}"')
    kql = f"""
ContainerLogV2
| extend payload=parse_json(LogMessage)
| extend service=tostring(payload.service), level=toupper(tostring(payload.level)), message=tostring(payload.msg)
| where {' and '.join(filters)}
| project TimeGenerated, service, level, message, PodName, ContainerName
| order by TimeGenerated desc
| take {max(1, min(int(limit), 100))}
"""
    return {"workspace": WORKSPACE_ID, "minutes": minutes, "lines": _query(kql, minutes)}


def error_summary(minutes: int = 60):
    kql = """
ContainerLogV2
| where PodNamespace == "telugu-pickles"
| extend payload=parse_json(LogMessage)
| extend service=tostring(payload.service), level=toupper(tostring(payload.level)), message=tostring(payload.msg)
| where level in ("ERROR", "WARN")
| summarize count=count(), last_seen=max(TimeGenerated), example_pod=any(PodName) by service, level, message
| top 25 by count desc
"""
    return {"workspace": WORKSPACE_ID, "minutes": minutes, "groups": _query(kql, minutes)}
