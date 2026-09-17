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
# Stormshift (and some clusters) register notebooks.intel.com before kubeflow.org.
NOTEBOOK_API="${WINGS3_NOTEBOOK_API:-notebook.kubeflow.org}"
REPO_DEST="/opt/app-root/src/wings"
DEMO_DEST="${REPO_DEST}/demo"
GIT_URL="${WINGS3_GIT_URL:-https://github.com/gmodzelewski/wings.git}"
SR_TEMPLATE="${WINGS3_SR_TEMPLATE:-vllm-cuda-runtime-template}"
IS_MANIFEST="${MANIFESTS}/inferenceservice-llama-32-3b-instruct.yaml"
INSTANTIATE_SR="${WINGS3_ROOT}/scripts/instantiate_servingruntime.py"

EVALHUB_DSC_COMPONENT="${WINGS3_EVALHUB_DSC_COMPONENT:-}"
GARAK_DSC_COMPONENT="${WINGS3_GARAK_DSC_COMPONENT:-}"

MAAS_NS="${WINGS3_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_MODEL="${WINGS3_MAAS_MODEL:-gpt-oss-120b}"
MAAS_SUBSCRIPTION="${WINGS3_MAAS_SUBSCRIPTION:-wings3-gpt-oss-120b}"
MAAS_UPSTREAM_ENDPOINT="${WINGS3_MAAS_UPSTREAM_ENDPOINT:-maas-rhdp.apps.maas.redhatworkshops.io}"
MAAS_PART_OF="${WINGS3_MAAS_PART_OF:-wings3-demo}"
KUADRANT_NS="${WINGS3_KUADRANT_NAMESPACE:-kuadrant-system}"
GATEWAY_NS="${WINGS3_GATEWAY_NAMESPACE:-openshift-ingress}"
SM_NS="${WINGS3_SERVICEMESH_NAMESPACE:-istio-system}"
SM_CNI_NS="${WINGS3_SERVICEMESH_CNI_NAMESPACE:-istio-cni}"
OGX_SERVER_NAME="${WINGS3_OGX_SERVER_NAME:-wings3-ogx}"

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
  local name="${suffix%%.*}"
  if [[ "$suffix" == *.* ]]; then
    oc get crd "$suffix" >/dev/null 2>&1 && return 0
  fi
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

ogx_operator_available() {
  crd_registered 'ogxservers\.ogx\.io'
}

mcp_lifecycle_available() {
  crd_registered 'mcpservers\.mcp\.x-k8s\.io'
}

ogx_dsc_ready() {
  local ready=""
  ready=$(oc get datasciencecluster "$DSC" \
    -o jsonpath='{.status.conditions[?(@.type=="OGXReady")].status}' 2>/dev/null || true)
  [[ "$ready" == "True" ]]
}

