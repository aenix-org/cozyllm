# open-webui

Chat UI over any OpenAI-compatible LLM. Wraps the upstream [open-webui/open-webui](https://github.com/open-webui/open-webui) chart. Backing services: managed Postgres (users + chat history), optional Qdrant (RAG over documents).

## Deploy — minimal

Without a pre-set LLM backend (you wire it through the UI later):

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"OpenWebUI","metadata":{"name":"chat"},"spec":{"database":{"size":"5Gi","replicas":1,"user":"openwebui","name":"openwebui"}}}' | kubectl -n <ns> apply -f -
```

## Deploy — pre-wired to LiteLLM

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"OpenWebUI","metadata":{"name":"chat"},"spec":{"database":{"size":"5Gi","replicas":1,"user":"openwebui","name":"openwebui"},"openaiBaseApiUrl":"http://litellm-gateway.<ns>.svc.cluster.local:4000/v1","openaiApiKey":"sk-master-CHANGEME"}}' | kubectl -n <ns> apply -f -
```

## Deploy — with Qdrant RAG enabled

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"OpenWebUI","metadata":{"name":"chat"},"spec":{"database":{"size":"5Gi","replicas":1,"user":"openwebui","name":"openwebui"},"qdrant":{"enabled":true,"size":"10Gi","replicas":1}}}' | kubectl -n <ns> apply -f -
```

Adds a Pattern C `Qdrant` CR; Open WebUI gets `VECTOR_DB=qdrant`, `QDRANT_URI`, `QDRANT_API_KEY` env vars wired automatically.

## Spec reference

| Field | Notes |
|---|---|
| `database.{size,replicas,user,name}` | Pattern C Postgres |
| `qdrant.{enabled,size,replicas}` | Pattern C Qdrant — defaults to off (Open WebUI uses embedded ChromaDB) |
| `openaiBaseApiUrl` | OpenAI-compatible endpoint. In-cluster LiteLLM recommended. |
| `openaiApiKey` | Bearer token, stored as Secret |
| `host` | Hostname for external Ingress |

Full reference: [packages/apps/open-webui/README.md](../../packages/apps/open-webui/README.md).

## Access

```bash
kubectl -n <ns> port-forward svc/open-webui-chat-app 3000:80
```

Open `http://localhost:3000`. On first visit there's a setup wizard:

- Email + password creates the local owner account (not federated with Keycloak)
- All subsequent registrations land in "Pending Approval" — admin approves via **Admin Panel**

## Configure models

If `openaiBaseApiUrl` was set in the CR, models auto-populate. Otherwise: **Settings → Connections → OpenAI API**:

- URL: `http://litellm-gateway.<ns>.svc.cluster.local:4000/v1` (in-cluster LiteLLM)
- API key: LiteLLM master key
- Save → models appear in the top dropdown

## RAG over documents

With `qdrant.enabled=true`:

1. **Settings → Documents → +** → upload PDFs, .md, .txt files
2. Open WebUI chunks them, embeds via the configured embedding model, stores in Qdrant
3. Future chats automatically retrieve relevant chunks → injected into LLM context

For programmatic indexing (e.g. nightly Confluence sync), use n8n with HTTP calls to Open WebUI's `/api/v1/documents/upload`.

## MCP tool integration

Open WebUI 0.9+ supports MCP. **Settings → Tools → +** → add MCP server URLs (kubernetes-mcp, GitHub MCP, etc.). Enable per-chat from the tool palette under the message input.

## Use as backend for HolmesGPT

Treat HolmesGPT's `/api/chat` endpoint as if it were OpenAI:

- In Open WebUI **Settings → Connections** add a second OpenAI API
- URL: `http://holmesgpt-<release>-app-holmes.<ns>.svc.cluster.local/api/v1`
- Model: arbitrary (HolmesGPT ignores it)

Now switch the model dropdown to the Holmes endpoint → chat questions become cluster diagnostic queries.
