# Module 5 — EvalHub and Garak platform gates

**Time:** 14 minutes (6 min EvalHub + 8 min Garak) | **Role:** Platform engineer / MLOps  
**Where:** RHOAI console (**Develop & train → Evaluations**) + optional notebook `04_evalhub_garak.ipynb`  
**Target:** Same agent endpoint as Acts 2–4 (`MAAS_BASE_URL` from Secret `wings3-judge-llm`; ConfigMap `wings3-llm-endpoint` is synced at install)

## Know

**Red thread step 5:** MLflow judges on `math_golden` prove *correctness*. EvalHub **operationalizes** benchmarks as platform jobs. Garak stress-tests *safety under attack*.

| Tool | Question it answers |
|------|---------------------|
| MLflow `v2-judged` | Is the answer right? |
| EvalHub benchmark (lm-eval-harness backend) | Does the model pass a benchmark gate? |
| Garak benchmark | Does the model resist adversarial prompts? |

**RHOAI 3.5 console vocabulary:** The UI asks for **Benchmark** or **Benchmark suite** — not a provider name. EvalHub picks the backend (`lm_evaluation_harness`, `garak`, …) from the benchmark you select. **Benchmark suite** = a collection (e.g. `standard-llm-evals-v1`). **Benchmark** = one task (e.g. `gsm8k`, Garak `quick`).

**Say before Act 5 demos:**

> Same endpoint the calculator agent called in Act 2. MLflow is the system of record; EvalHub and Garak are platform gates before promote.

## UI roles (do not conflate)

| Surface | Job in the story | What it is **not** |
|---------|------------------|--------------------|
| **Develop & train → Evaluations** | **Measure** — list EvalHub jobs, start **benchmark** / **Garak** scans, open HTML reports | Not a NeMo / Colang / GuardrailsOrchestrator settings page |
| **Gen AI studio → Playground → Guardrails** | **Intervene (optics)** — TP experiment toggles for “we add safety” | Not what retargets the next EvalHub job URL |
| **NemoGuardrails CR + Route `…/v1`** | **Intervene (real)** — OpenAI-compatible **guarded** endpoint for the second Garak run | Not configured inside the Evaluations form |

There is no “project settings → TrustyAI → Guardrails” admin page that flips protection for whatever endpoint EvalHub is hitting. Playground toggles alone do **not** rewrite the Garak target URL — you must point the second job at the NeMo Route (or another guarded URL) on purpose.

## Prerequisites

- `./scripts/install.sh` completed (InferenceService Ready, ConfigMap `wings3-llm-endpoint` applied)
- EvalHub operator `Managed` and **EvalHub CR** `evalhub` in `my-first-model` (`./check.sh` → `evalhub instance`)
- Optional: submit jobs from **Evaluations** UI or `scripts/submit_evalhub_demo_jobs.sh` before the session
- Session 1 end state: `v2-judged` in experiment `wings3-agent-eval-prod`

Endpoint (read from ConfigMap — do not hardcode):

```bash
oc get configmap wings3-llm-endpoint -n my-first-model \
  -o jsonpath='model={.data.model_name}{"\n"}url={.data.openai_base_url}{"\n"}'
```

On MaaS-only clusters (e.g. stormshift) this is **`gpt-oss-120b`** at the in-cluster MaaS gateway URL. On GPU sandbox clusters it may still be **`llama-32-3b-instruct`** at an in-cluster vLLM URL (`*.svc.cluster.local`).

## Demo A — EvalHub lm-eval job (6 min)

### 1. Open Evaluations (RHOAI 3.5)

There is **no** project-level **EvalHub** sidebar tile on 3.5. Use global navigation:

**Develop & train → Evaluations** → project filter **`my-first-model`**.

**No evaluation runs** on the list page is normal before your first submission. After **Start evaluation run**, you should see **Benchmark** and **Benchmark suite** — that means the EvalHub CR is wired up (`manifests/evalhub-instance.yaml`).

### 2. Create evaluation

**RHOAI 3.5 UI gap:** the console form has **no** field for `model.auth.secret_ref`. A Secret alone is not enough — EvalHub only mounts `hf-token` when the job payload references it. For `meta-llama/*` tokenizers, **pre-stage with the API script** (below), then open the run in **Evaluations**.

#### Option A — API script (recommended for WINGS; wires `hf-token`)

1. Create the HuggingFace secret (key must be **`hf-token`**, not `token`):

```bash
oc create secret generic hf-token -n my-first-model \
  --from-literal=hf-token='<your_huggingface_token>'
```

2. **Accept the model license** on [huggingface.co/meta-llama/Llama-3.2-3B-Instruct](https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct) while logged in as the **same HF account** as the token. A valid token alone is not enough — without license acceptance, downloads return 403 *not in the authorized list* even when adapter logs `HF_TOKEN set from model auth secret`.

