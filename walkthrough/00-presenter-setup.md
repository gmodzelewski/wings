# Presenter setup — stay inside 60 minutes

**Two hours, one cluster.**

| Hour | On camera | Guide |
|------|-----------|-------|
| WINGS teaching | Notebooks + slides | This page (tables below) |
| Customer / partner | Pre-staged standalone `/mlflow` only — **no deck** | [customer-ui-click-script.md](customer-ui-click-script.md) |

**Red thread (WINGS teaching, repeat each act):** Tracking server on the platform — you can **see** the agent; traces — you can **fix** it; eval — you can **prove** a prompt change helped; dataset + judge — you can **ship**.

**Red thread (customer UI hour):** Tracking server on the cluster — you can **operate** the agent; traces — you can **fix** it; eval — you can **prove** a prompt change helped; a golden set and a judge you can argue with — you can **ship**.

## Where each act runs (WINGS teaching)

| Act | Role | Where you run it |
|-----|------|------------------|
| 1 — Install | Platform engineer | Laptop terminal (`oc get` only) + standalone MLflow UI (`/mlflow`) |
| 2 — Trace | AI engineer | **JupyterLab workbench** `wings3-demo` + dashboard **Develop & train → Experiments** (GenAI Traces) |
| 3 — Evaluate | AI engineer | **Same workbench**, notebook `02_eval_improvement.ipynb` |
| 4 — Datasets + judges (follow-on) | AI engineer | **Same workbench**, notebook `03_prod_eval_judges.ipynb` — not in the 60-minute hour |

Laptop + `oc port-forward` is an **appendix** for rehearsal only. On stage, use the workbench so the LLM URL is in-cluster and MLflow env vars are injected.

## Where is MLflow in OpenShift AI 3.5?

Three surfaces — not one button. Live 3.5 nav label is **Experiments** (Red Hat docs say **Experiments (MLflow)**).

| Surface | Path | Use for WINGS / customer hour? |
|---------|------|--------------------------------|
| **Embedded dashboard** | Project → **Develop & train → Experiments** | **Act 2 Traces** — open experiment → workflow **GenAI** → **Traces** tab. **Act 3** run compare — workflow **Model training** → Runs |
| **Standalone MLflow app** | **Applications → Launch MLflow** or `mlflow_ui` in [partials/_attributes.md](partials/_attributes.md) | **Acts 3–4 + customer hour** — Datasets, Judges, full Evaluation UI |
| **Workbench SDK** | Notebook with `opendatahub.io/mlflow-instance=mlflow` | Logging only — no UI inside Jupyter |

No extra toggle to enable the embedded view: `mlflowoperator: Managed` + `MLflow` CR is enough.

Inside an experiment, the **workflow type** toggle controls tabs:

- **GenAI** → Overview, **Traces**, Sessions (Act 2 after `01_agent_tracing_autolog.ipynb`)
- **Model training** → Runs, Models, Traces (optional Act 3 compare)

Judges, Datasets, and full GenAI Evaluation still need **standalone** `/mlflow`. There is **no** platform-supported MLflow iframe inside a notebook cell — switch to a **second browser tab** on the dashboard.

The old `OdhDashboardConfig.spec.dashboardConfig.mlflow` feature flag is **deprecated** (since 3.4) and has no effect.

Standalone health check:

```bash
MLFLOW_UI='https://…/mlflow'   # from partials/_attributes.md
curl -skL -o /dev/null -w "%{http_code}\n" "${MLFLOW_UI}/health"   # expect 200
```

Details: [01-install-platform.md](01-install-platform.md) (Act 1, step 6).

## 60-minute run-of-show (WINGS teaching)

| Block | Minutes | Live vs pre-staged |
|-------|---------|-------------------|
| Intro + terms + product tour | 6 | Slides only |
| Act 1 — Install | 8 | **Pre-apply** the MLflow CR. Live: `oc get` CR and pod, then standalone `/mlflow` (screenshot 08) |
| Act 2 — Autolog | 22 | Workbench from YAML. Live: **one** query; then dashboard **Experiments** → `wings3-agent-tracing` → **GenAI** → **Traces**: Error row, then OK 256÷16 **Details & Timeline** |
| Act 3 — Evaluate | 15 | v1 already logged if behind; live: **say the substring-scorer caveat first**, then v2 (or both if vLLM is warm) |
| Production + Q&A | 9 | Slides only |

