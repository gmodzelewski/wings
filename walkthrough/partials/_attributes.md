# Cluster attributes (discovered from live cluster)

Sandbox URLs belong **only** here. Walkthrough modules paste `mlflow_ui` from this page — do not type `<gateway_host>` and do not hardcode a host in the modules. Update the table when you move clusters.

| Attribute | Value |
|-----------|-------|
| `gateway_host` | `rhods-dashboard-redhat-ods-applications.apps.ocp5.stormshift.coe.muc.redhat.com` |
| `mlflow_ui` | `https://rhods-dashboard-redhat-ods-applications.apps.ocp5.stormshift.coe.muc.redhat.com/mlflow` |
| `maas_gateway_host` | `openshift-ai-inference-openshift-ingress.apps.ocp5.stormshift.coe.muc.redhat.com` |
| `dsc_name` | `default-dsc` |
| `rhoai_version` | `3.5.0` |
| `workbench_namespace` | `my-first-model` |
| `mlflow_namespace` | `redhat-ods-applications` |
| `mlflow_workspace` | `my-first-model` |
| `llm_namespace` | `my-first-model` |
| `llm_model` | `gpt-oss-120b` |
| `llm_base_url` | `https://openshift-ai-inference-openshift-ingress.apps.ocp5.stormshift.coe.muc.redhat.com/llm/gpt-oss-120b/v1` |
| `mlflow_experiment_tracing` | `wings3-agent-tracing` |
| `mlflow_experiment_eval` | `wings3-agent-eval` |
| `mlflow_experiment_eval_prod` | `wings3-agent-eval-prod` |

## Today's cluster (copy-paste)

```bash
# Standalone MLflow UI (Act 2/3/Module 4 — Traces, Details & Timeline, Evaluation, Datasets)
# https://rhods-dashboard-redhat-ods-applications.apps.ocp5.stormshift.coe.muc.redhat.com/mlflow

curl -sk -o /dev/null -w "%{http_code}\n" \
  https://rhods-dashboard-redhat-ods-applications.apps.ocp5.stormshift.coe.muc.redhat.com/mlflow/health
```
