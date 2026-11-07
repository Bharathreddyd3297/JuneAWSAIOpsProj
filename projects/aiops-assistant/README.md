# Dude — Azure AIOps Assistant

Dude is a Streamlit chat client backed by an Azure Functions Python v2 app. The Function uses an
Azure OpenAI-compatible tool-calling deployment and read-only tools for AKS, Prometheus, and
Azure Monitor Logs.

## Components

- `function/`: Azure Functions app, assistant loop, Azure Monitor query tools, and read-only AKS tools.
- `app.py`: local Streamlit interface that calls the secured Function HTTP API.
- `requirements.txt`: Streamlit UI dependencies.
- `function/requirements.txt`: Function runtime dependencies.

Terraform creates the model endpoint and grants it to the Function's user-assigned managed identity,
along with access to Log Analytics and read-only AKS permissions. For local Function development,
set `AZURE_OPENAI_ENDPOINT` and `AZURE_OPENAI_DEPLOYMENT` from Terraform outputs in the ignored
`local.settings.json`. The `/api/aiops/ask`, `/api/aiops/health`, and `/api/aiops/incident` routes
require a Function key. Do not commit the key.

## Run the UI

1. Copy `.env.example` to `.env`.
2. Set `AIOPS_FUNCTION_URL` to the Function's `/api/aiops/ask` URL and set `AIOPS_FUNCTION_KEY`.
3. Install and start the UI:

   ```powershell
   python -m pip install -r requirements.txt
   streamlit run app.py
   ```

## Run the Function locally

Install Azure Functions Core Tools v4, Python 3.14, and Azurite. In `function/`, copy
`local.settings.json.example` to `local.settings.json`, then configure
`AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_DEPLOYMENT`, `LOG_ANALYTICS_WORKSPACE_ID`, and
`CLUSTER_ENDPOINT`. Authenticate with Azure CLI so `DefaultAzureCredential` can use your signed-in
identity. The local identity needs the same read permissions as the deployed Function identity.

```powershell
Set-Location function
Copy-Item local.settings.json.example local.settings.json
python -m pip install -r requirements.txt
func start
```

`local.settings.json` is ignored by Git. Never commit model keys, Function keys, or credentials.
