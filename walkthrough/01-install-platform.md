# Module 1 — Install platform (MLflow + EvalHub + Garak)

**Time:** 10 minutes live (operators pre-enabled) | **Role:** Platform engineer  
**Where:** Laptop terminal (`oc get` only), standalone MLflow UI (`/mlflow`), RHOAI console (EvalHub)

## Know

WINGS3 installs three platform layers on OpenShift AI:

| Layer | DSC component (typical) | What it gives you |
|-------|-------------------------|-------------------|
| **MLflow** | `mlflowoperator` (patch to `Managed` on 3.5 even if absent from stored spec) | Tracking server, traces, experiments, judges |
| **EvalHub** | `evalhuboperator` (3.4) or `trustyai` (3.5) | K8s orchestration for evaluation jobs |
| **Garak** | `garakoperator` or EvalHub provider only (3.5) | Adversarial red-team scans via EvalHub |

Pre-stage with `./scripts/install.sh` (or `./install.sh` from repo root). On camera: **prove** each layer with `oc get` and the console — do not cold-install operators on stage.

| Term | What it is |
|------|------------|
| **Project** | OpenShift namespace `my-first-model` (dashboard) |
| **Workspace** | MLflow's name for that same project (`MLFLOW_WORKSPACE`) |
| **Experiment** | A named bucket inside the workspace (`wings3-agent-tracing` vs `wings3-agent-eval`) |
| **EvalHub job** | Platform evaluation run (lm-eval-harness, Garak, …) against a model endpoint |

**On stage:** pre-enable `Managed` and pre-apply manifests (see [00-presenter-setup.md](00-presenter-setup.md)). Live: `oc get` only for CRs and pods, then open `/mlflow` and EvalHub in the console.

### Where is MLflow in OpenShift AI 3.5?

Three surfaces. Live nav label is **Experiments** (Red Hat docs: **Experiments (MLflow)**).

| Surface | Path | What you get |
|---------|------|--------------|
| **Embedded dashboard** | Project → **Develop & train → Experiments** | Act 2 **Traces** (experiment → workflow **GenAI** → **Traces**). Act 3 run compare (**Model training** → Runs) |
| **Standalone MLflow app** | **Applications → Launch MLflow** or `https://<dashboard-host>/mlflow` | Datasets, Judges, full GenAI Evaluation (Acts 3–4) |
| **Workbench SDK** | `opendatahub.io/mlflow-instance=mlflow` on the Notebook | Logging from Jupyter — no in-notebook UI |

No extra toggle for the embedded view: `mlflowoperator: Managed` + `MLflow` CR named `mlflow`.

The old `OdhDashboardConfig.spec.dashboardConfig.mlflow` feature flag is **deprecated** (since 3.4) and has no effect.

If the pod is `Running` but **Applications** has no MLflow tile, open `mlflow_ui` from [partials/_attributes.md](partials/_attributes.md) and pick workspace **`my-first-model`**.

## Show

Values: [partials/_attributes.md](partials/_attributes.md).

### 1. Confirm MLflow operator (pre-staged)

```bash
oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.mlflowoperator.managementState}{"\n"}'
```

**Expected:** `Managed`

Off-camera enable if needed:

```bash
oc patch datasciencecluster default-dsc --type=merge \
  -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Managed"}}}}'
```

```bash
oc get pods -n redhat-ods-applications | grep mlflow-operator
```

### 2. Confirm MLflow CR and server pod (pre-applied)

```bash
oc get mlflow -n redhat-ods-applications
oc get pods -n redhat-ods-applications -l app=mlflow
```

On camera: `oc get` only — do **not** `oc apply` the CR live.

### 3. Confirm EvalHub operator (pre-staged)

Confirm EvalHub operator state (on RHOAI 3.5 the component is `trustyai`):

```bash
# 3.4 example:
oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.evalhuboperator.managementState}{"\n"}'

# 3.5 example (EvalHub under TrustyAI):
oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.trustyai.managementState}{"\n"}'
```

