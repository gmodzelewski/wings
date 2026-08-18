#!/usr/bin/env bash
# Shared-cluster-safe reset of the WINGS3 demo workbench.
# Default does not delete the MLflow CR, operator, InferenceService, or project.
set -euo pipefail

WINGS3_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT="${WINGS3_PROJECT:-my-first-model}"
MLFLOW_NS="${WINGS3_MLFLOW_NAMESPACE:-redhat-ods-applications}"
LLM_MODEL="${WINGS3_LLM_MODEL:-llama-32-3b-instruct}"
WORKBENCH="${WINGS3_WORKBENCH:-wings3-demo}"
MLFLOW_CR="${WINGS3_MLFLOW_CR:-mlflow}"

DRY_RUN=0
PURGE_MLFLOW=0
PURGE_LLM=0
PURGE_PROJECT=0
YES=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Reset WINGS3 demo resources so you can bootstrap again.

Default (shared-cluster safe):
  Delete Notebook, PVC, and ServiceAccount ${WORKBENCH} in ${PROJECT}.
  Keep the MLflow CR, mlflowoperator, InferenceService, ServingRuntime, and project.

Does not:
  - Set mlflowoperator to Removed
  - Delete RHOAI / the DataScienceCluster

Options:
  --dry-run         Print actions; do not call oc
  --purge-mlflow    Also delete the cluster-scoped MLflow CR (SQLite data gone)
  --purge-llm       Also delete InferenceService and ServingRuntime ${LLM_MODEL}
  --purge-project   Also delete project ${PROJECT} (deletes the LLM too)
  --yes             Required with --purge-project
  -h, --help        Show this help

Environment:
  WINGS3_PROJECT              default my-first-model
  WINGS3_MLFLOW_NAMESPACE     default redhat-ods-applications
  WINGS3_LLM_MODEL            default llama-32-3b-instruct
  WINGS3_WORKBENCH            default wings3-demo
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

need_oc() {
  [[ "$DRY_RUN" == 1 ]] && return 0
  command -v oc >/dev/null || die "oc not on PATH"
  oc whoami >/dev/null || die "oc whoami failed; log in first"
}

delete_workbench() {
  echo "Delete workbench ${WORKBENCH} (notebook, pvc, serviceaccount)"
  run oc delete notebook "$WORKBENCH" -n "$PROJECT" --ignore-not-found=true
  run oc delete pvc "$WORKBENCH" -n "$PROJECT" --ignore-not-found=true
  run oc delete serviceaccount "$WORKBENCH" -n "$PROJECT" --ignore-not-found=true
  echo "keep InferenceService ${LLM_MODEL}"
  echo "keep ServingRuntime ${LLM_MODEL}"
  echo "keep MLflow CR ${MLFLOW_CR}"
  echo "keep mlflowoperator (would not change it)"
}

purge_llm() {
  echo "Delete InferenceService ${LLM_MODEL} and ServingRuntime ${LLM_MODEL} in ${PROJECT}"
  run oc delete inferenceservice "$LLM_MODEL" -n "$PROJECT" --ignore-not-found=true
  run oc delete servingruntime "$LLM_MODEL" -n "$PROJECT" --ignore-not-found=true
}

purge_mlflow() {
  echo "Delete MLflow CR ${MLFLOW_CR} in ${MLFLOW_NS} (SQLite artifacts gone)"
  run oc delete mlflow "$MLFLOW_CR" -n "$MLFLOW_NS" --ignore-not-found=true
  echo "would not change mlflowoperator"
}

purge_project() {
  echo "Delete project ${PROJECT} — this deletes InferenceService ${LLM_MODEL}"
  run oc delete project "$PROJECT"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --purge-mlflow) PURGE_MLFLOW=1 ;;
    --purge-llm) PURGE_LLM=1 ;;
    --purge-project) PURGE_PROJECT=1 ;;
    --yes) YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$PURGE_PROJECT" == 1 && "$YES" != 1 ]]; then
  echo "error: --purge-project deletes project ${PROJECT} and InferenceService ${LLM_MODEL}; pass --yes" >&2
  exit 1
fi

need_oc

if [[ "$PURGE_PROJECT" == 1 ]]; then
  purge_project
else
  delete_workbench
  if [[ "$PURGE_LLM" == 1 ]]; then
    purge_llm
  fi
fi

if [[ "$PURGE_MLFLOW" == 1 ]]; then
  purge_mlflow
fi

echo "Teardown complete."
