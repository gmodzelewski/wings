# Module 4 — Production-grade eval (datasets + judges)

**Time:** 20–25 minutes | **Persona:** Data scientist  
**Where:** Same JupyterLab workbench as Modules 2 and 3 — notebook first  
**Follow-on (WINGS teaching):** not part of that 60-minute run-of-show. Act 3 already closed with “add judges before you promote.”

**Customer UI hour:** this UI **is** in the 60 minutes, pre-logged — [customer-ui-click-script.md](customer-ui-click-script.md). `math_golden` and `v2-judged` are required before anyone sits down.

## Know

Traces showed **what** the agent did. Act 3 showed a **toy** substring gate moved. This lab shows a **reviewable** gate: a registered golden dataset, LLM-as-judge scorers with rationales, and scores in the standalone MLflow Evaluation UI.

**Say this before you run cells:** Llama 3.2 3B is the **agent**. Judges use hosted **gpt-oss-120b** from Secret `wings3-judge-llm` (`JUDGE_*`). Celebrate that scores now have **rationales** you can argue with. Hybrid scoring keeps `contains_expected` so a flaky judge row still has a cheap metric.

| Piece | What it is |
|-------|------------|
| Golden set | 8 calculator-only JSONL rows in git (`math_golden.jsonl`). First four are the Act 3 questions. |
| MLflow dataset | `create_dataset` + `merge_records` → **Datasets** tab, not a Python list |
| `contains_expected` | Same substring check as Act 3 (`expected_answer` in the output) |
| `Correctness` | Built-in judge vs `expected_facts` |
| `Guidelines` (`numeric_and_clear`) | Judge: digits in the response; one clear arithmetic result |
| Judge model | `hosted_vllm:/gpt-oss-120b` via LiteLLM + `HOSTED_VLLM_API_BASE` = hosted MaaS (`JUDGE_BASE_URL` from Secret `wings3-judge-llm`). Agent stays on in-cluster 3B. Do **not** use `openai:/…` — that always calls api.openai.com. Alternatives on the same endpoint: `deepseek-r1-distill-qwen-14b`, `llama-scout-17b`. |
| Prompt | **v2 only** (precise math assistant; always use calculator) |
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
4. **SHOW: hybrid scorers** — substring + `Correctness` + `Guidelines`; print `hosted_vllm:/gpt-oss-120b` and `HOSTED_VLLM_API_BASE` (MaaS, not the 3B predictor).
5. **SHOW: `mlflow.genai.evaluate()`** — define `run_eval` (does not call the LLM yet).
6. Run **v2** (skip if `v2-judged` is already logged and the clock is tight).
7. Print the metrics table, then open the standalone MLflow UI.

### 3. Compare in MLflow UI

Use the **standalone** `/mlflow` UI (`mlflow_ui` in attributes), not the embedded Experiments view.

Workspace **my-first-model** → experiment **`wings3-agent-eval-prod`**:

1. **Datasets** → `math_golden` — 8 records. This is the beat Act 3 cannot do (a named golden set).
2. **Evaluation** → run `v2-judged` — per-example `contains_expected`, `Correctness`, `numeric_and_clear`.
3. Open a row where substring and judge **disagree**, or a Fail with rationale, and **read the judge text**.

Eight rows × (1 agent + 2 judges) is about 24 LLM calls. Live numbers will vary on 3B. The story is a **reviewable gate**, not a production SLO.

### 4. CLI alternative (same workbench terminal)

```bash
cd …/demo/agent-tracing
export MLFLOW_WORKSPACE=my-first-model
export MLFLOW_EXPERIMENT_NAME=wings3-agent-eval-prod
python3 evaluate_agent_judges.py
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
| `JUDGE_API_KEY is missing` / env cell prints `JUDGE_MODEL=None` | RHOAI admission **strips** `secretKeyRef` / `envFrom` from the Notebook CR. The Secret must be **volume-mounted** at `/etc/wings3-judge-llm` (`workbench-wings3-demo.yaml`). Apply both manifests, start the workbench, restart the kernel, re-run the env cell (it reads those files into `os.environ`). Do not commit the token. |
| Judge JSON-parse / empty rationale | Try `JUDGE_MODEL=llama-scout-17b` (less reasoning-token wrapping than gpt-oss). Still compare `contains_expected` on that row. |
| `only one expected_response or expected_facts` | Correctness forbids both. Git JSONL has `expected_answer` + `expected_facts` only. Re-run the register cell so `math_golden` is **refreshed from git** (do not silent-reuse). Then re-run `v2-judged`. |
| Eval row errors / 3B context | Same as Act 2/3 — one tool per turn, `max_tokens` 256; skip remaining rows if needed |
| `create_dataset` already exists | Register cell drops existing rows and merges git. Do not skip that cell. |
| MLflow UI 504 | Open Evaluation in the browser; do not `search_traces` from the SDK |
| Cell 6 hangs > a few minutes; GPU idle | Not waiting on vLLM. MLflow 3.13 `evaluate()` default thread pool deadlocks while logging traces (`import` lock + Databricks/Spark probe). **Restart kernel** — Interrupt will not break it. Re-run from the env cell (the `run_eval` cell sets `MLFLOW_GENAI_EVAL_MAX_WORKERS=1`). Or skip live eval and open a pre-logged `v2-judged`. |
| vLLM cold / clock | Walk SHOW cells; open a pre-logged `v2-judged` run |

## Verification

- [ ] 3B-agent / hosted-judge split was spoken **before** the cells
- [ ] Golden JSONL and `expected_facts` were visible in the notebook
- [ ] Dataset `math_golden` exists in the MLflow Datasets tab
- [ ] Run `v2-judged` exists in experiment `wings3-agent-eval-prod` (live or pre-logged)
- [ ] A judge rationale (or substring/judge disagreement) was read in the Evaluation UI

## Learning outcomes

Registered evaluation datasets; hybrid deterministic + LLM-as-judge scorers; judge model pointed at in-cluster vLLM; Evaluation UI rationales as a reviewable gate.

## References

- [03_prod_eval_judges.ipynb](../demo/notebooks/03_prod_eval_judges.ipynb) — stage path
- [evaluate_agent_judges.py](../demo/agent-tracing/evaluate_agent_judges.py) — CLI only
- [math_golden.jsonl](../demo/datasets/math_golden.jsonl) — golden set
- [MLflow LLM-as-a-Judge](https://mlflow.org/docs/latest/genai/eval-monitor/scorers/llm-judge/)
