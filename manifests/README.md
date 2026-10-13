# WINGS manifests

Apply order for a fresh cluster (normally via `./install.sh`):

1. `mlflow-dev.yaml`, `namespace-my-first-model.yaml`
2. `secret-wings-judge-llm.yaml` (from `secret-wings-judge-llm.example.yaml`; patched by install)
3. `workbench-wings-demo.yaml`
4. `inferenceservice-llama-32-3b-instruct.yaml` (after `WINGS_LLM_STORAGE_URI` is set)
5. EvalHub: `configmap-wings-llm-endpoint.yaml`, `evalhub-rbac-wings.yaml`, `mlflow-workspace-proxy.yaml` (injects `X-MLflow-Workspace` — the EvalHub CR's `MLFLOW_TRACKING_URI` points at its Service), `evalhub-instance.yaml`
6. MaaS prerequisites: `connectivity-link-operator.yaml` (subscribes `rhcl-operator`), then `kuadrant-dev.yaml` (Kuadrant CR / Authorino), `maas-default-gateway.yaml` + `maas-default-gateway-config.yaml` (ClusterIP), `maas-default-gateway-route.yaml` (public Route for `maas-gateway.<apps-domain>`)
7. MaaS (demo lab Postgres + external judge model):
   - `maas-postgres-dev.yaml`
   - `maas-db-config-secret.yaml` (restart `maas-api` if MaaS was already Managed)
   - `secret-wings-maas-upstream-api-key.yaml` (from `.example.yaml`; workshop upstream token)
   - `maas-external-model-gpt-oss-120b.yaml`
   - `maas-modelref-gpt-oss-120b.yaml`
   - `maas-auth-subscription-redhat-maas.yaml`
8. Gen AI Studio (Playground + MCP Catalog browse):
   - `servicemesh3-operator.yaml`, `servicemesh3-istio.yaml` (Service Mesh 3.x — OGX prerequisite)
   - `ogx-postgres-dev.yaml`, `ogx-server-wings.yaml` (after `ogx` DSC component is Ready)
   - `openshift-mcp-server-config.yaml` (opt-in; apply before AI Hub MCP Catalog Deploy of openshift-mcp-server)
   - `gen-ai-aa-mcp-servers.yaml` (opt-in; after MCPServer Ready — registers server for Playground MCP tab)
9. LangGraph ReAct agent (after InferenceService Ready; skip with `WINGS_SKIP_AGENT=1`):
   - `agent-sandbox-operator.yaml` (Agent Sandbox operator in `agent-sandbox-system` — Tech Preview channel `preview-0.9`)
   - In-cluster build + Helm deploy of `langgraph-react-agent` from [agentic-starter-kits](https://github.com/red-hat-data-services/agentic-starter-kits) (`WINGS_AGENTIC_STARTER_KITS_REF`, default `rhoai-3.6`)
   - `agent-react-mlflow-rbac.yaml` (default SA → `mlflow-operator-mlflow-integration` for in-pod tracing)
   - `secret-wings-react-agent.example.yaml` → Secret `wings-react-agent`
   - `agent-react-sandbox.yaml` + `agent-react-sandbox-route.yaml` (AI Hub → Agents → Deployments)
   - `agent-profile-wings-react.yaml` (Playground → Load agent + AI asset endpoints → Agents)
10. Observability / token-consumption dashboard stack (runs as `enable_observability()` right after `enable_garak`, before the rest of `manifests/` — see below): `cluster-observability-operator.yaml`, `opentelemetry-operator.yaml`, `tempo-operator.yaml`, `loki-operator.yaml`, UWM `cluster-monitoring-config` merge, DSCI `monitoring.metrics`/`traces` patch, `maas-usage-logging-minio-secret.yaml`, `maas-usage-logging-minio.yaml`, `maas-usage-logging-lokistack.yaml`; MaaS telemetry + `usageLogging` + `limitador-redis.yaml`/`limitador-redis-secret.yaml` run later, inside `enable_maas()`

## Observability / token-consumption dashboard stack

`install.sh` calls `enable_observability()` after `enable_garak` and before
`apply_manifests`, then `enable_maas_observability()` inside `enable_maas()`.
Together these two steps add the per-request **Usage** (token consumption)
dashboard in OpenShift AI, on top of whatever observability RHOAI 3.5
already ships. Every piece has a matching `purge_*` function wired into
`uninstall.sh --all` via `purge_observability_resources` — a full uninstall
returns the cluster to its pre-install state.

| File | Purpose |
|------|---------|
| `cluster-observability-operator.yaml` | COO subscription in its own `openshift-cluster-observability-operator` namespace (Perses NetworkPolicy requires a dedicated namespace) |
| `opentelemetry-operator.yaml` | Red Hat build of OpenTelemetry subscription (`opentelemetry-product` channel) |
| `tempo-operator.yaml` | Tempo Operator subscription (`tempo-product` channel) — tracing backend for GenAI → Traces |
| `loki-operator.yaml` | Loki Operator subscription; `REPLACE_LOKI_CHANNEL` is substituted at apply time with the channel `discover_loki_channel()` resolves from the `redhat-operators` catalog (the community Grafana `loki-operator` package publishes a different, incompatible channel under the same name — must filter packagemanifests by `status.catalogSource`, not just `metadata.name`) |
| `cluster-monitoring-config.yaml` | Reference-only: documents the fresh-cluster shape of the User Workload Monitoring ConfigMap. The real merge logic lives in `merge_uwm_enabled_flag()` in `wings_lib.sh` so an existing `cluster-monitoring-config` (if any) isn't clobbered — only the `enableUserWorkload: true` line is added/removed |
| `maas-usage-logging-minio-secret.yaml` | S3 credentials Secret for the demo MinIO (LokiStack object storage backend) |
| `maas-usage-logging-minio.yaml` | PVC + Deployment + Service + bucket-create Job for a demo-only MinIO instance in `redhat-ods-monitoring` |
| `maas-usage-logging-lokistack.yaml` | `LokiStack` CR (`1x.demo` size class) backed by the MinIO Secret — stores per-request MaaS usage logs that the Usage dashboard reads |
| `limitador-redis.yaml` | Dev Redis Deployment/Service in `redis-limitador`, used as Limitador's persistent rate-limit counter backend |
| `limitador-redis-secret.yaml` | `redis-config` Secret in `kuadrant-system` (`configSecretRef` for the `Limitador` CR's `spec.storage.redis`) |

What each step actually does on the cluster:

- **DSCI patch** (`patch_dsci_observability_metrics`) — sets
  `spec.monitoring.metrics.storage` and `spec.monitoring.traces` on the
  `DSCInitialization`, which makes the RHOAI operator provision a
  MonitoringStack, Perses, and a ThanosQuerier (`wait_for_dsci_monitoring_ready`
  polls `MonitoringStackAvailable`).
- **Dashboard flag** — `ensure_genai_dashboard_prereqs()` also patches
  `OdhDashboardConfig` `spec.dashboardConfig.observabilityDashboard: true`,
  which is what makes the Usage/token-consumption tab appear in the console
  at all.
- **MaaS telemetry** (`enable_maas_tenant_telemetry`) — patches the
  `MaasTenantConfig` CR: `spec.telemetry.enabled: true`,
  `metrics.captureModelUsage: true`, `metrics.captureUser` controlled by
  `WINGS_MAAS_CAPTURE_USER` (**on by default**). The RHOAI-shipped "Usage"
  dashboard (`dashboard-3-maas-usage-admin`) hard-codes `user!=""` on every
  panel — including the plain totals, not just a per-user drill-down — so
  without this label Limitador's `authorized_hits_total` /
  `authorized_calls_total` / `limited_calls_total` metrics carry no `user`
  label and the whole dashboard reads 0, even though requests are being
  served and logged. Set `WINGS_MAAS_CAPTURE_USER=0` to opt out for
  privacy/cardinality-sensitive clusters (the Usage dashboard totals will
  then read 0 by RHOAI's own dashboard design — the per-request Loki usage
  logs under "Usage (logs)" are unaffected and still carry `user_id` either
  way).
- **MaaS usage logging** (`enable_maas_usage_logging`) — patches
  `configs.maas.opendatahub.io` `spec.usageLogging: true`, which tells the
  gateway to emit the per-request logs the LokiStack above stores.
- **Limitador Redis** (`ensure_limitador_redis`) — patches the `Limitador` CR
  `spec.storage.redis.configSecretRef` so rate-limit counters survive pod
  restarts (the operator default is in-memory, which resets on every
  Limitador restart).

### Environment variables (observability)

| Variable | Default | Purpose |
|----------|---------|---------|
| `WINGS_SKIP_OBSERVABILITY` | `0` | Skip the entire stack (COO/OTel/Tempo/Loki, UWM, DSCI patch, MinIO+LokiStack, Redis Limitador, MaaS telemetry/usageLogging) |
| `WINGS_MAAS_CAPTURE_USER` | `1` | Set to `0` to disable per-user labelling on MaaS token metrics (Usage dashboard totals will then read 0 — see above) |
| `WINGS_COO_NAMESPACE` / `WINGS_OTEL_NAMESPACE` / `WINGS_TEMPO_NAMESPACE` / `WINGS_LOKI_OPERATOR_NAMESPACE` / `WINGS_REDIS_LIMITADOR_NAMESPACE` / `WINGS_MONITORING_NAMESPACE` / `WINGS_DSCI_NAME` | see `wings_lib.sh` | Override namespaces/names if they conflict with an existing install |

### UI verification (RHOAI 3.5)

- **Observe → Usage** (or the equivalent token-consumption dashboard entry) —
  shows per-model/per-tenant token counts once a few MaaS inference calls
  have been made (the dashboard is empty until there's traffic through the
  gateway).
- `oc get lokistack usage -n redhat-ods-monitoring` — `Ready=True`
- `oc get dsci default-dsci -o jsonpath='{.status.conditions[?(@.type=="MonitoringStackAvailable")].status}'` — `True`

### Shared-namespace safety (openshift-operators-redhat)

`loki-operator.yaml` installs into `openshift-operators-redhat`, a Red
Hat-conventional namespace that other, unrelated operators on a cluster may
already use. Install and uninstall never assume WINGS owns this namespace:

- `apply_operator_manifest_ns_aware` (install) only applies the Namespace
  document — and takes ownership (`app.kubernetes.io/part-of: wings-demo`
  label) — if the namespace doesn't already exist. If it pre-exists, only
  the OperatorGroup/Subscription are applied into it.
- `purge_operator_manifest_ns_aware` (uninstall) only deletes the namespace
  itself if it carries that WINGS-owned label. Otherwise it strips back just
  the OperatorGroup/Subscription WINGS added, leaving the (shared) namespace
  and anything else in it untouched.

The same helpers are used for the COO/OpenTelemetry/Tempo operator
namespaces as a defensive measure, even though those are less likely to be
shared in practice.

### Uninstall symmetry

`uninstall.sh --all` calls `purge_observability_resources`, which reverts
every step above in reverse: `purge_maas_tenant_telemetry`,
`purge_maas_usage_logging`, `purge_limitador_redis` (nulls
`Limitador.spec.storage`, deletes the Redis Deployment/Secret),
`purge_usage_logging_backend` (deletes the LokiStack/MinIO/MinIO-secret
manifests), `revert_dsci_observability_metrics` (nulls the DSCI
metrics/traces patch back out), `purge_observability_operators` (deletes the
COO/OTel/Tempo/Loki namespaces, which removes their CSVs too), and
`revert_user_workload_monitoring` (deletes `cluster-monitoring-config` if
WINGS created it from scratch, or surgically removes just the
`enableUserWorkload` line if the ConfigMap pre-existed).

## MaaS external model (gpt-oss-120b)

On RHOAI 3.5+, enable `spec.components.aigateway.modelsAsAService` (legacy `kserve.modelsAsService` cannot be re-enabled once Removed). Set `OdhDashboardConfig` `genAiStudio: true`, `modelAsService: true`, and `guardrails: true` (patched by `install.sh` when needed; Guardrails tab in Gen AI Studio Playground is Technology Preview and off by default). MaaS judges do not require OGX. Install **Red Hat Connectivity Link**: `install.sh` subscribes `rhcl-operator` from `redhat-operators` (via `connectivity-link-operator.yaml`) when `kuadrants.kuadrant.io` is missing, waits for the CRD, then applies `kuadrant-dev.yaml` (`Kuadrant` CR in `kuadrant-system`).

## Gen AI Studio (Playground + MCP Catalog)

`install.sh` runs `enable_genai_studio()` after MaaS:

1. **Service Mesh 3** (`servicemesh3-operator.yaml`) — prerequisite for OGX
2. **Llama Stack removal** — set `spec.components.llamastackoperator: Removed` (blocks OGX on RHOAI 3.5)
3. **OGX** — `spec.components.ogx: Managed` on DSC; wait for `ogxservers.ogx.io` CRDs (`ogx.io/v1beta1`, renamed from `llamastack.io/v1alpha1`)
4. **OGXServer** — `ogx-postgres-dev.yaml` + `ogx-server-wings.yaml` in `my-first-model`
5. **MCP lifecycle** — `spec.components.mcplifecycleoperator: Managed`; enables MCP Catalog deploy gate
6. **Dashboard** — `genAiStudio`, `modelAsService`, `mcpCatalog`, `guardrails`, `agentsCatalog` (AI Hub → Agents), `agentOps`, `agentConfigManagement`, `aiAssetCustomEndpoints: true`

MaaS and Playground are independent: judges use MaaS gateway; Playground uses OGXServer.

Before **AI Hub → MCP servers → Catalog → Deploy** of `openshift-mcp-server`, apply `openshift-mcp-server-config.yaml` in the target project (default `my-first-model`). The MCP lifecycle operator requires that ConfigMap (`config.toml` key) or the deploy stays `Accepted=False`. Not applied by `install.sh`.

Catalog Deploy runs the server but does **not** put it in Playground. After `MCPServer` is Ready (`oc get mcpserver -n my-first-model`), apply `gen-ai-aa-mcp-servers.yaml` (ConfigMap in `redhat-ods-applications`). Then in **Gen AI studio → Playground** → Settings → **MCP**: select the server → **Auth** (token optional for this in-cluster server) → confirm Connection successful → **View tools**. Prefer a tool-calling model; Llama 3.2 3B often fails silently at tool use. `oc apply` of that file replaces the whole ConfigMap `data` map — merge keys if other MCP entries exist. Not applied by `install.sh`.

| File | Purpose |
|------|---------|
| `servicemesh3-operator.yaml` | SM3 subscription (uses existing `global-operators` OG) |
| `servicemesh3-istio.yaml` | `Istio` / `IstioCNI` CRs (after operator CSV Succeeded) |
| `ogx-postgres-dev.yaml` | Lab Postgres for OGX metadata |
| `ogx-server-wings.yaml` | `OGXServer` wired to demo Llama 3.2 3B IS |
| `openshift-mcp-server-config.yaml` | ConfigMap `openshift-mcp-server-config` (`config.toml`) for catalog deploy of openshift-mcp-server |
| `gen-ai-aa-mcp-servers.yaml` | ConfigMap `gen-ai-aa-mcp-servers` — registers in-cluster MCP URL for Playground MCP tab |

### Environment variables (Gen AI Studio)

| Variable | Default | Purpose |
|----------|---------|---------|
| `WINGS_SKIP_OGX` | `0` | Skip Service Mesh + OGX + OGXServer |
| `WINGS_SKIP_MCP` | `0` | Skip MCP lifecycle operator + `mcpCatalog` flag |
| `WINGS_SKIP_SERVICEMESH` | `0` | Skip SM3 install (if pre-installed) |
| `WINGS_OGX_SERVER_NAME` | `wings-ogx` | OGXServer CR name |

Service Mesh and DSC `ogx` / `mcplifecycleoperator` are **not** removed by `uninstall.sh --all` (cluster-level). Demo `OGXServer` and ogx Postgres are purged.

## LangGraph ReAct agent (AI Hub / Playground)

`install.sh` calls `deploy_react_agent()` after `install_llm`. Presenter machine needs `helm`, `git`, and `make` in addition to `oc`.

1. Install **Agent Sandbox operator** (`agent-sandbox-operator.yaml`) and wait for `sandboxes.agents.x-k8s.io`
2. Apply **MLflow RBAC** (`agent-react-mlflow-rbac.yaml`) so the namespace `default` SA can log traces
3. Clone [agentic-starter-kits](https://github.com/red-hat-data-services/agentic-starter-kits) into `.cache/agentic-starter-kits` (gitignored)
4. In-cluster `make build-openshift` + `make deploy` for `agents/langgraph/templates/react_agent`, with `BASE_URL` pointing at `llama-32-3b-instruct-predictor`, `MODEL_ID=llama-32-3b-instruct`, and in-pod `MLFLOW_*` (kubernetes-namespaced auth)
5. Apply Sandbox + Route (Hub Deployments) and AgentProfile ConfigMap (Playground Load agent / AI asset endpoints)

Standalone: `./scripts/install_react_agent.sh` / `./scripts/uninstall_react_agent.sh` (`--operator` also removes the operator Subscription).

| File | Purpose |
|------|---------|
| `agent-sandbox-operator.yaml` | NS + OperatorGroup + Subscription (`preview-0.9`) |
| `agent-react-mlflow-rbac.yaml` | RoleBinding `default` SA → `mlflow-operator-mlflow-integration` |
| `secret-wings-react-agent.example.yaml` | Agent `api-key` (default `not-needed`) |
| `agent-react-sandbox.yaml` | `Sandbox` `wings-react-agent-sbx` with `opendatahub.io/dashboard=true` + MLflow env |
| `agent-react-sandbox-route.yaml` | Route named after the Sandbox (dashboard Ready check) |
| `agent-profile-wings-react.yaml` | AgentProfile ConfigMap for Load agent / AI asset endpoints |

| Variable | Default | Purpose |
|----------|---------|---------|
| `WINGS_SKIP_AGENT` | `0` | Skip operator + agent build/deploy + Hub registration |
| `WINGS_AGENTIC_STARTER_KITS_REF` | `rhoai-3.6` | Git branch/tag to clone |
| `WINGS_AGENTIC_STARTER_KITS_URL` | GitHub URL above | Override clone URL |
| `WINGS_AGENTIC_STARTER_KITS_DIR` | `.cache/agentic-starter-kits` | Pre-populated or alternate checkout |
| `WINGS_REACT_AGENT_MLFLOW_EXPERIMENT` | `wings-react-agent` | MLflow experiment for Helm/Sandbox agent traces |

### MLflow traces (Helm / Sandbox traffic)

Traces appear only for requests that hit the **deployed ReAct agent** (Helm Route or Sandbox), not for Playground **Load agent** (that path talks to the InferenceService model URI via Gen AI Studio).

1. Standalone `/mlflow` → workspace **`my-first-model`**
2. Experiment **`wings-react-agent`** → **Traces** → open a row → **Details & Timeline**

Smoke test after deploy:

```bash
ROUTE=$(oc get route langgraph-react-agent -n my-first-model -o jsonpath='{.spec.host}')
curl -sk "https://${ROUTE}/v1/chat/completions" -H 'Content-Type: application/json' \
  -d '{"model":"llama-32-3b-instruct","messages":[{"role":"user","content":"What is 2+2?"}]}'
```

### UI verification

- **AI Hub → Agents → Deployments** — **WINGS ReAct Agent** (`sandbox/wings-react-agent-sbx`)
- **Gen AI studio → Playground → Load agent** — profile **WINGS ReAct Agent**
- **Gen AI studio → AI asset endpoints → Agents** — same profile
- Helm Route: `oc get route langgraph-react-agent -n my-first-model` then `curl https://<host>/health`
- MLflow: experiment `wings-react-agent` after a Helm/Sandbox chat request (see above)

`uninstall.sh` always removes the agent workload (including MLflow RoleBinding). `uninstall.sh --all` also removes the wings-owned Agent Sandbox operator Subscription (and namespace if WINGS created it).

Sandboxes without `maas-default-gateway` get one from `maas-default-gateway.yaml` (TLS cert auto-detected, namespace `redhat-ai-gateway-infra` allowed for `maas-api` routes). ClusterIP gateways are exposed via `maas-default-gateway-route.yaml` on **`maas-gateway.<apps-domain>`** (not `inference-gateway.*` — that name is usually claimed by the `openshift-ai-inference` LoadBalancer DNSRecord). Reencrypt Routes require clearing the Gateway HTTPS hostname filter (SNI mismatch). Without the Route, external mint/inference probes time out. Judge URLs use HTTPRoute paths `/{project}/{model}/v1` (not `/llm/...`). `maas-db-config` is required in both `redhat-ods-applications` and `redhat-ai-gateway-infra`. API key mint goes through `https://<gateway>/maas-api/v1/api-keys` with `oc whoami -t` (port-forward fallback injects Authorino identity headers).

Secret `wings-judge-llm` sets both the **agent** (`MAAS_MODEL`, `MAAS_BASE_URL`, `MAAS_API_KEY`) and **judges** (`JUDGE_*`). On GPU clusters the example uses in-cluster llama; `install.sh` patches both to gpt-oss-120b on MaaS-only clusters. `wings-llm-endpoint` ConfigMap is synced from `MAAS_*` for EvalHub/Garak. Judges call the in-cluster MaaS gateway, not the workshop URL directly. The workshop API key lives only in `wings-maas-upstream-api-key` (shared by all ExternalModels) — inject via `WINGS_MAAS_UPSTREAM_API_KEY` or a gitignored local yaml; never commit real keys. Label that Secret `inference.llm-d.ai/ipp-managed=true` so the gateway IPP can inject it (Playground fails with `authType 'apikey' credentials not found` without it).

| File | Purpose |
|------|---------|
| `maas-postgres-dev.yaml` | Lab Postgres for MaaS API key storage (demo only, not HA) |
| `maas-db-config-secret.yaml` | `maas-db-config` with `DB_CONNECTION_URL` |
| `secret-wings-maas-upstream-api-key.example.yaml` | Template for workshop upstream `api-key` (`ipp-managed` + `bbr-managed` labels; gitignored copy holds the real value) |
| `maas-external-model-gpt-oss-120b.yaml` | `ExternalModel` → workshop host (`targetModel: gpt-oss-120b`) |
| `maas-external-model-gpt-oss-20b.yaml` | `ExternalModel` → same host / shared credential (`gpt-oss-20b`) |
| `maas-external-model-llama-scout-17b.yaml` | `ExternalModel` → same host / shared credential (`llama-scout-17b`) |
| `maas-external-model-qwen36-35b-a3b.yaml` | `ExternalModel` → same host / shared credential (`qwen36-35b-a3b`) |
| `maas-modelref-*.yaml` | Publish each external model to MaaS — `install.sh` applies one per id in `WINGS_MAAS_CATALOG_MODELS` (filenames constructed dynamically, so grep won't find them referenced) |
| `maas-auth-subscription-redhat-maas.yaml` | Subscription + auth policy for all four modelRefs |

### Environment variables

| Variable | Purpose |
|----------|---------|
| `WINGS_MAAS_UPSTREAM_API_KEY` | Workshop token for **all** ExternalModels (shared Secret) |
| `WINGS_MAAS_CATALOG_MODELS` | Space-separated catalog ids (default: `gpt-oss-120b gpt-oss-20b llama-scout-17b qwen36-35b-a3b`) |
| `WINGS_JUDGE_API_KEY` | Optional override for judge secret after install mints a MaaS key |

### UI verification (RHOAI 3.5)

- **Gen AI Studio → AI asset endpoints → Models tab** — **gpt-oss-120b**, **gpt-oss-20b**, **llama-scout-17b**, **qwen36-35b-a3b**; **View** shows **Model as a Service** badge
- **Gen AI Studio → API keys** — create a key scoped to subscription `redhat-maas`
- **Gen AI Studio → Playground** — create playground after `ogxserver/wings-ogx` is Ready
- **Gen AI hub → MCP server** — catalog browse (deploy requires MCP lifecycle CRD; no demo deploy needed)

Inference URL shape on this cluster: `https://<gateway>/my-first-model/<model>/v1`.

```bash
oc get externalmodel -n my-first-model
oc get maasmodelref -n my-first-model
oc get secret wings-judge-llm -n my-first-model -o jsonpath='{.data.JUDGE_BASE_URL}' | base64 -d; echo
```

`JUDGE_BASE_URL` must **not** contain `maas.redhatworkshops.io` after install (in-cluster gateway preferred; workshop fallback is OK for notebooks when gateway probe fails).
