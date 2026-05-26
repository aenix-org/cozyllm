# holmesgpt

[HolmesGPT](https://github.com/robusta-dev/holmesgpt) — AI SRE agent for Kubernetes troubleshooting, packaged as a Cozystack external app.

Wraps the upstream `robusta/holmes` chart and points it at any OpenAI-compatible LLM endpoint — typically a LiteLLM gateway already running in the same cluster, so HolmesGPT routes through your local vLLM models instead of public OpenAI.

## Connecting to the AI cluster

Default wiring assumes a `litellm` instance exists in the same cluster. Set:

```yaml
spec:
  openaiBaseUrl: "http://litellm-<release>.cozy-litellm.svc.cluster.local:4000/v1"
  openaiApiKey: "<your litellm master key>"
  model: "openai/qwen-7b"   # whatever you registered in LiteLLM
```

Leave `openaiBaseUrl` empty to fall back to the public OpenAI API.

## Required cluster permissions

The upstream chart creates a `ServiceAccount` and `ClusterRole` granting HolmesGPT read access to most Kubernetes resources (pods, events, logs, services, deployments, …). HolmesGPT performs read-only investigation — it never mutates cluster state.

## Parameters

### Common parameters

| Name   | Description                                                            | Type     | Value |
| ------ | ---------------------------------------------------------------------- | -------- | ----- |
| `host` | Hostname for external access via Ingress. Leave empty to skip Ingress. | `string` | `""`  |


### LLM backend

| Name            | Description                                                                                                                                                                                                                                         | Type     | Value           |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | --------------- |
| `model`         | LiteLLM-format model identifier (e.g. openai/qwen-7b, anthropic/claude-3-5-sonnet). Must be registered in the gateway pointed to by openaiBaseUrl, or be a public OpenAI / Anthropic model when calling those APIs directly.                        | `string` | `openai/gpt-4o` |
| `openaiBaseUrl` | OpenAI-compatible API endpoint. Point this at an in-cluster LiteLLM gateway (e.g. http://litellm-<release>.cozy-litellm.svc.cluster.local:4000/v1) to keep all SRE-related LLM calls inside the cluster. Empty falls back to the public OpenAI API. | `string` | `""`            |
| `openaiApiKey`  | Bearer token for the API endpoint. For LiteLLM, this is the master key. Stored as a Kubernetes Secret.                                                                                                                                              | `string` | `""`            |


### Replication

| Name           | Description               | Type  | Value |
| -------------- | ------------------------- | ----- | ----- |
| `replicaCount` | Number of HolmesGPT pods. | `int` | `1`   |

