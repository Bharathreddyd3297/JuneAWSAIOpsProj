"""Read-only AKS API and Prometheus client using the Function's managed identity."""

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from functools import lru_cache

from azure.identity import DefaultAzureCredential

ENDPOINT = os.environ["CLUSTER_ENDPOINT"].rstrip("/")
PROMETHEUS_PROXY = os.environ.get(
    "PROMETHEUS_SERVICE_PROXY",
    "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy",
)
AKS_SERVER_SCOPE = "6dae42f8-4368-4678-94ff-3960e28e3630/.default"


@lru_cache(maxsize=1)
def _credential() -> DefaultAzureCredential:
    return DefaultAzureCredential(
        managed_identity_client_id=os.environ.get("AZURE_CLIENT_ID") or None
    )


def _token() -> str:
    return _credential().get_token(AKS_SERVER_SCOPE).token


def get(path: str, params: dict[str, str] | None = None) -> dict:
    """GET a Kubernetes API path and return parsed JSON."""
    url = ENDPOINT + path + ("?" + urllib.parse.urlencode(params) if params else "")
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {_token()}",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise RuntimeError(f"AKS API returned HTTP {exc.code}: {detail}") from exc


def prom(query: str) -> list:
    """Run an instant PromQL query through the Kubernetes API service proxy."""
    data = get(PROMETHEUS_PROXY + "/api/v1/query", {"query": query})
    return data.get("data", {}).get("result", [])


def prom_alerts() -> list:
    data = get(PROMETHEUS_PROXY + "/api/v1/alerts")
    return data.get("data", {}).get("alerts", [])