servicemesh_installed() {
  local csv=""
  csv=$(oc get csv -A -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | grep -E '^servicemeshoperator3\.' | head -1 || true)
  if [[ -z "$csv" ]]; then
    return 1
  fi
  if ! oc get istio default -n "$SM_NS" >/dev/null 2>&1; then
    return 1
  fi
  local phase=""
  phase=$(oc get istio default -n "$SM_NS" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [[ "$phase" == "True" ]]
}

wait_for_servicemesh() {
  local timeout="${1:-1200}"
  local elapsed=0
  while ((elapsed < timeout)); do
    if servicemesh_installed; then
      info "Service Mesh 3 control plane Ready"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "warning: timed out waiting for Service Mesh 3" >&2
  return 1
}

wait_for_servicemesh_operator() {
  local timeout="${1:-1200}"
  local elapsed=0
  while ((elapsed < timeout)); do
    if oc get csv -n openshift-operators servicemeshoperator3.v3.4.2 >/dev/null 2>&1 \
      || oc get csv -A -o name 2>/dev/null | grep -q 'servicemeshoperator3\.'; then
      local csv=""
      csv=$(oc get csv -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null \
        | grep 'servicemeshoperator3\.' | grep Succeeded | head -1 || true)
      if [[ -n "$csv" ]]; then
        info "Service Mesh 3 operator CSV Succeeded"
        return 0
      fi
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "warning: timed out waiting for servicemeshoperator3 CSV" >&2
  return 1
}

ensure_servicemesh() {
  if servicemesh_installed; then
    log "Service Mesh 3 already installed"
    return 0
  fi
  info "installing Service Mesh 3 (OGX prerequisite)"
  # Remove conflicting OG if a prior install attempt created one (TooManyOperatorGroups).
  if oc get operatorgroup servicemeshoperator3-og -n openshift-operators >/dev/null 2>&1; then
    log "remove conflicting servicemeshoperator3-og OperatorGroup"
    oc delete operatorgroup servicemeshoperator3-og -n openshift-operators --ignore-not-found=true
  fi
  run oc apply -f "${MANIFESTS}/servicemesh3-operator.yaml"
  wait_for_servicemesh_operator 1200 || return 1
  if crd_registered 'istios\.sailoperator\.io'; then
    run oc apply -f "${MANIFESTS}/servicemesh3-istio.yaml"
  else
    echo "warning: sailoperator.io CRDs missing; skip Istio CR apply" >&2
    return 1
  fi
  oc label namespace "$SM_NS" istio-discovery=enabled --overwrite >/dev/null 2>&1 || true
  oc label namespace "$PROJECT" istio-discovery=enabled --overwrite >/dev/null 2>&1 || true
  wait_for_servicemesh 1200 || return 1
}

wait_for_ogx_crds() {
  local timeout="${1:-1200}"
  local elapsed=0
  while ((elapsed < timeout)); do
    if ogx_operator_available && ogx_dsc_ready; then
      info "OGX operator Ready"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  return 1
}

revert_ogx_if_broken() {
  local state=""
  state=$(dsc_component_state ogx)
  if [[ "$state" == "Managed" ]] && ! ogx_operator_available; then
    log "ogx Managed but ogx.io CRDs still missing; reverting to Removed"
    oc patch datasciencecluster "$DSC" --type=merge \
      -p '{"spec":{"components":{"ogx":{"managementState":"Removed"}}}}' \
      >/dev/null 2>&1 || true
  fi
}

enable_ogx_dsc() {
  local llama_state=""
  llama_state=$(dsc_component_state llamastackoperator)
  if [[ "$llama_state" == "Managed" ]]; then
    log "llamastackoperator blocks OGX on RHOAI 3.5; setting Removed"
    oc patch datasciencecluster "$DSC" --type=merge \
      -p '{"spec":{"components":{"llamastackoperator":{"managementState":"Removed"}}}}' \
      >/dev/null 2>&1 || true
  fi
  patch_dsc_component ogx "OGX" || return 1
  if wait_for_ogx_crds 1200; then
    return 0
  fi
  revert_ogx_if_broken
  echo "warning: OGX operator did not become Ready within timeout" >&2
  return 1
}

wait_for_ogx_server() {
  local timeout="${1:-900}"
  local elapsed=0
  while ((elapsed < timeout)); do
    local ready=""
    ready=$(oc get ogxserver "$OGX_SERVER_NAME" -n "$PROJECT" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "$ready" == "True" ]]; then
      info "OGXServer ${OGX_SERVER_NAME} Ready"
      return 0
    fi
    ready=$(oc get ogxserver "$OGX_SERVER_NAME" -n "$PROJECT" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$ready" == "Ready" ]]; then
      info "OGXServer ${OGX_SERVER_NAME} Ready"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "warning: timed out waiting for OGXServer ${OGX_SERVER_NAME}" >&2
  return 1
}

ensure_ogx_operator_registry_auth() {
  if ! oc get deployment ogx-k8s-operator-controller-manager -n "$MLFLOW_NS" >/dev/null 2>&1; then
    return 0
  fi
  if ! oc get secret pull-secret -n "$MLFLOW_NS" >/dev/null 2>&1; then
    oc get secret pull-secret -n openshift-config -o json \
      | python3 -c 'import json,sys; s=json.load(sys.stdin); s["metadata"]={"name":"pull-secret","namespace":"'"$MLFLOW_NS"'"}; {s.pop(k,None) for k in ("resourceVersion","uid","creationTimestamp")}; json.dump(s,sys.stdout)' \
      | oc apply -f - >/dev/null 2>&1 || true
  fi
  oc secrets link ogx-k8s-operator-controller-manager pull-secret --for=pull -n "$MLFLOW_NS" \
    >/dev/null 2>&1 || true
  if ! oc get deployment ogx-k8s-operator-controller-manager -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DOCKER_CONFIG")].value}' 2>/dev/null \
    | grep -q /tmp/dockerconfig; then
    log "mount registry pull-secret on OGX operator (OCI label fetch)"
    oc set volume deployment/ogx-k8s-operator-controller-manager -n "$MLFLOW_NS" \
      --add --name=dockerconfig --type=secret --secret-name=pull-secret \
      --mount-path=/tmp/dockerconfig --read-only=true >/dev/null 2>&1 || true
    oc set env deployment/ogx-k8s-operator-controller-manager -n "$MLFLOW_NS" \
      DOCKER_CONFIG=/tmp/dockerconfig >/dev/null 2>&1 || true
  fi
}

deploy_ogx_server() {
  if ! ogx_operator_available; then
    echo "warning: skip OGXServer — ogx.io CRDs missing" >&2
    return 1
  fi
  info "deploying OGXServer ${OGX_SERVER_NAME}"
  ensure_ogx_operator_registry_auth || true
  run oc apply -f "${MANIFESTS}/ogx-postgres-dev.yaml"
  wait_for_pod_grep "$PROJECT" "wings3-ogx-postgres" 300 0 || true
  run oc apply -f "${MANIFESTS}/ogx-base-config-wings3.yaml"
  run oc apply -f "${MANIFESTS}/ogx-server-wings3.yaml"
  wait_for_ogx_server 900 || true
}

wait_for_mcp_lifecycle() {
  local timeout="${1:-600}"
  local elapsed=0
  while ((elapsed < timeout)); do
    if mcp_lifecycle_available; then
      info "MCP lifecycle operator CRDs present"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "warning: timed out waiting for MCP lifecycle CRDs" >&2
  return 1
}

enable_mcplifecycle() {
  patch_dsc_component mcplifecycleoperator "MCP lifecycle" || return 1
  wait_for_mcp_lifecycle 600 || true
}

label_maas_external_model_assets() {
  if oc get externalmodels.maas.opendatahub.io "$MAAS_MODEL" -n "$PROJECT" >/dev/null 2>&1; then
    oc label externalmodels.maas.opendatahub.io "$MAAS_MODEL" -n "$PROJECT" \
      opendatahub.io/dashboard=true opendatahub.io/genai-asset=true \
      --overwrite >/dev/null 2>&1 || true
  fi
  if oc get externalmodels.inference.opendatahub.io "$MAAS_MODEL" -n "$PROJECT" >/dev/null 2>&1; then
    oc label externalmodels.inference.opendatahub.io "$MAAS_MODEL" -n "$PROJECT" \
      opendatahub.io/dashboard=true opendatahub.io/genai-asset=true \
      --overwrite >/dev/null 2>&1 || true
  fi
  if oc get maasmodelref "$MAAS_MODEL" -n "$PROJECT" >/dev/null 2>&1; then
    oc label maasmodelref "$MAAS_MODEL" -n "$PROJECT" \
      opendatahub.io/dashboard=true opendatahub.io/genai-asset=true \
      --overwrite >/dev/null 2>&1 || true
  fi
}

restart_maas_dashboard_ui_if_unhealthy() {
  local unhealthy=0
  if ! oc get deployment maas-ui -n "$MLFLOW_NS" >/dev/null 2>&1; then
    return 0
  fi
  if ! wait_for_pod_grep "$MLFLOW_NS" "maas-ui" 30 0; then
    unhealthy=1
  fi
  if oc logs -n "$MLFLOW_NS" deployment/maas-ui --tail=30 2>/dev/null \
    | grep -qE 'SERVER_UNAVAILABLE|context deadline exceeded'; then
    unhealthy=1
  fi
  if [[ "$unhealthy" == 1 ]]; then
    log "restart maas-ui and gen-ai-ui after BFF errors"
    oc rollout restart deployment/maas-ui deployment/gen-ai-ui -n "$MLFLOW_NS" \
      >/dev/null 2>&1 || true
    wait_for_pod_grep "$MLFLOW_NS" "maas-ui" 120 0 || true
    wait_for_pod_grep "$MLFLOW_NS" "gen-ai-ui" 120 0 || true
  fi
}

ensure_genai_dashboard_prereqs() {
  local gen_ai="" maas_tab="" mcp_catalog=""
  gen_ai=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.genAiStudio}' 2>/dev/null || true)
  maas_tab=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.modelAsService}' 2>/dev/null || true)
  mcp_catalog=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.mcpCatalog}' 2>/dev/null || true)
  if [[ "$gen_ai" != "true" || "$maas_tab" != "true" || "$mcp_catalog" != "true" ]]; then
    log "patch OdhDashboardConfig genAiStudio + modelAsService + mcpCatalog"
    oc patch odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" --type=merge \
      -p '{"spec":{"dashboardConfig":{"genAiStudio":true,"modelAsService":true,"mcpCatalog":true}}}' \
      >/dev/null 2>&1 || true
  fi
  label_maas_external_model_assets || true
  restart_maas_dashboard_ui_if_unhealthy || true
}

