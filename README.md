# WINGS3 — MLflow on OpenShift AI (Deep Dive)

Public repo: https://github.com/gmodzelewski/wings

Two 60-minute paths on the same cluster:

| Hour | On camera | Guide |
|------|-----------|-------|
| WINGS teaching | Notebooks + slides | [walkthrough/00-presenter-setup.md](walkthrough/00-presenter-setup.md) |
| Customer / partner | Pre-staged `/mlflow` only — no deck | [walkthrough/customer-ui-click-script.md](walkthrough/customer-ui-click-script.md) |

**WINGS red thread:** Without a tracking server you cannot see the agent; without traces you cannot debug it; without eval you cannot prove it got better.

**Customer red thread:** operate → fix → prove → ship (golden set + judges in the hour; `math_golden` and `v2-judged` are required pre-stage).

## 60-minute run-of-show (WINGS teaching)

See [walkthrough/00-presenter-setup.md](walkthrough/00-presenter-setup.md).

| Block | Minutes | Live |
|-------|---------|------|
| Intro + personas | 6 | Slides |
| Act 1 Install | 8 | Pre-apply CR; live `oc get` + standalone `/mlflow` |
| Act 2 Autolog | 22 | Workbench `wings3-demo` (YAML); one query; Error then OK trace |
| Act 3 Evaluate | 15 | Same workbench notebook; substring scorer, not a production SLO |
| Production + Q&A | 9 | Slides |

## Where to run code

Acts 2 and 3 run in JupyterLab workbench **`wings3-demo`** in project `my-first-model`. Create it only with `oc apply -f manifests/workbench-wings3-demo.yaml` (named ServiceAccount `wings3-demo`). Dashboard **Create workbench** uses `default` and gets `PERMISSION_DENIED`. The workbench clones this repo to `/opt/app-root/src/wings` so you can `git pull` from JupyterLab. Laptop port-forward is rehearsal-only (appendix in Module 2).

## Cluster

Values: [walkthrough/partials/_attributes.md](walkthrough/partials/_attributes.md).

## Bootstrap / teardown

RHOAI must already be installed. Bootstrap creates the GPU InferenceService from the cluster `vllm-cuda-runtime-template` (set `WINGS3_LLM_STORAGE_URI` if none exists yet). Use `--skip-llm` on a GPU-less sandbox.

```bash
# After oc login, from this repo root:
./scripts/bootstrap.sh              # operator, MLflow CR, project, GPU model, workbench, git clone, pip
./scripts/bootstrap.sh --warmup     # plus one autolog query and v1 eval
./scripts/bootstrap.sh --skip-llm
./scripts/bootstrap.sh --dry-run

./scripts/teardown.sh               # workbench only (keeps MLflow, operator, LLM)
./scripts/teardown.sh --purge-llm
./scripts/teardown.sh --purge-mlflow
./scripts/teardown.sh --purge-project --yes
```

Details: [walkthrough/00-presenter-setup.md](walkthrough/00-presenter-setup.md).

## Workbench — autolog

JupyterLab root is this clone. Open `demo/notebooks/01_agent_tracing_autolog.ipynb`. Optional first cell: `git pull --ff-only`. On stage, stop at each **SHOW:** comment (calculator tool, `mlflow.langchain.autolog()`, one query `256 ÷ 16`).

CLI / warmup only:

```bash
cd demo/agent-tracing
pip install -r requirements.txt --extra-index-url https://pypi.org/simple
export MLFLOW_WORKSPACE=my-first-model
export MLFLOW_EXPERIMENT_NAME=wings3-agent-tracing
export MAAS_API_KEY=unused
export MAAS_MODEL=llama-32-3b-instruct
export MAAS_BASE_URL=http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1
export WINGS3_ONE_QUERY=1
python3 run_tracing_demo_autolog.py
```

## Workbench — evaluation

Open `demo/notebooks/02_eval_improvement.ipynb`. On stage, stop at each **SHOW:** comment (prompts, four-row dataset, substring scorer, `mlflow.genai.evaluate()`).

## Workbench — production-grade eval (follow-on for WINGS teaching)

Not in the WINGS teaching hour. **Required on camera for the customer UI hour** (pre-logged, not live-run). Open `demo/notebooks/03_prod_eval_judges.ipynb` only if asked. Guide: [walkthrough/04-prod-eval-judges.md](walkthrough/04-prod-eval-judges.md). Registered golden set + hybrid substring + LLM judges on hosted MaaS (`gpt-oss-120b`, Secret `wings3-judge-llm`); agent stays on in-cluster 3B. Scores in experiment `wings3-agent-eval-prod`. Pre-stage commands: [walkthrough/00-presenter-setup.md](walkthrough/00-presenter-setup.md) → Customer UI hour.

## Build presentation

Plain deck (default Office layouts, speaker notes on every slide). Teach → PAUSE → RETURN wrap. Run-of-show times stay 6 / 8 / 22 / 15 / 9; Module 4 is a follow-on section in the same file.

```bash
python3 scripts/build_wings3_deck.py
```

Output: [`MLflow-on-RHOAI-Deep-Dive.pptx`](MLflow-on-RHOAI-Deep-Dive.pptx)

## Layout

- `walkthrough/` — presenter setup, four modules (04 is a WINGS follow-on), and [customer-ui-click-script.md](walkthrough/customer-ui-click-script.md) (Module 4 UI in that hour)
- `demo/agent-tracing/` — autolog + evaluate scripts
- `demo/datasets/` — golden eval JSONL for Module 4
- `demo/notebooks/` — Act 2 autolog + Act 3 eval + Module 4 judges notebooks (`SHOW:` comments)
- `manifests/` — MLflow CR, dashboard namespace label, workbench `wings3-demo`, judge Secret `wings3-judge-llm` (empty `JUDGE_API_KEY`), InferenceService, prod CR example
- `scripts/` — diagrams, slide content, deck builder, `bootstrap.sh` / `teardown.sh`
- `tests/` — unit tests for deck, calculator, cluster scripts
