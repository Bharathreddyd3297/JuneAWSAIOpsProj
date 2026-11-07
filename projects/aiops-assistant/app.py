"""
AIOps Assistant — Streamlit chat UI for Dude.
Dude is a multi-agent AIOps assistant backed by the Azure Functions app in `function/`.
A supervisor delegates to Azure Monitor Logs, Prometheus, and AKS tools through a
tool-calling Azure-hosted model deployment.

Run (sign in with Azure CLI so the Function can use your Azure identity):
    pip install -r requirements.txt
    streamlit run app.py
"""

import os
import uuid

import requests
import streamlit as st
from dotenv import load_dotenv

load_dotenv()

# --- Config ---
FUNCTION_URL = os.getenv("AIOPS_FUNCTION_URL", "").rstrip("/")
FUNCTION_KEY = os.getenv("AIOPS_FUNCTION_KEY", "")


# --- Page Config ---
st.set_page_config(
    page_title="Dude — AIOps Assistant",
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


# --- Initialize Session State ---
if "messages" not in st.session_state:
    st.session_state.messages = []
if "session_id" not in st.session_state:
    st.session_state.session_id = str(uuid.uuid4())


# --- Azure Functions API ---
@st.cache_data(ttl=60, show_spinner=False)
def kira_status():
    """Returns whether the configured Azure Functions API is reachable and ready."""
    if not FUNCTION_URL:
        return False, "AIOPS_FUNCTION_URL is not configured."
    if not FUNCTION_KEY:
        return False, "AIOPS_FUNCTION_KEY is not configured."
    try:
        response = requests.get(
            FUNCTION_URL.rsplit("/", 1)[0] + "/health",
            headers={"x-functions-key": FUNCTION_KEY},
            timeout=15,
        )
        response.raise_for_status()
        status = response.json()
        if not status.get("ready"):
            return False, "Function app is reachable, but its model or platform configuration is incomplete."
        return True, status.get("model", "Azure model configured")
    except (requests.RequestException, ValueError) as exc:
        return False, str(exc)


def ask_kira(prompt: str) -> dict:
    """Call the Azure Functions HTTP endpoint with the question and chat history."""
    if not FUNCTION_URL or not FUNCTION_KEY:
        return {"answer": "Configure AIOPS_FUNCTION_URL and AIOPS_FUNCTION_KEY first.", "steps": []}
    history = [{"role": m["role"], "text": m["content"]} for m in st.session_state.messages[:-1][-10:]]
    try:
        response = requests.post(
            FUNCTION_URL,
            headers={"x-functions-key": FUNCTION_KEY},
            json={"question": prompt, "history": history},
            timeout=300,
        )
        response.raise_for_status()
        result = response.json()
        if not isinstance(result, dict) or not isinstance(result.get("answer"), str):
            return {"answer": "Azure Functions returned an invalid response.", "steps": []}
        return result
    except (requests.RequestException, ValueError) as exc:
        return {"answer": f"Azure Functions request failed: {exc}", "steps": []}


# --- Header ---
st.markdown("""
<div class="main-header">
    <h1>⚡ DUDE</h1>
    <p>AIOps Assistant — Root Cause Analysis Engine</p>
</div>
""", unsafe_allow_html=True)


# --- Config Error ---
config_ok, status_detail = kira_status()
if not config_ok:
    st.markdown("""
    <div class="status-bar">
        <div class="status-dot-error"></div>
        <span style="color: #ef4444;">NOT CONFIGURED</span>
    </div>
    """, unsafe_allow_html=True)
    st.error(f"Azure Functions API is not ready: {status_detail}")
    st.markdown(
        "1. Set `AIOPS_FUNCTION_URL` and `AIOPS_FUNCTION_KEY` in `.env`.\n"
        "2. Deploy the Azure Function app and configure its Azure model endpoint.\n"
        "3. Ensure its managed identity can query Log Analytics and read the AKS API."
    )
    st.stop()


# --- Status Bar ---
st.markdown(f"""
<div class="status-bar">
    <div class="status-dot"></div>
    <span style="color: #22d3ee;">ONLINE</span>
    <span style="color: #2a3040;">|</span>
    <span style="color: #5a6270;">Session: {st.session_state.session_id[:8]}</span>
    <span style="color: #2a3040;">|</span>
    <span style="color: #5a6270;">Models: {status_detail}</span>
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
        with st.spinner("🔍 Dude is investigating with the specialist agents (up to ~1-2 min)..."):
            result = ask_kira(prompt)
        response, steps = result.get("answer", ""), result.get("steps", [])
        if steps:
            agents = sorted({s.split(" ")[0] for s in steps})
            with st.expander(f"How Dude investigated: {len(steps)} steps by {', '.join(agents)} "
                             f"({result.get('seconds', '?')} s, "
                             f"{result.get('tokens_in', 0) + result.get('tokens_out', 0)} tokens)"):
                st.markdown("\n".join(f"- `{s}`" for s in steps))
        st.markdown(response)

    st.session_state.messages.append({"role": "assistant", "content": response})


# --- Sidebar ---
with st.sidebar:
    st.markdown("""
    <div style="font-family: 'JetBrains Mono', monospace; padding: 1rem 0;">
        <h3 style="color: #22d3ee; font-size: 1rem;">⚡ DUDE</h3>
        <p style="color: #5a6270; font-size: 0.8rem;">AIOps Assistant v1.0</p>
    </div>
    """, unsafe_allow_html=True)

    st.markdown("---")
    st.markdown("**Dude's team (Azure model tool-calling):**")
    st.markdown("- 📋 **logs-agent**: Azure Monitor Logs / Log Analytics")
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