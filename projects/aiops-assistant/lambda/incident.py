"""Automatic incident report.

CloudWatch alarm -> SNS topic "telugu-pickles-alarms" -> this Lambda
  -> asks the Kira supervisor agent for a root-cause analysis
  -> publishes the report to SNS topic "telugu-pickles-aiops-reports" (email) and to its own log.
"""
import json
import logging
import os
import uuid

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

AGENT_ID = os.environ["AGENT_ID"]
AGENT_ALIAS_ID = os.environ["AGENT_ALIAS_ID"]
REPORT_TOPIC = os.environ["REPORT_TOPIC_ARN"]

agents = boto3.client("bedrock-agent-runtime")
sns = boto3.client("sns")

PROMPT = """AUTOMATIC INCIDENT INVESTIGATION.
CloudWatch alarm "{name}" changed to ALARM at {time}.
Reason: {reason}
Description: {description}

Investigate now using your specialist agents (logs, metrics, deployments). Check whether a release
(blue-green or canary) is in progress or was just rolled back. Then write the incident report."""


def ask_kira(prompt: str, session: str) -> str:
    resp = agents.invoke_agent(agentId=AGENT_ID, agentAliasId=AGENT_ALIAS_ID, sessionId=session, inputText=prompt)
    return "".join(e["chunk"]["bytes"].decode() for e in resp["completion"] if "chunk" in e)


def handler(event, _context):
    for record in event.get("Records", []):
        alarm = json.loads(record["Sns"]["Message"])
        if alarm.get("NewStateValue") != "ALARM":
            log.info("ignoring state %s", alarm.get("NewStateValue"))
            continue
        name = alarm.get("AlarmName", "unknown")
        session = f"incident-{uuid.uuid4().hex[:12]}"
        prompt = PROMPT.format(name=name, time=alarm.get("StateChangeTime"), reason=alarm.get("NewStateReason"),
                               description=alarm.get("AlarmDescription") or "-")
        try:
            report = ask_kira(prompt, session)
        except Exception as exc:  # still tell the humans that something is wrong
            log.exception("agent failed")
            report = f"Kira could not investigate ({type(exc).__name__}: {exc}). Check Grafana and Argo CD manually."
        log.info(json.dumps({"alarm": name, "session": session, "report": report}))
        sns.publish(TopicArn=REPORT_TOPIC, Subject=f"[AIOps] {name}: incident report"[:100],
                    Message=f"Alarm: {name}\nTime: {alarm.get('StateChangeTime')}\nSession: {session}\n\n{report}")
    return {"ok": True}
