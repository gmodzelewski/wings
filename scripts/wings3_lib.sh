#!/usr/bin/env bash
# Shared helpers for WINGS3 install/uninstall/check scripts.
set -euo pipefail

WINGS3_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WINGS3_ROOT=$(cd "${WINGS3_LIB_DIR}/.." && pwd)
MANIFESTS="${WINGS3_ROOT}/manifests"
PROJECT="${WINGS3_PROJECT:-my-first-model}"
DSC="${WINGS3_DSC_NAME:-default-dsc}"
MLFLOW_NS="${WINGS3_MLFLOW_NAMESPACE:-redhat-ods-applications}"
LLM_MODEL="${WINGS3_LLM_MODEL:-llama-32-3b-instruct}"
WORKBENCH="${WINGS3_WORKBENCH:-wings3-demo}"
REPO_DEST="/opt/app-root/src/wings"
DEMO_DEST="${REPO_DEST}/demo"
GIT_URL="${WINGS3_GIT_URL:-https://github.com/gmodzelewski/wings.git}"
SR_TEMPLATE="${WINGS3_SR_TEMPLATE:-vllm-cuda-runtime-template}"
IS_MANIFEST="${MANIFESTS}/inferenceservice-llama-32-3b-instruct.yaml"
INSTANTIATE_SR="${WINGS3_ROOT}/scripts/instantiate_servingruntime.py"

EVALHUB_DSC_COMPONENT="${WINGS3_EVALHUB_DSC_COMPONENT:-}"
GARAK_DSC_COMPONENT="${WINGS3_GARAK_DSC_COMPONENT:-}"

log() {
  if [[ "${WINGS3_VERBOSE:-0}" == 1 ]]; then
    echo "$*"
  fi
}

info() {
  echo "$*"
}

die() {
  echo "error: $*" >&2
  exit 1
}

run() {
  "$@"
}

need_oc() {
  command -v oc >/dev/null || die "oc not on PATH"
  oc whoami >/dev/null || die "oc whoami failed; log in first"
}

