# WINGS3 manifests

Apply order for a fresh cluster (normally via `./install.sh`):

1. `mlflow-dev.yaml`, `namespace-my-first-model.yaml`
2. `secret-wings3-judge-llm.yaml` (from `secret-wings3-judge-llm.example.yaml`; patched by install)
3. `workbench-wings3-demo.yaml`
4. `inferenceservice-llama-32-3b-instruct.yaml` (after `WINGS3_LLM_STORAGE_URI` is set)
5. EvalHub: `configmap-wings3-llm-endpoint.yaml`, `evalhub-rbac-wings3.yaml`, `evalhub-instance.yaml`
6. MaaS prerequisites: `kuadrant-dev.yaml` (Connectivity Link / Authorino), `maas-default-gateway.yaml` (TLS + `redhat-ai-gateway-infra` allowed)
7. MaaS (demo lab Postgres + external judge model):
   - `maas-postgres-dev.yaml`
   - `maas-db-config-secret.yaml` (restart `maas-api` if MaaS was already Managed)
   - `secret-wings3-maas-upstream-api-key.yaml` (from `.example.yaml`; workshop upstream token)
   - `maas-external-model-gpt-oss-120b.yaml`
   - `maas-modelref-gpt-oss-120b.yaml`
   - `maas-auth-subscription-gpt-oss-120b.yaml`
8. Gen AI Studio (Playground + MCP Catalog browse):
   - `servicemesh3-operator.yaml`, `servicemesh3-istio.yaml` (Service Mesh 3.x — OGX prerequisite)
   - `ogx-postgres-dev.yaml`, `ogx-server-wings3.yaml` (after `ogx` DSC component is Ready)

## MaaS external model (gpt-oss-120b)

On RHOAI 3.5+, enable `spec.components.aigateway.modelsAsAService` (legacy `kserve.modelsAsService` cannot be re-enabled once Removed). Set `OdhDashboardConfig` `genAiStudio: true` and `modelAsService: true` (patched by `install.sh` when needed). MaaS judges do not require OGX. Install **Red Hat Connectivity Link** (Kuadrant + Authorino operators, then `Kuadrant` CR in `kuadrant-system`). `install.sh` applies `kuadrant-dev.yaml` when missing.

## Gen AI Studio (Playground + MCP Catalog)

`install.sh` runs `enable_genai_studio()` after MaaS:

1. **Service Mesh 3** (`servicemesh3-operator.yaml`) — prerequisite for OGX
2. **Llama Stack removal** — set `spec.components.llamastackoperator: Removed` (blocks OGX on RHOAI 3.5)
3. **OGX** — `spec.components.ogx: Managed` on DSC; wait for `ogxservers.ogx.io` CRDs (`ogx.io/v1beta1`, renamed from `llamastack.io/v1alpha1`)
4. **OGXServer** — `ogx-postgres-dev.yaml` + `ogx-server-wings3.yaml` in `my-first-model`
5. **MCP lifecycle** — `spec.components.mcplifecycleoperator: Managed`; enables MCP Catalog deploy gate
6. **Dashboard** — `genAiStudio`, `modelAsService`, `mcpCatalog: true`

MaaS and Playground are independent: judges use MaaS gateway; Playground uses OGXServer.

| File | Purpose |
|------|---------|
| `servicemesh3-operator.yaml` | SM3 subscription (uses existing `global-operators` OG) |
| `servicemesh3-istio.yaml` | `Istio` / `IstioCNI` CRs (after operator CSV Succeeded) |
| `ogx-postgres-dev.yaml` | Lab Postgres for OGX metadata |
| `ogx-server-wings3.yaml` | `OGXServer` wired to demo Llama 3.2 3B IS |

### Environment variables (Gen AI Studio)

| Variable | Default | Purpose |
|----------|---------|---------|
| `WINGS3_SKIP_OGX` | `0` | Skip Service Mesh + OGX + OGXServer |
| `WINGS3_SKIP_MCP` | `0` | Skip MCP lifecycle operator + `mcpCatalog` flag |
| `WINGS3_SKIP_SERVICEMESH` | `0` | Skip SM3 install (if pre-installed) |
| `WINGS3_OGX_SERVER_NAME` | `wings3-ogx` | OGXServer CR name |

Service Mesh and DSC `ogx` / `mcplifecycleoperator` are **not** removed by `uninstall.sh --all` (cluster-level). Demo `OGXServer` and ogx Postgres are purged.

Sandboxes without `maas-default-gateway` get one from `maas-default-gateway.yaml` (hostname copied from `openshift-ai-inference`, TLS cert auto-detected from router secret, namespace `redhat-ai-gateway-infra` allowed for `maas-api` routes). `maas-db-config` is required in both `redhat-ods-applications` and `redhat-ai-gateway-infra`. API key mint goes through `https://<gateway>/maas-api/v1/api-keys` with `oc whoami -t`.

Secret `wings3-judge-llm` sets both the **agent** (`MAAS_MODEL`, `MAAS_BASE_URL`, `MAAS_API_KEY`) and **judges** (`JUDGE_*`). On GPU clusters the example uses in-cluster llama; `install.sh` patches both to gpt-oss-120b on MaaS-only clusters. `wings3-llm-endpoint` ConfigMap is synced from `MAAS_*` for EvalHub/Garak. Judges call the in-cluster MaaS gateway, not the workshop URL directly. The workshop API key lives only in `wings3-maas-upstream-api-key` for the `ExternalModel`.

| File | Purpose |
|------|---------|
| `maas-postgres-dev.yaml` | Lab Postgres for MaaS API key storage (demo only, not HA) |
| `maas-db-config-secret.yaml` | `maas-db-config` with `DB_CONNECTION_URL` |
| `secret-wings3-maas-upstream-api-key.example.yaml` | Template for workshop upstream `api-key` |
| `maas-external-model-gpt-oss-120b.yaml` | `ExternalModel` → `maas-rhdp.apps.maas.redhatworkshops.io` |
| `maas-modelref-gpt-oss-120b.yaml` | Publish external model to MaaS |
| `maas-auth-subscription-gpt-oss-120b.yaml` | Subscription + auth policy for `system:authenticated` |

### Environment variables

| Variable | Purpose |
|----------|---------|
| `WINGS3_MAAS_UPSTREAM_API_KEY` | Workshop token for `ExternalModel` (else reuse existing `JUDGE_API_KEY` if still workshop direct) |
| `WINGS3_JUDGE_API_KEY` | Optional override for judge secret after install mints a MaaS key |

### UI verification (RHOAI 3.5)

- **Gen AI Studio → AI asset endpoints → Models tab** — external model **gpt-oss-120b** listed; **View** shows **Model as a Service** badge
- **Gen AI Studio → API keys** — create a key scoped to subscription `wings3-gpt-oss-120b`
- **Gen AI Studio → Playground** — create playground after `ogxserver/wings3-ogx` is Ready
- **Gen AI hub → MCP server** — catalog browse (deploy requires MCP lifecycle CRD; no demo deploy needed)

Inference URL shape on this cluster: `https://<gateway>/my-first-model/gpt-oss-120b/v1`.

```bash
oc get externalmodel gpt-oss-120b -n my-first-model
oc get maasmodelref gpt-oss-120b -n my-first-model
oc get secret wings3-judge-llm -n my-first-model -o jsonpath='{.data.JUDGE_BASE_URL}' | base64 -d; echo
```

`JUDGE_BASE_URL` must **not** contain `maas.redhatworkshops.io` after install.
