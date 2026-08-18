# Module 2 — Agent tracing with autolog

**Time:** 22 minutes | **Persona:** AI developer  
**Where:** JupyterLab **workbench** `wings3-demo` in project `my-first-model` (not your laptop)

## Know

`mlflow.langchain.autolog()` captures LLM calls, tool invocations, and nested spans — **no manual spans**. Without that calculator span, you would miss the tool call.

The SHOW notebook inlines the calculator and autolog line. It imports `create_agent_graph` from `traced_agent.py` (calculator-only). You do not need to open that file on stage.

On RHOAI, annotation **`opendatahub.io/mlflow-instance=mlflow`** on the Notebook injects:

- `MLFLOW_TRACKING_URI`
- `MLFLOW_K8S_INTEGRATION=true`
- `MLFLOW_TRACKING_AUTH=kubernetes-namespaced`

You still set **`MLFLOW_WORKSPACE`** to the project name (`my-first-model`) — that is the RBAC boundary. The LLM is the in-cluster vLLM predictor (KServe, Llama 3.2 3B) — no port-forward. The workbench pod must run as ServiceAccount **`wings3-demo`** (same name as the Notebook, from the YAML). Dashboard-created notebooks use `default` and get `PERMISSION_DENIED`.

**Pip (pre-stage):** RHOAI 3.4 RHAI index has langgraph 1.x only. Install with `--extra-index-url https://pypi.org/simple`. The venv is **not** on the PVC — re-pip after a workbench restart.

**Llama 3.2 3B:** one tool call per turn; keep `max_tokens` small; calculator-only. Extra queries often land as **Error**. That is the Act 2 teaching object: open an Error row, show where it broke, then cut to the OK 256÷16 tree.

**On stage:** dependencies already installed. Live: **one** query if the clock is tight.

## Show

### 1. Open the pre-staged workbench

Do **not** create a workbench from the dashboard during this hour. Dashboard notebooks use ServiceAccount `default`; the MLflow webhook binds RBAC to `wings3-demo`.

1. OpenShift AI → **Projects** → `my-first-model` → **Workbenches**.
2. Open **wings3-demo** (status must be **Running**).
3. If it is missing, that is a pre-stage miss — **off camera**: `oc apply -f manifests/workbench-wings3-demo.yaml`, wait until Running, then continue.

### 2. Confirm the git clone

JupyterLab root **is** this repo (`/opt/app-root/src/wings`). The workbench initContainer clones https://github.com/gmodzelewski/wings.git if `.git` is missing. Do **not** clone slideorama.

In the JupyterLab **terminal** (or the optional notebook cell):

```bash
cd /opt/app-root/src/wings   # already the Jupyter root
git pull --ff-only           # pick up laptop pushes; skip on stage if current
```

If the file browser is empty or not a git repo: stop/start the workbench so the initContainer runs. If `/opt/app-root/src/wings` exists without `.git`, remove that directory and restart. Cluster must reach GitHub.

Pre-stage this before the hour.

### 3. Install deps (pre-stage; skip live if already done)

```bash
cd demo/agent-tracing
# RHOAI 3.4 RHAI index ships langgraph 1.x only; extra-index supplies langgraph 0.2.
# Re-run after a workbench restart (venv is not on the PVC).
pip install -r requirements.txt --extra-index-url https://pypi.org/simple
```

### 4. Open the tracing notebook

In JupyterLab: `demo/notebooks/01_agent_tracing_autolog.ipynb`

Do **not** open `run_tracing_demo_autolog.py` on stage (CLI / `bootstrap.sh --warmup` only).

### 5. Stop at each SHOW comment (top to bottom)

1. Env — injected `MLFLOW_*`. `MLFLOW_WORKSPACE` must be `my-first-model`.
2. **SHOW: calculator tool** — the span autolog will capture.
3. **SHOW: `mlflow.langchain.autolog()`** — one line, before the agent runs.
4. **SHOW: one query** — `Calculate 256 divided by 16` → `16.0`. Skip extra-query cells.

**Expected (success path):**

```text
MLflow: https://…/mlflow
Workspace: my-first-model
…
--- Query: Calculate 256 divided by 16
The result of 256 divided by 16 is 16.0.
Done → MLflow UI → Traces → Details & Timeline
```

### 6. Open traces — debug an Error, then show the OK tree

Use the **standalone** MLflow UI (`mlflow_ui` in attributes), not the embedded dashboard Experiments view.