wait_for_pod() {
  local ns="$1"
  local selector="$2"
  local timeout="${3:-600}"
  local elapsed=0
  while ((elapsed < timeout)); do
    local name=""
    name=$(oc get pod -n "$ns" -l "$selector" --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$name" ]] && oc wait --for=condition=Ready "pod/${name}" -n "$ns" --timeout=30s >/dev/null 2>&1; then
      log "Ready: ${ns}/${name}"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  die "timed out waiting for pod -n ${ns} -l ${selector}"
}

wait_for_pod_grep() {
  local ns="$1"
  local pattern="$2"
  local timeout="${3:-600}"
  local required="${4:-1}"
  local elapsed=0
  while ((elapsed < timeout)); do
    local name=""
    name=$(oc get pods -n "$ns" --no-headers 2>/dev/null | awk -v p="$pattern" '$1 ~ p && $3 == "Running" {print $1; exit}')
    if [[ -n "$name" ]] && oc wait --for=condition=Ready "pod/${name}" -n "$ns" --timeout=30s >/dev/null 2>&1; then
      log "Ready: ${ns}/${name}"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  if [[ "$required" == 1 ]]; then
    die "timed out waiting for pod -n ${ns} matching ${pattern}"
  fi
  return 1
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

dsc_component_state() {
  local component="$1"
  oc get datasciencecluster "$DSC" \
    -o jsonpath="{.spec.components.${component}.managementState}" 2>/dev/null || true
}

crd_registered() {
  local suffix="$1"
  oc api-resources -o name 2>/dev/null | grep -q "$suffix"
}

discover_dsc_component() {
  local pattern="$1"
  python3 - "$DSC" "$pattern" <<'PY'
import json
import subprocess
import sys

dsc, kind = sys.argv[1], sys.argv[2]
try:
    raw = subprocess.check_output(
        ["oc", "get", "datasciencecluster", dsc, "-o", "json"],
        stderr=subprocess.DEVNULL,
        text=True,
    )
except subprocess.CalledProcessError:
    sys.exit(0)

def crd_registered(suffix: str) -> bool:
    try:
        lines = subprocess.check_output(
            ["oc", "api-resources", "-o", "name"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except subprocess.CalledProcessError:
        return False
    return any(suffix in line for line in lines.splitlines())

data = json.loads(raw)
components = data.get("spec", {}).get("components", {}) or {}
names = sorted(components.keys())
if kind == "evalhub":
    prefs = ["evalhuboperator", "evalhub", "evaluationoperator", "rhaievaluationoperator"]
    for name in prefs:
        if name in components:
            print(name)
            sys.exit(0)
    for name in names:
        if "evalhub" in name.lower() or name.lower().endswith("evaluationoperator"):
            print(name)
            sys.exit(0)
    if "trustyai" in components and crd_registered("evalhubs.trustyai.opendatahub.io"):
        print("trustyai")
        sys.exit(0)
elif kind == "garak":
    prefs = ["garakoperator", "garakpipelineoperator", "garak", "garakpipeline"]
    for name in prefs:
        if name in components:
            print(name)
            sys.exit(0)
    for name in names:
        if "garak" in name.lower():
            print(name)
            sys.exit(0)
PY
}

discover_evalhub_resources() {
  if [[ -z "$EVALHUB_DSC_COMPONENT" ]]; then
    EVALHUB_DSC_COMPONENT=$(discover_dsc_component evalhub || true)
  fi
  if [[ -z "$GARAK_DSC_COMPONENT" ]]; then
    GARAK_DSC_COMPONENT=$(discover_dsc_component garak || true)
  fi
  if [[ -z "$EVALHUB_DSC_COMPONENT" ]]; then
    echo "warning: no EvalHub DSC component found on ${DSC}" >&2
  fi
}

patch_dsc_component() {
  local component="$1"
  local label="$2"
  if [[ -z "$component" ]]; then
    log "skip ${label}: DSC component not discovered"
    return 1
  fi
  local state=""
  state=$(dsc_component_state "$component")
  if [[ "$state" == "Managed" ]]; then
    log "${label}: ${component} already Managed"
    return 0
  fi
  log "patch ${DSC} ${component}=Managed"
  if oc patch datasciencecluster "$DSC" --type=merge \
    -p "{\"spec\":{\"components\":{\"${component}\":{\"managementState\":\"Managed\"}}}}" >/dev/null 2>&1; then
    return 0
  fi
  echo "warning: could not patch ${component} on ${DSC}" >&2
  return 1
}

enable_mlflow_operator() {
  if patch_dsc_component mlflowoperator "MLflow"; then
    wait_for_pod_grep "$MLFLOW_NS" "mlflow-operator" 600
  fi
}

enable_evalhub_operator() {
  discover_evalhub_resources
  if patch_dsc_component "$EVALHUB_DSC_COMPONENT" "EvalHub"; then
    local pattern found=0
    for pattern in eval-hub evalhub evaluation; do
      if wait_for_pod_grep "$MLFLOW_NS" "$pattern" 120 0; then
        found=1
        break
      fi
    done
    if [[ "$found" != 1 ]]; then
      echo "warning: no EvalHub pod Ready in ${MLFLOW_NS}" >&2
    fi
  fi
}

enable_garak() {
  if [[ -z "$GARAK_DSC_COMPONENT" ]]; then
    return 0
  fi
  if patch_dsc_component "$GARAK_DSC_COMPONENT" "Garak"; then
    wait_for_pod_grep "$MLFLOW_NS" "garak" 120 0 || true
  fi
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
  local host=""
  host=$(discover_gateway_host)
  if [[ -z "$host" ]]; then
    echo "warning: no dashboard route; skip logout URL annotate" >&2
    return 0
  fi
  oc annotate notebook "$WORKBENCH" -n "$PROJECT" --overwrite \
    "notebooks.opendatahub.io/oauth-logout-url=https://${host}/projects/${PROJECT}?notebookLogout=${WORKBENCH}" >/dev/null
}

hardware_profile_exists() {
  oc get hardwareprofile default-profile -n "$MLFLOW_NS" >/dev/null 2>&1 \
    || oc get hardwareprofile.opendatahub.io default-profile -n "$MLFLOW_NS" >/dev/null 2>&1
}

strip_hardware_profile_if_missing() {
  if hardware_profile_exists; then
    return 0
  fi
  oc annotate notebook "$WORKBENCH" -n "$PROJECT" --overwrite \
    opendatahub.io/hardware-profile-name- \
    opendatahub.io/hardware-profile-namespace- >/dev/null
}

apply_judge_secret() {
  local secret="${MANIFESTS}/secret-wings3-judge-llm.yaml"
  if ! oc get secret wings3-judge-llm -n "$PROJECT" >/dev/null 2>&1; then
    oc apply -f "$secret"
  fi
  if [[ -n "${WINGS3_JUDGE_API_KEY:-}" ]]; then
    oc set env "secret/wings3-judge-llm" -n "$PROJECT" "JUDGE_API_KEY=${WINGS3_JUDGE_API_KEY}"
  fi
  local key_b64=""
  key_b64=$(oc get secret wings3-judge-llm -n "$PROJECT" -o jsonpath='{.data.JUDGE_API_KEY}' 2>/dev/null || true)
  if [[ -z "$key_b64" ]]; then
    echo "warning: JUDGE_API_KEY is empty on secret/wings3-judge-llm — Module 4 judges will fail." >&2
    echo "warning: oc set env secret/wings3-judge-llm -n ${PROJECT} JUDGE_API_KEY='<token>'" >&2
    echo "warning: or export WINGS3_JUDGE_API_KEY and re-run install.sh" >&2
  fi
}

ensure_workbench_judge_mount() {
  run oc apply -f "${MANIFESTS}/workbench-wings3-demo.yaml"
}

apply_evalhub_manifests() {
  run oc apply -f "${MANIFESTS}/configmap-wings3-llm-endpoint.yaml"
  if [[ -f "${MANIFESTS}/evalhub-rbac-wings3.yaml" ]]; then
    run oc apply -f "${MANIFESTS}/evalhub-rbac-wings3.yaml"
  fi
}

wait_for_workbench() {
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
      log "Ready: ${PROJECT}/${name}"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  die "timed out waiting for workbench ${WORKBENCH} in ${PROJECT}"
}

apply_manifests() {
  run oc apply -f "${MANIFESTS}/mlflow-dev.yaml"
  run oc apply -f "${MANIFESTS}/namespace-my-first-model.yaml"
  apply_judge_secret
  ensure_workbench_judge_mount
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
    printf '%s' "${WINGS3_LLM_STORAGE_URI}"
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

template_runtime_version() {
  oc get template "$SR_TEMPLATE" -n "$MLFLOW_NS" \
    -o jsonpath='{.objects[0].metadata.annotations.opendatahub\.io/runtime-version}' 2>/dev/null || true
}

servingruntime_runtime_version() {
  oc get servingruntime "$LLM_MODEL" -n "$PROJECT" \
    -o jsonpath='{.metadata.annotations.opendatahub\.io/runtime-version}' 2>/dev/null || true
}

servingruntime_stale() {
  local template_version sr_version
  template_version=$(template_runtime_version)
  sr_version=$(servingruntime_runtime_version)
  [[ -z "$template_version" ]] && return 1
  [[ -z "$sr_version" || "$sr_version" != "$template_version" ]]
}

instantiate_serving_runtime() {
  if ! oc get template "$SR_TEMPLATE" -n "$MLFLOW_NS" >/dev/null 2>&1; then
    die "missing template ${SR_TEMPLATE} in ${MLFLOW_NS}"
  fi
  oc get template "$SR_TEMPLATE" -n "$MLFLOW_NS" -o json \
    | WINGS3_LLM_MODEL="$LLM_MODEL" WINGS3_PROJECT="$PROJECT" python3 "$INSTANTIATE_SR" \
    | oc apply -f -
}

ensure_servingruntime_current() {
  if ! servingruntime_stale; then
    return 0
  fi
  log "refresh ServingRuntime ${LLM_MODEL} from ${SR_TEMPLATE}"
  instantiate_serving_runtime
  if oc get inferenceservice "$LLM_MODEL" -n "$PROJECT" >/dev/null 2>&1; then
    patch_recreate
    wait_for_inferenceservice
  fi
}

patch_recreate() {
  local elapsed=0 timeout=300
  while ((elapsed < timeout)); do
    if oc get deployment "${LLM_MODEL}-predictor" -n "$PROJECT" >/dev/null 2>&1; then
      oc patch deployment "${LLM_MODEL}-predictor" -n "$PROJECT" --type=merge \
        -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}' >/dev/null
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  die "timed out waiting for deployment ${LLM_MODEL}-predictor"
}

wait_for_inferenceservice() {
  if oc wait --for=condition=Ready "inferenceservice/${LLM_MODEL}" -n "$PROJECT" --timeout=900s >/dev/null; then
    return 0
  fi
  die "InferenceService ${LLM_MODEL} not Ready"
}

inferenceservice_ready() {
  oc get inferenceservice "$LLM_MODEL" -n "$PROJECT" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q '^True$'
}

install_llm() {
  if [[ "${SKIP_LLM:-0}" == 1 ]]; then
    return 0
  fi
  ensure_servingruntime_current
  if inferenceservice_ready; then
    log "reusing InferenceService ${LLM_MODEL}"
    return 0
  fi
  local uri=""
  uri=$(resolve_storage_uri)
  if [[ -z "$uri" ]]; then
    die "no storageUri: set WINGS3_LLM_STORAGE_URI"
  fi
  apply_inferenceservice "$uri"
  patch_recreate
  wait_for_inferenceservice
}

clone_repo() {
  local pod
  pod=$(workbench_pod)
  oc exec -n "$PROJECT" "$pod" -- bash -lc "
    set -euo pipefail
    DEST=${REPO_DEST}
    if [ -d \"\$DEST/.git\" ]; then exit 0; fi
    if [ -e \"\$DEST\" ]; then
      echo \"error: \$DEST exists but is not a git repo\" >&2
      exit 1
    fi
    git clone ${GIT_URL} \"\$DEST\"
  "
}

pip_install() {
  local pod
  pod=$(workbench_pod)
  oc exec -n "$PROJECT" "$pod" -- bash -lc \
    "cd ${DEMO_DEST}/agent-tracing && pip install -q -r requirements.txt --extra-index-url https://pypi.org/simple"
}

wait_for_resource_gone() {
  local kind="$1"
  local name="$2"
  local ns="$3"
  local timeout="${4:-60}"
  local elapsed=0
  while ((elapsed < timeout)); do
    if ! oc get "$kind" "$name" -n "$ns" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo "warning: ${kind}/${name} still present in ${ns}" >&2
}

delete_workbench_resources() {
  run oc delete notebook "$WORKBENCH" -n "$PROJECT" --ignore-not-found=true
  run oc delete pvc "$WORKBENCH" -n "$PROJECT" --ignore-not-found=true
  run oc delete serviceaccount "$WORKBENCH" -n "$PROJECT" --ignore-not-found=true
  wait_for_resource_gone notebook "$WORKBENCH" "$PROJECT" 60
  wait_for_resource_gone pvc "$WORKBENCH" "$PROJECT" 60
}

delete_evalhub_manifests() {
  run oc delete configmap wings3-llm-endpoint -n "$PROJECT" --ignore-not-found=true
  if [[ -f "${MANIFESTS}/evalhub-rbac-wings3.yaml" ]]; then
    run oc delete -f "${MANIFESTS}/evalhub-rbac-wings3.yaml" --ignore-not-found=true
  fi
}

delete_judge_secret() {
  run oc delete secret wings3-judge-llm -n "$PROJECT" --ignore-not-found=true
}

purge_mlflow_cr() {
  local cr="${WINGS3_MLFLOW_CR:-mlflow}"
  oc delete mlflow "$cr" --ignore-not-found=true 2>/dev/null \
    || run oc delete mlflow "$cr" -n "$MLFLOW_NS" --ignore-not-found=true
}

purge_evalhub_demo_jobs() {
  if crd_registered 'evaluations\.redhat\.com'; then
    run oc delete evaluation wings3-demo-lm-eval -n "$PROJECT" --ignore-not-found=true
    run oc delete evaluation wings3-demo-garak -n "$PROJECT" --ignore-not-found=true
  fi
  if crd_registered 'lmevaljobs\.trustyai\.opendatahub\.io'; then
    run oc delete lmevaljob wings3-demo-lm-eval -n "$PROJECT" --ignore-not-found=true
  fi
}

purge_evalhub_resources() {
  purge_evalhub_demo_jobs
  delete_evalhub_manifests
}
