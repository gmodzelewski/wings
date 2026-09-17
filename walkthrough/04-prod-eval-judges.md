# Module 4 — Production-grade eval (datasets + judges)

**Time:** 20–25 minutes | **Role:** AI engineer  
**Where:** Same JupyterLab workbench as Modules 2 and 3 — notebook first  
**Follow-on (WINGS teaching):** not part of that 60-minute run-of-show. Act 3 already closed with “add judges before you promote.”

**Customer UI hour:** this UI **is** in the 60 minutes, pre-logged — [customer-ui-click-script.md](customer-ui-click-script.md). `math_golden` and `v2-judged` are required before anyone sits down.

## Know

Traces showed **what** the agent did. Act 3 showed a **toy** substring gate moved. This lab shows a **reviewable** gate: a registered golden dataset, a registered `Correctness` judge, LLM-as-judge scorers with rationales, and scores in the standalone MLflow Evaluation UI.

Four different MLflow objects — do not treat them as one:

| Object | How it gets there | Where you look |
|--------|-------------------|----------------|
| Agent system prompt | `register_prompt(name="wings3-agent-v2")` | **Prompts** → `wings3-agent-v2` |
| Golden dataset | `create_dataset` + `merge_records` | **Datasets** → `math_golden` |
| Built-in judge | `Correctness(...).register(name="correctness")` | **Judges** (or **Scorers**) → `correctness` |
| Guidelines judge | `Guidelines(...).register(name="numeric_and_clear")` | **Judges** → `numeric_and_clear` (shows guidelines) |
| Eval scores / rationales | `mlflow.genai.evaluate(scorers=…)` | **Evaluation** → run `v2-judged` |

`evaluate()` without `.register()` is enough for Evaluation columns. It is **not** enough for the Prompts or Judges catalogs. The `@scorer` substring check (`contains_expected`) cannot be registered — it stays on the `evaluate()` list only.

**Say this before you run cells:** The **agent** uses `MAAS_MODEL` from Secret `wings3-judge-llm`. **Judges** use `JUDGE_*` from the same secret (often **gpt-oss-120b** through the in-cluster MaaS gateway). The workshop upstream is only on the `ExternalModel`; judges never call `maas.redhatworkshops.io` directly. Celebrate that scores now have **rationales** you can argue with. Hybrid scoring keeps `contains_expected` so a flaky judge row still has a cheap metric.

| Piece | What it is |
|-------|------------|
| Golden set | 8 calculator-only JSONL rows in git (`math_golden.jsonl`). First four are the Act 3 questions. |
| MLflow dataset | `create_dataset` + `merge_records` → **Datasets** tab, not a Python list |
| `contains_expected` | Same substring check as Act 3 (`expected_answer` in the output). Eval-only — cannot register. |
| `Correctness` | Built-in judge vs `expected_facts`. **Register** it so it appears under Judges / Scorers. |
| `Guidelines` (`numeric_and_clear`) | Judge: digits in the response; one clear arithmetic result. **Register** it so guidelines appear under Judges. |
| Judge model | `hosted_vllm:/gpt-oss-120b` via LiteLLM + `HOSTED_VLLM_API_BASE` = in-cluster MaaS (`JUDGE_BASE_URL` from Secret `wings3-judge-llm`, minted by `install.sh`). Agent stays on in-cluster 3B. Do **not** use `openai:/…` — that always calls api.openai.com. UI: **Gen AI Studio → Models as a Service** shows external model **gpt-oss-120b**. |
| Agent prompt | **v2 only** (precise math assistant; always use calculator). Register as `wings3-agent-v2` in **Prompts**. |
| Experiment | `wings3-agent-eval-prod` (Act 3 stays on `wings3-agent-eval`) |

Do **not** use trace-based `make_judge(..., {{ trace }})` on stage. 3B already blows context on extra queries in Act 2.

**On stage:** walk SHOW cells even if vLLM is cold. Live-run `v2-judged` only if the model is warm; otherwise open a pre-logged Evaluation run.

## Show

### 1. Open the notebook

In JupyterLab: `demo/notebooks/03_prod_eval_judges.ipynb`

### 2. Stop at each SHOW comment (top to bottom)

