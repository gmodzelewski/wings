# Presenter setup — stay inside 60 minutes

**Red thread (repeat each act):** Without a tracking server you cannot see the agent; without traces you cannot debug it; without eval you cannot prove it got better.

## Where each act runs

| Act | Persona | Where you run it |
|-----|---------|------------------|
| 1 — Install | Platform engineer | Laptop terminal (`oc get` only) + standalone MLflow UI (`/mlflow`) |
| 2 — Trace | AI developer | **JupyterLab workbench** `wings3-demo`, notebook `01_agent_tracing_autolog.ipynb` |
| 3 — Evaluate | Data scientist | **Same workbench**, notebook `02_eval_improvement.ipynb` |
| 4 — Datasets + judges (follow-on) | Data scientist | **Same workbench**, notebook `03_prod_eval_judges.ipynb` — not in the 60-minute hour |

Laptop + `oc port-forward` is an **appendix** for rehearsal only. On stage, use the workbench so the LLM URL is in-cluster and MLflow env vars are injected.

## 60-minute run-of-show

| Block | Minutes | Live vs pre-staged |
|-------|---------|-------------------|
| Intro + red thread + personas | 6 | Slides only |
| Act 1 — Install | 8 | **Pre-apply** the MLflow CR. Live: `oc get` CR and pod, then standalone `/mlflow` (screenshot 08) |
| Act 2 — Autolog | 22 | Workbench created from YAML. Live: **one** query; Traces: Error row, then OK 256÷16 **Details & Timeline** |
| Act 3 — Evaluate | 15 | v1 already logged if behind; live: **say the substring-scorer caveat first**, then v2 (or both if vLLM is warm) |
| Production + Q&A | 9 | Slides only |

If the operator is not `Managed` yet, do **not** wait for Ready on camera. Use backup screenshots and finish install after the session.

## Fast path (bootstrap / teardown)

From the repo root, after `oc login`. RHOAI must already be installed. Bootstrap instantiates ServingRuntime `llama-32-3b-instruct` from `vllm-cuda-runtime-template` and applies the lab InferenceService. Set `WINGS3_LLM_STORAGE_URI` if no InferenceService already exists (do not invent a HuggingFace URI).

```bash
./scripts/bootstrap.sh
./scripts/bootstrap.sh --warmup   # optional: one OK trace + v1 eval (slow)
./scripts/bootstrap.sh --skip-llm # GPU-less sandbox

# Shared-cluster safe: delete workbench Notebook/PVC/SA only
./scripts/teardown.sh

./scripts/teardown.sh --purge-llm                 # IS + ServingRuntime only
./scripts/teardown.sh --purge-mlflow              # also drops SQLite tracking data
./scripts/teardown.sh --purge-project --yes       # also deletes the LLM in my-first-model
```

`--dry-run` prints the plan without calling `oc`. Default teardown never removes `mlflowoperator` or the InferenceService.

## Pre-stage checklist (day before or morning of)

- [ ] `mlflowoperator` is `Managed` and the `mlflow` pod is `Running`
- [ ] `oc apply -f manifests/mlflow-dev.yaml` if no `MLflow` CR exists (do **not** apply this on camera)
- [ ] Namespace `my-first-model` has `opendatahub.io/dashboard=true`
- [ ] `bootstrap.sh` finished: InferenceService `llama-32-3b-instruct` is Ready (ServingRuntime from `vllm-cuda-runtime-template`; predictor strategy Recreate)
- [ ] Workbench in `my-first-model` is **Running** (not Stopped). Create **only** with `oc apply -f manifests/workbench-wings3-demo.yaml`. Do **not** use dashboard **Create workbench** — that notebook uses ServiceAccount `default` and gets `PERMISSION_DENIED`. The YAML Notebook uses ServiceAccount `wings3-demo` (the MLflow webhook binds RBAC to that name). After apply, **stop/start** the workbench so the initContainer can `git clone https://github.com/gmodzelewski/wings.git` into `/opt/app-root/src/wings`. Cluster must reach GitHub. If that path exists but is not a git repo, remove it and restart.
- [ ] JupyterLab file browser is this clone (`demo/notebooks/…`). `git pull --ff-only` from the repo root (terminal or the optional notebook cell).
- [ ] `pip install -r agent-tracing/requirements.txt --extra-index-url https://pypi.org/simple` already succeeded in the workbench (RHOAI 3.4 RHAI index has no langgraph 0.2). Re-run after a workbench restart; the venv is not on the PVC.
- [ ] Optional: v1 eval run already in experiment `wings3-agent-eval`
- [ ] Optional follow-on (Module 4, not the 60-minute hour): golden set registered as `math_golden` and one `v2-judged` run in experiment `wings3-agent-eval-prod`

Cluster-specific URLs live in [partials/_attributes.md](partials/_attributes.md).

## When the new cluster is up (not before)

1. Fill `gateway_host` / `mlflow_ui` in `_attributes.md`. Set `WINGS3_LLM_STORAGE_URI` from the catalog or copy it from an existing InferenceService, then run `bootstrap.sh`.
2. Recapture screenshots `08`, `12`, `14`, `18`, `19` on today’s `/mlflow` whenever the gateway host changes; flip captions to this cluster. (Done 18 Aug 2026 on sandbox956.)
3. Rebuild `MLflow-on-RHOAI-Deep-Dive.pptx` (`python3 scripts/build_wings3_deck.py`). Plain deck; speaker notes are in the notes pane.
4. Rehearse: Act 1 `oc get` only; Act 2 SHOW cells + Error then OK; Act 3 substring caveat before the cells.

## If you are behind the clock

- Act 2: run **one** query (`Calculate 256 divided by 16`), not three. In Traces: ~20s on an Error row (a rehearsal Error is fine if the live query is OK), then the OK 256÷16 **Details & Timeline** tree
- Act 3: skip v1 live; show existing v1 run and execute v2 only. Still say the substring-scorer caveat **before** the cells
- Do not debug `search_traces` from the laptop SDK — use the MLflow UI
