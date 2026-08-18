# Module 1 — Install MLflow on OpenShift AI

**Time:** 8 minutes live (operator pre-enabled) | **Persona:** Platform engineer  
**Where:** Laptop terminal (`oc get` only) and the standalone MLflow UI (`/mlflow`)

## Know

MLflow on RHOAI is a **managed component** (`mlflowoperator` on `DataScienceCluster`) plus a cluster-scoped `MLflow` CR. The tracking server is reached through the data-science gateway.

| Term | What it is |
|------|------------|
| **Project** | OpenShift namespace `my-first-model` (dashboard) |
| **Workspace** | MLflow’s name for that same project (`MLFLOW_WORKSPACE`) — the RBAC boundary |
| **Experiment** | A named bucket inside the workspace (`wings3-agent-tracing` vs `wings3-agent-eval`) |

Dev CR uses SQLite + PVC. Production uses PostgreSQL + S3 (`replicas` > 1 needs remote storage). See [mlflow-prod.example.yaml](../manifests/mlflow-prod.example.yaml) — do not apply it in this hour.

**On stage:** do not wait for a cold operator install. Pre-enable `Managed` and **pre-apply** the lab CR (see [00-presenter-setup.md](00-presenter-setup.md)). Live: prove the CR and pod with `oc get`, then open the standalone MLflow UI. Workbench injects tracking URI and Kubernetes auth; you set `MLFLOW_WORKSPACE`. Do not export a laptop token on camera.

## Show

Values: [partials/_attributes.md](partials/_attributes.md) — paste `mlflow_ui` from **Today’s cluster**. Do not type angle-bracket placeholders.

### 1. Confirm the operator (pre-staged)

```bash
oc get datasciencecluster default-dsc \
  -o jsonpath='{.spec.components.mlflowoperator.managementState}{"\n"}'
```

**Expected:** `Managed`

If it prints `Removed`, enable it **off-camera** or before the hour:

```bash
oc patch datasciencecluster default-dsc --type=merge \
  -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Managed"}}}}'
```

```bash
oc get pods -n redhat-ods-applications | grep mlflow-operator
```

**Expected:** a `mlflow-operator-controller-manager-…` pod `1/1 Running`.

### 2. Confirm the MLflow CR and server pod (pre-applied)

The CR is applied in [00-presenter-setup.md](00-presenter-setup.md). On camera, only `oc get` — do **not** `oc apply` the CR live.

```bash
oc get mlflow -n redhat-ods-applications
oc get pods -n redhat-ods-applications -l app=mlflow
```

**Expected:**

```text
NAME     AGE
mlflow   …

NAME                     READY   STATUS    RESTARTS   AGE
mlflow-…                 2/2     Running   …          …
```

First start can take several minutes (image pull). If `READY` is not `2/2`, switch to the backup screenshot and keep talking — do not watch CrashLoop on camera.

### 3. Confirm the demo project is labeled (pre-staged)

```bash
oc get namespace my-first-model --show-labels | grep opendatahub.io/dashboard
```

**Expected:** `opendatahub.io/dashboard=true`. If the label is missing, apply it **off-camera**:

```bash
oc label namespace my-first-model opendatahub.io/dashboard=true --overwrite
```

### 4. Open the standalone MLflow UI (this is the Act 2/3 UI)

Screenshot `08-dashboard-verify.png` is **MLflow home** for workspace `my-first-model`, not the dashboard Projects list.

Paste `mlflow_ui` from [partials/_attributes.md](partials/_attributes.md) (**Today’s cluster**). Do not type angle-bracket placeholders. Do not paste a previous-cluster host.

1. Open today’s `mlflow_ui`.
2. Workspace dropdown → `my-first-model`.
3. You should see experiments (or an empty list on a fresh cluster).

The dashboard **Projects** list proves the namespace label. Traces (**Details & Timeline**) and Evaluation live in this standalone GenAI UI, not the embedded **Develop & train → Experiments (MLflow)** view. Leave the embedded view for Acts 2 and 3.

```bash
# Paste mlflow_ui from partials/_attributes.md (Today's cluster)
MLFLOW_UI='https://…/mlflow'
curl -sk -o /dev/null -w "%{http_code}\n" "${MLFLOW_UI}/health"
```

**Expected:** `200` or `302`.

### 5. Say the workspace rule

Workbench pods get `MLFLOW_TRACKING_URI` and Kubernetes auth injected when the notebook has `opendatahub.io/mlflow-instance`. You still set **`MLFLOW_WORKSPACE=my-first-model`**. Without it the API returns `Workspace context is required`. Laptop token exports are rehearsal-only (appendix).

## Verification

- [ ] `mlflowoperator` is `Managed`
- [ ] MLflow pod is `Running` (`oc get`, not `oc apply`)
- [ ] Standalone `/mlflow` loads; workspace dropdown is `my-first-model`
- [ ] Experiments list is empty or only prior rehearsal data

## Fallback screenshot

`assets/screenshots/08-dashboard-verify.png` — this cluster: MLflow home after workspace `my-first-model` (recaptured 18 Aug 2026). Match this click path. Do not narrate the file as the Projects list.

## Learning outcomes

Enable MLflow as a RHOAI component; verify a lab CR; map Project, Workspace, and Experiment.

## References

- [Install MLflow (RHOAI 3.4)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow/installing-mlflow_mlflow)

## Appendix — laptop rehearsal only

Do **not** export these on camera. Acts 2 and 3 run in the workbench.

```bash
export MLFLOW_WORKSPACE=my-first-model   # must match the OpenShift project
export MLFLOW_TRACKING_TOKEN=$(oc whoami --show-token)
export MLFLOW_TRACKING_URI=   # paste mlflow_ui from partials/_attributes.md
export MLFLOW_TRACKING_INSECURE_TLS=true
```
