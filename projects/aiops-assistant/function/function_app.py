import json
import logging

import azure.functions as func

from kira import ask_kira, handle_alert

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


@app.route(route="aiops/ask", methods=["POST"])
def ask(req: func.HttpRequest) -> func.HttpResponse:
    try:
        payload = req.get_json()
    except ValueError:
        return func.HttpResponse("Request body must be valid JSON.", status_code=400)

    question = payload.get("question") if isinstance(payload, dict) else None
    history = payload.get("history", []) if isinstance(payload, dict) else None
    if not isinstance(question, str) or not question.strip():
        return func.HttpResponse("A non-empty 'question' string is required.", status_code=400)
    if len(question) > 4000 or not isinstance(history, list):
        return func.HttpResponse("Question/history is invalid or too large.", status_code=400)

    try:
        result = ask_kira(question.strip(), history)
    except Exception:
        logging.exception("AIOps investigation failed")
        return func.HttpResponse("AIOps investigation failed; check Function logs.", status_code=500)
    return func.HttpResponse(json.dumps(result, default=str), mimetype="application/json")


@app.route(route="aiops/health", methods=["GET"])
def health(_: func.HttpRequest) -> func.HttpResponse:
    from kira import configuration_status

    status = configuration_status()
    return func.HttpResponse(
        json.dumps(status),
        mimetype="application/json",
        status_code=200 if status["ready"] else 503,
    )


@app.route(route="aiops/incident", methods=["POST"])
def incident(req: func.HttpRequest) -> func.HttpResponse:
    try:
        payload = req.get_json()
    except ValueError:
        return func.HttpResponse("Request body must be valid JSON.", status_code=400)

    if not isinstance(payload, dict):
        return func.HttpResponse("Alert payload must be a JSON object.", status_code=400)
    try:
        result = handle_alert(payload)
    except Exception:
        logging.exception("Automatic AIOps incident investigation failed")
        return func.HttpResponse("Incident investigation failed; check Function logs.", status_code=500)
    return func.HttpResponse(json.dumps(result, default=str), mimetype="application/json")
