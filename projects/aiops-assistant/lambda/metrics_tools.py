"""Metrics agent tools — Prometheus (kube-prometheus-stack) inside the cluster.

App metrics (prom-client, label app=<service>):
  http_requests_total{method,route,status_code}, http_request_duration_seconds_bucket,
  tp_orders_placed_total{status,payment_method}
"""
import re

import k8s

NS = 'namespace="telugu-pickles"'
_NAME = re.compile(r"^[a-z0-9-]*$")


def _window(minutes) -> str:
    return f"{max(1, min(int(minutes), 1440))}m"


def _service(service: str) -> str:
    if service and not _NAME.match(service):
        raise ValueError("service must look like catalog-service")
    return service or ""


def _by(results: list, key: str, digits: int = 3) -> dict:
    out = {}
    for r in results:
        v = float(r["value"][1])
        out[r["metric"].get(key, "all")] = None if v != v else round(v, digits)  # NaN -> None
    return out


def service_health(minutes: int = 5):
    """Requests/s, 5xx error % and p95 latency (s) for every service."""
    w = _window(minutes)
    rps = k8s.prom(f"sum by (app) (rate(http_requests_total{{{NS}}}[{w}]))")
    err = k8s.prom(f'100 * sum by (app) (rate(http_requests_total{{{NS},status_code=~"5.."}}[{w}])) '
                   f"/ clamp_min(sum by (app) (rate(http_requests_total{{{NS}}}[{w}])), 1e-9)")
    p95 = k8s.prom(f"histogram_quantile(0.95, sum by (le, app) (rate(http_request_duration_seconds_bucket{{{NS}}}[{w}])))")
    rps, err, p95 = _by(rps, "app"), _by(err, "app", 2), _by(p95, "app")
    services = sorted(set(rps) | set(err) | set(p95))
    return {"window": w, "services": [
        {"service": s, "requests_per_s": rps.get(s), "error_pct_5xx": err.get(s, 0.0), "p95_latency_s": p95.get(s)}
        for s in services]}


def pod_errors(service: str, minutes: int = 10):
    """Per-POD request rate and 5xx % for one service. Shows a bad canary next to healthy stable pods."""
    service, w = _service(service), _window(minutes)
    sel = f'{NS},app="{service}"'
    rps = _by(k8s.prom(f"sum by (pod) (rate(http_requests_total{{{sel}}}[{w}]))"), "pod")
    err = _by(k8s.prom(f'100 * sum by (pod) (rate(http_requests_total{{{sel},status_code=~"5.."}}[{w}])) '
                       f"/ clamp_min(sum by (pod) (rate(http_requests_total{{{sel}}}[{w}])), 1e-9)"), "pod", 2)
    return {"service": service, "window": w, "pods": [
        {"pod": p, "requests_per_s": rps.get(p), "error_pct_5xx": err.get(p, 0.0)} for p in sorted(rps)]}


def business_metrics(minutes: int = 30):
    """Orders placed by status and payment method (PAYMENT_FAILED = checkout problems)."""
    w = _window(minutes)
    res = k8s.prom(f"sum by (status, payment_method) (increase(tp_orders_placed_total[{w}]))")
    return {"window": w, "orders": [
        {"status": r["metric"].get("status"), "payment_method": r["metric"].get("payment_method"),
         "count": round(float(r["value"][1]), 1)} for r in res]}


def pod_resources():
    """CPU (cores), memory (MiB) and restarts in the last hour for every app pod."""
    cpu = _by(k8s.prom(f'sum by (pod) (rate(container_cpu_usage_seconds_total{{{NS},container!=""}}[5m]))'), "pod", 4)
    mem = _by(k8s.prom(f'sum by (pod) (container_memory_working_set_bytes{{{NS},container!=""}}) / 1048576'), "pod", 1)
    rst = _by(k8s.prom(f"sum by (pod) (increase(kube_pod_container_status_restarts_total{{{NS}}}[1h]))"), "pod", 0)
    return {"pods": [{"pod": p, "cpu_cores": cpu.get(p), "memory_mib": mem.get(p), "restarts_1h": rst.get(p, 0)}
                     for p in sorted(set(cpu) | set(mem))]}


def firing_alerts():
    """Prometheus alerts that are firing or pending right now (HighServerErrorRate, SlowRequestsP95, ...)."""
    return {"alerts": [
        {"name": a["labels"].get("alertname"), "state": a.get("state"), "severity": a["labels"].get("severity"),
         "labels": {k: v for k, v in a["labels"].items() if k not in ("alertname", "severity", "prometheus")},
         "summary": a.get("annotations", {}).get("summary"), "since": a.get("activeAt"), "value": a.get("value")}
        for a in k8s.prom_alerts() if a["labels"].get("alertname") not in ("Watchdog", "InfoInhibitor")]}

