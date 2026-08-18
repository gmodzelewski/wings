# Module 3 — Workbench evaluation improvement

**Time:** 15 minutes | **Persona:** Data scientist  
**Where:** Same JupyterLab workbench as Module 2 — notebook first

## Know

Traces show **what** the agent did. `mlflow.genai.evaluate()` scores **whether a prompt change moved a toy gate**.

**Say this before you run cells:** `contains_expected` is a **substring** check on **four** math rows. It is not an LLM-as-judge and not a production SLO. Rehearsal moved `contains_expected/mean` 25% → 50%; `has_numeric_result` was already 100% on both. Celebrate **direction of improvement**, then say you would add judges and a larger dataset before a real promote gate.

Scorer **`contains_expected`**: true if the model output string contains the dataset’s `expected_answer` (for example `16` in “256 divided by 16”).

| Version | System prompt | Why it scores lower/higher |
|---------|---------------|----------------------------|
| v1 | `You are a helper. Answer briefly.` | May skip the tool or omit the number |
| v2 | Precise math assistant; **always use calculator**; state the numeric result | More likely to include the expected digits |

**On stage:** if v1 already exists from rehearsal, run **v2 only** and compare in the Evaluation tab.

## Show

### 1. Open the notebook

In JupyterLab: `demo/notebooks/02_eval_improvement.ipynb`

### 2. Stop at each SHOW comment (top to bottom)

The notebook inlines the eval code. Do **not** open `evaluate_agent.py` on stage (that file is CLI / `bootstrap.sh --warmup` only).

1. Env — injected `MLFLOW_*`.
2. **SHOW: prompts** — v1 vs v2 text on screen.
3. **SHOW: four-row dataset**.
4. **SHOW: substring scorer** (`contains_expected`).
5. **SHOW: `mlflow.genai.evaluate()`** — define `run_eval` (does not call the LLM yet).
6. Run **v1** (skip if pre-logged).
7. Run **v2**.
8. Print the metrics table, then open the standalone MLflow UI.
### 3. Compare in MLflow UI

Use the **standalone** `/mlflow` UI (same as Act 2), not the embedded Experiments view.

**Evaluation** tab → experiment `wings3-agent-eval` → `v1-baseline` vs `v2-improved-prompt`.

Pick a **False** `contains_expected` row and read the output, then contrast a **True** row that includes the number.

**Expected (this cluster, 18 Aug 2026):** `contains_expected/mean` **25% → 50%**; `has_numeric_result/mean` 100% both runs. Your live numbers may differ; the story is **direction of improvement**, not a production SLO.

### 4. CLI alternative (same workbench terminal)

```bash
cd …/demo/agent-tracing
export MLFLOW_WORKSPACE=my-first-model
export MLFLOW_EXPERIMENT_NAME=wings3-agent-eval
export WINGS3_PROMPT_VERSION=v1 && python3 evaluate_agent.py
export WINGS3_PROMPT_VERSION=v2 && python3 evaluate_agent.py
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ModuleNotFoundError: No module named 'langchain_core'` | Same as Act 2: run the **1b** `%pip install` cell first (`--extra-index-url https://pypi.org/simple`), then re-run the env cell. Venv is not on the PVC. |
| `Field required` / calculator `b` missing | Eval row 3 is sqrt(144). 3B omits `b`. Re-run the scorer cell so `b` is optional, then v2. Two-step rows (`25*17+89`) can still fail: 3B is one tool call per turn. |
| `Workspace context is required` | `os.environ["MLFLOW_WORKSPACE"] = "my-first-model"` then re-run |
| Empty `MLFLOW_TRACKING_URI` | Stop/start the workbench; confirm `opendatahub.io/mlflow-instance=mlflow` |
| Third eval row errors / 3B context | Narrate the model limit; still compare `contains_expected` on the rows that scored |
| MLflow UI 504 | Open Evaluation in the browser; do not `search_traces` from the SDK |
| v1 and v2 look identical | Confirm you ran `run_eval("v1")` then `run_eval("v2")` and that the prompt cell printed both strings |

## Verification

- [ ] Substring-scorer caveat was spoken **before** the cells
- [ ] Prompts v1 and v2 were visible in the notebook
- [ ] v1 and v2 runs exist in MLflow
- [ ] A False `contains_expected` row was read in the Evaluation UI
- [ ] v2 `contains_expected` ≥ v1 (or you can explain a regression from a failed LLM call)

## Fallback screenshots

`18-eval-metrics.png` and `19-eval-per-example.png` are from this cluster (`wings3-agent-eval`, v1 25% → v2 50% `contains_expected`, recaptured 18 Aug 2026). Prefer the live UI.

## Learning outcomes

Custom scorers; prompt iteration tied to a metric; honest scope of a substring gate; workbench-native MLflow.

## References

- [02_eval_improvement.ipynb](../demo/notebooks/02_eval_improvement.ipynb) — stage path
- [evaluate_agent.py](../demo/agent-tracing/evaluate_agent.py) — CLI / warmup only

Follow-on (not in the 60-minute hour): [Module 4 — Production-grade eval](04-prod-eval-judges.md) — registered golden set + LLM judges.
