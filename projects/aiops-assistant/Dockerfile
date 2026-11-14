FROM python:3.12-slim

WORKDIR /app
COPY requirements-api.txt .
RUN pip install --no-cache-dir --default-timeout=120 --retries=8 -r requirements-api.txt
COPY agent ./agent

RUN useradd --create-home --uid 10001 appuser
USER appuser
EXPOSE 8000
CMD ["uvicorn", "agent.api:app", "--host", "0.0.0.0", "--port", "8000"]
