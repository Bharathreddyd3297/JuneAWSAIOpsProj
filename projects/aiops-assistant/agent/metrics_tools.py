"""Prometheus tools for application and business health."""

from agent import k8s

NS = 'namespace="telugu-pickles"'


def _window(minutes) -> str:
    return f"{max(1, min(int(minutes), 1440))}m"


def _by(results: list, key: str, digits: int = 3) -> dict:
    values = {}
    for result in results:
        value = float(result["value"][1])
        values[result["metric"].get(key, "all")] = None if value != value else round(value, digits)
    return values


def service_health(minutes: int = 5):
    window = _window(minutes)
    rps = _by(k8s.prom(f"sum by (app) (rate(http_requests_total{{{NS}}}[{window}]))"), "app")
    errors = _by(k8s.prom(
        f'100 * sum by (app) (rate(http_requests_total{{{NS},status_code=~"5.."}}[{window}])) '
        f'/ clamp_min(sum by (app) (rate(http_requests_total{{{NS}}}[{window}])), 1e-9)'), "app", 2)
    latency = _by(k8s.prom(
        f"histogram_quantile(0.95, sum by (le, app) (rate(http_request_duration_seconds_bucket{{{NS}}}[{window}])))"),
        "app")
    services = sorted(set(rps) | set(errors) | set(latency))
    return {"window": window, "services": [
        {"service": service, "requests_per_s": rps.get(service), "error_pct_5xx": errors.get(service, 0),
         "p95_latency_s": latency.get(service)} for service in services
    ]}


def business_metrics(minutes: int = 30):
    window = _window(minutes)
    orders = k8s.prom(f"sum by (status, payment_method) (increase(tp_orders_placed_total[{window}]))")
    payments = k8s.prom(f"sum by (method, result) (increase(tp_payments_total[{window}]))")
    return {"window": window, "orders": [
        {"status": item["metric"].get("status"), "payment_method": item["metric"].get("payment_method"),
         "count": round(float(item["value"][1]), 1)} for item in orders
    ], "payments": [
        {"method": item["metric"].get("method"), "result": item["metric"].get("result"),
         "count": round(float(item["value"][1]), 1)} for item in payments
    ]}


def firing_alerts():
    return {"alerts": [
        {"name": alert["labels"].get("alertname"), "state": alert.get("state"),
         "severity": alert["labels"].get("severity"), "summary": alert.get("annotations", {}).get("summary")}
        for alert in k8s.prom_alerts()
        if alert["labels"].get("alertname") not in ("Watchdog", "InfoInhibitor")
    ]}
