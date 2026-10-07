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

| File | Purpose |
|------|---------|
| `servicemesh3-operator.yaml` | SM3 subscription (uses existing `global-operators` OG) |
| `servicemesh3-istio.yaml` | `Istio` / `IstioCNI` CRs (after operator CSV Succeeded) |
| `ogx-postgres-dev.yaml` | Lab Postgres for OGX metadata |
| `ogx-server-wings.yaml` | `OGXServer` wired to demo Llama 3.2 3B IS |

### Environment variables (Gen AI Studio)

| Variable | Default | Purpose |
|----------|---------|---------|
| `WINGS_SKIP_OGX` | `0` | Skip Service Mesh + OGX + OGXServer |
| `WINGS_SKIP_MCP` | `0` | Skip MCP lifecycle operator + `mcpCatalog` flag |
| `WINGS_SKIP_SERVICEMESH` | `0` | Skip SM3 install (if pre-installed) |
| `WINGS_OGX_SERVER_NAME` | `wings-ogx` | OGXServer CR name |

Service Mesh and DSC `ogx` / `mcplifecycleoperator` are **not** removed by `uninstall.sh --all` (cluster-level). Demo `OGXServer` and ogx Postgres are purged.

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
