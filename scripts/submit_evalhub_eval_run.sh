#!/usr/bin/env bash
# Submit an EvalHub evaluation job via REST API.
#
# RHOAI 3.5 Evaluations UI cannot set model.auth.secret_ref (HuggingFace hf-token).
# Use this script for lm-eval when the tokenizer is gated (meta-llama/*), or for
# Garak benchmarks (auto-detected). Results still appear in Develop & train → Evaluations.
set -euo pipefail

WINGS3_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="${WINGS3_PROJECT:-my-first-model}"
LLM_MODEL="${WINGS3_LLM_MODEL:-llama-32-3b-instruct}"
HF_SECRET="${WINGS3_HF_SECRET:-hf-token}"
TOKENIZER="${WINGS3_EVAL_TOKENIZER:-meta-llama/Llama-3.2-3B-Instruct}"
BENCHMARK="${WINGS3_EVAL_BENCHMARK:-arc_easy}"
NUM_EXAMPLES="${WINGS3_EVAL_NUM_EXAMPLES:-10}"
LIMIT="${WINGS3_EVAL_LIMIT:-5}"
RUN_NAME="${WINGS3_EVAL_NAME:-wings3-demo-${BENCHMARK}}"
EVALHUB_DEPLOY="${WINGS3_EVALHUB_DEPLOY:-evalhub}"
PROVIDER="${WINGS3_EVAL_PROVIDER:-auto}"
MODEL_AUTH_SECRET="${WINGS3_EVAL_MODEL_AUTH_SECRET:-wings3-maas-upstream-api-key}"

# Garak benchmark ids (EvalHub provider garak)
GARAK_BENCHMARKS="quick intents owasp_llm_top10 avid avid_security avid_ethics avid_performance quality cwe"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Submit an EvalHub evaluation job via REST API (not the console form).

Provider auto-detection: Garak benchmarks (${GARAK_BENCHMARKS// /, }) use
provider_id garak; all others use lm_evaluation_harness.

Examples:
  $(basename "$0") --benchmark arc_easy --tokenizer gpt2
  $(basename "$0") --benchmark quick --name wings3-demo-garak-quick

Options:
  --benchmark ID     Benchmark id (default: ${BENCHMARK})
  --name NAME        Evaluation name (default: ${RUN_NAME})
  --provider MODE    auto | garak | lm (default: ${PROVIDER})
  --tokenizer ID     HuggingFace tokenizer for lm-eval (default: ${TOKENIZER})
  --hf-secret NAME   Secret with key hf-token (default: ${HF_SECRET})
  --no-hf-secret     Omit model.auth even if secret exists
  --model-auth-secret NAME  MaaS api-key secret (default: ${MODEL_AUTH_SECRET})
  -h, --help         Show this help

Watch: Develop & train → Evaluations → project ${PROJECT}
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

normalize_openai_endpoint() {
  local url="$1"
  url="${url%/}"
  if [[ "$url" != */v1 ]]; then
    url="${url}/v1"
  fi
  printf '%s' "$url"
}

is_garak_benchmark() {
  local id="$1"
  [[ " ${GARAK_BENCHMARKS} " == *" ${id} "* ]]
}

secret_has_api_key() {
  local name="$1"
  local b64=""
  b64=$(oc get secret "$name" -n "$PROJECT" -o jsonpath='{.data.api-key}' 2>/dev/null || true)
  [[ -n "$b64" ]]
}

endpoint_needs_maas_auth() {
  [[ "$1" != *".svc.cluster.local"* ]]
}

resolve_provider() {
  case "$PROVIDER" in
    auto)
      if is_garak_benchmark "$BENCHMARK"; then
        printf '%s' garak
      else
        printf '%s' lm
      fi
      ;;
    garak|lm) printf '%s' "$PROVIDER" ;;
    *) die "invalid --provider: ${PROVIDER} (use auto, garak, or lm)" ;;
  esac
}

USE_HF_SECRET=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --benchmark) BENCHMARK="$2"; shift 2 ;;
    --name) RUN_NAME="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --tokenizer) TOKENIZER="$2"; shift 2 ;;
    --hf-secret) HF_SECRET="$2"; shift 2 ;;
    --model-auth-secret) MODEL_AUTH_SECRET="$2"; shift 2 ;;
    --no-hf-secret) USE_HF_SECRET=0; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

command -v oc >/dev/null || die "oc not on PATH"
oc whoami >/dev/null || die "oc whoami failed; log in first"
oc get deploy "$EVALHUB_DEPLOY" -n "$PROJECT" >/dev/null 2>&1 \
  || die "deploy/${EVALHUB_DEPLOY} not found in ${PROJECT} — apply manifests/evalhub-instance.yaml"