3. Verify license + token (optional but saves demo time):

```bash
./scripts/verify_hf_gated_access.sh
```

4. Submit from your laptop (results appear in the Evaluations UI):

```bash
./scripts/submit_evalhub_eval_run.sh --benchmark arc_easy --name wings3-demo-arc-easy
```

The script sets `model.auth.secret_ref: hf-token`, `tokenizer: meta-llama/Llama-3.2-3B-Instruct`, model name `llama-32-3b-instruct`, and the in-cluster endpoint.

**Demo fallback** (no Llama license on stage): use an ungated tokenizer — still scores against the vLLM endpoint:

```bash
./scripts/submit_evalhub_eval_run.sh --benchmark arc_easy --tokenizer gpt2 --name wings3-demo-arc-easy
```

#### Option B — Console form (no gated tokenizer)

Use **Start evaluation run** in the UI only if you do **not** need a gated HuggingFace tokenizer (limited on Llama 3.2 demos):

1. **Benchmark** → e.g. `arc_easy`
2. **Endpoint URL** and **model name** `llama-32-3b-instruct`
3. **Benchmark parameters:**

```json
{
  "tokenizer": "meta-llama/Llama-3.2-3B-Instruct",
  "num_examples": 10,
  "limit": 5
}
```

Without `model.auth.secret_ref` (API/script only today), gated `meta-llama/*` fails even when Secret `hf-token` exists in the namespace.

Do **not** expect a **Provider** dropdown — `lm_evaluation_harness` is selected automatically for harness benchmarks.

### 3. Run and review

Submit → **Running** → **Completed**. Open the run row for metrics and pass/fail.

**Tie back:** *"Act 4 judged 8 golden rows; EvalHub runs harness tasks as a schedulable platform job."*

## Demo B — Garak scan + HTML report (8 min)

### 1. Submit Garak evaluation

#### Option A — API script (recommended; normalizes endpoint `/v1`)

```bash
./scripts/submit_evalhub_eval_run.sh --benchmark quick --name wings3-demo-garak-quick
```

The script auto-selects provider `garak` for benchmarks like `quick`, `intents`, and `owasp_llm_top10`. Results appear in **Develop & train → Evaluations**.

#### Option B — Console form

**Develop & train → Evaluations** → project **`my-first-model`** → **Start evaluation run**.

1. **Select evaluation type:** **Benchmark**
2. **Benchmark:** a Garak probe — for live demo use **`quick`** (~2 min smoke test). For a richer story use **`intents`** or **`owasp_llm_top10`** (longer; pre-stage before the session)
3. **Endpoint URL** — must end with **`/v1`** (copy verbatim from ConfigMap `wings3-llm-endpoint`)
4. **Model name** — copy from the same ConfigMap (`model_name`; often `gpt-oss-120b` on MaaS clusters)
5. **API key** — paste a minted MaaS `sk-*` key (not `DUMMY`) when the endpoint is a MaaS gateway
6. **Evaluate**

Garak runs as the `garak` provider under the hood; you choose it by picking a Garak benchmark, not a provider field. If the endpoint omits `/v1`, Garak calls `...:8080/chat/completions` and vLLM returns **404 Not Found**.

### 2. List view vs detail — **Completed** vs **Pass**

Garak uses two different success concepts. Do not treat the list row as the security gate.

WINGS submit scripts set `primary_score.lower_is_better: true` on Garak jobs. That flips the list **Score** into a **normalised evaluation score** (higher = better), not raw ASR.

| UI surface | What it means (with WINGS Garak submit) | Example on `quick` |
|------------|------------------------------------------|-------------------|
| **Status: Completed** | The scan **ran to completion** (no adapter crash). | Job finished; probes executed. |
| **Score** (list) | Normalised evaluation score from ASR. List hides Score when job-level `pass` is **false** (shows **-**). | Unguarded ASR 1.0 → Fail → **-**. Guarded ASR 0.0 → Pass → **100%**. |
| **Pass / Fail** + metrics (detail) | Benchmark gate on **attack success rate** (lower is better; threshold **0.3**). | Unguarded ASR **1.0 Fail**; guarded ASR **0.0 Pass**. |

Raw ASR still lives in the **benchmark detail**, HTML report, and MLflow metric `attack_success_rate` (1.0 vs 0.0). Do not read the list Score as “attack success %” once `lower_is_better` is set.

**Say on stage:**

> Completed means the platform job finished. Fail on the benchmark detail means the model did not pass the safety gate — which is a valid demo outcome. We are not looking for a green check on Garak; we are looking for signal.

Trust the **benchmark detail** and the HTML report for ASR. The list Score is only a coarse pass/fail percentage after polarity correction.

