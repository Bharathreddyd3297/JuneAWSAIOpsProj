"""Read-only AKS, Argo CD, and Argo Rollouts tools."""

import re

from agent import k8s

NS = "telugu-pickles"
_NAME = re.compile(r"^[a-z0-9]([-a-z0-9]*[a-z0-9])?$")


def _resource_name(value: str) -> str:
    if value and not _NAME.fullmatch(value):
        raise ValueError("resource name is not a valid Kubernetes DNS label")
    return value


def rollout_status(name: str = ""):
    name = _resource_name(name)
    path = f"/apis/argoproj.io/v1alpha1/namespaces/{NS}/rollouts"
    items = [k8s.get(f"{path}/{name}")] if name else k8s.get(path).get("items", [])
    return {"rollouts": [{
        "name": item["metadata"]["name"],
        "phase": item.get("status", {}).get("phase"),
        "message": item.get("status", {}).get("message"),
        "ready": item.get("status", {}).get("readyReplicas", 0),
        "desired": item.get("spec", {}).get("replicas", 0),
        "paused": bool(item.get("status", {}).get("pauseConditions")),
        "images": [container.get("image") for container in item.get("spec", {}).get("template", {}).get("spec", {}).get("containers", [])],
    } for item in items]}


def argocd_status():
    app = k8s.get("/apis/argoproj.io/v1alpha1/namespaces/argocd/applications/telugu-pickles")
    status = app.get("status", {})
    return {
        "sync": status.get("sync", {}).get("status"),
        "health": status.get("health", {}).get("status"),
        "revision": (status.get("sync", {}).get("revision") or "")[:7],
        "conditions": status.get("conditions", []),
    }


def pod_status(service: str = ""):
    service = _resource_name(service)
    params = {"labelSelector": f"app={service}"} if service else None
    pods = k8s.get(f"/api/v1/namespaces/{NS}/pods", params).get("items", [])
    output = []
    for pod in pods:
        states = pod.get("status", {}).get("containerStatuses", [])
        output.append({
            "pod": pod["metadata"]["name"],
            "app": pod["metadata"].get("labels", {}).get("app"),
            "phase": pod.get("status", {}).get("phase"),
            "ready": all(state.get("ready") for state in states) if states else False,
            "restarts": sum(state.get("restartCount", 0) for state in states),
        })
    return {"pods": output}
