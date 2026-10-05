# WINGS3 — Agent observability with MLflow on OpenShift AI

Demo assets for a 60-minute deep dive: trace a tool-using agent with MLflow on
OpenShift AI, evaluate a prompt change, gate it with a golden dataset + LLM
judges, then run platform benchmarks (EvalHub) and safety scans (Garak).

Public repo: https://github.com/gmodzelewski/wings

Two 60-minute paths run on the same cluster:

| Hour | On camera | Guide |
|------|-----------|-------|
| WINGS teaching | Notebooks + slides | [walkthrough/00-presenter-setup.md](walkthrough/00-presenter-setup.md) |
| Customer / partner | Pre-staged `/mlflow` UI only — no deck | [walkthrough/customer-ui-click-script.md](walkthrough/customer-ui-click-script.md) |

## Quickstart

Prerequisites: `oc login` to a cluster with **RHOAI 3.4 or 3.5 already installed**.

```bash
./install.sh              # install the full demo
./install.sh --skip-llm   # GPU-less sandbox (no InferenceService)

./check.sh                # verify the demo is healthy; exit 1 on failure

./uninstall.sh            # remove the workbench only (shared-cluster safe)
./uninstall.sh --all      # full demo reset (keeps LLM InferenceService + operators)
```

Install patches the MLflow + EvalHub operators to `Managed`, enables
Models-as-a-Service with four workshop ExternalModels, applies everything in
`manifests/`, creates the workbench and (on GPU clusters) the LLM
InferenceService, and clones this repo into the workbench at
`/opt/app-root/src/wings`.

Useful environment variables (all optional):

| Variable | Purpose |
|----------|---------|
| `WINGS3_MAAS_UPSTREAM_API_KEY` | Workshop upstream token for the ExternalModels (never commit it) |
| `WINGS3_LLM_STORAGE_URI` | Model storage URI if no InferenceService exists yet |
| `WINGS3_VERBOSE=1` | Detailed install progress |
| `WINGS3_SKIP_OGX` / `WINGS3_SKIP_MCP` / `WINGS3_SKIP_SERVICEMESH` | Skip Gen AI Studio layers on small clusters |

Full pre-stage checklist and run-of-show:
[walkthrough/00-presenter-setup.md](walkthrough/00-presenter-setup.md).
Cluster-specific URLs: [walkthrough/partials/_attributes.md](walkthrough/partials/_attributes.md).

## Where the demo runs

Acts 2–4 run in the JupyterLab workbench **`wings3-demo`** (namespace
`my-first-model`). Create it only with
`oc apply -f manifests/workbench-wings3-demo.yaml` — the dashboard **Create
workbench** button uses the wrong ServiceAccount and gets `PERMISSION_DENIED`.
Notebooks live in `demo/notebooks/` (01 tracing, 02 evaluation, 03 judges,
04 EvalHub/Garak); Act 5 runs in the **Develop & train → Evaluations** console.

## Layout

- `walkthrough/` — presenter guides: [index](walkthrough/index.md), modules 0–5, customer click script
- `manifests/` — all cluster YAML applied by install; apply order and details in [manifests/README.md](manifests/README.md)
- `demo/notebooks/` — the four on-camera notebooks
- `demo/agent-tracing/` — Python sources behind the notebooks (agent, eval, judges)
- `demo/evalhub/` — Act 5 job templates; `demo/datasets/` — golden eval set; `demo/assets/` — fallback screenshots
- `scripts/` — install/uninstall/check engine (`wings3_lib.sh`, `check_demo.py`), deck builders, helper scripts
- `tests/` — pytest suite for scripts, deck content, and demo code
- `install.sh` / `check.sh` / `uninstall.sh` — thin wrappers into `scripts/`

## Rebuild the slides

```bash
python3 scripts/build_wings3_deck.py           # plain deck → MLflow-on-RHOAI-Deep-Dive.pptx
python3 scripts/revise_wings3_branded_deck.py  # branded deck → AI Wings 3 - Deep Dive.pptx
```

Both `.pptx` outputs are gitignored — rebuild after cloning.
