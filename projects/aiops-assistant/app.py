"""
AIOps Assistant — Streamlit chat UI for Kira, the Bedrock supervisor agent.
Kira delegates to three specialist agents (logs, metrics, deployments) created by Terraform
(projects/Infrastructure/modules/aiops).

Run (AWS CLI must be logged in to the account that has the agents):
    pip install -r requirements.txt
    streamlit run app.py
"""

import streamlit as st
import boto3
import uuid
import json
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# --- Config ---
# AWS credentials come from your normal AWS CLI login (aws configure / SSO). No keys in files.
# The agent is found by name (created by Terraform); set the IDs in .env only to override.
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
AGENT_NAME = os.getenv("BEDROCK_AGENT_NAME", "telugu-pickles-kira")
AGENT_ID = os.getenv("BEDROCK_AGENT_ID")
AGENT_ALIAS_ID = os.getenv("BEDROCK_AGENT_ALIAS_ID")


def find_agent():
    """Look up Kira's agent ID and its 'live' alias by name."""
    client = boto3.client("bedrock-agent", region_name=AWS_REGION)
    for page in client.get_paginator("list_agents").paginate():
        for agent in page["agentSummaries"]:
            if agent["agentName"] == AGENT_NAME:
                aliases = client.list_agent_aliases(agentId=agent["agentId"])["agentAliasSummaries"]
                live = [a for a in aliases if a["agentAliasName"] == "live"]
                return agent["agentId"], (live[0]["agentAliasId"] if live else None)
    return None, None


if not (AGENT_ID and AGENT_ALIAS_ID):
    try:
        AGENT_ID, AGENT_ALIAS_ID = find_agent()
    except Exception as exc:  # no credentials / no permission
        st.session_state["lookup_error"] = str(exc)


# --- Page Config ---
st.set_page_config(
    page_title="Kira — AIOps Assistant",
    page_icon="🔍",
    layout="wide",
    initial_sidebar_state="collapsed",
)

# --- Custom CSS ---
st.markdown("""
<style>
    @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&family=DM+Sans:wght@400;500;700&display=swap');

    .stApp {
        background-color: #0a0e14;
        color: #c5c8c6;
    }

    .main-header {
        padding: 1.5rem 0 1rem 0;
        border-bottom: 1px solid #1a1f2e;
        margin-bottom: 1.5rem;
    }
    .main-header h1 {
        font-family: 'JetBrains Mono', monospace;
        color: #22d3ee;
        font-size: 1.6rem;
        font-weight: 700;
        margin: 0;
        letter-spacing: -0.5px;
    }
    .main-header p {
        font-family: 'DM Sans', sans-serif;
        color: #5a6270;
        font-size: 0.85rem;
        margin: 0.3rem 0 0 0;
    }

    .status-bar {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.5rem 1rem;
        background: #0d1117;
        border: 1px solid #1a1f2e;
        border-radius: 6px;
        margin-bottom: 1rem;
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.75rem;
    }
    .status-dot {
        width: 8px;
        height: 8px;
        background: #22d3ee;
        border-radius: 50%;
        box-shadow: 0 0 6px #22d3ee;
        animation: pulse 2s infinite;
    }
    @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.4; }
    }

    .status-dot-error {
        width: 8px;
        height: 8px;
        background: #ef4444;
        border-radius: 50%;
        box-shadow: 0 0 6px #ef4444;
    }

    .stChatMessage {
        background: #0d1117 !important;
        border: 1px solid #1a1f2e !important;
        border-radius: 8px !important;
        font-family: 'DM Sans', sans-serif !important;
    }

    [data-testid="stChatMessage"]:has([data-testid="chatAvatarIcon-user"]) {
        background: #111820 !important;
        border-left: 3px solid #22d3ee !important;
    }

    [data-testid="stChatMessage"]:has([data-testid="chatAvatarIcon-assistant"]) {
        background: #0d1117 !important;
        border-left: 3px solid #f97316 !important;
    }

    .stChatInput textarea {
        font-family: 'DM Sans', sans-serif !important;
        background: #0d1117 !important;
        color: #c5c8c6 !important;
    }

    [data-testid="stSidebar"] {
        background: #0d1117;
        border-right: 1px solid #1a1f2e;
    }

    ::-webkit-scrollbar { width: 6px; }
    ::-webkit-scrollbar-track { background: #0a0e14; }
    ::-webkit-scrollbar-thumb { background: #1a1f2e; border-radius: 3px; }

    .stButton > button {
        background: #111820 !important;
        border: 1px solid #1a1f2e !important;
        color: #8b95a5 !important;
        font-family: 'JetBrains Mono', monospace !important;
        font-size: 0.75rem !important;
        padding: 0.4rem 0.8rem !important;
        border-radius: 4px !important;
        transition: all 0.2s !important;
    }
    .stButton > button:hover {
        border-color: #22d3ee !important;
        color: #22d3ee !important;
        background: #0d1117 !important;
    }

    #MainMenu { visibility: hidden; }
    footer { visibility: hidden; }
    header { visibility: hidden; }
</style>
""", unsafe_allow_html=True)


# --- Validate Config ---
# Access keys optional: boto3 uses ~/.aws/credentials, SSO, env, or IAM role if unset.
config_ok = bool(AGENT_ID and AGENT_ALIAS_ID)


# --- Initialize Session State ---
if "messages" not in st.session_state:
    st.session_state.messages = []
if "session_id" not in st.session_state:
    st.session_state.session_id = str(uuid.uuid4())


# --- Bedrock Agent Client ---
@st.cache_resource
def get_bedrock_client():
    from botocore.config import Config
    # multi-agent investigations can take 1-2 minutes
    return boto3.client("bedrock-agent-runtime", region_name=AWS_REGION,
                        config=Config(read_timeout=300, retries={"max_attempts": 1}))


