"""Read-only in-cluster Kubernetes and Prometheus clients."""

import json
import os
import ssl
import urllib.parse
import urllib.request

API = os.getenv("KUBERNETES_API", "https://kubernetes.default.svc")
TOKEN_FILE = "/var/run/secrets/kubernetes.io/serviceaccount/token"
CA_FILE = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
PROMETHEUS = os.getenv(
    "PROMETHEUS_URL",
    "http://kube-prometheus-stack-prometheus.monitoring.svc:9090",
).rstrip("/")


def _token() -> str:
    with open(TOKEN_FILE, encoding="utf-8") as handle:
        return handle.read().strip()


def get(path: str, params: dict | None = None) -> dict:
    url = API.rstrip("/") + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    context = ssl.create_default_context(cafile=CA_FILE)
    request = urllib.request.Request(
        url,
        headers={"Authorization": f"Bearer {_token()}", "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, context=context, timeout=20) as response:
        return json.loads(response.read())


def _prometheus(path: str, params: dict | None = None) -> dict:
    url = PROMETHEUS + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=20) as response:
        return json.loads(response.read())


def prom(query: str) -> list:
    return _prometheus("/api/v1/query", {"query": query}).get("data", {}).get("result", [])


def prom_alerts() -> list:
    return _prometheus("/api/v1/alerts").get("data", {}).get("alerts", [])
