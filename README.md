> [!IMPORTANT]
> **This repository has moved.** Development continues in the public repositories [aenix-io/cozyllm](https://github.com/aenix-io/cozyllm) (free catalog: vLLM, LiteLLM, JupyterHub, Langflow, ComfyUI, HolmesGPT) and [aenix-io/cozyllm-nonfree](https://github.com/aenix-io/cozyllm-nonfree) (n8n, Open WebUI — non-OSS upstream licenses). This private repository is archived; its history and unmerged branches are preserved for reference only.

# cozyllm

External AI applications for [Cozystack](https://cozystack.io). Deploy production-ready AI infrastructure — model serving, vector storage, chat UIs, workflow automation, SRE assistance — into your Cozystack cluster through the dashboard.

## What's inside

| App | What it is | Backing services |
| --- | --- | --- |
| **[vllm-inference](docs/apps/vllm-inference.md)** | GPU-accelerated LLM inference (OpenAI-compatible API) | none |
| **[litellm](docs/apps/litellm.md)** | Unified gateway in front of one or more model backends | Postgres |
| **[open-webui](docs/apps/open-webui.md)** | Chat interface over any OpenAI-compatible API | Postgres, optional Qdrant |
| **[comfyui](docs/apps/comfyui.md)** | Node-based UI for Stable Diffusion / image generation | none (GPU + PVC) |
| **[jupyterhub](docs/apps/jupyterhub.md)** | Multi-user Jupyter notebooks for ML experimentation | Postgres |
| **[langflow](docs/apps/langflow.md)** | Visual LLM-pipeline builder | Postgres |
| **[n8n](docs/apps/n8n.md)** | General workflow automation with native AI nodes | Postgres |

Every app appears as a first-class entity in the Cozystack dashboard — deploy with a click, configure through a generated form, scale and tear down independently.

### Admin components

| Component | What it is |
| --- | --- |
| **[HolmesGPT](docs/holmesgpt.md)** | AI SRE agent for Kubernetes troubleshooting |

HolmesGPT is **not** tenant-deployable: it needs cluster-wide read RBAC, so it is installed once by the cluster admin as an opt-in platform component (`holmesgpt.enabled: true`) rather than offered in the tenant dashboard. See [docs/holmesgpt.md](docs/holmesgpt.md).

## Quick install

Apply the bootstrap manifest to a Cozystack 1.4+ cluster:

```bash
kubectl apply -f https://raw.githubusercontent.com/aenix-org/cozyllm/main/init.yaml
```

This registers a FluxCD `GitRepository` and a platform `HelmRelease` in `cozy-system`. Flux pulls every minute; within ~2 minutes you'll see seven new `ApplicationDefinition` resources in the dashboard.

For pinning to a stable release rather than tracking `main`, see [docs/upgrades.md](docs/upgrades.md).

For the full install walkthrough including verification, troubleshooting and uninstall, see [docs/install.md](docs/install.md).

## Architecture

```text
┌──────────────────────────────────────────────────────┐
│            Cozystack Dashboard (PaaS)                │
│         Click → fill form → deploy CR                │
└─────────────────────┬────────────────────────────────┘
                      │
        ┌─────────────▼──────────────┐
        │   ApplicationDefinitions   │
        │  registered by this repo   │
        └──┬──────┬──────────┬───────┘
           │      │          │
   ┌───────▼┐  ┌──▼──────┐  ┌▼─────────────────┐
   │ vLLM   │  │ LiteLLM │  │  Front-end apps  │
   │ (GPU)  │◄─┤ gateway │◄─┤  Open WebUI      │
   │        │  │ +Postgr │  │  Langflow        │
   └────────┘  └─────────┘  │  n8n             │
   ┌────────┐               │  JupyterHub      │
   │ComfyUI │               │  ComfyUI (GPU)   │
   │(GPU)   │               └──────────────────┘
   └────────┘
```

- vLLM serves models on raw GPU hardware
- LiteLLM unifies one-or-more vLLM endpoints (plus public OpenAI/Anthropic/etc.) behind one API
- Front-end apps talk to LiteLLM as if it were OpenAI — single key, model registry, usage tracking
- ComfyUI is independent: no LLM dependency, just GPU + Stable Diffusion

## Documentation

- **[Install guide](docs/install.md)** — detailed install + verification + uninstall
- **[Upgrade policy](docs/upgrades.md)** — semver, ref pinning, schema migrations
- **[Application reference](docs/apps/)** — per-app deploy options + usage
- **[End-to-end examples](docs/examples.md)** — wiring apps together: AI stack from zero, support-triage workflow, RAG over docs

## Strategy and rationale

Why these apps, why an external repository instead of merging into Cozystack core, how this scales into a community marketplace — see [STRATEGY_EXTERNAL_APPS.md](STRATEGY_EXTERNAL_APPS.md).

## Status

Alpha. Pinned to specific upstream chart versions. Renovate opens PRs for patch bumps automatically (auto-merge once CI is green); major bumps need human review.

## Contributing

To add a new app, the easiest path is the [`cozystack:external-app-create`](https://github.com/cozystack/ccp/tree/main/plugins/cozystack/skills/external-app-create) skill from the cozystack/ccp marketplace — it generates a fully spec-compliant chart skeleton, dependency wiring (Postgres / Redis / Qdrant via Pattern C), and platform registration in one command.

Run `make generate` inside any `packages/apps/<name>/` after editing `values.yaml` to regenerate `values.schema.json` and `README.md` via `cozyvalues-gen`. Mirror the regenerated schema into the corresponding `openAPISchema` field in `packages/core/platform/templates/cozyrds.yaml`.
