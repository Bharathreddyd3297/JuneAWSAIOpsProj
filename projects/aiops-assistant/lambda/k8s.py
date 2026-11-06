"""Tiny read-only Kubernetes client for Lambda (standard library + boto3 only).

How it logs in: it signs an STS GetCallerIdentity URL with the Lambda's IAM role.
That is the same token `aws eks get-token` produces. EKS maps the role (an EKS access
entry, created by Terraform) to the Kubernetes group "aiops-readers", which has a
read-only ClusterRole. Prometheus is reached through the API server's service proxy,
so it never needs a public load balancer.
"""
import base64
import json
import os
import ssl
import urllib.parse
import urllib.request

import boto3
from botocore.signers import RequestSigner

REGION = os.environ.get("AWS_REGION", "us-east-1")
CLUSTER = os.environ["CLUSTER_NAME"]
ENDPOINT = os.environ["CLUSTER_ENDPOINT"].rstrip("/")
_CA = base64.b64decode(os.environ["CLUSTER_CA"]).decode()
_SSL = ssl.create_default_context(cadata=_CA)

PROMETHEUS_PROXY = "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy"


def _token() -> str:
    session = boto3.session.Session()
    sts = session.client("sts", region_name=REGION)
    signer = RequestSigner(sts.meta.service_model.service_id, REGION, "sts", "v4",
                           session.get_credentials(), session.events)
    url = signer.generate_presigned_url(
        {
            "method": "GET",
            "url": f"https://sts.{REGION}.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15",
            "body": {},
            "headers": {"x-k8s-aws-id": CLUSTER},
            "context": {},
        },
        region_name=REGION, expires_in=60, operation_name="",
    )
    return "k8s-aws-v1." + base64.urlsafe_b64encode(url.encode()).decode().rstrip("=")


def get(path: str, params: dict | None = None) -> dict:
    """GET a Kubernetes API path and return parsed JSON."""
    url = ENDPOINT + path + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {_token()}", "Accept": "application/json"})
    with urllib.request.urlopen(req, context=_SSL, timeout=15) as resp:
        return json.loads(resp.read())


def prom(query: str) -> list:
    """Instant PromQL query -> list of {"metric": {...}, "value": [ts, "val"]}."""
    data = get(PROMETHEUS_PROXY + "/api/v1/query", {"query": query})
    return data.get("data", {}).get("result", [])


def prom_alerts() -> list:
    data = get(PROMETHEUS_PROXY + "/api/v1/alerts")
    return data.get("data", {}).get("alerts", [])