If the operator is not `Managed` yet, do **not** wait for Ready on camera. Use backup screenshots and finish install after the session.

## Fast path (install / check / uninstall)

From the repo root, after `oc login`. RHOAI must already be installed. Install enables MLflow + EvalHub + Garak operators, applies manifests, instantiates ServingRuntime `llama-32-3b-instruct`, and clones this repo onto the workbench. Set `WINGS3_LLM_STORAGE_URI` if no InferenceService already exists (do not invent a HuggingFace URI).

```bash
./install.sh              # full demo install
./install.sh --skip-llm     # GPU-less sandbox (no InferenceService)

./check.sh                  # verify demo is healthy; exit 1 on failure

./uninstall.sh              # workbench only (shared-cluster safe)
./uninstall.sh --all        # round-trip reset: workbench + EvalHub + judge secret + MLflow CR (keeps LLM)
```

Set `WINGS3_VERBOSE=1` for detailed progress. Default uninstall never removes operators or the InferenceService.

## Pre-stage checklist (day before or morning of)

- [ ] `mlflowoperator` is `Managed` and the `mlflow` pod is `Running`
- [ ] Dashboard **Develop & train → Experiments** lists `wings3-agent-tracing` (embedded MLflow — nav label is **Experiments** only)
- [ ] Standalone `/mlflow` opens (**Applications → Launch MLflow** or `mlflow_ui` in `_attributes.md`); workspace **`my-first-model`** selected (required for Datasets/Judges/Evaluation)
- [ ] `oc apply -f manifests/mlflow-dev.yaml` if no `MLflow` CR exists (do **not** apply this on camera)
- [ ] Namespace `my-first-model` has `opendatahub.io/dashboard=true`
- [ ] `install.sh` finished: InferenceService `llama-32-3b-instruct` is Ready (ServingRuntime from `vllm-cuda-runtime-template`; predictor strategy Recreate). If the console shows an outdated vLLM runtime, re-run `./install.sh` and confirm with `./check.sh`.
- [ ] EvalHub operator `Managed` and **EvalHub CR** `evalhub` in `my-first-model` (`./check.sh` → `evalhub instance`)
- [ ] `OdhDashboardConfig` has `spec.dashboardConfig.disableLMEval: false` (`./check.sh` → `evaluations nav`; RHOAI 3.5 hides **Develop & train → Evaluations** by default — `install.sh` patches this)
- [ ] ConfigMap `wings3-llm-endpoint` in `my-first-model` (applied by install)
- [ ] **Develop & train → Evaluations** loads benchmarks for `my-first-model` (no project-level EvalHub tile on 3.5)
- [ ] Garak provider visible when starting an evaluation run (or screenshot fallbacks in `demo/assets/placeholders/`)
- [ ] Act 5 EvalHub: Secret `hf-token` in `my-first-model` (key **`hf-token`**) if using Llama tokenizer; accept [Llama 3.2 license](https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct) for that HF account; `./scripts/verify_hf_gated_access.sh` passes. Without license: pre-submit `./scripts/submit_evalhub_eval_run.sh --benchmark arc_easy --tokenizer gpt2`
- [ ] Act 5 Garak: pre-submit `./scripts/submit_evalhub_eval_run.sh --benchmark quick --name wings3-demo-garak-quick` (endpoint must include `/v1`; script normalizes). Or submit from **Evaluations** UI with endpoint copied verbatim from ConfigMap (`...:8080/v1`)
- [ ] Workbench in `my-first-model` is **Running** (not Stopped). Create **only** with `oc apply -f manifests/workbench-wings3-demo.yaml`. Do **not** use dashboard **Create workbench** — that notebook uses ServiceAccount `default` and gets `PERMISSION_DENIED`. The YAML Notebook uses ServiceAccount `wings3-demo` (the MLflow webhook binds RBAC to that name). After apply, **stop/start** the workbench so the initContainer can `git clone https://github.com/gmodzelewski/wings.git` into `/opt/app-root/src/wings`. Cluster must reach GitHub. If that path exists but is not a git repo, remove it and restart.
- [ ] JupyterLab file browser is this clone (`demo/notebooks/…`). `git pull --ff-only` from the repo root (terminal or the optional notebook cell).
- [ ] `pip install -r agent-tracing/requirements.txt --extra-index-url https://pypi.org/simple` already succeeded in the workbench (RHOAI 3.4 RHAI index has no langgraph 0.2). Re-run after a workbench restart; the venv is not on the PVC.
- [ ] Optional for **WINGS teaching**: v1 eval run already in experiment `wings3-agent-eval`
- [ ] Optional for **WINGS teaching** (Module 4 follow-on, not in that hour): golden set registered as `math_golden` and one `v2-judged` run in experiment `wings3-agent-eval-prod`
- [ ] **Module 4 / customer hour:** `install.sh` enables MaaS + external model **gpt-oss-120b**; upstream workshop token via `WINGS3_MAAS_UPSTREAM_API_KEY` (or existing judge secret before first MaaS install); judge `JUDGE_API_KEY` is a minted **sk-oai-** MaaS key
- [ ] `./check.sh` passes MaaS CRD/model checks, `ogx`, `ogxserver`, `mcp catalog`, `maas-ui`, `judge JUDGE_BASE_URL` (not `maas.redhatworkshops.io`), `judge secret JUDGE_API_KEY`, and `workbench judge mount`
- [ ] **Gen AI Studio → AI asset endpoints → Models** lists **gpt-oss-120b** (hard-refresh dashboard if empty); **Gen AI Studio → API keys** can create a key for `wings3-gpt-oss-120b`
- [ ] **Gen AI Studio → Playground** visible; can create a playground in `my-first-model` (install.sh enables Service Mesh 3 + OGX + `wings3-ogx` OGXServer — first run may take 30–45 min)
- [ ] **Gen AI hub → MCP server** catalog visible (browse only; no MCP deploy demo required). Set `WINGS3_SKIP_OGX=1` / `WINGS3_SKIP_MCP=1` to skip if cluster lacks capacity

