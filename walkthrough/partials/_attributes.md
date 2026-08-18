# Cluster attributes (discovered from live cluster)

Sandbox URLs belong **only** here. Walkthrough modules paste `mlflow_ui` from this page — do not type `<gateway_host>` and do not hardcode a host in the modules. Update the table when you move clusters.

| Attribute | Value |
|-----------|-------|
| `gateway_host` | `rh-ai.apps.ocp.l9tcs.sandbox956.opentlc.com` |
| `mlflow_ui` | `https://rh-ai.apps.ocp.l9tcs.sandbox956.opentlc.com/mlflow` |
| `dsc_name` | `default-dsc` |
| `rhoai_version` | `3.4.3` |
| `workbench_namespace` | `my-first-model` |
| `mlflow_namespace` | `redhat-ods-applications` |
| `mlflow_workspace` | `my-first-model` |
| `llm_namespace` | `my-first-model` |
| `llm_model` | `llama-32-3b-instruct` |
| `llm_base_url` | `http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1` |
| `mlflow_experiment_tracing` | `wings3-agent-tracing` |
| `mlflow_experiment_eval` | `wings3-agent-eval` |
| `mlflow_experiment_eval_prod` | `wings3-agent-eval-prod` |

## Today's cluster (copy-paste)

```bash
# Standalone MLflow UI (Act 2/3/Module 4 — Traces, Details & Timeline, Evaluation, Datasets)
# https://rh-ai.apps.ocp.l9tcs.sandbox956.opentlc.com/mlflow

curl -sk -o /dev/null -w "%{http_code}\n" \
  https://rh-ai.apps.ocp.l9tcs.sandbox956.opentlc.com/mlflow/health
```