The notebook inlines the eval code. Do **not** open `evaluate_agent_judges.py` on stage (that file is CLI only).

1. Env — injected `MLFLOW_*` and `JUDGE_*` (Secret `wings3-judge-llm`). Experiment `wings3-agent-eval-prod`.
2. **SHOW: golden JSONL** — 8 rows; `expected_answer` vs `expected_facts`.
3. **SHOW: register dataset** — `create_dataset` + `merge_records`, or drop existing rows and merge from git (never silent-reuse).
4. **SHOW: hybrid scorers** — substring + `Correctness` + `Guidelines`; print `hosted_vllm:/gpt-oss-120b` and `HOSTED_VLLM_API_BASE` (MaaS, not the 3B predictor). **SHOW: register** — `register_prompt(wings3-agent-v2)`, `correctness.register()`, `numeric_and_clear.register()`; print that `contains_expected` is eval-only. Re-running this cell is enough to fill Prompts + Judges (no 24-call eval).
5. **SHOW: `mlflow.genai.evaluate()`** — define `run_eval` (does not call the LLM yet).
6. Run **v2** (skip if `v2-judged` is already logged and the clock is tight).
7. Print the metrics table, then open the standalone MLflow UI.

### 3. Compare in MLflow UI

Use the **standalone** `/mlflow` UI (`mlflow_ui` in attributes), not the embedded Experiments view.

Workspace **my-first-model** → experiment **`wings3-agent-eval-prod`**:

1. **Prompts** → `wings3-agent-v2` — agent system prompt for the v2 eval run.
2. **Datasets** → `math_golden` — 8 records. This is the beat Act 3 cannot do (a named golden set).
3. **Judges** (or **Scorers**) → `correctness` and `numeric_and_clear`. Catalog entries from `.register()`, not from `evaluate()`. Built-in `correctness` may show a read-only template in the UI.
4. **Evaluation** → run `v2-judged` — per-example `contains_expected`, `Correctness`, `numeric_and_clear`.
5. Open a row where substring and judge **disagree**, or a Fail with rationale, and **read the judge text**. Scores and rationales live here, not on the Judges tab.

Eight rows × (1 agent + 2 judges) is about 24 LLM calls. Live numbers will vary on 3B. The story is a **reviewable gate**, not a production SLO.

### 4. CLI alternative (same workbench terminal)

