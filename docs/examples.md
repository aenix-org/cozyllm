# End-to-end examples

Scenarios that wire two or more cozyllm apps together. Each example assumes the catalog is already installed (see [install.md](install.md)). Replace `<ns>` with your tenant namespace throughout.

## 1. AI chat stack from zero

Goal: chat with an LLM running entirely inside your cluster — model serving, gateway, chat UI.

```bash
# Step 1: model server (requires GPU)
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"VllmInference","metadata":{"name":"qwen"},"spec":{"model":"Qwen/Qwen2.5-7B-Instruct","gpuCount":1,"quantization":"fp16","maxContextLength":8192}}' | kubectl -n <ns> apply -f -

# Step 2: wait for the model to download and load (~5-15 min)
kubectl -n <ns> logs -l cozyllm.io/model=true -f
# Look for: "Application startup complete."

# Step 3: gateway in front of the model
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"Litellm","metadata":{"name":"gateway"},"spec":{"masterKey":"sk-master-CHANGEME","postgres":{"enabled":true,"replicas":1,"size":"5Gi","user":"litellm","name":"litellm"},"models":[{"name":"qwen-7b","url":"http://vllm-inference-qwen.<ns>.svc.cluster.local:8000/v1"}]}}' | kubectl -n <ns> apply -f -

# Step 4: chat UI on top of the gateway
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"OpenWebUI","metadata":{"name":"chat"},"spec":{"database":{"size":"5Gi","replicas":1,"user":"openwebui","name":"openwebui"},"openaiBaseApiUrl":"http://litellm-gateway.<ns>.svc.cluster.local:4000/v1","openaiApiKey":"sk-master-CHANGEME"}}' | kubectl -n <ns> apply -f -

# Step 5: port-forward to the chat UI
kubectl -n <ns> port-forward svc/open-webui-chat-app 3000:80
# Open http://localhost:3000 → create owner account → start chatting
```

## 2. RAG over your company documents

Goal: chat that can quote from internal PDFs and Markdown files.

```bash
# Add Qdrant to the chat stack from example 1:
kubectl -n <ns> patch openwebui chat --type merge \
  -p '{"spec":{"qdrant":{"enabled":true,"size":"10Gi","replicas":1}}}'
```

Wait for `helmrelease/qdrant-chat-vector` to reach Ready. Then in Open WebUI:

1. **Settings → Documents → +** → upload PDFs / .md files
2. The webui chunks documents, embeds via the configured embedding model, stores in Qdrant
3. Future chats retrieve relevant chunks → injected into LLM context

For programmatic indexing (e.g. nightly Confluence sync), use n8n's HTTP Request node against Open WebUI's `/api/v1/documents/upload`.

## 3. AI-powered support triage

Goal: WHMCS sends ticket-created webhook → n8n classifies → routes to Slack channels by type.

Prerequisite: complete example 1 (LiteLLM gateway must be running).

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"N8n","metadata":{"name":"triage"},"spec":{"database":{"size":"5Gi","replicas":1,"user":"n8n","name":"n8n"},"encryptionKey":"'$(openssl rand -hex 32)'"}}' | kubectl -n <ns> apply -f -

kubectl -n <ns> port-forward svc/n8n-triage-app 5678:80
```

In n8n at `http://localhost:5678`:

1. **New Workflow** → add **Webhook** trigger → copy the test URL
2. → **OpenAI Chat Model** node:
   - Credentials: base URL `http://litellm-gateway.<ns>:4000/v1`, master key as API key
   - Model: `qwen-7b`
   - Prompt: `"Classify this support ticket as one of: billing | technical | sales | abuse. Output only the label. Ticket: {{ $json.body.subject }} {{ $json.body.message }}"`
3. → **Switch** node, conditions on the classification output
4. Each branch → **Slack** node → respective channel
5. **Activate** workflow
6. In WHMCS: point ticket-created webhook at the n8n URL from step 1

## 4. Alertmanager root-cause analysis

Goal: VictoriaMetrics alert fires → n8n receives → HolmesGPT investigates → enriched Slack message.

