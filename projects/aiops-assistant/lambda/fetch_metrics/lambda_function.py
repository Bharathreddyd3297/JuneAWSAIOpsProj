import json
import os
import urllib.request
import urllib.parse
from datetime import datetime

PROMETHEUS_URL = os.environ.get("PROMETHEUS_URL", "http://<YOUR_PROMETHEUS_URL>:9090")

DEFAULT_NAMESPACE = os.environ.get("K8S_NAMESPACE", "telugu-pickles")

# Fixed, reviewed PromQL only (the agent picks a key; it can NOT send raw PromQL).
# "{ns}" is replaced with the Kubernetes namespace.
METRIC_QUERIES = {
    # --- Kubernetes / container level ---
    "pod_cpu_utilization": 'sum(rate(container_cpu_usage_seconds_total{namespace="{ns}", container!=""}[5m])) by (pod)',
    "pod_memory_utilization": 'sum(container_memory_working_set_bytes{namespace="{ns}", container!=""}) by (pod)',
    "pod_restarts": 'increase(kube_pod_container_status_restarts_total{namespace="{ns}"}[1h])',
    "deployment_replicas_unavailable": 'kube_deployment_status_replicas_unavailable{namespace="{ns}"}',
    "deployment_replicas_available": 'kube_deployment_status_replicas_available{namespace="{ns}"}',
    # --- Telugu Pickles application (RED metrics, label "app" = service name) ---
    "request_rate": 'sum by (app) (rate(http_requests_total{namespace="{ns}"}[5m]))',
    "error_rate_percent": '100 * sum by (app) (rate(http_requests_total{namespace="{ns}",status_code=~"5.."}[5m])) / clamp_min(sum by (app) (rate(http_requests_total{namespace="{ns}"}[5m])), 1e-9)',
    "latency_p95_seconds": 'histogram_quantile(0.95, sum by (le, app) (rate(http_request_duration_seconds_bucket{namespace="{ns}"}[5m])))',
    "dependency_errors": 'sum by (app, dependency) (rate(tp_dependency_errors_total{namespace="{ns}"}[5m]))',
    # --- Business ---
    "orders_by_status": 'sum by (status) (rate(tp_orders_placed_total{namespace="{ns}"}[5m]))',
    "payments_by_result": 'sum by (method, result) (rate(tp_payments_total{namespace="{ns}"}[5m]))',
    "nodejs_event_loop_lag": 'max by (app) (nodejs_eventloop_lag_p99_seconds{namespace="{ns}"})',
}


def prometheus_query(query):
    """Run an instant PromQL query."""
    url = f"{PROMETHEUS_URL}/api/v1/query?query={urllib.parse.quote(query)}"
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.loads(resp.read())["data"]["result"]


def prometheus_range_query(query, hours_back, step="5m"):
    """Run a range PromQL query and return time-series data."""
    end = int(datetime.utcnow().timestamp())
    start = end - (hours_back * 3600)
    url = (
        f"{PROMETHEUS_URL}/api/v1/query_range"
        f"?query={urllib.parse.quote(query)}"
        f"&start={start}&end={end}&step={step}"
    )
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.loads(resp.read())["data"]["result"]


def lambda_handler(event, context):
    params = {}
    for param in event.get("parameters", []):
        params[param["name"]] = param["value"]

    metric_name = params.get("metric_name", "pod_cpu_utilization")
    namespace = params.get("namespace", DEFAULT_NAMESPACE)
    hours_back = int(params.get("hours_back", "1"))

    try:
        if metric_name not in METRIC_QUERIES:
            raise ValueError(f"Unknown metric '{metric_name}'. Use one of: {', '.join(METRIC_QUERIES)}")
        query = METRIC_QUERIES[metric_name].replace("{ns}", namespace)

        raw_results = prometheus_range_query(query, hours_back)

        if not raw_results:
            result = {"status": "no_data", "metric": metric_name, "ns": namespace}
        else:
            series = []
            for r in raw_results[:10]:  # cap at 10 series
                m = r["metric"]
                label = m.get("pod") or m.get("app") or m.get("deployment") or m.get("status") or "total"
                if m.get("dependency"):
                    label += f" -> {m['dependency']}"
                if m.get("result"):
                    label = f"{m.get('method', '')} {m['result']}".strip()
                values = [float(v[1]) for v in r["values"]]
                series.append({
                    "series": label,
                    "cur": round(values[-1], 3),
                    "avg": round(sum(values) / len(values), 3),
                    "max": round(max(values), 3),
                })

            result = {"status": "ok", "metric": metric_name, "ns": namespace, "data": series}

    except Exception as e:
        result = {"status": "error", "message": str(e)}

    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", ""),
            "apiPath": event.get("apiPath", ""),
            "httpMethod": event.get("httpMethod", ""),
            "httpStatusCode": 200,
            "responseBody": {
                "application/json": {
                    "body": json.dumps(result, separators=(',', ':'))
                }
            },
        },
    }
