# Act 5 — EvalHub and Garak

Platform gates after MLflow Acts 1–4. Same calculator agent endpoint: `llama-32-3b-instruct` in `my-first-model`.

## Red thread step 5

MLflow judges answer *is the answer right?* EvalHub runs **platform jobs** (benchmarks, pass/fail). Garak asks *is it safe under attack?*

## Endpoint

Read from the cluster ConfigMap (applied by `install.sh`):

```bash
oc get configmap wings3-llm-endpoint -n my-first-model -o yaml
```

In-cluster OpenAI-compatible URL:

```text
http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1
```

## Live demo (console)

On RHOAI 3.5 there is no project-level **EvalHub** tile. Use:

1. **Develop & train → Evaluations** → project filter **`my-first-model`**
2. **Start evaluation run** → benchmark **arc_easy** (lm-eval) → endpoint URL above (**must include `/v1`**)
3. **Start evaluation run** → benchmark **quick** (Garak) → same endpoint → open HTML report

Requires EvalHub CR `evalhub` in `my-first-model` (`manifests/evalhub-instance.yaml`, applied by `install.sh`).

Walkthrough: [`../../walkthrough/05-evalhub-garak.md`](../../walkthrough/05-evalhub-garak.md)

## Pre-stage (recommended)

```bash
# lm-eval (auto: lm_evaluation_harness)
./scripts/submit_evalhub_eval_run.sh --benchmark arc_easy --tokenizer gpt2

# Garak (auto: provider garak; endpoint normalized to .../v1)
./scripts/submit_evalhub_eval_run.sh --benchmark quick --name wings3-demo-garak-quick
```

`submit_evalhub_eval_run.sh` auto-detects Garak benchmarks (`quick`, `intents`, `owasp_llm_top10`, …). Override with `--provider garak` or `--provider lm`.

Garak scans can exceed five minutes for full suites. Submit **`quick`** before the session or use screenshots in `demo/assets/placeholders/`.

## Job templates

- [`jobs/lm-eval-demo.json`](jobs/lm-eval-demo.json) — REST/UI payload for lm-eval-harness
- [`jobs/garak-demo.json`](jobs/garak-demo.json) — REST/UI payload for Garak

Manifest equivalents: [`../../manifests/evalhub-demo-lm-eval.yaml`](../../manifests/evalhub-demo-lm-eval.yaml), [`../../manifests/evalhub-demo-garak.yaml`](../../manifests/evalhub-demo-garak.yaml)

## Notebook

Presenter aid: [`../notebooks/04_evalhub_garak.ipynb`](../notebooks/04_evalhub_garak.ipynb)
