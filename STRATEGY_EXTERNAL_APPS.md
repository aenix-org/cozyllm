# Cozystack External Apps — стратегия и AI-кластер вокруг CozyLLM

> Контекст: обсуждение 2026-05-26. CozyLLM — первое внешнее приложение для Cozystack. На фоне свежеопубликованного скилла `/cozystack:external-app-create` (плагин cozystack/ccp) и доки `cozystack.io/docs/v1.3/applications/external` появилась возможность расти не как одиночное приложение, а как тематический кластер apps вокруг GPU/AI use-case.

## 1. Почему внешний репозиторий, а не core Cozystack

Решение — оставить vLLM-инференс **во внешнем репо** (`aenix-org/cozyllm`), не вносить в `cozystack/cozystack`. Три причины:

1. **vLLM апдейтится быстрее core.** Релизы vLLM каждые 1–2 недели, релизы Cozystack каждые ~3 месяца. Внутри core версия будет устаревать. Внешний репо позволяет догонять upstream без оглядки на release cycle Cozystack.
2. **GPU — опциональная фича, не universal.** В core должны быть только вещи, работающие на любой инсталляции. GPU-нода — это конкретный customer profile, не базовый.
3. **CozyLLM — прецедент для будущего marketplace.** Если первое же стороннее приложение втянуть в core, никто не будет делать внешние, паттерн умрёт в зародыше.

В core имеет смысл переносить только то, что **универсально и стабильно**. vLLM — ни то, ни другое.

---

## 2. Подход к marketplace — снизу вверх

**Главная ошибка, которую избегаем:** строить marketplace UI и каталог до того, как есть пять приложений и обкатанная спецификация. Через год получишь marketplace с двумя приложениями, написанными самой командой.

Правильная последовательность:

### Этап 1. Спецификация (✅ уже есть)

Документ `cozystack.io/docs/v1.3/applications/external` определяет:
- Структура репы (`init.yaml`, `packages/core/platform/`, `packages/apps/<name>/`)
- ApplicationDefinition CRD: kind/singular/plural, openAPISchema (без `if/then/else`), chartRef к HelmChart в `cozy-public`, prefix, dashboard metadata
- FluxCD bootstrap (GitRepository + HelmRelease)
- HelmChart с `reconcileStrategy: Revision` для статичных `version: 0.0.0`
- Operator deployment через отдельный `HelmRepository` в `external-<op>-operator` namespace
- Naming-конвенции (PascalCase Kind, lowercase singular/plural, hyphenated prefix)

Reference implementation: `cozystack/external-apps-example` (minecraft-server + minecraft-plugin).

### Этап 2. Scaffold-tool (✅ уже есть)

Claude Code скилл `/cozystack:external-app-create` в плагине `cozystack/ccp` — 10 фаз: парсит args, делает pre-flight, собирает app spec, резолвит deps против `packages/system/<dep>-rd/cozyrds/<dep>.yaml`, выбирает Pattern A/B/C, презентует план, генерит chart skeleton + templates, апдейтит пять platform-файлов, валидирует.

Поддерживаемые dependency patterns:
- **Pattern C** (рекомендуется): app chart emits `apps.cozystack.io/v1alpha1` CR (Postgres, Redis, …); cozystack reconciles it. Шарит mонiтoринг, бэкапы, миграции с tenant-инстансами этого же сервиса.
- **Pattern A** (system-style escape hatch): in-chart operator CR (CNPG `Cluster`, Spotahome `RedisFailover`). Используется когда cozystack ApplicationDefinition недоступен или app system-scoped (harbor, keycloak).
- **Pattern B**: external reference — пользователь сам провижнит сервис, передаёт connection details через values.

Инструмент-зависимости скилла: `yq` v4, `jq`, `base64`, `helm`, `cozyvalues-gen`. Последний — критичный, без него скилл бейлит в Phase 2.

### Этап 3. Flagship-приложения (в работе)

Не пытаемся сразу покрыть все категории. Делаем **одну тему сильно** — AI/ML вокруг существующего CozyLLM.

