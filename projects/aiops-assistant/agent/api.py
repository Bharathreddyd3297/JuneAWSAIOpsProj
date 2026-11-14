"""HTTP API hosted in AKS for the Azure-native AIOps agent."""

import os
import secrets
import threading
from typing import Literal

from fastapi import Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel, Field

from agent.kira import SPECIALIST_MODEL, SUPERVISOR_MODEL, ask_kira

app = FastAPI(title="Telugu Pickles AIOps", version="2.0")
_requests = threading.BoundedSemaphore(value=2)


class HistoryItem(BaseModel):
    role: Literal["user", "assistant"]
    text: str = Field(min_length=1, max_length=4000)


class Question(BaseModel):
    question: str = Field(min_length=1, max_length=4000)
    history: list[HistoryItem] = Field(default_factory=list, max_length=10)


def require_api_token(authorization: str = Header(default="")):
    expected = os.getenv("AIOPS_API_TOKEN", "")
    supplied = authorization.removeprefix("Bearer ").strip()
    if not expected:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "AIOps API token is not configured")
    if not supplied or not secrets.compare_digest(supplied, expected):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid bearer token")


@app.get("/healthz")
def health():
    return {
        "status": "ok", "cloud": "azure", "supervisor": SUPERVISOR_MODEL,
        "specialist": SPECIALIST_MODEL, "authentication": "bearer",
    }


@app.post("/ask")
def ask(request: Question, _authorized: None = Depends(require_api_token)):
    if not _requests.acquire(blocking=False):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "AIOps is already handling two investigations")
    try:
        return ask_kira(request.question, [item.model_dump() for item in request.history])
    finally:
        _requests.release()