1. Workspace **my-first-model** → experiment **wings3-agent-tracing** → **Traces**.
2. **Debug beat (red thread):** open an **Error** row (often a later query or a 3B context blow-up; a rehearsal Error is fine if the live query is OK). Show the tool or LLM failure. Say: this is why you needed traces — you can see where it failed. Do not linger.
3. Close it. Open an **OK** row whose request is **Calculate 256 divided by 16** (State OK). Latest is often Error; do **not** pick latest by default.
4. In the drawer, open **Details & Timeline**. Span tree: LangGraph → ChatOpenAI → **calculator** → ChatOpenAI. Point at the calculator span — that is what autolog captured without a manual span.

If the drawer does not open, add `selectedEvaluationId=<trace-id>` to the Traces URL.

## Verification

- [ ] Pointed at **SHOW:** `mlflow.langchain.autolog()` in `01_agent_tracing_autolog.ipynb`
- [ ] Workbench `MLFLOW_TRACKING_URI` is set
- [ ] At least one successful agent response (`Calculate 256 divided by 16` → `16.0`)
- [ ] Opened an Error row and named the failure (timeout, empty response, or missing tool)
- [ ] Opened an OK **Calculate 256 divided by 16** row
- [ ] **Details & Timeline** shows ChatOpenAI → calculator → ChatOpenAI

## Fallback screenshots

`12-traces-list.png` and `14-traces-span-tree.png` are from this cluster (workspace `my-first-model`, recaptured 18 Aug 2026). Open an **OK** live trace; the drawer query param is `selectedEvaluationId`. Tab: **Details & Timeline**.

## Appendix — CLI (same workbench terminal)

Prefer the notebook on stage. This script is `bootstrap.sh --warmup` and rehearsal.

```bash
cd …/demo/agent-tracing
export MLFLOW_WORKSPACE=my-first-model
export MLFLOW_EXPERIMENT_NAME=wings3-agent-tracing
export MAAS_API_KEY=unused
export MAAS_MODEL=llama-32-3b-instruct
export MAAS_BASE_URL=http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1
export WINGS3_ONE_QUERY=1
python3 run_tracing_demo_autolog.py
```

## Appendix — laptop rehearsal only

Do **not** use this on stage.

```bash
POD=$(oc get pod -n my-first-model -l serving.kserve.io/inferenceservice=llama-32-3b-instruct \
  -o jsonpath='{.items[0].metadata.name}')
oc port-forward -n my-first-model pod/$POD 18080:8080
export MAAS_BASE_URL=http://127.0.0.1:18080/v1
export MLFLOW_TRACKING_TOKEN=$(oc whoami --show-token)
```

Port-forward the **pod on 8080**. `svc/…-predictor 18080:80` fails with connection refused.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ModuleNotFoundError: No module named 'langchain_core'` | Kernel venv is empty (never pip'd, or workbench restarted — venv is not on the PVC). Run the **1b** `%pip install -r ../agent-tracing/requirements.txt --extra-index-url https://pypi.org/simple` cell **first**, then re-run the env cell (it imports langchain/mlflow). Terminal `pip` without `--extra-index-url` hits the RHAI index and can miss `langchain-core`. |
| `Field required` / `validation error for calculator` / `b` missing | 3B called `sqrt` with only `a`. Tool schema must have `b: float \| None = None`. Re-run the SHOW calculator cell from the updated notebook, then the agent cell. Old traces keep the Error rows — that is still the Act 2 debug beat. |
| `Workspace context is required` | Re-run the env cell (`MLFLOW_WORKSPACE=my-first-model`) |
| `PERMISSION_DENIED` from workbench SDK | Pod must use SA `wings3-demo` (see `workbench-wings3-demo.yaml`); `default` is not bound. Do not create the notebook from the dashboard. |
| `This model only supports single tool-calls` | Calculator-only agent (already the demo); one tool per turn |
| `max_tokens` / context too large | `MAAS_MAX_TOKENS=256`; skip extra queries |
| LLM connection error from laptop | Use workbench in-cluster URL, or pod port-forward 8080 |
| MLflow UI 504 / SDK `search_traces` timeout | Use the browser Traces tab; server may be slow on SQLite |
| Empty JupyterLab / not a git repo | Stop/start workbench so the initContainer clones `github.com/gmodzelewski/wings`. If `/opt/app-root/src/wings` exists without `.git`, remove it and restart. Cluster must reach GitHub. |

## Learning outcomes

Autolog from a RHOAI workbench; debug an Error trace; read an OK span tree in **Details & Timeline**; workspace = project.

## References

- [01_agent_tracing_autolog.ipynb](../demo/notebooks/01_agent_tracing_autolog.ipynb) — stage path
- [run_tracing_demo_autolog.py](../demo/agent-tracing/run_tracing_demo_autolog.py) — CLI / warmup only
- [mlflow-on-rhoai agent-tracing](https://github.com/rh-aiservices-bu/mlflow-on-rhoai/tree/main/agent-tracing)
