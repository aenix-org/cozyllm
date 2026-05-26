# jupyterhub

Multi-user JupyterHub for ML / data-science teams. Wraps the upstream [zero-to-jupyterhub-k8s](https://github.com/jupyterhub/zero-to-jupyterhub-k8s) chart. Backing service: managed Postgres (hub state — users, groups, server records).

## Deploy

```bash
echo '{"apiVersion":"apps.cozystack.io/v1alpha1","kind":"JupyterHub","metadata":{"name":"hub"},"spec":{"database":{"size":"5Gi","replicas":1,"user":"jupyterhub","name":"jupyterhub"}}}' | kubectl -n <ns> apply -f -
```

## Spec reference

| Field | Notes |
|---|---|
| `database.{size,replicas,user,name}` | Pattern C Postgres |
| `host` | Hostname for external Ingress |
| `replicaCount` | Multi-replica needs sticky sessions; the upstream chart doesn't configure them by default — stay at 1 unless you patch the inner HelmRelease |

Full reference: [packages/apps/jupyterhub/README.md](../../packages/apps/jupyterhub/README.md).

## Access

```bash
kubectl -n <ns> port-forward svc/jupyterhub-hub-app-proxy-public 8080:80
```

Open `http://localhost:8080`.

## First-time auth

Default authenticator is `dummy` — any username + any password lets you in. **Never expose this to the internet without changing it.**

To switch to OIDC (Keycloak, GitHub, Google), override the upstream chart's `hub.config.JupyterHub.authenticator_class` via a follow-up patch. Example for Keycloak:

```bash
kubectl -n <ns> patch helmrelease jupyterhub-hub-app --type merge -p '{"spec":{"values":{"hub":{"config":{"JupyterHub":{"authenticator_class":"generic-oauth"},"GenericOAuthenticator":{"client_id":"jupyterhub","client_secret":"<secret>","oauth_callback_url":"https://<host>/hub/oauth_callback","authorize_url":"https://keycloak.../auth","token_url":"https://keycloak.../token","userdata_url":"https://keycloak.../userinfo","scope":["openid","profile","email"],"login_service":"Keycloak","username_key":"preferred_username"}}}}}}'
```

See upstream [JupyterHub auth docs](https://z2jh.jupyter.org/en/stable/administrator/authentication.html).

## Start a notebook

After login → **Start My Server**. JupyterHub spawns a single-user pod (kubespawner), gives you a notebook UI. Each user gets a `claim-<user>` PVC for their files.

## Connect notebooks to in-cluster LLMs

In a notebook cell:

```python
import os
os.environ['OPENAI_API_KEY'] = 'sk-master-CHANGEME'
os.environ['OPENAI_BASE_URL'] = 'http://litellm-gateway.<ns>.svc.cluster.local:4000/v1'

from openai import OpenAI
client = OpenAI()
r = client.chat.completions.create(
    model='qwen-7b',
    messages=[{'role':'user','content':'explain pandas groupby'}],
)
print(r.choices[0].message.content)
```

To bake these env vars into every spawned notebook (so users don't have to set them), patch the inner HelmRelease's `singleuser.extraEnv`:

```yaml
singleuser:
  extraEnv:
    OPENAI_API_KEY: "sk-master-CHANGEME"   # ideally use a secret reference
    OPENAI_BASE_URL: "http://litellm-gateway.<ns>:4000/v1"
```

## GPU notebooks

The default `singleuser` profile is CPU-only. To add a GPU option, configure `singleuser.profileList`:

```yaml
singleuser:
  profileList:
    - display_name: "CPU"
      default: true
    - display_name: "GPU (1× NVIDIA)"
      kubespawner_override:
        extra_resource_limits:
          nvidia.com/gpu: "1"
        image: jupyter/tensorflow-notebook:python-3.11
```

Users pick a profile on **Start My Server**.

## Persistent user data

Per-user PVCs survive pod restarts. They are *not* deleted when a user is deleted from the hub DB — that's by design (data retention). To clean up: `kubectl get pvc -l hub.jupyter.org/username=<user>`.