```bash
cd …/demo/agent-tracing
export MLFLOW_WORKSPACE=my-first-model
export MLFLOW_EXPERIMENT_NAME=wings3-agent-eval-prod
python3 evaluate_agent_judges.py              # full eval
python3 evaluate_agent_judges.py --register-only   # Prompts + Judges only (fast pre-stage)
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ModuleNotFoundError: No module named 'langchain_core'` | Same as Act 2: run the **1b** `%pip install` cell first (`--extra-index-url https://pypi.org/simple`), then re-run the env cell. Venv is not on the PVC. |
| `Field required` / calculator `b` missing | Same as Act 2/3: `b` must be optional. Golden set includes sqrt(144). Re-run the hybrid-scorer cell. |
| `Workspace context is required` | `os.environ["MLFLOW_WORKSPACE"] = "my-first-model"` then re-run |
| Empty `MLFLOW_TRACKING_URI` | Stop/start the workbench; confirm `opendatahub.io/mlflow-instance=mlflow` |
| Judge 401 / `api.openai.com` / `Incorrect API key provided: unused` | You used `openai:/…`. That provider is hosted OpenAI. Re-run the hybrid-scorer cell: print must be `hosted_vllm:/gpt-oss-120b` and `HOSTED_VLLM_API_BASE` must be the MaaS `/v1` URL (Secret `wings3-judge-llm`), not the in-cluster 3B predictor. Install `litellm` (`%pip install -r …requirements.txt`). Then re-run `v2-judged`. |
| Judge calls OpenAI / `gpt-4o-mini` | Same as 401: URI must be `hosted_vllm:/…`, not `openai:/…` and not the default gpt-4o-mini. |
| `JUDGE_API_KEY is missing` / env cell prints `JUDGE_MODEL=None` | Three common causes. (1) **Empty Secret key** — `install.sh` creates `wings3-judge-llm` with `JUDGE_API_KEY: ""`; run `oc set env secret/wings3-judge-llm -n my-first-model JUDGE_API_KEY='<token>'` or `export WINGS3_JUDGE_API_KEY='…' && ./install.sh`. Do **not** re-apply `secret-wings3-judge-llm.yaml` after setting the token. (2) **Mount stripped** — dashboard reconcile removed `/etc/wings3-judge-llm` from the live Notebook; run `oc apply -f manifests/workbench-wings3-demo.yaml`, stop/start workbench, verify with `./check.sh` (`workbench judge mount`). (3) **Stale kernel** — restart kernel and re-run the env cell after secret/mount changes. RHOAI strips `secretKeyRef` / `envFrom`; file mount + env cell is the supported path. |
| Judge JSON-parse / empty rationale | Try `JUDGE_MODEL=llama-scout-17b` (less reasoning-token wrapping than gpt-oss). Still compare `contains_expected` on that row. |
| `only one expected_response or expected_facts` | Correctness forbids both. Git JSONL has `expected_answer` + `expected_facts` only. Re-run the register cell so `math_golden` is **refreshed from git** (do not silent-reuse). Then re-run `v2-judged`. |
| Eval row errors / 3B context | Same as Act 2/3 — one tool per turn, `max_tokens` 256; skip remaining rows if needed |
| `create_dataset` already exists | Register cell drops existing rows and merges git. Do not skip that cell. |
| Prompts tab empty | Re-run the hybrid-scorer cell or `evaluate_agent_judges.py --register-only`. `register_prompt(name="wings3-agent-v2")` is required; `evaluate()` does not create Prompt Registry entries. |
| Judges / Scorers tab empty, or **currently not available** | Two different issues. (1) Catalog is empty until `.register()` — re-run the hybrid-scorer cell; `evaluate()` does not create catalog entries. `contains_expected` stays eval-only; register `correctness` and `numeric_and_clear`. (2) Dashboard **Develop & train → Experiments** (embedded view) does not host Prompts, Judges, or Datasets. Use standalone `/mlflow`. |
| MLflow UI 504 | Open Evaluation in the browser; do not `search_traces` from the SDK |
| Cell 6 hangs > a few minutes; GPU idle | Not waiting on vLLM. MLflow 3.13 `evaluate()` default thread pool deadlocks while logging traces (`import` lock + Databricks/Spark probe). **Restart kernel** — Interrupt will not break it. Re-run from the env cell (the `run_eval` cell sets `MLFLOW_GENAI_EVAL_MAX_WORKERS=1`). Or skip live eval and open a pre-logged `v2-judged`. |
| vLLM cold / clock | Walk SHOW cells; open a pre-logged `v2-judged` run |

## Verification

- [ ] 3B-agent / hosted-judge split was spoken **before** the cells
- [ ] Golden JSONL and `expected_facts` were visible in the notebook
- [ ] Prompt `wings3-agent-v2` exists in standalone `/mlflow` → Prompts
- [ ] Dataset `math_golden` exists in the MLflow Datasets tab
- [ ] Judges `correctness` and `numeric_and_clear` exist in standalone `/mlflow` → Judges (or Scorers)
- [ ] Run `v2-judged` exists in experiment `wings3-agent-eval-prod` (live or pre-logged)
- [ ] A judge rationale (or substring/judge disagreement) was read in the Evaluation UI

## Learning outcomes

Registered agent prompt in the Prompt Registry; registered evaluation datasets; registered `Correctness` and `Guidelines` judges in the Judges catalog; hybrid deterministic + LLM-as-judge scorers; judge model on hosted MaaS; Evaluation UI rationales as a reviewable gate.

## References

- [03_prod_eval_judges.ipynb](../demo/notebooks/03_prod_eval_judges.ipynb) — stage path
- [evaluate_agent_judges.py](../demo/agent-tracing/evaluate_agent_judges.py) — CLI only
- [math_golden.jsonl](../demo/datasets/math_golden.jsonl) — golden set
- [MLflow LLM-as-a-Judge](https://mlflow.org/docs/latest/genai/eval-monitor/scorers/llm-judge/)