A **Completed + Fail** Garak run is ideal for Demo B: open the report and walk one **vulnerable** probe (model complied) — that is the “correct in MLflow, not safe under attack” beat.

### 3. Pipeline status (optional, 1 min)

Job detail → Kubeflow pipeline link if shown. Skip deep Kubeflow UI if the clock is tight.

### 4. Open HTML report

Walk **two** probe categories:

- One **resisted** — model refused or gave a safe response
- One **vulnerable** — model complied (redact sensitive text on screen)

### 5. Tie back

> Remediate: prompt change, model swap, runtime guardrails, or block promotion until Garak passes.

Open MLflow → `v2-judged` where the judge passed — *"correct but not necessarily safe."*

## Demo C — Guardrails coda (before / intervene / after)

Optional short beat after Demo B when you want the full “measure → change → re-measure” story.

1. **Before:** Open pre-staged **`wings3-demo-garak-unguarded`** in **Evaluations** (or Demo B’s failing `quick` run). List Score is often **-** (job-level Fail); open detail for ASR **100%** / **Fail** and the HTML report.
2. **Intervene (UI-friendly):** Cut to **Gen AI studio → Playground → Guardrails** — flip input/output rails. **Say honestly:** this is TP Playground config for the safety story, not an EvalHub form control.
3. **Wire for re-eval (must be real):** Second Garak job must target a **guarded** OpenAI-compatible URL. Prefer NeMo Route `…/v1` when EvalHub pods can reach it (TLS + auth). On this lab cluster, `./scripts/prestage_garak_before_after.sh` uses in-cluster **`wings3-guarded-llm`** (refuse-mode stub mirroring guarded behavior) because EvalHub job pods hit service-CA / kube-rbac issues against `nemoguardrails` HTTPS. Live Playground / curl demos still use the NeMo Route.
4. **After:** Open **`wings3-demo-garak-guarded`** — list Score **100%** (normalised: ASR 0), detail **Pass** / ASR **0.0**.

**Where to see which endpoint was tested:** Evaluations list/detail — job **tags** (`target:unguarded` / `target:guarded`) and **description**; detail **model.url**. MLflow → experiment `wings3-evalhub-garak` → run → **Parameters** `model_url` and `target_endpoint_kind` (logged by `submit_evalhub_eval_run.sh` after the job completes; default `--wait`). There is no product “guardrails used” badge.

Pre-stage both jobs (clock-safe):

```bash
./scripts/prestage_garak_before_after.sh
```

Lab fallback when the workshop upstream key is 401: apply `manifests/demo-openai-stub.yaml` (unguarded stub + shared server.py) plus `wings3-guarded-llm` refuse Deployment, and the updated `manifests/nemo-guardrails.yaml` (NeMo → stub + regex rails for live Route demos). Replace the upstream key for real Qwen with `./scripts/rotate_maas_upstream_key.sh` when you have a fresh `sk-oai-…` token.

## Notebook aid

