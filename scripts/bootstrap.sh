#!/usr/bin/env bash
# Bring a RHOAI cluster (operator already installed) to WINGS3 demo-ready.
# Instantiates ServingRuntime from vllm-cuda-runtime-template and applies
# the lab InferenceService. Does not uninstall RHOAI.
set -euo pipefail

WINGS3_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFESTS="$WINGS3_ROOT/manifests"
PROJECT="${WINGS3_PROJECT:-my-first-model}"
DSC="${WINGS3_DSC_NAME:-default-dsc}"
MLFLOW_NS="${WINGS3_MLFLOW_NAMESPACE:-redhat-ods-applications}"
LLM_MODEL="${WINGS3_LLM_MODEL:-llama-32-3b-instruct}"
WORKBENCH="${WINGS3_WORKBENCH:-wings3-demo}"
REPO_DEST="/opt/app-root/src/wings"
DEMO_DEST="${REPO_DEST}/demo"
GIT_URL="${WINGS3_GIT_URL:-https://github.com/gmodzelewski/wings.git}"
LLM_BASE_URL="${WINGS3_LLM_BASE_URL:-http://${LLM_MODEL}-predictor.${PROJECT}.svc.cluster.local:8080/v1}"
SR_TEMPLATE="${WINGS3_SR_TEMPLATE:-vllm-cuda-runtime-template}"
IS_MANIFEST="$MANIFESTS/inferenceservice-llama-32-3b-instruct.yaml"
INSTANTIATE_SR="$WINGS3_ROOT/scripts/instantiate_servingruntime.py"

DRY_RUN=0
WARMUP=0
SKIP_PIP=0
SKIP_COPY=0
SKIP_LLM=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Bring a RHOAI cluster from "operator installed" to WINGS3 demo-ready.

Does:
  - Set DataScienceCluster ${DSC} mlflowoperator=Managed
  - Apply manifests/mlflow-dev.yaml, namespace-my-first-model.yaml,
    workbench-wings3-demo.yaml
  - Instantiate ServingRuntime ${LLM_MODEL} from ${SR_TEMPLATE}
  - Apply manifests/inferenceservice-llama-32-3b-instruct.yaml
    (storageUri from an existing InferenceService or WINGS3_LLM_STORAGE_URI)
  - Patch the predictor Deployment to Recreate; wait Ready
  - Annotate workbench logout URL from the dashboard route
  - Wait for the MLflow server and workbench pods
  - git clone ${GIT_URL} onto the workbench PVC at ${REPO_DEST} (if .git is missing)
  - pip install -r requirements.txt --extra-index-url https://pypi.org/simple

Does not:
  - Uninstall or recreate RHOAI itself
  - Invent a HuggingFace storageUri

Options:
  --dry-run     Print actions; do not call oc
  --warmup      After pip: one autolog query + v1 eval (slow; needs a Ready LLM)
  --skip-pip    Skip pip install (venv already populated)
  --skip-copy   Skip git clone onto the workbench PVC
  --skip-llm    Skip ServingRuntime / InferenceService (GPU-less sandbox)
  -h, --help    Show this help

Environment:
  WINGS3_PROJECT              default my-first-model
  WINGS3_DSC_NAME             default default-dsc
  WINGS3_MLFLOW_NAMESPACE     default redhat-ods-applications
  WINGS3_LLM_MODEL            default llama-32-3b-instruct
  WINGS3_LLM_STORAGE_URI      optional; used when no existing IS storageUri
  WINGS3_WORKBENCH            default wings3-demo
  WINGS3_GIT_URL              default https://github.com/gmodzelewski/wings.git
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