Roadmap:
1. **vllm-inference** (✅ deployed, MVP, нужны фиксы — см. §4).
2. **litellm** (✅ deployed, унифицированный OpenAI gateway, Pattern C Postgres).
3. **cozy-comfyui** (планируется) — image generation, GPU, ComfyUI или Stable Diffusion WebUI.
4. **cozy-jupyterhub** (планируется) — multi-user JupyterHub для ML-команд, Pattern C Postgres, OIDC через Keycloak.
5. **cozy-langflow** или **cozy-n8n** (планируется) — workflow-builder поверх vLLM endpoints.

После 4–5 рабочих apps в одной теме станет понятно:
- Где спека не покрывает реальные кейсы (GPU resource declarations, MIG-партиции, multi-namespace).
- Какие dependency patterns ещё нужны (Kafka? ClickHouse? S3 как dep, а не как PVC?).
- Какие boilerplate-фрагменты повторяются — кандидаты на helper templates / shared chart library.

### Этап 4. Хостинг каталога — ArtifactHub, не своё

ArtifactHub уже поддерживает custom kinds (Tekton Tasks, CoreDNS Plugins, OLM Operators). Регистрируем `Cozystack App` как новый kind, индексируется автоматически из репозиториев с правильным метафайлом. **Свой UI каталога не строить, пока приложений меньше ~50.**

### Этап 5. Discovery в дашборде Cozystack — одна кнопка

В UI: «Browse community apps» → ведёт на `cozystack.io/apps` (статичная Hugo-страница со списком, отрендеренная из ArtifactHub API). Не embedded marketplace внутри UI — просто внешний линк. Работает с первого дня без UI-разработки.

### Этап 6. Verified publishers — позже

Раздел «verified» (aenix-org, партнёры) vs community появляется, когда есть 10+ внешних приложений и начинаются вопросы про trust/security. Сейчас рано.

---

## 3. AI-кластер: тематика и обоснование

Почему именно AI/ML вокруг CozyLLM, а не «грибами в разные стороны»:

- **Уже есть GPU-инфра** на `tenant-client123` — vLLM работает. Накатить рядом ComfyUI / JupyterHub / Langflow дешевле, чем разводить новый бренчинг.
- **AI-аудитория сейчас на пике** — конверсия в установку и звёзды на GitHub выше, чем у любой другой темы 2026 года.
- **Cluster-эффект**: пять приложений одной темы укрепляют друг друга в дашборде. Пользователь, поставивший vLLM, видит рядом ComfyUI и думает «о, и это попробую». Десять разрозненных apps таких связок не создают.
- **Тестовый стенд для спецификации**: GPU-апликации лучше всего вскроют что в текущей external-app спеке не предусмотрено (resource requests/limits для GPU, runtimeClassName, node selectors).

### Сценарий «один тенант = один AI-стек»

```
tenant-client123/
├── vllm-inference (Llama 3.1 70B)        ← inference backend
├── vllm-inference (Qwen 2.5 7B)          ← lightweight backend
├── litellm                               ← unified API gateway
├── cozy-comfyui                          ← image generation
├── cozy-jupyterhub                       ← exploration & experimentation
└── cozy-langflow                         ← visual workflow builder
```

Всё через дашборд Cozystack, без `kubectl`, без `helm install`, без YAML-ручек со стороны клиента.

---

## 4. Текущее состояние CozyLLM vs скилл-спека

Аудит 2026-05-26 показал, что текущая реализация **в основном соответствует** спецификации внешних apps, но есть мелкие расхождения, которые стоит подравнять при следующих коммитах:

### Соответствует

- ✅ Структура репы: `init.yaml`, `packages/core/platform/`, `packages/apps/{vllm-inference,litellm}/`, `scripts/package.mk`.
- ✅ FluxCD bootstrap: GitRepository (`cozyllm` — параметрический, скилл извлекает через `yq`) + HelmRelease на platform chart.
- ✅ HelmChart naming: `cozyllm-vllm-inference`, `cozyllm-litellm` (схема `$GIT_REPO_NAME-$APP_NAME`).
- ✅ `ApplicationDefinition.release.chartRef.kind: HelmChart`, namespace `cozy-public`.
- ✅ Label `cozystack.io/ui: "true"`.
- ✅ Category `PaaS`, dashboard metadata (singular, plural, description, tags, icon в base64).
- ✅ LiteLLM использует **Pattern C** для Postgres (`apps.cozystack.io/v1alpha1`) — корректный путь для external app.