[`demo/notebooks/04_evalhub_garak.ipynb`](../demo/notebooks/04_evalhub_garak.ipynb) — endpoint + job JSON templates. Primary demo remains the **Evaluations** console.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `LiteLLM Virtual Key expected. Received=DUMMY` / `401 auth_error` | MaaS gateway needs an `sk-*` API key. UI: replace default `DUMMY` in the **API key** field with a minted key (`oc get secret wings3-judge-llm -n my-first-model -o jsonpath='{.data.JUDGE_API_KEY}' \| base64 -d`). Or use `./scripts/submit_evalhub_eval_run.sh` (wires `model.auth.secret_ref` → `wings3-maas-upstream-api-key`). |
| Garak **Scan timed out after 600 seconds** / TLS `x509: certificate signed by unknown authority` in job logs | EvalHub job pods cannot reach the **external** `openshift-ai-inference-*` Route reliably. Re-run `./install.sh --skip-llm` (or `source scripts/wings3_lib.sh && sync_llm_endpoint_configmap`) so `wings3-llm-endpoint` uses the **workshop-direct** URL that probes successfully from the cluster. Then re-submit via `./scripts/submit_evalhub_eval_run.sh --benchmark quick`. |
| No **Evaluations** under **Develop & train** | RHOAI 3.5 default: `OdhDashboardConfig.spec.dashboardConfig.disableLMEval` is `true`. Set to `false`: `oc patch odhdashboardconfig odh-dashboard-config -n redhat-ods-applications --type=merge -p '{"spec":{"dashboardConfig":{"disableLMEval":false}}}'` then hard-refresh the dashboard; or re-run `./install.sh` |
| No **EvalHub** in project view | Normal on 3.5 — use **Develop & train → Evaluations** |
| List shows **No evaluation runs** | Normal until you submit a run from **Start evaluation run** |
| **Start evaluation run** has no Benchmark / Benchmark suite | Missing EvalHub CR — `oc apply -f manifests/evalhub-instance.yaml` (`spec.tenancy: single`) or re-run `./install.sh`; set project filter to **`my-first-model`** (not `default`) |
| EvalHub CR phase `Error` / `InvalidPlacement` | Remove tenant label: `oc label namespace my-first-model evalhub.trustyai.opendatahub.io/tenant-` — single-tenant EvalHub cannot run in a tenant-labelled namespace |
| `EvalHub CR not found` in eval-hub-ui logs | Same — deploy `evalhub/evalhub` in `my-first-model` |
| LMEvalJob exists but UI empty | `LMEvalJob` is a separate TrustyAI CR; dashboard list is populated by evaluation runs started from **Evaluations** |
| `Workspace context is required` on **Evaluate** | EvalHub `MLFLOW_TRACKING_URI` must include the `/mlflow` path (see `manifests/evalhub-instance.yaml`). Re-apply and restart: `oc apply -f manifests/evalhub-instance.yaml && oc rollout restart deploy/evalhub -n my-first-model` |
| Empty **GenAI → Traces** for Garak / experiment `wings3-evalhub-garak` has no Traces | Expected. Garak does **not** use `mlflow.langchain.autolog()`. Look under **Runs** (metrics/HTML artifacts), or **Develop & train → Evaluations**. Traces are Act 2 only (`01_agent_tracing_autolog.ipynb`). |
| MLflow experiment exists but **no Runs**; adapter logs `run ID: None` | Job was submitted **without** `experiment.name`. Re-submit via `./scripts/submit_evalhub_eval_run.sh` (defaults to `wings3-evalhub-garak` / `wings3-evalhub-lmeval`) or include `"experiment": {"name": "wings3-evalhub-garak"}` in the REST body. Console forms that omit experiment tracking will skip MLflow. |
| `not a valid model identifier listed on huggingface.co` | Keep **model name** `llama-32-3b-instruct`; set **Benchmark parameters** `tokenizer` to `meta-llama/Llama-3.2-3B-Instruct` (see Demo A step 9) |
| Gated HuggingFace / `authentication required` / `not in the authorized list` | Check adapter log: `HF_TOKEN set from model auth secret` means the secret **is** wired. If download still fails, the HF account behind the token has **not accepted** the [Llama license](https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct) — run `./scripts/verify_hf_gated_access.sh`. UI cannot set `secret_ref` on 3.5; use `./scripts/submit_evalhub_eval_run.sh`. |
| Secret exists but job still fails HF auth | Creating the Secret is not enough; the job must include `model.auth.secret_ref: hf-token` (script or API). UI-only submits do not mount it. |
| Need a run **now** without Llama license | `./scripts/submit_evalhub_eval_run.sh --benchmark arc_easy --tokenizer gpt2` (ungated tokenizer; job completes against the same vLLM endpoint). |
| Job fails — endpoint unreachable | `oc get inferenceservice llama-32-3b-instruct -n my-first-model` must be Ready |
| No Garak benchmarks in dropdown | EvalHub CR must include `garak` in `spec.providers`; use `demo/assets/placeholders/demo3-garak-pipeline.png` as fallback |
| Garak `404 Not Found` / `openai.NotFoundError` | **Endpoint URL must end with `/v1`**. UI often submits `...:8080` without the suffix; use the ConfigMap value or `./scripts/submit_evalhub_eval_run.sh --benchmark quick` (script normalizes the URL). |
| Garak list shows **Completed** and **100%**, detail shows **Fail** | Older jobs submitted **without** `lower_is_better` treat list Score as raw ASR (1.0 → 100%) while benchmark detail correctly **Fails** ASR > 0.3. Re-submit with `./scripts/submit_evalhub_eval_run.sh` (sets `lower_is_better: true`). |
| Guarded Garak list Score is **-** instead of a percentage | EvalHub list hides Score when job-level `pass` is false. Without `lower_is_better`, ASR 0 → `pass: false` → **-**. WINGS Garak submit sets `lower_is_better: true` so guarded ASR 0 becomes normalised Score **100%** and `pass: true`. Raw ASR **0.0** is still on the detail / MLflow run. |
| Guarded list shows **100%** but you expected **0%** | List Score is **not** ASR after polarity correction — **100%** means “evaluation passed / ASR 0”. Open detail or MLflow `attack_success_rate` for the **0.0** attack rate. |
| Garak slow (>5 min) | Use benchmark **`quick`** on stage, or pre-stage **`intents`** / **`owasp_llm_top10`** before the session |
| RBAC denied | Platform admin account or pre-configured namespace |

## Verification

- [ ] Same endpoint as calculator agent
- [ ] lm-eval job completed with visible metrics
- [ ] Garak run **Completed**; benchmark detail **Pass or Fail** understood (ASR lower is better; Fail is a valid demo outcome)
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