ensure_maas_dashboard_prereqs() {
  ensure_genai_dashboard_prereqs
}

enable_genai_studio() {
  if [[ "${WINGS3_SKIP_OGX:-0}" == 1 && "${WINGS3_SKIP_MCP:-0}" == 1 ]]; then
    log "skip Gen AI Studio stack (WINGS3_SKIP_OGX=1 and WINGS3_SKIP_MCP=1)"
    return 0
  fi
  if [[ "${WINGS3_SKIP_OGX:-0}" != 1 ]]; then
    if [[ "${WINGS3_SKIP_SERVICEMESH:-0}" != 1 ]]; then
      ensure_servicemesh || echo "warning: Service Mesh install incomplete" >&2
    fi
    enable_ogx_dsc || echo "warning: OGX DSC enablement incomplete" >&2
    deploy_ogx_server || echo "warning: OGXServer deploy incomplete" >&2
  fi
  if [[ "${WINGS3_SKIP_MCP:-0}" != 1 ]]; then
    enable_mcplifecycle || echo "warning: MCP lifecycle enablement incomplete" >&2
  fi
  ensure_genai_dashboard_prereqs || true
  if oc get deployment gen-ai-ui -n "$MLFLOW_NS" >/dev/null 2>&1; then
    oc rollout restart deployment/gen-ai-ui -n "$MLFLOW_NS" >/dev/null 2>&1 || true
    wait_for_pod_grep "$MLFLOW_NS" "gen-ai-ui" 180 0 || true
  fi
}

maas_models_as_service_state() {
  local state=""
  state=$(oc get datasciencecluster "$DSC" \
    -o jsonpath='{.spec.components.aigateway.modelsAsAService.managementState}' 2>/dev/null || true)
  if [[ -n "$state" ]]; then
    printf '%s' "$state"
    return 0
  fi
  oc get datasciencecluster "$DSC" \
    -o jsonpath='{.spec.components.kserve.modelsAsService.managementState}' 2>/dev/null || true
}

enable_maas_operator() {
  local state=""
  state=$(maas_models_as_service_state)
  if [[ "$state" == "Managed" ]]; then
    log "MaaS: modelsAsAService already Managed"
    return 0
  fi
  log "patch ${DSC} aigateway + modelsAsAService=Managed"
  if oc patch datasciencecluster "$DSC" --type=merge \
    -p '{"spec":{"components":{"aigateway":{"managementState":"Managed","modelsAsAService":{"managementState":"Managed"}}}}}' \
    >/dev/null 2>&1; then
    return 0
  fi
  log "patch ${DSC} kserve.modelsAsService=Managed (legacy)"
  if oc patch datasciencecluster "$DSC" --type=merge \
    -p '{"spec":{"components":{"kserve":{"modelsAsService":{"managementState":"Managed"}}}}}' \
    >/dev/null 2>&1; then
    return 0
  fi
  echo "warning: could not enable MaaS on ${DSC} (try aigateway.modelsAsAService)" >&2
  return 1
}

wait_for_maas_crds() {
  local timeout="${1:-1200}"
  local elapsed=0
  while ((elapsed < timeout)); do
    if crd_registered 'externalmodels\.maas\.opendatahub\.io' \
      && crd_registered 'maasmodelrefs\.maas\.opendatahub\.io'; then
      return 0
    fi
    if crd_registered 'externalmodels\.maas\.opendatahub\.io' \
      && crd_registered 'maasmodelrefs\.models\.opendatahub\.io'; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "warning: timed out waiting for MaaS CRDs" >&2
  return 1
}

wait_for_maas_namespace() {
  local timeout="${1:-300}"
  local elapsed=0
  while ((elapsed < timeout)); do
    if oc get namespace "$MAAS_NS" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "warning: timed out waiting for namespace ${MAAS_NS}" >&2
  return 1
}

