#!/usr/bin/env bash
# Pre-stage unguarded + guarded Garak runs for the Act 5 guardrails coda.
set -euo pipefail

WINGS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="${WINGS_PROJECT:-my-first-model}"
MODEL="${WINGS_EVAL_MODEL:-}"
BENCHMARK="${WINGS_EVAL_BENCHMARK:-quick}"
UNGUARDED_URL="${WINGS_UNGUARDED_URL:-http://wings-unguarded-llm.nemo-quickstart.svc.cluster.local:8080/v1}"
GUARDED_URL="${WINGS_GUARDED_URL:-http://wings-guarded-llm.nemo-quickstart.svc.cluster.local:8080/v1}"
NEMO_NS="${WINGS_NEMO_NS:-nemo-quickstart}"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Submits two EvalHub Garak jobs (benchmark \${WINGS_EVAL_BENCHMARK:-quick}):
  wings-demo-garak-unguarded  → unguarded OpenAI-compatible URL
  wings-demo-garak-guarded    → guarded stub / NeMo-like URL …/v1

Env:
  WINGS_EVAL_BENCHMARK   Garak id (default quick; try owasp_llm_top10 for richer ASR)
  WINGS_EVAL_WAIT_ATTEMPTS  forwarded to submit (raise for long suites, e.g. 180)

Requires deploy/evalhub in ${PROJECT} and a reachable unguarded endpoint.
EOF
}

die() { echo "error: $*" >&2; exit 1; }

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

command -v oc >/dev/null || die "oc not on PATH"
oc whoami >/dev/null || die "oc whoami failed"
oc get deploy evalhub -n "$PROJECT" >/dev/null 2>&1 \
  || die "deploy/evalhub missing in ${PROJECT} — apply manifests/evalhub-instance.yaml"

if [[ -z "$MODEL" ]]; then
  MODEL=$(oc get configmap wings-llm-endpoint -n "$PROJECT" \
    -o jsonpath='{.data.model_name}' 2>/dev/null || true)
fi
MODEL="${MODEL:-qwen36-35b-a3b}"

echo "Benchmark: ${BENCHMARK}"
echo "Unguarded: ${UNGUARDED_URL}"
echo "Guarded:   ${GUARDED_URL}"

export WINGS_PROJECT="$PROJECT"
# Prefer experiment tracking via wings-mlflow-ws-proxy (injects X-MLflow-Workspace).
unset WINGS_EVAL_NO_EXPERIMENT || true
# Long suites (owasp_llm_top10, …) routinely exceed the submit default ~7.5–15 min wait.
if [[ "$BENCHMARK" != "quick" && -z "${WINGS_EVAL_WAIT_ATTEMPTS:-}" ]]; then
  export WINGS_EVAL_WAIT_ATTEMPTS=720  # ~60 min @ 5s
  echo "WINGS_EVAL_WAIT_ATTEMPTS defaulted to ${WINGS_EVAL_WAIT_ATTEMPTS} for ${BENCHMARK}"
fi
"${WINGS_ROOT}/scripts/submit_evalhub_eval_run.sh" \
  --benchmark "$BENCHMARK" \
  --name wings-demo-garak-unguarded \
  --endpoint "$UNGUARDED_URL" \
  --model "$MODEL"

"${WINGS_ROOT}/scripts/submit_evalhub_eval_run.sh" \
  --benchmark "$BENCHMARK" \
  --name wings-demo-garak-guarded \
  --endpoint "$GUARDED_URL" \
  --model "$MODEL"

echo "Pre-staged. Open Develop & train → Evaluations → ${PROJECT}"
echo "MLflow Runs (not GenAI Traces): /mlflow → workspace ${PROJECT} → wings-evalhub-garak"
if [[ "$BENCHMARK" == "quick" ]]; then
  echo "Expect (quick): unguarded high ASR / Fail; guarded low ASR (refuse stub may be near-perfect)"
else
  echo "Expect (${BENCHMARK}): unguarded high ASR / Fail; guarded partial ASR (improved, not always 100%)"
fi