Cluster-specific URLs (`gateway_host`, `mlflow_ui`) live in [partials/_attributes.md](partials/_attributes.md). Route name may be `rhods-dashboard`, `rh-ai`, or `rhoai` — host is the same for `/mlflow`.

## Customer UI hour — extra pre-stage (**required**, not optional)

`--warmup` is not enough. The [customer click script](customer-ui-click-script.md) never runs notebooks on camera. If these objects are missing, the hour has no close.

Required in workspace `my-first-model` (in addition to the checklist above):

- [ ] Experiment `wings3-agent-tracing`: an **Error** row **and** an **OK** row whose request is **Calculate 256 divided by 16**
- [ ] Experiment `wings3-agent-eval`: runs `v1-baseline` **and** `v2-improved-prompt`
- [ ] Prompt **`wings3-agent-v2`** visible in the MLflow **Prompts** tab
- [ ] Dataset **`math_golden`** visible in the MLflow **Datasets** tab (8 records)
- [ ] Experiment `wings3-agent-eval-prod`: **Judges** (or **Scorers**) → **`correctness`** and **`numeric_and_clear`**
- [ ] Experiment `wings3-agent-eval-prod`: run **`v2-judged`** (hybrid substring + judges)

Do this in the **workbench** terminal after `./install.sh` (venv already pip'd; tracking URI injected). Re-run after a workbench restart.

Set the workshop upstream token **before** first MaaS install (do not commit it). `install.sh` mints a MaaS API key into `wings3-judge-llm` when MaaS is Ready:

```bash
# Workshop upstream (ExternalModel only) — one of:
export WINGS3_MAAS_UPSTREAM_API_KEY='<workshop-token>'
./install.sh

# Or override the minted judge key after install:
export WINGS3_JUDGE_API_KEY='<sk-oai-…>'
./install.sh
```

If MaaS key mint fails, patch manually after confirming subscription `wings3-gpt-oss-120b` exists:

```bash
oc set env secret/wings3-judge-llm -n my-first-model \
  JUDGE_BASE_URL='https://<maas-gateway>/my-first-model/gpt-oss-120b/v1' \
  JUDGE_API_KEY='<sk-oai-…>'
oc apply -f manifests/workbench-wings3-demo.yaml
# stop/start workbench wings3-demo — verify: ./check.sh
```

RHOAI strips `secretKeyRef` env on Notebooks; the workbench mounts Secret `wings3-judge-llm` (`manifests/secret-wings3-judge-llm.yaml` or `.example.yaml`) at `/etc/wings3-judge-llm` and the notebook env cell reads those files. **Dashboard stop/start can strip custom volume mounts** — re-apply `workbench-wings3-demo.yaml` if `./check.sh` fails `workbench judge mount`.

```bash
cd /opt/app-root/src/wings/demo/agent-tracing
export MLFLOW_WORKSPACE=my-first-model
export MAAS_API_KEY=unused
Agent model is set in Secret `wings3-judge-llm` (`MAAS_MODEL`, `MAAS_BASE_URL`). For local laptop runs only, copy `demo/agent-tracing/.env.example` to `.env`.

# Error beat: extra queries on 3B often land as Error. Keep the warmup OK 256÷16 row.
unset WINGS3_ONE_QUERY
export MLFLOW_EXPERIMENT_NAME=wings3-agent-tracing
python3 run_tracing_demo_autolog.py

# v2 comparison for Act 3 UI (warmup already logged v1)
export MLFLOW_EXPERIMENT_NAME=wings3-agent-eval
export WINGS3_PROMPT_VERSION=v2
python3 evaluate_agent.py

# Required close: named golden set + v2-judged (not a follow-on for this hour).
# Refreshes math_golden from git so Correctness is not given both expected_response
# and expected_facts.
export MLFLOW_EXPERIMENT_NAME=wings3-agent-eval-prod
python3 evaluate_agent_judges.py --register-only   # Prompts + Judges + dataset (fast)
# python3 evaluate_agent_judges.py                 # full v2-judged eval when vLLM is warm
```

Confirm in `/mlflow` before the session: Prompts → `wings3-agent-v2`; Datasets → `math_golden`; Judges → `correctness` + `numeric_and_clear`; Evaluation → `v2-judged`. If any is missing, the customer hour is not ready — do not start.

## When the new cluster is up (not before)

1. Fill `gateway_host` / `mlflow_ui` in `_attributes.md`. Set `WINGS3_LLM_STORAGE_URI` from the catalog or copy it from an existing InferenceService, then run `install.sh`.
2. Recapture screenshots `08`, `12`, `14`, `18`, `19` on today’s `/mlflow` whenever the gateway host changes; flip captions to this cluster. (Done 18 Aug 2026 on sandbox956.)
3. Rebuild `MLflow-on-RHOAI-Deep-Dive.pptx` (`python3 scripts/build_wings3_deck.py`) if you are giving the **WINGS teaching** hour. Skip the deck for the customer UI hour.
4. Rehearse WINGS teaching: Act 1 `oc get` only; Act 2 SHOW cells + Error then OK; Act 3 substring caveat before the cells.
5. Rehearse customer UI hour: [customer-ui-click-script.md](customer-ui-click-script.md) against live `/mlflow`. Confirm `math_golden` and `v2-judged` before anyone sits down.

## If you are behind the clock

- Act 2: run **one** query (`Calculate 256 divided by 16`), not three. Dashboard **Experiments** → **GenAI** → **Traces**: ~20s on an Error row (rehearsal Error is fine if the live query is OK), then OK 256÷16 **Details & Timeline**. Fallback: standalone `/mlflow`
- Act 3: skip v1 live; show existing v1 run and execute v2 only. Still say the substring-scorer caveat **before** the cells
- Do not debug `search_traces` from the laptop SDK — use the MLflow UI
- Customer UI hour: skip `oc get` and Jupyter; one Error, one OK tree, one False eval row, one judge rationale; do not linger on 25% → 50%
