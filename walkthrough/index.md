# AgentOps-style walkthrough: MLflow on OpenShift AI

**Duration:** 60 minutes  
**Audience:** Platform engineers and AI engineers  
**Red thread:** Tracking server on the platform — you can see the agent; traces — you can fix it; eval — you can prove a prompt change helped; dataset + judge — you can ship; **EvalHub + Garak** — platform gates before promote (Act 5 / Session 2).

Customer / partner hour (no deck, Module 4 UI in the 60 minutes): [customer-ui-click-script.md](customer-ui-click-script.md). Pre-stage `math_golden` + `v2-judged` is required: [00-presenter-setup.md](00-presenter-setup.md).

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
| Intro + terms + product tour | 6 | Slides |
| 1 — Install | 10 | [01-install-platform.md](01-install-platform.md) |
| 2 — Autolog tracing | 22 | [02-agent-tracing-autolog.md](02-agent-tracing-autolog.md) |
| 3 — Evaluation | 15 | [03-workbench-evaluation.md](03-workbench-evaluation.md) |
| Production + Q&A | 9 | Slides |

**Pre-stage and clock-saving rules:** [00-presenter-setup.md](00-presenter-setup.md). Cluster scripts: [`../install.sh`](../install.sh), [`../check.sh`](../check.sh), and [`../uninstall.sh`](../uninstall.sh).

## Modules

| Module | Time | Where |
|--------|------|-------|
| 0 — Presenter setup | before the hour | [00-presenter-setup.md](00-presenter-setup.md) |
| 1 — Install | 10 min live | Laptop `oc get` + `/mlflow` + EvalHub/Garak console check |
| 2 — Autolog tracing | 22 min | JupyterLab notebook `01_agent_tracing_autolog.ipynb` |
| 3 — Evaluation | 15 min | Same workbench notebook |
| 4 — Datasets + judges | 20–25 min follow-on | Same workbench notebook `03_prod_eval_judges.ipynb` — [04-prod-eval-judges.md](04-prod-eval-judges.md). Not in the WINGS teaching hour. In the customer UI hour this is the close (pre-logged). |
| 5 — EvalHub + Garak | 14 min (Session 2) | EvalHub console + [05-evalhub-garak.md](05-evalhub-garak.md); notebook `04_evalhub_garak.ipynb` |

## Presentation

Delivered deck: `../AI Wings 3 - Deep Dive.pptx` (branded). Apply feedback copy and screenshot placeholders with `python3 scripts/revise_wings3_branded_deck.py`.

Plain rebuild (default Office layouts, speaker notes on every slide): `../MLflow-on-RHOAI-Deep-Dive.pptx` — teach → **PAUSE** to the cluster → RETURN wrap. Rebuild with `python3 scripts/build_wings3_deck.py`. Walkthrough modules stay the source of truth for live clicks.

Fallback screenshots in `assets/screenshots/` are from this cluster (recaptured 18 Aug 2026). Prefer the live UI. Recapture if the gateway host in `_attributes.md` changes.

## References

- [RHOAI 3.4 — Working with MLflow](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html/working_with_mlflow/index)
- [mlflow-on-rhoai](https://github.com/rh-aiservices-bu/mlflow-on-rhoai)
