"""Deployment agent tools — Argo CD, Argo Rollouts and pod health (read-only Kubernetes API)."""
from datetime import datetime, timedelta, timezone

import k8s

NS = "telugu-pickles"
ROLLOUTS = f"/apis/argoproj.io/v1alpha1/namespaces/{NS}/rollouts"
ANALYSIS = f"/apis/argoproj.io/v1alpha1/namespaces/{NS}/analysisruns"
ARGO_APP = "/apis/argoproj.io/v1alpha1/namespaces/argocd/applications/telugu-pickles"


def _images(pod_spec: dict) -> list:
    return [c.get("image", "").split("/")[-1] for c in pod_spec.get("containers", [])]


def rollout_status(name: str = ""):
    """Blue-green / canary releases: phase, current step, stable vs new version, messages."""
    items = [k8s.get(f"{ROLLOUTS}/{name}")] if name else k8s.get(ROLLOUTS).get("items", [])
    out = []
    for r in items:
        spec, st = r.get("spec", {}), r.get("status", {})
        strategy = "blueGreen" if "blueGreen" in spec.get("strategy", {}) else "canary"
        steps = spec.get("strategy", {}).get("canary", {}).get("steps", [])
        out.append({
            "rollout": r["metadata"]["name"],
            "strategy": strategy,
            "phase": st.get("phase"),               # Healthy, Progressing, Paused, Degraded
            "message": st.get("message"),
            "paused": bool(spec.get("paused") or st.get("pauseConditions")),
            "pause_reasons": [p.get("reason") for p in st.get("pauseConditions") or []],
            "aborted": st.get("abort", False),
            "current_step": f"{st.get('currentStepIndex')}/{len(steps)}" if steps else None,
            "stable_hash": st.get("stableRS"),
            "new_hash": st.get("currentPodHash"),
            "replicas": {"desired": spec.get("replicas"), "ready": st.get("readyReplicas"),
                         "updated": st.get("updatedReplicas"), "available": st.get("availableReplicas")},
            "images": _images(spec.get("template", {}).get("spec", {})),
            "conditions": [{"type": c.get("type"), "status": c.get("status"), "reason": c.get("reason"),
                            "message": c.get("message")} for c in st.get("conditions", [])],
        })
    return {"rollouts": out}


def analysis_runs(rollout: str = "", limit: int = 5):
    """Automatic release checks (AnalysisRuns): which metric, measured values, Successful/Failed."""
    items = k8s.get(ANALYSIS).get("items", [])
    if rollout:
        items = [a for a in items
                 if any(o.get("kind") == "Rollout" and o.get("name") == rollout
                        for o in a["metadata"].get("ownerReferences", []))
                 or a["metadata"]["name"].startswith(rollout + "-")]
    items.sort(key=lambda a: a["metadata"]["creationTimestamp"], reverse=True)
    out = []
    for a in items[: max(1, min(int(limit), 20))]:
        st = a.get("status", {})
        out.append({
            "name": a["metadata"]["name"],
            "created": a["metadata"]["creationTimestamp"],
            "phase": st.get("phase"),   # Running, Successful, Failed, Error, Inconclusive
            "message": st.get("message"),
            "args": {x["name"]: x.get("value") for x in a.get("spec", {}).get("args", [])},
            "metrics": [{"name": m.get("name"), "phase": m.get("phase"), "failed": m.get("failed", 0),
                         "successful": m.get("successful", 0),
                         "values": [x.get("value") for x in m.get("measurements", [])][-6:]}
                        for m in st.get("metricResults", [])],
        })
    return {"analysis_runs": out}


def argocd_status():
    """Argo CD Application: sync + health, Git revision, last sync result, unhealthy resources."""
    app = k8s.get(ARGO_APP)
    st = app.get("status", {})
    op = st.get("operationState", {})
    return {
        "sync": st.get("sync", {}).get("status"),
        "health": st.get("health", {}).get("status"),
        "git_revision": (st.get("sync", {}).get("revision") or "")[:7],
        "last_operation": {"phase": op.get("phase"), "message": op.get("message"),
                           "finished": op.get("finishedAt"),
                           "revision": (op.get("syncResult", {}).get("revision") or "")[:7]},
        "recent_deploys": [{"revision": (h.get("revision") or "")[:7], "deployed_at": h.get("deployedAt")}
                           for h in (st.get("history") or [])[-5:]],
        "not_healthy": [{"kind": r.get("kind"), "name": r.get("name"), "health": r.get("health", {}).get("status"),
                         "message": r.get("health", {}).get("message")}
                        for r in st.get("resources", []) if r.get("health", {}).get("status") not in (None, "Healthy")],
        "conditions": st.get("conditions", []),
    }


def pod_status(service: str = ""):
    """Pods: ready, restarts, waiting reason (CrashLoopBackOff, ImagePullBackOff), last termination (OOMKilled)."""
    params = {"labelSelector": f"app={service}"} if service else None
    out = []
    for p in k8s.get(f"/api/v1/namespaces/{NS}/pods", params).get("items", []):
        cs = p.get("status", {}).get("containerStatuses", [])
        waiting = [c["state"]["waiting"].get("reason") for c in cs if "waiting" in c.get("state", {})]
        last = [c.get("lastState", {}).get("terminated", {}) for c in cs if c.get("lastState", {}).get("terminated")]
        out.append({
            "pod": p["metadata"]["name"],
            "app": p["metadata"].get("labels", {}).get("app"),
            "version_hash": p["metadata"].get("labels", {}).get("rollouts-pod-template-hash")
                            or p["metadata"].get("labels", {}).get("pod-template-hash"),
            "phase": p.get("status", {}).get("phase"),
            "ready": all(c.get("ready") for c in cs) if cs else False,
            "restarts": sum(c.get("restartCount", 0) for c in cs),
            "waiting_reason": waiting[0] if waiting else None,
            "last_termination": {"reason": last[0].get("reason"), "exit_code": last[0].get("exitCode"),
                                 "at": last[0].get("finishedAt")} if last else None,
            "images": _images(p.get("spec", {})),
            "started": p.get("status", {}).get("startTime"),
        })
    return {"pods": out}


def recent_events(minutes: int = 30, warnings_only: bool = True):
    """Kubernetes events in the app namespace (FailedScheduling, BackOff, Unhealthy, rollout steps...)."""
    since = datetime.now(timezone.utc) - timedelta(minutes=max(1, min(int(minutes), 1440)))
    params = {"fieldSelector": "type=Warning"} if warnings_only else None
    out = []
    for e in k8s.get(f"/api/v1/namespaces/{NS}/events", params).get("items", []):
        ts = e.get("lastTimestamp") or e.get("eventTime") or e["metadata"]["creationTimestamp"]
        if ts and datetime.fromisoformat(ts.replace("Z", "+00:00")) < since:
            continue
        out.append({"time": ts, "type": e.get("type"), "reason": e.get("reason"),
                    "object": f'{e.get("involvedObject", {}).get("kind")}/{e.get("involvedObject", {}).get("name")}',
                    "message": e.get("message"), "count": e.get("count")})
    out.sort(key=lambda x: x["time"] or "", reverse=True)
    return {"minutes": minutes, "events": out[:40]}

