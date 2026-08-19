# Customer UI hour — click script (no deck)

**Duration:** 60 minutes · **Room:** customer / partner · **Live:** standalone `/mlflow` only  
**Notebooks:** only if asked. **Slides:** none.

**Pain (say once, before any click):** A tool-using agent can be confidently wrong, and today you only see the chat bubble.

**Red thread (repeat before each screen):** Without a tracking server on the cluster you cannot **operate** the agent; without traces you cannot **fix** it; without eval you cannot **prove** a prompt change helped; without a golden set and a judge you can argue with, you cannot **ship**.

The calculator stands in for any tool (`retrieve_order`, `lookup_policy`, `call_api`). Do not rewrite the agent on camera.

Pre-stage (including **required** `math_golden` + `v2-judged`): [00-presenter-setup.md](00-presenter-setup.md) → **Customer UI hour**. Paste `mlflow_ui` from [partials/_attributes.md](partials/_attributes.md). Do not click the latest trace by default. Do not debug `search_traces` from the SDK.

| Clock | Screen | Click |
|-------|--------|-------|
| 0:00–1:00 | none | Spoken pain + red thread |
| 1:00–8:00 | MLflow home | Workspace `my-first-model` |
| 8:00–25:00 | Traces | Error row, then OK `256 ÷ 16` **Details & Timeline** |
| 25:00–40:00 | Evaluation | `wings3-agent-eval` · `v1-baseline` vs `v2-improved-prompt` |
| 40:00–52:00 | Datasets + Evaluation | `math_golden`, then `v2-judged` rationale |
| 52:00–60:00 | YAML or screenshot | [mlflow-prod.example.yaml](../manifests/mlflow-prod.example.yaml) + Q&A |

## Spoken line per screen

### 1. Home — operate

Open today’s `mlflow_ui`. Workspace dropdown → **my-first-model**. Optional 20s: operator is `Managed` (do not `oc apply`).

**Say:** This tracking server is a RHOAI component. Workspace is the OpenShift project. You are not exporting traces to LangSmith or Phoenix, and you are not running a DIY MLflow you have to HA and auth yourself. Without this UI the agent is a black box.

Fallback: `assets/screenshots/08-dashboard-verify.png`.

### 2. Traces — fix (MTTR)

Experiment **wings3-agent-tracing** → **Traces**. Open an **Error** row (not latest). Name the failure (timeout, empty response, or missing tool). Close it. Open the **OK** row **Calculate 256 divided by 16**. Drawer → **Details & Timeline**. Point at LangGraph → ChatOpenAI → **calculator** → ChatOpenAI.

**Say (Error):** Without traces you cannot fix it. This is MTTR: “the model is dumb” versus “the tool never ran.”

**Say (OK tree):** That calculator span is the feature. Autolog was one line; open the notebook only if someone asks. The tool is a stand-in for any production tool.

Fallback: `12-traces-list.png`, `14-traces-span-tree.png`.

### 3. Evaluation — prove (do not close on 25% → 50%)

**Say first:** `contains_expected` is a substring check on four math rows. It is not an LLM-as-judge and not a production SLO.

Experiment **wings3-agent-eval** → **Evaluation** → `v1-baseline` vs `v2-improved-prompt`. Open a **False** `contains_expected` row and read the output. Contrast a **True** row that includes the number.

**Say:** Without a number, prompt iteration is Slack opinion. The win is the pattern, not these toy percentages. Do not promote on a substring.

Fallback: `18-eval-metrics.png`, `19-eval-per-example.png`.

### 4. Datasets + judges — ship (this is the close)

**Say first:** the same Llama 3.2 3B is the agent and the judge. That is demo wiring, not a production split. A real gate uses a stronger dedicated judge and a larger golden set.

Experiment **wings3-agent-eval-prod**:

1. **Datasets** → `math_golden` (8 records). Named golden set, not a Python list.
2. **Evaluation** → `v2-judged`. Open a row where substring and judge **disagree**, or a Fail with rationale, and **read the judge text**.

**Say:** Without a golden set and a judge you can argue with, you cannot ship. Scores with rationales plus a cheap substring safety net — that is a reviewable gate. Do not walk out thinking 3B-as-judge is the product recommendation.

Lab detail if asked: [04-prod-eval-judges.md](04-prod-eval-judges.md).

If traces show `only one expected_response or expected_facts should be provided, not both`, the registered `math_golden` is stale. Re-run the Module 4 register cell (or `evaluate_agent_judges.py`) so rows refresh from git, then re-run `v2-judged`. Git has `expected_answer` + `expected_facts` only.

If traces show `Incorrect API key provided: unused` against `api.openai.com`, the judge URI was `openai:/…`. Re-run Module 4 after `git pull`: print must be `hosted_vllm:/llama-32-3b-instruct`. Then re-run `v2-judged`.

### 5. Production CR — then Q&A

Open [mlflow-prod.example.yaml](../manifests/mlflow-prod.example.yaml). Point at `backendStoreUriFrom` (Postgres) and `artifactsDestination` (S3). Do not apply it.

**Say:** SQLite plus PVC is the lab. Replicas greater than 1 need remote storage. Next step for the agent is this Module 4 pattern with a stronger judge.

## If you are behind the clock

- Skip `oc get`. Stay in `/mlflow`.
- Error row: 15s, name the failure, move to the OK tree.
- Eval: one False row, then jump to Datasets. Do not linger on 25% → 50%.
- Judges: one rationale out loud is the close. Skip remaining rows.
- No Jupyter unless asked. No `search_traces` from the laptop SDK.