maas_db_config_url() {
  printf 'postgresql://maas:wings3-maas-dev@wings3-maas-postgres.%s.svc:5432/maas?sslmode=disable' "$MLFLOW_NS"
}

ensure_maas_db_secrets() {
  local url=""
  url=$(maas_db_config_url)
  if ! oc get secret maas-db-config -n "$MLFLOW_NS" >/dev/null 2>&1; then
    run oc apply -f "${MANIFESTS}/maas-db-config-secret.yaml"
  fi
  oc create secret generic maas-db-config \
    -n redhat-ai-gateway-infra \
    --from-literal=DB_CONNECTION_URL="$url" \
    --dry-run=client -o yaml | oc apply -f -
  oc label secret maas-db-config -n redhat-ai-gateway-infra \
    app.kubernetes.io/part-of="$MAAS_PART_OF" --overwrite >/dev/null 2>&1 || true
}

ensure_maas_postgres() {
  if ! oc get deployment wings3-maas-postgres -n "$MLFLOW_NS" >/dev/null 2>&1; then
    run oc apply -f "${MANIFESTS}/maas-postgres-dev.yaml"
  fi
  wait_for_pod_grep "$MLFLOW_NS" "wings3-maas-postgres" 300 0 || true
  ensure_maas_db_secrets
}

discover_gateway_tls_secret() {
  local cert="" ns="$GATEWAY_NS"
  cert=$(oc get deployment router-default -n "$ns" \
    -o jsonpath='{.spec.template.spec.volumes[?(@.name=="default-certificate")].secret.secretName}' \
    2>/dev/null || true)
  if [[ -n "$cert" ]] && oc get secret "$cert" -n "$ns" >/dev/null 2>&1; then
    printf '%s' "$cert"
    return 0
  fi
  for cert in cert-manager-ingress-cert default-gateway-cert router-certs-default; do
    if oc get secret "$cert" -n "$ns" >/dev/null 2>&1; then
      printf '%s' "$cert"
      return 0
    fi
  done
  printf ''
}

discover_maas_route_hostname() {
  local host=""
  host=$(oc get route openshift-ai-inference -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$host" ]]; then
    printf '%s' "$host"
    return 0
  fi
  for name in maas-default-gateway openshift-ai-inference data-science-gateway; do
    host=$(oc get gateway "$name" -n "$GATEWAY_NS" \
      -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].hostname}' 2>/dev/null || true)
    if [[ -n "$host" ]]; then
      printf '%s' "$host"
      return 0
    fi
  done
  printf ''
}

patch_maas_gateway_hostname() {
  local host="" idx="" current=""
  host=$(discover_maas_route_hostname)
  if [[ -z "$host" ]]; then
    echo "warning: cannot discover Route hostname for maas-default-gateway" >&2
    return 1
  fi
  # Reencrypt Routes (openshift-ai-inference) send internal SNI to the gateway listener.
  # A hostname filter on the HTTPS listener causes filter_chain_not_found / 503 (RHOAI 3.5).
  if oc get route openshift-ai-inference -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.tls.termination}' 2>/dev/null | grep -q reencrypt; then
    current=$(oc get gateway maas-default-gateway -n "$GATEWAY_NS" \
      -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].hostname}' 2>/dev/null || true)
    if [[ -n "$current" ]]; then
      idx=$(oc get gateway maas-default-gateway -n "$GATEWAY_NS" -o json 2>/dev/null \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((i for i,l in enumerate(d.get("spec",{}).get("listeners",[])) if l.get("protocol")=="HTTPS"), ""))' || true)
      if [[ -n "$idx" ]]; then
        log "remove maas-default-gateway HTTPS hostname (reencrypt Route SNI mismatch)"
        oc patch gateway maas-default-gateway -n "$GATEWAY_NS" --type=json \
          -p "[{\"op\":\"remove\",\"path\":\"/spec/listeners/${idx}/hostname\"}]" \
          >/dev/null 2>&1 || true
      fi
    fi
    ensure_maas_bff_api_url "$host"
    return 0
  fi
  current=$(oc get gateway maas-default-gateway -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].hostname}' 2>/dev/null || true)
  if [[ "$current" == "$host" ]]; then
    ensure_maas_bff_api_url "$host"
    return 0
  fi
  idx=$(oc get gateway maas-default-gateway -n "$GATEWAY_NS" -o json 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((i for i,l in enumerate(d.get("spec",{}).get("listeners",[])) if l.get("protocol")=="HTTPS"), ""))' || true)
  if [[ -z "$idx" ]]; then
    echo "warning: maas-default-gateway has no HTTPS listener to patch hostname" >&2
    return 1
  fi
  log "patch maas-default-gateway HTTPS hostname -> ${host}"
  if [[ -n "$current" ]]; then
    oc patch gateway maas-default-gateway -n "$GATEWAY_NS" --type=json \
      -p "[{\"op\":\"replace\",\"path\":\"/spec/listeners/${idx}/hostname\",\"value\":\"${host}\"}]" \
      >/dev/null 2>&1 || true
  else
    oc patch gateway maas-default-gateway -n "$GATEWAY_NS" --type=json \
      -p "[{\"op\":\"add\",\"path\":\"/spec/listeners/${idx}/hostname\",\"value\":\"${host}\"}]" \
      >/dev/null 2>&1 || true
  fi
  ensure_maas_bff_api_url "$host"
}

