"""Logs agent tools — CloudWatch Logs Insights over the app's pod logs.

Fluent Bit ships every telugu-pickles container log line to LOG_GROUP. The app logs JSON,
which Fluent Bit nests under "data":  data.level, data.service, data.msg, data.requestId, ...
plus kubernetes.pod_name / kubernetes.container_name.
"""
import os
import re
import time

import boto3


LOG_GROUP = os.environ["LOG_GROUP"]
logs = boto3.client("logs", region_name=os.environ.get("AWS_REGION", "us-east-1"))

_SAFE = re.compile(r"^[A-Za-z0-9 _.:/\-]*$")  # values we put inside a query string


def _insights(query: str, minutes: int) -> list:
    minutes = max(1, min(int(minutes), 24 * 60))
    end = int(time.time())
    qid = logs.start_query(logGroupName=LOG_GROUP, startTime=end - minutes * 60, endTime=end,
                           queryString=query)["queryId"]
    for _ in range(40):  # up to ~20 s
        res = logs.get_query_results(queryId=qid)
        if res["status"] in ("Complete", "Failed", "Cancelled", "Timeout"):
            break
        time.sleep(0.5)
    if res["status"] != "Complete":
        raise RuntimeError(f"Logs Insights query {res['status']}")
    return [{f["field"].lstrip("@"): f["value"] for f in row if f["field"] != "@ptr"} for row in res["results"]]


def _check(name: str, value: str) -> str:
    if value and not _SAFE.match(value):
        raise ValueError(f"{name} contains unsupported characters")
    return value or ""


def search_logs(service: str = "", level: str = "ERROR", minutes: int = 30, text: str = "", limit: int = 30):
    """Most recent log lines, newest first. level: ERROR, WARN, INFO or ALL."""
    service, text, level = _check("service", service), _check("text", text), _check("level", level).upper()
    filters = []
    if level and level != "ALL":
        filters.append(f'data.level = "{level}"')
    if service:
        filters.append(f'data.service = "{service}"')
    if text:
        filters.append(f'data.msg like "{text}"')  # substring match
    where = ("| filter " + " and ".join(filters)) if filters else ""
    query = (f"fields @timestamp, data.service, data.level, data.msg, data.path, data.status, "
             f"data.err.message, kubernetes.pod_name {where} | sort @timestamp desc | limit {max(1, min(int(limit), 100))}")
    rows = _insights(query, minutes)
    return {"log_group": LOG_GROUP, "minutes": minutes, "count": len(rows), "lines": rows}


def error_summary(minutes: int = 60):
    """ERROR and WARN counts per service and message, the biggest first."""
    query = ('filter data.level in ["ERROR", "WARN"] '
             "| stats count(*) as count, latest(@timestamp) as last_seen, latest(kubernetes.pod_name) as example_pod "
             "by data.service, data.level, data.msg | sort count desc | limit 25")
    rows = _insights(query, minutes)
    for row in rows:  # Logs Insights returns epoch milliseconds for latest(@timestamp)
        if str(row.get("last_seen", "")).isdigit():
            row["last_seen"] = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime(int(row["last_seen"]) / 1000))
    return {"log_group": LOG_GROUP, "minutes": minutes, "groups": rows}
