# AgentOps-style walkthrough: MLflow on OpenShift AI

**Duration:** 60 minutes  
**Audience:** Platform engineers, AI developers, data scientists  
**Red thread:** Without a tracking server you cannot see the agent; without traces you cannot debug it; without eval you cannot prove it got better.

## Environment

Cluster URLs and names: [partials/_attributes.md](partials/_attributes.md).

| Where | What |
|-------|------|
| OpenShift AI dashboard | Projects, workbench `wings3-demo` (YAML only — do not Create workbench) |
| MLflow UI | Standalone `/mlflow` — Traces, **Details & Timeline**, Evaluation (`mlflow_ui` in attributes) |
| JupyterLab workbench | Acts 2 and 3 — notebooks with **SHOW:** comments. File browser is the [wings](https://github.com/gmodzelewski/wings) git clone. Module 4 is a follow-on lab in the same workbench. |

## 60-minute run-of-show

| Block | Minutes | Guide |
|-------|---------|-------|
| Intro + personas | 6 | Slides |
| 1 — Install | 8 | [01-install-mlflow.md](01-install-mlflow.md) |
| 2 — Autolog tracing | 22 | [02-agent-tracing-autolog.md](02-agent-tracing-autolog.md) |
| 3 — Evaluation | 15 | [03-workbench-evaluation.md](03-workbench-evaluation.md) |
| Production + Q&A | 9 | Slides |

**Pre-stage and clock-saving rules:** [00-presenter-setup.md](00-presenter-setup.md). Cluster bootstrap/teardown: [`../scripts/bootstrap.sh`](../scripts/bootstrap.sh) and [`../scripts/teardown.sh`](../scripts/teardown.sh).

## Modules

| Module | Time | Where |
|--------|------|-------|
| 0 — Presenter setup | before the hour | [00-presenter-setup.md](00-presenter-setup.md) |
| 1 — Install | 8 min live | Laptop `oc get` + standalone `/mlflow` |
| 2 — Autolog tracing | 22 min | JupyterLab notebook `01_agent_tracing_autolog.ipynb` |
| 3 — Evaluation | 15 min | Same workbench notebook |
| 4 — Datasets + judges | 20–25 min follow-on | Same workbench notebook `03_prod_eval_judges.ipynb` — [04-prod-eval-judges.md](04-prod-eval-judges.md). Not in the 60-minute hour. |

## Presentation

Slides: `../MLflow-on-RHOAI-Deep-Dive.pptx` — plain title/bullets plus speaker notes; teach → **PAUSE** to the cluster → RETURN wrap. Read the notes pane. Walkthrough modules stay the source of truth for live clicks. Rebuild with `python3 scripts/build_wings3_deck.py`.

Fallback screenshots in `assets/screenshots/` are from this cluster (recaptured 18 Aug 2026). Prefer the live UI. Recapture if the gateway host in `_attributes.md` changes.

## References

- [RHOAI 3.4 — Working with MLflow](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow/index)
- [mlflow-on-rhoai](https://github.com/rh-aiservices-bu/mlflow-on-rhoai)