wait_for_pod() {
  local ns="$1"
  local selector="$2"
  local timeout="${3:-600}"
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: wait for Ready pod -n ${ns} -l ${selector}"
    return 0
  fi
  local elapsed=0
  while ((elapsed < timeout)); do
    local name=""
    name=$(oc get pod -n "$ns" -l "$selector" --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$name" ]] && oc wait --for=condition=Ready "pod/${name}" -n "$ns" --timeout=30s >/dev/null 2>&1; then
      echo "Ready: ${ns}/${name}"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo "waiting for pod -n ${ns} -l ${selector} (${elapsed}s/${timeout}s)"
  done
  die "timed out waiting for pod -n ${ns} -l ${selector}"
}

wait_for_pod_grep() {
  local ns="$1"
  local pattern="$2"
  local timeout="${3:-600}"
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: wait for Ready pod -n ${ns} matching ${pattern}"
    return 0
  fi
  local elapsed=0
  while ((elapsed < timeout)); do
    local name=""
    name=$(oc get pods -n "$ns" --no-headers 2>/dev/null | awk -v p="$pattern" '$1 ~ p && $3 == "Running" {print $1; exit}')
    if [[ -n "$name" ]] && oc wait --for=condition=Ready "pod/${name}" -n "$ns" --timeout=30s >/dev/null 2>&1; then
      echo "Ready: ${ns}/${name}"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo "waiting for pod -n ${ns} matching ${pattern} (${elapsed}s/${timeout}s)"
  done
  die "timed out waiting for pod -n ${ns} matching ${pattern}"
}

workbench_pod() {
  local name=""
  name=$(oc get pod -n "$PROJECT" -l "notebook-name=${WORKBENCH}" --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$name" ]]; then
    name=$(oc get pod -n "$PROJECT" -l "app=${WORKBENCH}" --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  fi
  if [[ -z "$name" ]]; then
    name="${WORKBENCH}-0"
  fi
  printf '%s' "$name"
}

enable_operator() {
  echo "Set DataScienceCluster ${DSC} mlflowoperator=Managed"
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: oc patch datasciencecluster ${DSC} mlflowoperator=Managed"
    return 0
  fi
  local state=""
  state=$(oc get datasciencecluster "$DSC" -o jsonpath='{.spec.components.mlflowoperator.managementState}' 2>/dev/null || true)
  if [[ "$state" != "Managed" ]]; then
    oc patch datasciencecluster "$DSC" --type=merge \
      -p '{"spec":{"components":{"mlflowoperator":{"managementState":"Managed"}}}}'
  fi
  wait_for_pod_grep "$MLFLOW_NS" "mlflow-operator" 600
}

wait_for_workbench() {
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: wait for Ready workbench pod ${WORKBENCH} in ${PROJECT}"
    return 0
  fi
  local elapsed=0 timeout=600 name=""
  while ((elapsed < timeout)); do
    name=$(oc get pod -n "$PROJECT" -l "notebook-name=${WORKBENCH}" --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -z "$name" ]]; then
      name=$(oc get pod -n "$PROJECT" -l "app=${WORKBENCH}" --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    fi
    if [[ -z "$name" ]] && oc get "pod/${WORKBENCH}-0" -n "$PROJECT" >/dev/null 2>&1; then
      name="${WORKBENCH}-0"
    fi
    if [[ -n "$name" ]] && oc wait --for=condition=Ready "pod/${name}" -n "$PROJECT" --timeout=30s >/dev/null 2>&1; then
      echo "Ready: ${PROJECT}/${name}"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo "waiting for workbench ${WORKBENCH} in ${PROJECT} (${elapsed}s/${timeout}s)"
  done
  die "timed out waiting for workbench ${WORKBENCH} in ${PROJECT}"
}

hardware_profile_exists() {
  oc get hardwareprofile default-profile -n "$MLFLOW_NS" >/dev/null 2>&1 \
    || oc get hardwareprofile.opendatahub.io default-profile -n "$MLFLOW_NS" >/dev/null 2>&1
}

strip_hardware_profile_if_missing() {
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: strip hardware-profile annotations if default-profile is missing"
    return 0
  fi
  if hardware_profile_exists; then
    echo "HardwareProfile default-profile present"
    return 0
  fi
  echo "HardwareProfile default-profile missing; stripping notebook annotations"
  oc annotate notebook "$WORKBENCH" -n "$PROJECT" --overwrite \
    opendatahub.io/hardware-profile-name- \
    opendatahub.io/hardware-profile-namespace- >/dev/null
}

discover_gateway_host() {
  local host="" name
  for name in rhods-dashboard rh-ai rhoai; do
    host=$(oc get route "$name" -n "$MLFLOW_NS" -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -n "$host" ]]; then
      printf '%s' "$host"
      return 0
    fi
  done
  host=$(oc get route -n "$MLFLOW_NS" -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' 2>/dev/null \
    | grep -E 'rh-ai|rhods|rhoai' | head -1 || true)
  printf '%s' "$host"
}

annotate_logout_url() {
  echo "annotate workbench oauth-logout-url from dashboard route"
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: oc annotate notebook ${WORKBENCH} notebooks.opendatahub.io/oauth-logout-url"
    return 0
  fi
  local host=""
  host=$(discover_gateway_host)
  if [[ -z "$host" ]]; then
    echo "warning: no dashboard route in ${MLFLOW_NS}; skip logout URL annotate" >&2
    return 0
  fi
  oc annotate notebook "$WORKBENCH" -n "$PROJECT" --overwrite \
    "notebooks.opendatahub.io/oauth-logout-url=https://${host}/projects/${PROJECT}?notebookLogout=${WORKBENCH}"
}

apply_manifests() {
  run oc apply -f "$MANIFESTS/mlflow-dev.yaml"
  run oc apply -f "$MANIFESTS/namespace-my-first-model.yaml"
  run oc apply -f "$MANIFESTS/workbench-wings3-demo.yaml"
  strip_hardware_profile_if_missing
  annotate_logout_url
  wait_for_pod "$MLFLOW_NS" "app=mlflow" 600
  wait_for_workbench
}

resolve_storage_uri() {
  local existing=""
  existing=$(oc get inferenceservice "$LLM_MODEL" -n "$PROJECT" \
    -o jsonpath='{.spec.predictor.model.storageUri}' 2>/dev/null || true)
  if [[ -n "$existing" && "$existing" != "REPLACE_ME" ]]; then
    printf '%s' "$existing"
    return 0
  fi
  if [[ -n "${WINGS3_LLM_STORAGE_URI:-}" && "${WINGS3_LLM_STORAGE_URI}" != "REPLACE_ME" ]]; then
    printf '%s' "$WINGS3_LLM_STORAGE_URI"
    return 0
  fi
  existing=$(awk '/storageUri:/ {print $2; exit}' "$IS_MANIFEST")
  if [[ -n "$existing" && "$existing" != "REPLACE_ME" ]]; then
    printf '%s' "$existing"
    return 0
  fi
  printf ''
}

apply_inferenceservice() {
  local uri="$1"
  if grep -q 'storageUri: REPLACE_ME' "$IS_MANIFEST"; then
    python3 - "$IS_MANIFEST" "$uri" <<'PY' | oc apply -f -
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
uri = sys.argv[2]
sys.stdout.write(text.replace("REPLACE_ME", uri, 1))
PY
  else
    oc apply -f "$IS_MANIFEST"
  fi
}

instantiate_serving_runtime() {
  echo "instantiate ServingRuntime ${LLM_MODEL} from ${SR_TEMPLATE}"
  if [[ "$DRY_RUN" == 1 ]]; then
    return 0
  fi
  if ! oc get template "$SR_TEMPLATE" -n "$MLFLOW_NS" >/dev/null 2>&1; then
    die "missing template ${SR_TEMPLATE} in ${MLFLOW_NS}; is RHOAI installed?"
  fi
  oc get template "$SR_TEMPLATE" -n "$MLFLOW_NS" -o json \
    | WINGS3_LLM_MODEL="$LLM_MODEL" WINGS3_PROJECT="$PROJECT" python3 "$INSTANTIATE_SR" \
    | oc apply -f -
}

patch_recreate() {
  echo "patch predictor Deployment ${LLM_MODEL}-predictor strategy Recreate"
  if [[ "$DRY_RUN" == 1 ]]; then
    return 0
  fi
  local elapsed=0 timeout=300
  while ((elapsed < timeout)); do
    if oc get deployment "${LLM_MODEL}-predictor" -n "$PROJECT" >/dev/null 2>&1; then
      oc patch deployment "${LLM_MODEL}-predictor" -n "$PROJECT" --type=merge \
        -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    echo "waiting for deployment ${LLM_MODEL}-predictor (${elapsed}s/${timeout}s)"
  done
  die "timed out waiting for deployment ${LLM_MODEL}-predictor"
}

wait_for_inferenceservice() {
  echo "wait Ready InferenceService ${LLM_MODEL}"
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: oc wait inferenceservice ${LLM_MODEL} --for=condition=Ready --timeout=900s"
    return 0
  fi
  if oc wait --for=condition=Ready "inferenceservice/${LLM_MODEL}" -n "$PROJECT" --timeout=900s; then
    echo "InferenceService ${LLM_MODEL} is Ready"
    return 0
  fi
  die "InferenceService ${LLM_MODEL} not Ready"
}

install_llm() {
  if [[ "$SKIP_LLM" == 1 ]]; then
    echo "skip llm (ServingRuntime / InferenceService)"
    return 0
  fi
  echo "apply ${IS_MANIFEST}"
  echo "storageUri from existing InferenceService or WINGS3_LLM_STORAGE_URI"
  instantiate_serving_runtime
  if [[ "$DRY_RUN" == 1 ]]; then
    patch_recreate
    wait_for_inferenceservice
    return 0
  fi
  local uri=""
  uri=$(resolve_storage_uri)
  if [[ -z "$uri" ]]; then
    die "no storageUri: set WINGS3_LLM_STORAGE_URI or leave an existing InferenceService ${LLM_MODEL} (do not invent a HuggingFace URI)"
  fi
  apply_inferenceservice "$uri"
  patch_recreate
  wait_for_inferenceservice
}

clone_repo() {
  if [[ "$SKIP_COPY" == 1 ]]; then
    echo "skip clone"
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: git clone ${GIT_URL} ${REPO_DEST} (if .git missing)"
    return 0
  fi
  local pod
  pod=$(workbench_pod)
  oc exec -n "$PROJECT" "$pod" -- bash -lc "
    set -euo pipefail
    DEST=${REPO_DEST}
    if [ -d \"\$DEST/.git\" ]; then
      echo \"wings clone already present\"
      exit 0
    fi
    if [ -e \"\$DEST\" ]; then
      echo \"error: \$DEST exists but is not a git repo; remove it and restart the workbench\" >&2
      exit 1
    fi
    git clone ${GIT_URL} \"\$DEST\"
  "
  echo "cloned ${GIT_URL} to ${PROJECT}/${pod}:${REPO_DEST}"
}

pip_install() {
  if [[ "$SKIP_PIP" == 1 ]]; then
    echo "skip pip"
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: pip install -r requirements.txt --extra-index-url https://pypi.org/simple"
    return 0
  fi
  local pod
  pod=$(workbench_pod)
  oc exec -n "$PROJECT" "$pod" -- bash -lc \
    "cd ${DEMO_DEST}/agent-tracing && pip install -r requirements.txt --extra-index-url https://pypi.org/simple"
}

warmup() {
  if [[ "$WARMUP" != 1 ]]; then
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "DRY-RUN: WINGS3_ONE_QUERY=1 python3 run_tracing_demo_autolog.py"
    echo "DRY-RUN: WINGS3_PROMPT_VERSION=v1 python3 evaluate_agent.py"
    return 0
  fi
  local pod
  pod=$(workbench_pod)
  oc exec -n "$PROJECT" "$pod" -- bash -lc "
    set -euo pipefail
    cd ${DEMO_DEST}/agent-tracing
    export MLFLOW_WORKSPACE=${PROJECT}
    export MAAS_API_KEY=unused
    export MAAS_MODEL=${LLM_MODEL}
    export MAAS_BASE_URL=${LLM_BASE_URL}
    export MLFLOW_EXPERIMENT_NAME=wings3-agent-tracing
    export WINGS3_ONE_QUERY=1
    python3 run_tracing_demo_autolog.py
    export MLFLOW_EXPERIMENT_NAME=wings3-agent-eval
    export WINGS3_PROMPT_VERSION=v1
    python3 evaluate_agent.py
  "
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --warmup) WARMUP=1 ;;
    --skip-pip) SKIP_PIP=1 ;;
    --skip-copy) SKIP_COPY=1 ;;
    --skip-llm) SKIP_LLM=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

need_oc
enable_operator
apply_manifests
install_llm
clone_repo
pip_install
warmup

echo "Bootstrap complete. Live hour: oc get only, then workbench wings3-demo."