Prerequisite: examples 1 and 3 (LiteLLM and n8n running).

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"HolmesGPT","metadata":{"name":"sre"},"spec":{"model":"openai/qwen-7b","openaiBaseUrl":"http://litellm-gateway.<ns>.svc.cluster.local:4000/v1","openaiApiKey":"sk-master-CHANGEME"}}' | kubectl -n <ns> apply -f -
```

In n8n:

1. **Webhook** trigger → copy URL (you'll register this as an Alertmanager receiver)
2. → **HTTP Request** node:
   - Method: POST
   - URL: `http://holmesgpt-sre-app-holmes.<ns>:80/api/investigate`
   - Body (map Alertmanager → Holmes payload):
     ```json
     {
       "source":"prometheus",
       "title":"{{ $json.alerts[0].labels.alertname }}",
       "description":"{{ $json.alerts[0].annotations.description }}",
       "subject":{
         "namespace":"{{ $json.alerts[0].labels.namespace }}",
         "name":"{{ $json.alerts[0].labels.pod }}",
         "kind":"Pod"
       }
     }
     ```
3. → **Slack** node:
   - Message: `"🚨 {{ $('Webhook').first().json.alerts[0].labels.alertname }}\n\n*Holmes analysis:*\n{{ $json.analysis }}"`
4. In Alertmanager config: route alerts to the n8n webhook URL

## 5. Multi-user ML notebooks

Goal: data-science team shares one JupyterHub, each user's notebooks hit the same LiteLLM gateway.

Prerequisite: example 1 (LiteLLM running).

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"JupyterHub","metadata":{"name":"team"},"spec":{"database":{"size":"5Gi","replicas":1,"user":"jupyterhub","name":"jupyterhub"}}}' | kubectl -n <ns> apply -f -
```

Bake the LLM connection into every spawned notebook by patching the inner HelmRelease values:

```bash
kubectl -n <ns> patch helmrelease jupyterhub-team-app --type merge -p '{"spec":{"values":{"singleuser":{"extraEnv":{"OPENAI_API_KEY":"sk-master-CHANGEME","OPENAI_BASE_URL":"http://litellm-gateway.<ns>.svc.cluster.local:4000/v1"}}}}}'
```

Users can now run `from openai import OpenAI; OpenAI().chat.completions.create(model="qwen-7b", messages=[...])` without any per-user config.

## 6. Visual LLM pipelines as APIs

Goal: business team designs a flow in Langflow → exports it as an HTTP endpoint → backend developers call it from production code.

Prerequisite: example 1.

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"Langflow","metadata":{"name":"flows"},"spec":{"database":{"size":"5Gi","replicas":1,"user":"langflow","name":"langflow"}}}' | kubectl -n <ns> apply -f -

kubectl -n <ns> port-forward svc/langflow-flows-app 7860:80
```

In Langflow UI at `http://localhost:7860`:

1. Build a flow (e.g. ChatInput → Prompt template → OpenAI → ChatOutput)
2. **Share → API Access** → copy the curl example
3. Hand the endpoint to backend devs — they call it without knowing the flow internals
4. When the team iterates on the flow, downstream code keeps working (same endpoint, evolved logic inside)

## 7. Image generation pipeline

Goal: n8n triggers ComfyUI to generate an image, posts it back to Slack.

Prerequisite: example 3 (n8n running), plus a GPU-capable node for ComfyUI.

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"ComfyUI","metadata":{"name":"design"},"spec":{"gpuEnabled":true,"gpuCount":1,"storage":{"size":"100Gi"}}}' | kubectl -n <ns> apply -f -
```

Load at least one Stable Diffusion checkpoint into ComfyUI (via the UI's Manager → Install Models).

In n8n:

1. Trigger (Schedule / Slack slash command / Webhook)
2. → **HTTP Request** node:
   - Method: POST
   - URL: `http://comfyui-design.<ns>:8188/prompt`
   - Body: a workflow JSON (export from ComfyUI's UI via Save (API Format))
3. Poll `/history/<prompt_id>` until the image is ready
4. Download the image from `/view?filename=...` → upload to Slack node