def invoke_agent(prompt: str) -> tuple[str, list]:
    """Send a message to Kira. Returns (answer, [specialist agents / tools she used])."""
    client = get_bedrock_client()
    try:
        response = client.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS_ID,
            sessionId=st.session_state.session_id,
            inputText=prompt,
            enableTrace=True,  # lets us show which specialist agents were consulted
        )
        answer, steps = "", []
        for event in response["completion"]:
            if "chunk" in event:
                answer += event["chunk"].get("bytes", b"").decode("utf-8")
            elif "trace" in event:
                orch = event["trace"].get("trace", {}).get("orchestrationTrace", {})
                inv = orch.get("invocationInput", {})
                collab = inv.get("agentCollaboratorInvocationInput", {}).get("agentCollaboratorName")
                tool = inv.get("actionGroupInvocationInput", {}).get("function")
                step = f"🤝 {collab}" if collab else (f"🔧 {tool}" if tool else None)
                if step and step not in steps:
                    steps.append(step)
        return answer, steps
    except Exception as e:
        return f"⚠️ Error: {str(e)}", []


# --- Header ---
st.markdown("""
<div class="main-header">
    <h1>⚡ KIRA</h1>
    <p>AIOps Assistant — Root Cause Analysis Engine</p>
</div>
""", unsafe_allow_html=True)


# --- Config Error ---
if not config_ok:
    st.markdown(f"""
    <div class="status-bar">
        <div class="status-dot-error"></div>
        <span style="color: #ef4444;">NOT CONFIGURED</span>
    </div>
    """, unsafe_allow_html=True)

    st.error(f"Bedrock agent `{AGENT_NAME}` not found in {AWS_REGION}. "
             + st.session_state.get("lookup_error", ""))
    st.markdown("1. Check the AWS CLI works: `aws sts get-caller-identity`\n"
                "2. Create the agents: **Actions → Infrastructure → apply** (with `aiops_enabled = true`)\n"
                "3. Or set `BEDROCK_AGENT_ID` and `BEDROCK_AGENT_ALIAS_ID` in `.env`")
    st.stop()


# --- Status Bar ---
st.markdown(f"""
<div class="status-bar">
    <div class="status-dot"></div>
    <span style="color: #22d3ee;">ONLINE</span>
    <span style="color: #2a3040;">|</span>
    <span style="color: #5a6270;">Session: {st.session_state.session_id[:8]}</span>
    <span style="color: #2a3040;">|</span>
    <span style="color: #5a6270;">Region: {AWS_REGION}</span>
    <span style="color: #2a3040;">|</span>
    <span style="color: #5a6270;">Agent: {AGENT_ID}</span>
</div>
""", unsafe_allow_html=True)


# --- Quick Actions ---
col1, col2, col3, col4 = st.columns(4)
with col1:
    if st.button("🩺 Is everything healthy?"):
        st.session_state.quick_action = "Is the Telugu Pickles platform healthy right now? Check all services briefly."
with col2:
    if st.button("🚦 Release status"):
        st.session_state.quick_action = ("What is the state of the blue-green (frontend) and canary (catalog-service) "
                                         "releases? Did any release check fail recently?")
with col3:
    if st.button("🔴 Investigate errors"):
        st.session_state.quick_action = ("We are seeing errors in the shop. Investigate the last 30 minutes "
                                         "and give me a full incident report.")
with col4:
    if st.button("🫙 Checkout failures"):
        st.session_state.quick_action = "Why are checkouts failing? Check orders, payment-service and its logs."

st.markdown("<div style='height: 0.5rem'></div>", unsafe_allow_html=True)


# --- Chat History ---
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])


# --- Handle Quick Actions ---
quick_action = st.session_state.pop("quick_action", None)


# --- Chat Input ---
user_input = st.chat_input("Describe the issue... e.g. 'Why is the API slow?'")

prompt = quick_action or user_input

if prompt:
    # Show user message
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    # Get agent response
    with st.chat_message("assistant"):
        with st.spinner("🔍 Kira is investigating with her specialist agents (up to ~1-2 min)..."):
            response, steps = invoke_agent(prompt)
        if steps:
            with st.expander("How Kira investigated: " + ", ".join(steps)):
                st.markdown("\n".join(f"- {s}" for s in steps))
        st.markdown(response)

    st.session_state.messages.append({"role": "assistant", "content": response})


# --- Sidebar ---
with st.sidebar:
    st.markdown("""
    <div style="font-family: 'JetBrains Mono', monospace; padding: 1rem 0;">
        <h3 style="color: #22d3ee; font-size: 1rem;">⚡ KIRA</h3>
        <p style="color: #5a6270; font-size: 0.8rem;">AIOps Assistant v1.0</p>
    </div>
    """, unsafe_allow_html=True)

    st.markdown("---")
    st.markdown("**Kira's team (Bedrock multi-agent):**")
    st.markdown("- 📋 **logs-agent**: CloudWatch Logs Insights")
    st.markdown("- 📊 **metrics-agent**: Prometheus (RED, per-pod, orders, alerts)")
    st.markdown("- 🚦 **deployment-agent**: Argo CD, Rollouts, pods, events")

    st.markdown("---")
    st.markdown("**Sample Questions:**")
    st.markdown("""
    - Why did the last catalog-service canary roll back?
    - Is the new frontend (blue-green preview) waiting for promotion?
    - Which pods return 5xx errors right now?
    - Are payments failing? Since when?
    - Did errors start after the last deployment?
    - Which pod uses the most memory?
    """)

    st.markdown("---")
    if st.button("🔄 New Session"):
        st.session_state.messages = []
        st.session_state.session_id = str(uuid.uuid4())
        st.rerun()