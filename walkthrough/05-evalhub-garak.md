# Module 5 — EvalHub and Garak platform gates

**Time:** 14 minutes (6 min EvalHub + 8 min Garak) | **Role:** Platform engineer / MLOps  
**Where:** RHOAI console (EvalHub UI) + optional notebook `04_evalhub_garak.ipynb`  
**Target:** Same `llama-32-3b-instruct` endpoint as Acts 2–4

## Know

**Red thread step 5:** MLflow judges on `math_golden` prove *correctness*. EvalHub **operationalizes** benchmarks as platform jobs. Garak stress-tests *safety under attack*.

| Tool | Question it answers |
|------|---------------------|
| MLflow `v2-judged` | Is the answer right? |
| EvalHub lm-eval-harness | Does the model pass a benchmark gate? |
| Garak | Does the model resist adversarial prompts? |

**Say before Act 5 demos:**

> Same endpoint the calculator agent called in Act 2. MLflow is the system of record; EvalHub and Garak are platform gates before promote.

## Prerequisites

- `./scripts/install.sh` completed (InferenceService Ready, ConfigMap `wings3-llm-endpoint` applied)
- EvalHub operator `Managed` (Act 1)
- Optional: submit jobs from EvalHub UI or `scripts/submit_evalhub_demo_jobs.sh` before the session
- Session 1 end state: `v2-judged` in experiment `wings3-agent-eval-prod`

Endpoint (from ConfigMap):

```text
http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1
```

## Demo A — EvalHub lm-eval job (6 min)

### 1. Open EvalHub

OpenShift AI → project `my-first-model` → **EvalHub**.

### 2. Create evaluation

- **New evaluation**
- **Provider:** `lm-eval-harness`
- **Target:** endpoint URL above; model `llama-32-3b-instruct`
- **Task:** one small harness task (demo speed — not a full production suite)
- **Threshold:** pass/fail if the UI exposes it

### 3. Run and review

Submit → **running** → **completed**. Open metrics and pass/fail.

**Tie back:** *"Act 4 judged 8 golden rows; EvalHub runs harness tasks as a schedulable platform job."*

## Demo B — Garak scan + HTML report (8 min)

### 1. Submit Garak evaluation

EvalHub → **New evaluation** → provider **Garak** → same endpoint → default probe set.

### 2. Pipeline status (optional, 1 min)

Job detail → Kubeflow pipeline link if shown. Skip deep Kubeflow UI if the clock is tight.

### 3. Open HTML report

Walk **two** probe categories:

- One **resisted** — model refused or gave a safe response
- One **vulnerable** — model complied (redact sensitive text on screen)

### 4. Tie back

> Remediate: prompt change, model swap, runtime guardrails, or block promotion until Garak passes.

Open MLflow → `v2-judged` where the judge passed — *"correct but not necessarily safe."*

## Notebook aid

[`demo/notebooks/04_evalhub_garak.ipynb`](../demo/notebooks/04_evalhub_garak.ipynb) — endpoint + job JSON templates. Primary demo remains the EvalHub console.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| EvalHub not in console | Run `./check.sh`; enable operator off-camera |
| Job fails — endpoint unreachable | `oc get inferenceservice llama-32-3b-instruct -n my-first-model` must be Ready |
| Garak provider missing | Use `demo/assets/placeholders/demo3-garak-pipeline.png` |
| Garak slow (>5 min) | Pre-stage jobs from EvalHub UI before the session |
| RBAC denied | Platform admin account or pre-configured namespace |

## Verification

- [ ] Same endpoint as calculator agent
- [ ] lm-eval job completed with visible metrics
- [ ] Garak HTML report opened; one resisted + one vulnerable category discussed
- [ ] Compared to MLflow `v2-judged`

## Fallback screenshots

- `demo/assets/placeholders/demo1-evalhub-submit.png`
- `demo/assets/placeholders/demo2-evalhub-results.png`
- `demo/assets/placeholders/demo3-garak-pipeline.png`
- `demo/assets/placeholders/demo4-garak-html-report.png`

## Session handoff (from Session 1)

At end of Act 4 / start of Act 5:

> We've closed the loop in MLflow: golden dataset, registered judge, `v2-judged` with rationales. Act 5 asks how the **platform team** enforces that gate — and adds **safety testing** judges don't cover.