ensure_maas_bff_api_url() {
  local host="${1:-}"
  if [[ -z "$host" ]]; then
    host=$(discover_maas_route_hostname)
  fi
  [[ -z "$host" ]] && return 0
  local url="https://${host}/maas-api"
  for dep in rhods-dashboard maas-ui gen-ai-ui; do
    if oc get deployment "$dep" -n "$MLFLOW_NS" >/dev/null 2>&1; then
      local current=""
      current=$(oc get deployment "$dep" -n "$MLFLOW_NS" \
        -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MAAS_API_URL")].value}' 2>/dev/null || true)
      if [[ "$current" != "$url" ]]; then
        log "set ${dep} MAAS_API_URL -> ${url}"
        oc set env deployment/"$dep" -n "$MLFLOW_NS" "MAAS_API_URL=${url}" >/dev/null 2>&1 || true
      fi
    fi
  done
}

patch_maas_gateway_tls() {
  local cert=""
  cert=$(discover_gateway_tls_secret)
  if [[ -z "$cert" ]]; then
    echo "warning: no TLS secret found for maas-default-gateway in ${GATEWAY_NS}" >&2
    return 1
  fi
  local current=""
  current=$(oc get gateway maas-default-gateway -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.listeners[0].tls.certificateRefs[0].name}' 2>/dev/null || true)
  if [[ "$current" == "$cert" ]]; then
    return 0
  fi
  log "patch maas-default-gateway TLS cert -> ${cert}"
  oc patch gateway maas-default-gateway -n "$GATEWAY_NS" --type=json \
    -p "[{\"op\":\"replace\",\"path\":\"/spec/listeners/0/tls/certificateRefs/0/name\",\"value\":\"${cert}\"}]" \
    >/dev/null 2>&1 || true
}

ensure_maas_gateway() {
  local host=""
  if ! oc get gateway maas-default-gateway -n "$GATEWAY_NS" >/dev/null 2>&1; then
    host=$(oc get gateway openshift-ai-inference -n "$GATEWAY_NS" \
      -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null || true)
    if [[ -z "$host" ]]; then
      echo "warning: cannot discover inference gateway hostname for maas-default-gateway" >&2
      return 1
    fi
    if [[ -f "${MANIFESTS}/maas-default-gateway.yaml" ]]; then
      local cert=""
      cert=$(discover_gateway_tls_secret)
      if [[ -n "$cert" ]]; then
        sed -e "s/REPLACE_MAAS_GATEWAY_HOST/${host}/" \
          -e "s/default-gateway-tls/${cert}/" \
          "${MANIFESTS}/maas-default-gateway.yaml" | oc apply -f -
      else
        sed "s/REPLACE_MAAS_GATEWAY_HOST/${host}/" "${MANIFESTS}/maas-default-gateway.yaml" | oc apply -f -
      fi
    fi
  fi
  patch_maas_gateway_hostname || true
  patch_maas_gateway_tls || true
  if ! oc get gateway maas-default-gateway -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.listeners[0].allowedRoutes.namespaces.selector.matchExpressions[0].values}' 2>/dev/null \
    | grep -q redhat-ai-gateway-infra; then
    oc patch gateway maas-default-gateway -n "$GATEWAY_NS" --type=json \
      -p '[{"op":"add","path":"/spec/listeners/0/allowedRoutes/namespaces/selector/matchExpressions/0/values/-","value":"redhat-ai-gateway-infra"}]' \
      >/dev/null 2>&1 || true
  fi
  if oc get aitenant models-as-a-service -n ai-tenants >/dev/null 2>&1; then
    oc patch aitenant models-as-a-service -n ai-tenants --type=merge \
      -p '{"spec":{"gateway":{"name":"maas-default-gateway"}}}' >/dev/null 2>&1 || true
  fi
}

ensure_kuadrant() {
  if [[ "${WINGS3_SKIP_KUADRANT:-0}" == 1 ]]; then
    return 0
  fi
  if ! oc get kuadrant kuadrant -n "$KUADRANT_NS" >/dev/null 2>&1; then
    if [[ -f "${MANIFESTS}/kuadrant-dev.yaml" ]]; then
      run oc apply -f "${MANIFESTS}/kuadrant-dev.yaml"
    fi
  fi
}

wait_for_kuadrant_ready() {
  local timeout="${1:-600}"
  local elapsed=0 ready="" authorino=""
  while ((elapsed < timeout)); do
    ready=$(oc get kuadrant kuadrant -n "$KUADRANT_NS" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    authorino=$(oc get authorino -n "$KUADRANT_NS" \
      -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "$ready" == "True" && "$authorino" == "True" ]]; then
      return 0
    fi
    if [[ "$ready" == "True" ]] && wait_for_pod_grep "$KUADRANT_NS" "authorino" 120 0; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "warning: Kuadrant/Authorino not Ready in ${KUADRANT_NS}" >&2
  return 1
}

authorino_service_name() {
  oc get svc -n "$KUADRANT_NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | grep -E '^authorino' | head -1
}