### Требует доработки

| Что | Где | Спека требует |
| --- | --- | --- |
| Нет `title: "Chart Values"` в openAPISchema | `cozyrds.yaml`, обе ApplicationDefinition | Спека: "The `openAPISchema` title must always be `\"Chart Values\"`." |
| openAPISchema формат | Сейчас multi-line block scalar `\|` | Спека показывает single-line JSON string. Возможно работают оба, но reference repo (minecraft) использует single-line. |
| `litellm/templates/postgres.yaml` минималистичен | Только `replicas` | Pattern C-postgres должен передавать `size`, `users`, `databases`, optional `storageClass`. Текущая форма работает, но не использует cozystack-postgres backup/quota/migration возможности. |
| Нет README на верхнем уровне репы | `~/claude/cozyllm/README.md` | Документация — пререквизит публикации. |
| Репо приватный | `aenix-org/cozyllm` | Marketplace кейс требует public. |

### Прочее наследие

- ✅ S3-кэш весов через Cozystack Bucket (`vllm-inference/templates/bucket.yaml`).
- ✅ `gpuEnabled` флаг для CPU-only тестов (commit `d0753a2`, паред с этим commit'ом — values.yaml).
- ⚠️ Версия `vllm-inference` `0.1.0` / appVersion `0.6.6` — vLLM сейчас далеко вперёд, нужно синкать.
- ⚠️ Нет CI: helm lint, schema validation, версионирование чартов.

---

## 5. План действий

### Сейчас (без скилла)

1. ✅ Эта стратегия записана.
2. Закоммитить незакломмиченный `gpuEnabled: true` в `values.yaml` (паред с commit `d0753a2`).
3. Заполнить deltас по спеке (`title: "Chart Values"`, расширить `litellm/postgres.yaml`) — отдельным коммитом, чтобы не смешивать.

### После установки скилла + cozyvalues-gen

Для каждого из трёх новых apps подготовить точные invocations:

```text
/cozystack:external-app-create cozy-comfyui \
  --repo-dir=/home/tym83/claude/cozyllm

/cozystack:external-app-create cozy-jupyterhub \
  --depends-on=postgres \
  --operator=https://hub.jupyter.org/helm-chart/ \
  --repo-dir=/home/tym83/claude/cozyllm

/cozystack:external-app-create cozy-langflow \
  --depends-on=postgres \
  --repo-dir=/home/tym83/claude/cozyllm
```

> Точные args (особенно `--operator` для ComfyUI и chart source для Langflow) — окончательно определяются в Phase 3 диалоге скилла на основе ответов о chart source и icon.

### Перед публикацией

1. README.md на верхнем уровне — что такое CozyLLM, что внутри, как ставить, ссылка на спеку external apps.
2. CI workflow: `helm lint` всех чартов + `yq e '.' packages/core/platform/templates/cozyrds.yaml` + `helm template` платформенного чарта.
3. Перевести репо в public.
4. Объявление в Cozystack Slack `#cozystack` + блог-пост на cozystack.io.

---

## 6. Что НЕ делать сейчас

- ❌ Втягивать vLLM в core Cozystack.
- ❌ Строить собственный UI marketplace до 10+ apps.
- ❌ Расширяться в темы вне AI/ML (storage, networking, security) до того, как AI-кластер обкатан.
- ❌ Добавлять categories в дашборд (PaaS уже есть, новые категории создают фрагментацию).
- ❌ Заводить shared chart library / helper templates — преждевременно, пока spec себя не показал на 5 разных apps.

---

## 7. Источники

- Скилл: `https://github.com/cozystack/ccp/tree/main/plugins/cozystack/skills/external-app-create`
- Reference example: `https://github.com/cozystack/external-apps-example`
- Документация: `https://cozystack.io/docs/v1.3/applications/external`
- Установка плагина:
  ```
  /plugin marketplace add cozystack/ccp
  /plugin install cozystack@cozystack-claude-plugins
  ```
- `cozyvalues-gen` release: `https://github.com/cozystack/cozyvalues-gen/releases/latest`

---

_Документ обновляется по ходу работ. История версий — в git log._