cm_model=$(oc get configmap wings3-llm-endpoint -n "$PROJECT" \
  -o jsonpath='{.data.model_name}' 2>/dev/null || true)
if [[ -n "$cm_model" ]]; then
  LLM_MODEL="$cm_model"
fi

endpoint=$(oc get configmap wings3-llm-endpoint -n "$PROJECT" \
  -o jsonpath='{.data.openai_base_url}' 2>/dev/null || true)
if [[ -z "$endpoint" ]]; then
  endpoint="http://${LLM_MODEL}-predictor.${PROJECT}.svc.cluster.local:8080/v1"
fi
endpoint=$(normalize_openai_endpoint "$endpoint")

resolved_provider=$(resolve_provider)

model_auth_field=""
auth_secret=""
if secret_has_api_key "$MODEL_AUTH_SECRET"; then
  auth_secret="$MODEL_AUTH_SECRET"
  model_auth_field=$',
    "auth": {"secret_ref": "'"${MODEL_AUTH_SECRET}"'"}'
  echo "Using model auth secret: ${PROJECT}/${MODEL_AUTH_SECRET} (key api-key)"
elif endpoint_needs_maas_auth "$endpoint"; then
  echo "warning: MaaS endpoint needs api-key — create ${MODEL_AUTH_SECRET} or re-run ./install.sh" >&2
elif [[ "$resolved_provider" == lm ]] && [[ "$USE_HF_SECRET" == 1 ]] \
  && oc get secret "$HF_SECRET" -n "$PROJECT" >/dev/null 2>&1; then
  auth_secret="$HF_SECRET"
  model_auth_field=$',
    "auth": {"secret_ref": "'"${HF_SECRET}"'"}'
  echo "Using HuggingFace secret: ${PROJECT}/${HF_SECRET} (key hf-token)"
fi

if [[ "$resolved_provider" == lm ]] && [[ -z "$auth_secret" ]] && [[ "$USE_HF_SECRET" == 1 ]]; then
  echo "warning: no model.auth.secret_ref — gated tokenizer ${TOKENIZER} will likely fail" >&2
fi
if [[ "$resolved_provider" == lm ]] && [[ "$auth_secret" == "$MODEL_AUTH_SECRET" ]] \
  && [[ "$USE_HF_SECRET" == 1 ]] && [[ "$TOKENIZER" == meta-llama/* ]]; then
  echo "warning: gated tokenizer ${TOKENIZER} needs hf-token in ${MODEL_AUTH_SECRET} or use --tokenizer gpt2" >&2
fi

if [[ "$resolved_provider" == garak ]]; then
  payload=$(cat <<EOF
{
  "name": "${RUN_NAME}",
  "model": {
    "url": "${endpoint}",
    "name": "${LLM_MODEL}"${model_auth_field}
  },
  "benchmarks": [{
    "provider_id": "garak",
    "id": "${BENCHMARK}"
  }]
}
EOF
)
else
  payload=$(cat <<EOF
{
  "name": "${RUN_NAME}",
  "model": {
    "url": "${endpoint}",
    "name": "${LLM_MODEL}"${model_auth_field}
  },
  "benchmarks": [{
    "provider_id": "lm_evaluation_harness",
    "id": "${BENCHMARK}",
    "parameters": {
      "tokenizer": "${TOKENIZER}",
      "num_examples": ${NUM_EXAMPLES},
      "limit": ${LIMIT}
    }
  }]
}
EOF
)
fi

user=$(oc whoami)
token=$(oc whoami --show-token)

echo "Submitting ${BENCHMARK} (${resolved_provider}) → ${endpoint} (model ${LLM_MODEL})"
response=$(oc exec -n "$PROJECT" "deploy/${EVALHUB_DEPLOY}" -c evalhub -- \
  curl -sk -w '\n__HTTP_CODE__:%{http_code}' \
  -H "Authorization: Bearer ${token}" \
  -H "X-Tenant: ${PROJECT}" \
  -H "X-User: ${user}" \
  -H "Content-Type: application/json" \
  -d "${payload}" \
  "http://127.0.0.1:8444/api/v1/evaluations/jobs")

http_code=${response##*__HTTP_CODE__:}
body=${response%__HTTP_CODE__:*}
if [[ "$http_code" != "202" && "$http_code" != "200" ]]; then
  echo "EvalHub API failed (HTTP ${http_code}):" >&2
  echo "$body" >&2
  exit 1
fi

job_id=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["resource"]["id"])' 2>/dev/null \
  || true)
echo "Submitted. HTTP ${http_code}${job_id:+  job_id=${job_id}}"
echo "Open Develop & train → Evaluations → ${PROJECT} to watch the run."