ensure_authorino_tls() {
  local svc="" authorino_name=""
  if ! oc get namespace "$KUADRANT_NS" >/dev/null 2>&1; then
    return 1
  fi
  svc=$(authorino_service_name)
  authorino_name=$(oc get authorino -n "$KUADRANT_NS" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$svc" || -z "$authorino_name" ]]; then
    return 1
  fi
  oc annotate service "$svc" -n "$KUADRANT_NS" \
    service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
    --overwrite >/dev/null 2>&1 || true
  oc patch authorino "$authorino_name" -n "$KUADRANT_NS" --type=merge \
    -p '{"spec":{"listener":{"tls":{"enabled":true,"certSecretRef":{"name":"authorino-server-cert"}}}}}' \
    >/dev/null 2>&1 || true
  oc -n "$KUADRANT_NS" set env deployment/authorino \
    SSL_CERT_FILE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/openshift-service-ca/service-ca-bundle.crt \
    >/dev/null 2>&1 || true
  oc annotate gateway maas-default-gateway -n "$GATEWAY_NS" \
    security.opendatahub.io/authorino-tls-bootstrap=true \
    --overwrite >/dev/null 2>&1 || true
}

reconcile_maas_subscription() {
  local phase=""
  phase=$(oc get maassubscription "$MAAS_SUBSCRIPTION" -n "$MAAS_NS" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)
  if [[ "$phase" != "Failed" ]]; then
    return 0
  fi
  log "reconcile failed MaaSSubscription ${MAAS_SUBSCRIPTION}"
  run oc delete tokenratelimitpolicy "maas-trlp-${MAAS_MODEL}" -n "$PROJECT" --ignore-not-found=true
  run oc apply -f "${MANIFESTS}/maas-auth-subscription-gpt-oss-120b.yaml"
  local elapsed=0
  while ((elapsed < 120)); do
    phase=$(oc get maassubscription "$MAAS_SUBSCRIPTION" -n "$MAAS_NS" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$phase" == "Active" ]]; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "warning: MaaSSubscription ${MAAS_SUBSCRIPTION} phase=${phase}" >&2
  return 1
}

read_secret_key() {
  local name="$1"
  local ns="$2"
  local key="$3"
  local b64=""
  b64=$(oc get secret "$name" -n "$ns" -o "jsonpath={.data.${key}}" 2>/dev/null || true)
  if [[ -z "$b64" ]]; then
    printf ''
    return 0
  fi
  printf '%s' "$b64" | base64 -d 2>/dev/null || true
}

bootstrap_maas_upstream_secret() {
  local upstream_key="${WINGS3_MAAS_UPSTREAM_API_KEY:-}"
  local secret_file="${MANIFESTS}/secret-wings3-maas-upstream-api-key.yaml"
  local example="${MANIFESTS}/secret-wings3-maas-upstream-api-key.example.yaml"
  if [[ -z "$upstream_key" ]]; then
    upstream_key=$(read_secret_key wings3-maas-upstream-api-key "$PROJECT" api-key)
  fi
  if [[ -z "$upstream_key" ]]; then
    upstream_key=$(read_secret_key wings3-judge-llm "$PROJECT" JUDGE_API_KEY)
    if [[ -n "$upstream_key" ]] && [[ "$upstream_key" == sk-oai-* ]]; then
      upstream_key=""
    fi
  fi
  if [[ -z "$upstream_key" ]]; then
    echo "warning: WINGS3_MAAS_UPSTREAM_API_KEY unset and no upstream api-key found" >&2
    echo "warning: copy ${example} to ${secret_file} or export WINGS3_MAAS_UPSTREAM_API_KEY" >&2
    return 1
  fi
  if [[ -f "$secret_file" ]]; then
    run oc apply -f "$secret_file"
  else
    run oc create secret generic wings3-maas-upstream-api-key \
      -n "$PROJECT" \
      --from-literal=api-key="$upstream_key" \
      --dry-run=client -o yaml \
      | oc label -f - --local app.kubernetes.io/part-of="$MAAS_PART_OF" \
        inference.networking.k8s.io/bbr-managed=true --overwrite \
      | oc apply -f -
  fi
  if ! oc get secret wings3-maas-upstream-api-key -n "$PROJECT" >/dev/null 2>&1; then
    return 1
  fi
  oc patch secret wings3-maas-upstream-api-key -n "$PROJECT" --type=merge \
    -p "{\"metadata\":{\"labels\":{\"app.kubernetes.io/part-of\":\"${MAAS_PART_OF}\",\"inference.networking.k8s.io/bbr-managed\":\"true\"}}}" \
    >/dev/null 2>&1 || true
  if [[ -n "${WINGS3_MAAS_UPSTREAM_API_KEY:-}" ]]; then
    oc set data secret/wings3-maas-upstream-api-key -n "$PROJECT" "api-key=${WINGS3_MAAS_UPSTREAM_API_KEY}"
  fi
}

apply_maas_manifests() {
  run oc apply -f "${MANIFESTS}/maas-external-model-gpt-oss-120b.yaml"
  run oc apply -f "${MANIFESTS}/maas-modelref-gpt-oss-120b.yaml"
  run oc apply -f "${MANIFESTS}/maas-auth-subscription-gpt-oss-120b.yaml"
}

wait_for_maas_modelref_ready() {
  local timeout="${1:-600}"
  local elapsed=0 phase=""
  while ((elapsed < timeout)); do
    phase=$(oc get maasmodelref "$MAAS_MODEL" -n "$PROJECT" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ -z "$phase" ]]; then
      phase=$(oc get maasmodelref "$MAAS_MODEL" -n "$PROJECT" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    fi
    if [[ "$phase" == "Ready" || "$phase" == "True" ]]; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "warning: MaaSModelRef/${MAAS_MODEL} not Ready after ${timeout}s (phase=${phase})" >&2
  return 1
}

discover_maas_gateway_host() {
  local host="" name
  for name in maas-default-gateway openshift-ai-inference data-science-gateway; do
    host=$(oc get gateway "$name" -n "$GATEWAY_NS" \
      -o jsonpath='{.spec.listeners[0].hostname}' 2>/dev/null || true)
    if [[ -n "$host" ]]; then
      printf '%s' "$host"
      return 0
    fi
  done
  host=$(oc get maasmodelref "$MAAS_MODEL" -n "$PROJECT" \
    -o jsonpath='{.status.endpoint}' 2>/dev/null || true)
  if [[ -n "$host" ]]; then
    host=${host#https://}
    host=${host#http://}
    host=${host%%/*}
    printf '%s' "$host"
    return 0
  fi
  for name in maas-default-gateway openshift-ai-inference; do
    host=$(oc get gateway "$name" -n "$GATEWAY_NS" \
      -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)
    if [[ -n "$host" && "$host" != *svc.cluster.local* ]]; then
      printf '%s' "$host"
      return 0
    fi
  done
  host=$(oc get httproute -n "$PROJECT" -o json 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((h for i in d.get("items",[]) for h in (i.get("spec",{}).get("hostnames") or []) if h), ""))' || true)
  if [[ -n "$host" ]]; then
    printf '%s' "$host"
    return 0
  fi
  printf ''
}

discover_maas_judge_base_url() {
  local endpoint="" path="" host=""
  endpoint=$(oc get maasmodelref "$MAAS_MODEL" -n "$PROJECT" \
    -o jsonpath='{.status.endpoint}' 2>/dev/null || true)
  path=$(oc get httproute "maas-${MAAS_MODEL}" -n "$PROJECT" \
    -o jsonpath='{.spec.rules[0].matches[0].path.value}' 2>/dev/null || true)
  if [[ -n "$endpoint" && -n "$path" ]]; then
    endpoint=${endpoint%/}
    path=${path#/}
    printf '%s/%s/v1' "$endpoint" "$path"
    return 0
  fi
  host=$(discover_maas_gateway_host)
  if [[ -n "$host" ]]; then
    printf 'https://%s/llm/%s/v1' "$host" "$MAAS_MODEL"
    return 0
  fi
  printf ''
}

mint_maas_api_key_via_portforward() {
  local token="" body="" key="" pf_pid=""
  token=$(oc whoami -t 2>/dev/null || true)
  if [[ -z "$token" ]]; then
    return 1
  fi
  oc port-forward -n redhat-ai-gateway-infra svc/maas-api 18443:8443 >/dev/null 2>&1 &
  pf_pid=$!
  sleep 2
  body=$(curl -fsS --max-time 15 -X POST "https://127.0.0.1:18443/v1/api-keys" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"wings3-judge\",\"subscription\":\"${MAAS_SUBSCRIPTION}\",\"expiresIn\":\"90d\"}" \
    2>/dev/null || true)
  kill "$pf_pid" >/dev/null 2>&1 || true
  wait "$pf_pid" 2>/dev/null || true
  if [[ -z "$body" ]]; then
    return 1
  fi
  key=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)
  if [[ -z "$key" ]]; then
    return 1
  fi
  printf '%s' "$key"
}

mint_maas_api_key() {
  local gateway_host="$1"
  local token="" body="" key=""
  token=$(oc whoami -t 2>/dev/null || true)
  if [[ -z "$token" ]]; then
    echo "warning: oc whoami -t failed; cannot mint MaaS API key" >&2
    return 1
  fi
  if [[ -n "$gateway_host" ]]; then
    body=$(curl -fsSk --max-time 20 -X POST "https://${gateway_host}/maas-api/v1/api-keys" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"wings3-judge\",\"subscription\":\"${MAAS_SUBSCRIPTION}\",\"expiresIn\":\"90d\"}" \
      2>/dev/null || true)
    key=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)
    if [[ -n "$key" ]]; then
      printf '%s' "$key"
      return 0
    fi
  fi
  key=$(mint_maas_api_key_via_portforward || true)
  if [[ -n "$key" ]]; then
    printf '%s' "$key"
    return 0
  fi
  echo "warning: MaaS API key mint failed (Authorino/OIDC may be missing on cluster)" >&2
  return 1
}

workshop_direct_base_url() {
  printf 'https://%s/v1' "${MAAS_UPSTREAM_ENDPOINT}"
}

maas_inference_probe() {
  local base_url="$1"
  local api_key="$2"
  local code=""
  if [[ -z "$base_url" || -z "$api_key" ]]; then
    return 1
  fi
  code=$(curl -fsSk --max-time 20 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${api_key}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${MAAS_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":5}" \
    "${base_url%/}/chat/completions" 2>/dev/null || echo "000")
  [[ "$code" == "200" ]]
}

patch_judge_secret_for_maas() {
  local base_url="$1"
  local api_key="$2"
  local maas_base_url="$1"
  local maas_api_key="$2"
  if [[ -z "$base_url" ]]; then
    echo "error: patch_judge_secret_for_maas requires base_url" >&2
    return 1
  fi
  if [[ -n "${WINGS3_JUDGE_API_KEY:-}" ]]; then
    api_key="${WINGS3_JUDGE_API_KEY}"
    maas_api_key="${WINGS3_JUDGE_API_KEY}"
  fi
  if ! maas_inference_probe "$base_url" "$api_key"; then
    local upstream_key=""
    upstream_key=$(read_secret_key wings3-maas-upstream-api-key "$PROJECT" api-key)
    if [[ -n "$upstream_key" ]]; then
      echo "warning: in-cluster MaaS gateway inference failed; using workshop direct for MAAS_* and JUDGE_*" >&2
      maas_base_url=$(workshop_direct_base_url)
      maas_api_key="$upstream_key"
      base_url="$maas_base_url"
      api_key="$upstream_key"
    fi
  fi
  oc create secret generic wings3-judge-llm \
    -n "$PROJECT" \
    --from-literal=MAAS_MODEL="$MAAS_MODEL" \
    --from-literal=MAAS_BASE_URL="$maas_base_url" \
    --from-literal=MAAS_API_KEY="$maas_api_key" \
    --from-literal=JUDGE_BASE_URL="$base_url" \
    --from-literal=JUDGE_MODEL="$MAAS_MODEL" \
    --from-literal=JUDGE_API_KEY="$api_key" \
    --dry-run=client -o yaml | oc apply -f -
  oc label secret wings3-judge-llm -n "$PROJECT" app.kubernetes.io/part-of="$MAAS_PART_OF" \
    --overwrite >/dev/null 2>&1 || true
}

enable_maas() {
  if [[ "${WINGS3_SKIP_MAAS:-0}" == 1 ]]; then
    log "skip MaaS (WINGS3_SKIP_MAAS=1)"
    return 0
  fi
  info "enabling MaaS external model ${MAAS_MODEL} for judges"
  enable_maas_operator || return 0
  ensure_kuadrant
  wait_for_kuadrant_ready 600 || true
  ensure_maas_postgres || true
  if ! wait_for_maas_crds 120; then
    wait_for_maas_crds 600 || return 0
  fi
  wait_for_maas_namespace 120 || true
  ensure_maas_gateway || true
  ensure_authorino_tls || true
  wait_for_pod_grep "$MLFLOW_NS" "maas-controller" 120 0 || true
  bootstrap_maas_upstream_secret || return 0
  apply_maas_manifests || return 0
  reconcile_maas_subscription || true
  wait_for_maas_modelref_ready 600 || true
  ensure_maas_dashboard_prereqs || true
  local host="" base_url="" maas_key=""
  host=$(discover_maas_gateway_host)
  base_url=$(discover_maas_judge_base_url)
  if [[ -z "$base_url" ]]; then
    echo "warning: could not discover MaaS judge base URL" >&2
    return 0
  fi
  maas_key=$(mint_maas_api_key "$host" || true)
  if [[ -z "$maas_key" ]]; then
    maas_key=$(read_secret_key wings3-judge-llm "$PROJECT" JUDGE_API_KEY)
    if [[ "$maas_key" != sk-oai-* ]]; then
      maas_key=""
    fi
  fi
  if [[ -z "$maas_key" ]]; then
    echo "warning: no MaaS API key for judges; patch judge secret manually" >&2
    patch_judge_secret_for_maas "$base_url" ""
    return 0
  fi
  patch_judge_secret_for_maas "$base_url" "$maas_key"
  info "MaaS judge endpoint: ${base_url}"
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
  oc annotate "${NOTEBOOK_API}" "$WORKBENCH" -n "$PROJECT" --overwrite \
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
  oc annotate "${NOTEBOOK_API}" "$WORKBENCH" -n "$PROJECT" --overwrite \
    opendatahub.io/hardware-profile-name- \
    opendatahub.io/hardware-profile-namespace- >/dev/null
}

apply_judge_secret() {
  local secret="${MANIFESTS}/secret-wings3-judge-llm.yaml"
  local example="${MANIFESTS}/secret-wings3-judge-llm.example.yaml"
  if [[ ! -f "$secret" ]]; then
    secret="$example"
  fi
  if ! oc get secret wings3-judge-llm -n "$PROJECT" >/dev/null 2>&1; then
    oc apply -f "$secret"
  else
    echo "warning: secret/wings3-judge-llm already exists — not re-applying ${secret}" >&2
    echo "warning: partial yaml would drop MAAS_* keys; use install.sh MaaS patch or oc set env" >&2
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

sync_llm_endpoint_configmap() {
  local model="" url=""
  run oc apply -f "${MANIFESTS}/configmap-wings3-llm-endpoint.yaml"
  model=$(read_secret_key wings3-judge-llm "$PROJECT" MAAS_MODEL)
  url=$(read_secret_key wings3-judge-llm "$PROJECT" MAAS_BASE_URL)
  if [[ -z "$model" || -z "$url" ]]; then
    log "skip wings3-llm-endpoint sync (MAAS_MODEL/MAAS_BASE_URL missing on secret)"
    return 0
  fi
  oc patch configmap wings3-llm-endpoint -n "$PROJECT" --type merge -p \
    "{\"data\":{\"model_name\":\"${model}\",\"openai_base_url\":\"${url}\"}}" >/dev/null
  info "wings3-llm-endpoint: model=${model}"
}

apply_evalhub_manifests() {
  sync_llm_endpoint_configmap
  if [[ -f "${MANIFESTS}/evalhub-rbac-wings3.yaml" ]]; then
    run oc apply -f "${MANIFESTS}/evalhub-rbac-wings3.yaml"
  fi
  if [[ -f "${MANIFESTS}/evalhub-instance.yaml" ]]; then
    run oc apply -f "${MANIFESTS}/evalhub-instance.yaml"
    # single-tenant EvalHub must not run in a tenant-labelled namespace
    run oc label namespace "$PROJECT" evalhub.trustyai.opendatahub.io/tenant- --overwrite 2>/dev/null || true
    if ! wait_for_pod_grep "$PROJECT" "evalhub" 300 0; then
      echo "warning: EvalHub server pod not Ready in ${PROJECT}" >&2
    fi
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
  run oc delete "${NOTEBOOK_API}" "$WORKBENCH" -n "$PROJECT" --ignore-not-found=true
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

purge_maas_resources() {
  run oc delete maasmodelref "$MAAS_MODEL" -n "$PROJECT" --ignore-not-found=true
  run oc delete externalmodel "$MAAS_MODEL" -n "$PROJECT" --ignore-not-found=true
  run oc delete maassubscription "$MAAS_SUBSCRIPTION" -n "$MAAS_NS" --ignore-not-found=true
  run oc delete maasauthpolicy "$MAAS_SUBSCRIPTION" -n "$MAAS_NS" --ignore-not-found=true
  run oc delete secret wings3-maas-upstream-api-key -n "$PROJECT" --ignore-not-found=true
  run oc delete -f "${MANIFESTS}/maas-postgres-dev.yaml" --ignore-not-found=true
  if oc get secret maas-db-config -n "$MLFLOW_NS" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}' 2>/dev/null \
    | grep -q "$MAAS_PART_OF"; then
    run oc delete secret maas-db-config -n "$MLFLOW_NS" --ignore-not-found=true
  fi
}

purge_ogx_resources() {
  if crd_registered 'ogxservers\.ogx\.io'; then
    run oc delete ogxserver "$OGX_SERVER_NAME" -n "$PROJECT" --ignore-not-found=true
  fi
  run oc delete -f "${MANIFESTS}/ogx-server-wings3.yaml" --ignore-not-found=true
  run oc delete -f "${MANIFESTS}/ogx-postgres-dev.yaml" --ignore-not-found=true
}
