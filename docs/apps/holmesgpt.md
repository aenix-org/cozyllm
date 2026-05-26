# holmesgpt

AI SRE agent for Kubernetes troubleshooting. Wraps [robusta-dev/holmesgpt](https://github.com/robusta-dev/holmesgpt) (CNCF Sandbox project). Read-only — Holmes investigates the cluster, it does not mutate state. No backing services. The upstream chart creates a ServiceAccount with a ClusterRole granting read access to pods, events, logs, services, deployments, etc.

## Deploy

Pointing at an in-cluster LiteLLM gateway:

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"HolmesGPT","metadata":{"name":"sre"},"spec":{"model":"openai/qwen-7b","openaiBaseUrl":"http://litellm-gateway.<ns>.svc.cluster.local:4000/v1","openaiApiKey":"sk-master-CHANGEME"}}' | kubectl -n <ns> apply -f -
```

Or directly against public OpenAI:

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"HolmesGPT","metadata":{"name":"sre"},"spec":{"model":"openai/gpt-4o","openaiApiKey":"sk-proj-..."}}' | kubectl -n <ns> apply -f -
```

## Spec reference

| Field | Notes |
|---|---|
| `model` | LiteLLM-format model identifier (`openai/qwen-7b`, `anthropic/claude-3-5-sonnet`, …) |
| `openaiBaseUrl` | OpenAI-compatible endpoint. In-cluster LiteLLM recommended. Empty → public OpenAI. |
| `openaiApiKey` | Bearer token. Stored as Secret. |
| `host` | Hostname for external Ingress |
| `replicaCount` | Holmes is stateless |

Full reference: [packages/apps/holmesgpt/README.md](../../packages/apps/holmesgpt/README.md).

## Access (HTTP API)

```bash
kubectl -n <ns> port-forward svc/holmesgpt-sre-app-holmes 8000:80
```

## Use

Ask an open question:

```bash
curl -s -X POST http://localhost:8000/api/chat \
  -H 'Content-Type: application/json' \
  -d '{"ask":"List unhealthy pods across all namespaces and explain the issue with each"}'
```

Investigate a specific incident (Alertmanager-shaped payload):

```bash
curl -s -X POST http://localhost:8000/api/investigate \
  -H 'Content-Type: application/json' \
  -d '{
    "source":"prometheus",
    "title":"PodCrashLooping",
    "description":"Pod has restarted 5 times in the last 10 minutes",
    "subject":{"namespace":"<ns>","name":"<pod>","kind":"Pod"}
  }'
```

Holmes pulls logs, events, and `describe` output through its ServiceAccount, sends the bundle to the configured LLM, and returns analysis + remediation suggestions.

## CLI in pod

For interactive use:

```bash
kubectl -n <ns> exec -it deploy/holmesgpt-sre-app-holmes -- holmes ask "why is my postgres-litellm-gateway-db-1 not replicating?"
```

## Integration patterns

**Alertmanager → Holmes → Slack**: webhook from Alertmanager → n8n receives → HTTP request to Holmes `/api/investigate` → Slack message with root cause.

**Scheduled cluster audits**: n8n on a cron → POST `/api/chat?ask=list problems` → email summary.

**Open WebUI as front-end**: configure an Open WebUI Connection with base URL pointing at Holmes — get a chat interface for cluster diagnosis without writing curl.

## Limitations

- Holmes is read-only by design. It will not auto-remediate; it explains what's wrong and suggests fixes.
- LLM quality matters. Small local models (7B) handle simple cases; complex multi-step diagnosis benefits from larger models (70B+ or hosted GPT-4 / Claude).
- Holmes does not see Cozystack-specific abstractions (Tenant, ApplicationDefinition, sibling CRs) unless the LLM has been trained on them or you provide context in the prompt.