Off-camera enable (`install.sh` does this automatically):

```bash
oc patch datasciencecluster default-dsc --type=merge \
  -p '{"spec":{"components":{"evalhuboperator":{"managementState":"Managed"}}}}'

# RHOAI 3.5 — if discover printed trustyai:
oc patch datasciencecluster default-dsc --type=merge \
  -p '{"spec":{"components":{"trustyai":{"managementState":"Managed"}}}}'
```

```bash
oc get pods -n redhat-ods-applications | grep -i evalhub
```

**Expected:** an EvalHub operator or server pod `Running`. If the DSC has no EvalHub component, skip live and use screenshot fallbacks for Act 5.

### 4. Confirm Garak pipeline / provider (pre-staged)

```bash
oc get pods -n redhat-ods-applications | grep -i garak
```

If a separate `garakoperator` DSC component exists, confirm it the same way as EvalHub. Garak may also appear only as an **EvalHub provider** after EvalHub is Ready — check the console:

OpenShift AI → project `my-first-model` → **EvalHub** → providers list includes **Garak** and **lm-eval-harness**.

### 5. Confirm demo project and endpoint ConfigMap (pre-staged)

```bash
oc get namespace my-first-model --show-labels | grep opendatahub.io/dashboard
oc get configmap wings3-llm-endpoint -n my-first-model
```

**Expected endpoint** (in-cluster):

```text
http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1
```

### 6. Confirm MLflow UI surfaces

**Embedded (Act 2 Traces):** project `my-first-model` → **Develop & train → Experiments** → `wings3-agent-tracing` → workflow **GenAI** → **Traces**.

**Standalone (Acts 3–4, Datasets, Judges):** **Applications → Launch MLflow** → workspace **`my-first-model`**, or paste `mlflow_ui` from [partials/_attributes.md](partials/_attributes.md).

```bash
MLFLOW_UI='https://…/mlflow'
curl -skL -o /dev/null -w "%{http_code}\n" "${MLFLOW_UI}/health"
```

### 7. Say the workspace rule

Workbench pods get `MLFLOW_TRACKING_URI` injected. You still set **`MLFLOW_WORKSPACE=my-first-model`**. EvalHub and Garak jobs target the ConfigMap endpoint above.

## Verification

- [ ] `mlflowoperator` is `Managed`; MLflow pod `Running`
- [ ] EvalHub operator/server pod `Running` (or screenshot fallback ready)
- [ ] Garak provider visible in EvalHub UI (or screenshot fallback ready)
- [ ] `wings3-llm-endpoint` ConfigMap present
- [ ] **Develop & train → Experiments** lists MLflow experiments for `my-first-model`
- [ ] Standalone `/mlflow` loads; workspace `my-first-model`

## Fallback screenshots

- `assets/screenshots/08-dashboard-verify.png` — MLflow home (this cluster)
- `demo/assets/placeholders/demo1-evalhub-submit.png` — EvalHub create job (Act 5)

## Learning outcomes

Enable MLflow, EvalHub, and Garak as RHOAI components; verify lab CRs; map the shared inference endpoint Acts 2–5 use.

## References

- [Install MLflow (RHOAI 3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/working_with_mlflow/installing-mlflow_mlflow)
- [Track and compare MLflow experiments (RHOAI 3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/working_with_mlflow/track-and-compare-mlflow-experiments_mlflow) — embedded **Experiments** view (docs: Experiments (MLflow))
- Act 5 walkthrough: [05-evalhub-garak.md](05-evalhub-garak.md)

## Appendix — laptop rehearsal only

```bash
export MLFLOW_WORKSPACE=my-first-model
export MLFLOW_TRACKING_TOKEN=$(oc whoami --show-token)
export MLFLOW_TRACKING_URI=   # paste mlflow_ui from partials/_attributes.md
export MLFLOW_TRACKING_INSECURE_TLS=true
```
