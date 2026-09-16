#!/usr/bin/env bash
# Submit small EvalHub demo jobs (lm-eval-harness + Garak) against the WINGS3 LLM endpoint.
set -euo pipefail

WINGS3_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFESTS="${WINGS3_ROOT}/manifests"
PROJECT="${WINGS3_PROJECT:-my-first-model}"
LLM_MODEL="${WINGS3_LLM_MODEL:-llama-32-3b-instruct}"
LLM_BASE_URL="${WINGS3_LLM_BASE_URL:-http://${LLM_MODEL}-predictor.${PROJECT}.svc.cluster.local:8080/v1}"

DRY_RUN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Pre-stage EvalHub demo jobs for Act 5. Applies manifests when a supported
evaluation CRD exists (evaluations.redhat.com on RHOAI 3.4, LMEvalJob on 3.5);
otherwise prints UI submit instructions.

Options:
  --dry-run   Print actions only
  -h, --help  Show this help
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

crd_present() {
  local pattern="$1"
  oc api-resources --namespaced=true -o name 2>/dev/null | grep -qi "$pattern"
}

resolve_endpoint() {
  local url=""
  url=$(oc get configmap wings3-llm-endpoint -n "$PROJECT" \
    -o jsonpath='{.data.openai_base_url}' 2>/dev/null || true)
  if [[ -n "$url" ]]; then
    printf '%s' "$url"
    return 0
  fi
  url=$(oc get inferenceservice "$LLM_MODEL" -n "$PROJECT" \
    -o jsonpath='{.status.url}' 2>/dev/null || true)
  if [[ -n "$url" ]]; then
    if [[ "$url" != */v1 ]]; then
      url="${url%/}/v1"
    fi
    printf '%s' "$url"
    return 0
  fi
  printf '%s' "$LLM_BASE_URL"
}

apply_if_crd() {
  local manifest="$1"
  local pattern="$2"
  local label="$3"
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: try oc apply -f ${manifest} (if ${label} CRD exists)"
    return 0
  fi
  if ! crd_present "$pattern"; then
    echo "skip ${manifest}: ${label} CRD not found on cluster"
    return 1
  fi
  run oc apply -f "$manifest"
  return 0
}

print_ui_fallback() {
  local endpoint="$1"
  cat <<EOF

EvalHub job CRD not available — submit via OpenShift AI console:

  Project: ${PROJECT}
  Target endpoint: ${endpoint}
  Model name: ${LLM_MODEL}

1. EvalHub → New evaluation → provider lm-eval-harness
   - Name: wings3-demo-lm-eval
   - Task: pick one small harness task for demo speed

2. EvalHub → New evaluation → provider Garak
   - Name: wings3-demo-garak
   - Probe set: default / demo configuration

Payload templates: demo/evalhub/jobs/lm-eval-demo.json and garak-demo.json
Walkthrough: walkthrough/05-evalhub-garak.md
EOF
}

print_garak_ui_note() {
  cat <<EOF
Garak: no Garak Job CRD on this cluster — submit via EvalHub UI (provider Garak).
Template: demo/evalhub/jobs/garak-demo.json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

command -v oc >/dev/null || die "oc not on PATH"
oc whoami >/dev/null || die "oc whoami failed; log in first"

endpoint=$(resolve_endpoint)
echo "Target endpoint: ${endpoint}"

applied=0
garak_applied=0

# RHOAI 3.4 — evaluations.redhat.com
if apply_if_crd "${MANIFESTS}/evalhub-demo-lm-eval.yaml" 'evaluations\.redhat\.com' "evaluations.redhat.com"; then
  if [[ "$DRY_RUN" == 1 ]] || crd_present 'evaluations\.redhat\.com'; then
    applied=1
  fi
fi
if apply_if_crd "${MANIFESTS}/evalhub-demo-garak.yaml" 'evaluations\.redhat\.com' "evaluations.redhat.com"; then
  if [[ "$DRY_RUN" == 1 ]] || crd_present 'evaluations\.redhat\.com'; then
    applied=1
    garak_applied=1
  fi
fi

# RHOAI 3.5 — TrustyAI LMEvalJob
if apply_if_crd "${MANIFESTS}/evalhub-demo-lmevaljob.yaml" 'lmevaljobs\.trustyai\.opendatahub\.io' "lmevaljobs.trustyai.opendatahub.io"; then
  if [[ "$DRY_RUN" == 1 ]] || crd_present 'lmevaljobs\.trustyai\.opendatahub\.io'; then
    applied=1
  fi
fi

if [[ "$applied" == 0 ]]; then
  print_ui_fallback "$endpoint"
elif [[ "$garak_applied" == 0 ]]; then
  echo "Demo EvalHub lm-eval job applied. Watch jobs in EvalHub UI for ${PROJECT}."
  print_garak_ui_note
else
  echo "Demo EvalHub manifests applied. Watch jobs in EvalHub UI for ${PROJECT}."
fi
