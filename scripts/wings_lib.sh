#!/usr/bin/env bash
# Shared helpers for WINGS install/uninstall/check scripts.
set -euo pipefail

WINGS_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WINGS_ROOT=$(cd "${WINGS_LIB_DIR}/.." && pwd)
MANIFESTS="${WINGS_ROOT}/manifests"
PROJECT="${WINGS_PROJECT:-my-first-model}"
DSC="${WINGS_DSC_NAME:-default-dsc}"
MLFLOW_NS="${WINGS_MLFLOW_NAMESPACE:-redhat-ods-applications}"
LLM_MODEL="${WINGS_LLM_MODEL:-llama-32-3b-instruct}"
WORKBENCH="${WINGS_WORKBENCH:-wings-demo}"
# Stormshift (and some clusters) register notebooks.intel.com before kubeflow.org.
NOTEBOOK_API="${WINGS_NOTEBOOK_API:-notebook.kubeflow.org}"
REPO_DEST="/opt/app-root/src/wings"
DEMO_DEST="${REPO_DEST}/demo"
GIT_URL="${WINGS_GIT_URL:-https://github.com/gmodzelewski/wings.git}"
SR_TEMPLATE="${WINGS_SR_TEMPLATE:-vllm-cuda-runtime-template}"
IS_MANIFEST="${MANIFESTS}/inferenceservice-llama-32-3b-instruct.yaml"
INSTANTIATE_SR="${WINGS_ROOT}/scripts/instantiate_servingruntime.py"

EVALHUB_DSC_COMPONENT="${WINGS_EVALHUB_DSC_COMPONENT:-}"
GARAK_DSC_COMPONENT="${WINGS_GARAK_DSC_COMPONENT:-}"

MAAS_NS="${WINGS_MAAS_NAMESPACE:-models-as-a-service}"
MAAS_MODEL="${WINGS_MAAS_MODEL:-gpt-oss-120b}"
# Catalog models for Gen AI Studio (shared wings-maas-upstream-api-key). Primary judge stays MAAS_MODEL.
MAAS_CATALOG_MODELS="${WINGS_MAAS_CATALOG_MODELS:-gpt-oss-120b gpt-oss-20b llama-scout-17b qwen36-35b-a3b}"
MAAS_SUBSCRIPTION="${WINGS_MAAS_SUBSCRIPTION:-redhat-maas}"
MAAS_UPSTREAM_ENDPOINT="${WINGS_MAAS_UPSTREAM_ENDPOINT:-maas-rhdp.apps.maas.redhatworkshops.io}"
MAAS_PART_OF="${WINGS_MAAS_PART_OF:-wings-demo}"
KUADRANT_NS="${WINGS_KUADRANT_NAMESPACE:-kuadrant-system}"
GATEWAY_NS="${WINGS_GATEWAY_NAMESPACE:-openshift-ingress}"
SM_NS="${WINGS_SERVICEMESH_NAMESPACE:-istio-system}"
SM_CNI_NS="${WINGS_SERVICEMESH_CNI_NAMESPACE:-istio-cni}"
OGX_SERVER_NAME="${WINGS_OGX_SERVER_NAME:-wings-ogx}"

DSCI_NAME="${WINGS_DSCI_NAME:-default-dsci}"
MONITORING_NS="${WINGS_MONITORING_NAMESPACE:-redhat-ods-monitoring}"
COO_NS="${WINGS_COO_NAMESPACE:-openshift-cluster-observability-operator}"
OTEL_NS="${WINGS_OTEL_NAMESPACE:-openshift-opentelemetry-operator}"
TEMPO_NS="${WINGS_TEMPO_NAMESPACE:-openshift-tempo-operator}"
LOKI_OPERATOR_NS="${WINGS_LOKI_OPERATOR_NAMESPACE:-openshift-operators-redhat}"
REDIS_LIMITADOR_NS="${WINGS_REDIS_LIMITADOR_NAMESPACE:-redis-limitador}"

log() {
  if [[ "${WINGS_VERBOSE:-0}" == 1 ]]; then
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
  # Accept either plain CRD names (kuadrants.kuadrant.io) or grep-escaped
  # patterns (kuadrants\.kuadrant\.io). Prefer `oc get crd` for dotted names.
  local suffix="$1"
  local crd_name="${suffix//\\/}"
  if [[ "$crd_name" == *.* ]]; then
    oc get crd "$crd_name" >/dev/null 2>&1 && return 0
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

# ---------------------------------------------------------------------------
# Observability (Usage/token-consumption dashboard): Cluster Observability
# Operator (COO), Red Hat OpenTelemetry, Tempo, Loki — plus DSCI metrics
# storage and the observabilityDashboard flag. MaaS-side telemetry hooks
# (MaasTenantConfig, usageLogging, Redis-backed Limitador) live in
# enable_maas_observability(), called at the end of enable_maas().
# ---------------------------------------------------------------------------

csv_succeeded_in_namespace() {
  local ns="$1" name_pattern="$2"
  oc get csv -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null \
    | awk -v p="$name_pattern" '$1 ~ p && $2 == "Succeeded" {found=1} END {exit !found}'
}

# Several operator manifests bundle a Namespace + OperatorGroup + Subscription
# in one file for convenience. Some of those namespaces (openshift-operators-
# redhat in particular) are Red Hat-conventional *shared* namespaces that
# other operators (unrelated to WINGS) may already use on a given cluster.
# These helpers let install apply only the OperatorGroup/Subscription when the
# namespace pre-exists (never taking ownership of someone else's namespace),
# and let uninstall symmetrically avoid deleting a namespace WINGS didn't
# create -- it only strips back the Subscription/OperatorGroup it added.
manifest_minus_namespace_doc() {
  # Reads a multi-document YAML manifest on stdin, drops any "---"-delimited
  # document containing a top-level "kind: Namespace", prints the rest.
  python3 -c '
import sys
content = sys.stdin.read()
docs = content.split("\n---\n")
kept = [d for d in docs if "kind: Namespace" not in d]
sys.stdout.write("\n---\n".join(kept))
'
}

namespace_owned_by_wings() {
  local ns="$1"
  oc get namespace "$ns" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}' 2>/dev/null \
    | grep -q '^wings-demo$'
}

apply_operator_manifest_ns_aware() {
  # $1 = namespace, manifest content on stdin.
  local ns="$1" content=""
  content=$(cat)
  if oc get namespace "$ns" >/dev/null 2>&1; then
    log "namespace ${ns} already exists -- not taking ownership, only adding OperatorGroup/Subscription"
    printf '%s' "$content" | manifest_minus_namespace_doc | run oc apply -f -
  else
    printf '%s' "$content" | run oc apply -f -
  fi
}

purge_operator_manifest_ns_aware() {
  # $1 = namespace, manifest content on stdin.
  local ns="$1" content=""
  content=$(cat)
  if ! oc get namespace "$ns" >/dev/null 2>&1; then
    return 0
  fi
  if namespace_owned_by_wings "$ns"; then
    printf '%s' "$content" | run oc delete -f - --ignore-not-found=true
  else
    log "namespace ${ns} predates/outlives WINGS install (shared) -- removing only the Subscription/OperatorGroup WINGS added, keeping the namespace"
    printf '%s' "$content" | manifest_minus_namespace_doc | run oc delete -f - --ignore-not-found=true
  fi
}

wait_for_csv_succeeded() {
  local ns="$1" name_pattern="$2" timeout="${3:-600}" elapsed=0
  while ((elapsed < timeout)); do
    if csv_succeeded_in_namespace "$ns" "$name_pattern"; then
      info "CSV Succeeded: ${ns}/${name_pattern}"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "warning: timed out waiting for CSV ${name_pattern} in ${ns}" >&2
  return 1
}

ensure_cluster_observability_operator() {
  if csv_succeeded_in_namespace "$COO_NS" 'cluster-observability-operator\.'; then
    log "Cluster Observability Operator already Succeeded"
    return 0
  fi
  info "installing Cluster Observability Operator"
  apply_operator_manifest_ns_aware "$COO_NS" < "${MANIFESTS}/cluster-observability-operator.yaml"
  wait_for_csv_succeeded "$COO_NS" 'cluster-observability-operator\.' 600
}

ensure_opentelemetry_operator() {
  if csv_succeeded_in_namespace "$OTEL_NS" 'opentelemetry-operator\.'; then
    log "Red Hat OpenTelemetry operator already Succeeded"
    return 0
  fi
  info "installing Red Hat build of OpenTelemetry"
  apply_operator_manifest_ns_aware "$OTEL_NS" < "${MANIFESTS}/opentelemetry-operator.yaml"
  wait_for_csv_succeeded "$OTEL_NS" 'opentelemetry-operator\.' 600
}

ensure_tempo_operator() {
  if csv_succeeded_in_namespace "$TEMPO_NS" 'tempo-operator\.'; then
    log "Tempo operator already Succeeded"
    return 0
  fi
  info "installing Tempo operator"
  apply_operator_manifest_ns_aware "$TEMPO_NS" < "${MANIFESTS}/tempo-operator.yaml"
  wait_for_csv_succeeded "$TEMPO_NS" 'tempo-operator\.' 600
}

discover_loki_channel() {
  # Multiple catalog sources publish a package named "loki-operator" (the
  # community Grafana operator and the Red Hat one) — select the one that
  # matches our Subscription's source: redhat-operators, not whichever
  # packagemanifest object the API happens to return first.
  local channel=""
  channel=$(oc get packagemanifest -n openshift-marketplace -o json 2>/dev/null \
    | python3 -c '
import json, sys
d = json.load(sys.stdin)
for item in d.get("items", []):
    if item["metadata"]["name"] == "loki-operator" and item["status"].get("catalogSource") == "redhat-operators":
        print(item["status"]["defaultChannel"])
        break
' || true)
  printf '%s' "${channel:-stable-6.6}"
}

ensure_loki_operator() {
  if csv_succeeded_in_namespace "$LOKI_OPERATOR_NS" 'loki-operator\.'; then
    log "Loki operator already Succeeded"
    return 0
  fi
  local channel=""
  channel=$(discover_loki_channel)
  info "installing Loki operator (channel ${channel})"
  sed "s/REPLACE_LOKI_CHANNEL/${channel}/" "${MANIFESTS}/loki-operator.yaml" \
    | apply_operator_manifest_ns_aware "$LOKI_OPERATOR_NS"
  wait_for_csv_succeeded "$LOKI_OPERATOR_NS" 'loki-operator\.' 600
}

uwm_configmap_owned_by_wings() {
  oc get configmap cluster-monitoring-config -n openshift-monitoring \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/part-of}' 2>/dev/null | grep -q wings-demo
}

merge_uwm_enabled_flag() {
  local value="$1"
  python3 - "$value" <<'PY'
import subprocess
import sys

value = sys.argv[1]
existing = subprocess.run(
    ["oc", "get", "configmap", "cluster-monitoring-config", "-n", "openshift-monitoring",
     "-o", "jsonpath={.data.config\\.yaml}"],
    capture_output=True, text=True,
)
body = existing.stdout if existing.returncode == 0 else ""
lines = [l for l in body.splitlines() if not l.strip().startswith("enableUserWorkload:")]
lines.append(f"enableUserWorkload: {value}")
new_body = "\n".join(lines) + "\n"

patch = {"data": {"config.yaml": new_body}}
import json
proc = subprocess.run(
    ["oc", "patch", "configmap", "cluster-monitoring-config", "-n", "openshift-monitoring",
     "--type=merge", "-p", json.dumps(patch)],
    capture_output=True, text=True,
)
sys.exit(0 if proc.returncode == 0 else 1)
PY
}

ensure_user_workload_monitoring() {
  if ! oc get configmap cluster-monitoring-config -n openshift-monitoring >/dev/null 2>&1; then
    log "create cluster-monitoring-config with enableUserWorkload: true"
    run oc apply -f "${MANIFESTS}/cluster-monitoring-config.yaml"
  else
    log "merge enableUserWorkload: true into existing cluster-monitoring-config"
    merge_uwm_enabled_flag true || echo "warning: could not merge UWM flag into cluster-monitoring-config" >&2
    if ! uwm_configmap_owned_by_wings; then
      oc annotate configmap cluster-monitoring-config -n openshift-monitoring --overwrite \
        wings-demo/added-enable-user-workload=true >/dev/null 2>&1 || true
    fi
  fi
  wait_for_pod_grep "openshift-user-workload-monitoring" "prometheus-user-workload" 300 0 || true
}

wait_for_dsci_monitoring_ready() {
  local timeout="${1:-900}" elapsed=0 status=""
  while ((elapsed < timeout)); do
    status=$(oc get dsci "$DSCI_NAME" \
      -o jsonpath='{.status.conditions[?(@.type=="MonitoringStackAvailable")].status}' 2>/dev/null || true)
    if [[ "$status" == "True" ]]; then
      info "DSCI MonitoringStackAvailable=True"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "warning: DSCI ${DSCI_NAME} MonitoringStackAvailable not True after ${timeout}s" >&2
  return 1
}

patch_dsci_observability_metrics() {
  local current=""
  current=$(oc get dsci "$DSCI_NAME" \
    -o jsonpath='{.spec.monitoring.metrics.storage.size}' 2>/dev/null || true)
  if [[ -n "$current" ]]; then
    log "DSCI ${DSCI_NAME} monitoring.metrics.storage already configured (${current})"
    return 0
  fi
  info "patch DSCI ${DSCI_NAME}: enable metrics + traces storage for observability stack"
  oc patch dsci "$DSCI_NAME" --type=merge -p '{
    "spec": {
      "monitoring": {
        "managementState": "Managed",
        "namespace": "'"${MONITORING_NS}"'",
        "metrics": {
          "replicas": 1,
          "storage": {
            "size": "5Gi",
            "retention": "15d"
          }
        },
        "traces": {
          "sampleRatio": "0.1",
          "storage": {
            "backend": "pv",
            "retention": "2160h"
          }
        }
      }
    }
  }' >/dev/null
}

ensure_observability_operators() {
  ensure_tempo_operator || echo "warning: Tempo operator install incomplete" >&2
  ensure_opentelemetry_operator || echo "warning: OpenTelemetry operator install incomplete" >&2
  ensure_cluster_observability_operator || echo "warning: Cluster Observability Operator install incomplete" >&2
  ensure_loki_operator || echo "warning: Loki operator install incomplete" >&2
}

wait_for_lokistack_ready() {
  local timeout="${1:-600}" elapsed=0 status=""
  while ((elapsed < timeout)); do
    status=$(oc get lokistack usage -n "$MONITORING_NS" \
      -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [[ "$status" == "True" ]]; then
      info "LokiStack/usage Ready"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  echo "warning: timed out waiting for LokiStack/usage Ready" >&2
  return 1
}

deploy_usage_logging_backend() {
  if ! crd_registered 'lokistacks\.loki\.grafana\.com'; then
    echo "warning: skip usage-logging backend — lokistacks.loki.grafana.com CRD missing" >&2
    return 1
  fi
  run oc apply -f "${MANIFESTS}/maas-usage-logging-minio-secret.yaml"
  run oc apply -f "${MANIFESTS}/maas-usage-logging-minio.yaml"
  wait_for_pod_grep "$MONITORING_NS" "^minio-" 180 0 || true
  run oc apply -f "${MANIFESTS}/maas-usage-logging-lokistack.yaml"
  wait_for_lokistack_ready 600 || true
}

enable_observability() {
  if [[ "${WINGS_SKIP_OBSERVABILITY:-0}" == 1 ]]; then
    log "skip observability stack (WINGS_SKIP_OBSERVABILITY=1)"
    return 0
  fi
  info "enabling observability stack (Usage/token-consumption dashboard)"
  ensure_user_workload_monitoring || echo "warning: UWM enablement incomplete" >&2
  ensure_observability_operators
  patch_dsci_observability_metrics || echo "warning: DSCI observability patch failed" >&2
  wait_for_dsci_monitoring_ready 900 || true
  deploy_usage_logging_backend || true
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
  wait_for_pod_grep "$PROJECT" "wings-ogx-postgres" 300 0 || true
  run oc apply -f "${MANIFESTS}/ogx-base-config-wings.yaml"
  run oc apply -f "${MANIFESTS}/ogx-server-wings.yaml"
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
  local model=""
  for model in $MAAS_CATALOG_MODELS; do
    if oc get externalmodels.maas.opendatahub.io "$model" -n "$PROJECT" >/dev/null 2>&1; then
      oc label externalmodels.maas.opendatahub.io "$model" -n "$PROJECT" \
        opendatahub.io/dashboard=true opendatahub.io/genai-asset=true \
        --overwrite >/dev/null 2>&1 || true
    fi
    if oc get externalmodels.inference.opendatahub.io "$model" -n "$PROJECT" >/dev/null 2>&1; then
      oc label externalmodels.inference.opendatahub.io "$model" -n "$PROJECT" \
        opendatahub.io/dashboard=true opendatahub.io/genai-asset=true \
        --overwrite >/dev/null 2>&1 || true
    fi
    # Gen AI Studio → AI asset endpoints lists ExternalProviders when
    # genAiStudioConfig.aiAssetCustomEndpoints.externalProviders is true.
    if oc get externalproviders.inference.opendatahub.io "$model" -n "$PROJECT" >/dev/null 2>&1; then
      oc label externalproviders.inference.opendatahub.io "$model" -n "$PROJECT" \
        opendatahub.io/dashboard=true opendatahub.io/genai-asset=true \
        --overwrite >/dev/null 2>&1 || true
    fi
    if oc get maasmodelref "$model" -n "$PROJECT" >/dev/null 2>&1; then
      oc label maasmodelref "$model" -n "$PROJECT" \
        opendatahub.io/dashboard=true opendatahub.io/genai-asset=true \
        --overwrite >/dev/null 2>&1 || true
    fi
  done
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
  local gen_ai="" maas_tab="" mcp_catalog="" disable_lmeval="" guardrails=""
  local agents_catalog="" agent_ops="" agent_cfg="" ai_asset_eps=""
  gen_ai=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.genAiStudio}' 2>/dev/null || true)
  maas_tab=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.modelAsService}' 2>/dev/null || true)
  mcp_catalog=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.mcpCatalog}' 2>/dev/null || true)
  disable_lmeval=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.disableLMEval}' 2>/dev/null || true)
  guardrails=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.guardrails}' 2>/dev/null || true)
  agents_catalog=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.agentsCatalog}' 2>/dev/null || true)
  agent_ops=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.agentOps}' 2>/dev/null || true)
  agent_cfg=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.agentConfigManagement}' 2>/dev/null || true)
  ai_asset_eps=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.aiAssetCustomEndpoints}' 2>/dev/null || true)
  local observability_dashboard=""
  observability_dashboard=$(oc get odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" \
    -o jsonpath='{.spec.dashboardConfig.observabilityDashboard}' 2>/dev/null || true)
  if [[ "$gen_ai" != "true" || "$maas_tab" != "true" || "$mcp_catalog" != "true" \
    || "$disable_lmeval" == "true" || "$guardrails" != "true" \
    || "$agents_catalog" != "true" || "$agent_ops" != "true" \
    || "$agent_cfg" != "true" || "$ai_asset_eps" != "true" \
    || "$observability_dashboard" != "true" ]]; then
    log "patch OdhDashboardConfig genAiStudio + MaaS + MCP + Agents + guardrails + observabilityDashboard"
    oc patch odhdashboardconfig odh-dashboard-config -n "$MLFLOW_NS" --type=merge \
      -p '{"spec":{"dashboardConfig":{"genAiStudio":true,"modelAsService":true,"mcpCatalog":true,"disableLMEval":false,"guardrails":true,"agentsCatalog":true,"agentOps":true,"agentConfigManagement":true,"aiAssetCustomEndpoints":true,"observabilityDashboard":true}}}' \
      >/dev/null 2>&1 || true
  fi
  label_maas_external_model_assets || true
  # Gen AI Studio AI asset endpoints lists models from this ConfigMap (not CRs).
  if [[ -f "${MANIFESTS}/gen-ai-aa-custom-model-endpoints.yaml" ]]; then
    run oc apply -f "${MANIFESTS}/gen-ai-aa-custom-model-endpoints.yaml"
  fi
  restart_maas_dashboard_ui_if_unhealthy || true
}

enable_genai_studio() {
  if [[ "${WINGS_SKIP_OGX:-0}" == 1 && "${WINGS_SKIP_MCP:-0}" == 1 ]]; then
    log "skip Gen AI Studio stack (WINGS_SKIP_OGX=1 and WINGS_SKIP_MCP=1)"
    return 0
  fi
  if [[ "${WINGS_SKIP_OGX:-0}" != 1 ]]; then
    if [[ "${WINGS_SKIP_SERVICEMESH:-0}" != 1 ]]; then
      ensure_servicemesh || echo "warning: Service Mesh install incomplete" >&2
    fi
    enable_ogx_dsc || echo "warning: OGX DSC enablement incomplete" >&2
    deploy_ogx_server || echo "warning: OGXServer deploy incomplete" >&2
  fi
  if [[ "${WINGS_SKIP_MCP:-0}" != 1 ]]; then
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
  printf 'postgresql://maas:wings-maas-dev@wings-maas-postgres.%s.svc:5432/maas?sslmode=disable' "$MLFLOW_NS"  # notsecret
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
  local fresh_db=0
  if ! oc get deployment wings-maas-postgres -n "$MLFLOW_NS" >/dev/null 2>&1; then
    run oc apply -f "${MANIFESTS}/maas-postgres-dev.yaml"
    fresh_db=1
  fi
  wait_for_pod_grep "$MLFLOW_NS" "wings-maas-postgres" 300 0 || true
  ensure_maas_db_secrets
  # maas-api runs its schema migration on startup. If this is a brand-new (empty)
  # Postgres -- e.g. right after `uninstall.sh --all` wiped the old one and
  # install.sh recreated it -- but the maas-api pod has been running since before
  # that (RHOAI's modelsAsAService component doesn't know the DB was swapped), it
  # keeps serving against a connection pool with no migrated schema and API key
  # minting fails with "relation \"api_keys\" does not exist". Restart it so the
  # fresh pod migrates the fresh DB.
  if [[ "$fresh_db" == 1 ]] && oc get deployment maas-api -n redhat-ai-gateway-infra >/dev/null 2>&1; then
    log "restarting maas-api so it migrates the freshly (re)created wings-maas-postgres schema"
    run oc rollout restart deployment/maas-api -n redhat-ai-gateway-infra
    oc rollout status deployment/maas-api -n redhat-ai-gateway-infra --timeout=180s >/dev/null 2>&1 || true
    wait_for_pod_grep redhat-ai-gateway-infra "maas-api" 180 0 || true
  fi
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

maas_lb_claimed_hostname() {
  # Hostname published by openshift-ai-inference LoadBalancer DNSRecord — Routes for
  # ClusterIP maas-default-gateway cannot steal that DNS.
  oc get gateway openshift-ai-inference -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].hostname}' 2>/dev/null || true
}

discover_maas_route_hostname() {
  local host="" name domain="" claimed=""
  claimed=$(maas_lb_claimed_hostname)
  domain=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
  # MaaS public host — do not use data-science-gateway (rh-ai) Route; that is dashboard.
  host=$(oc get route maas-default-gateway -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$host" && "$host" != HostAlreadyClaimed && "$host" != "$claimed" ]]; then
    printf '%s' "$host"
    return 0
  fi
  if [[ -n "$domain" ]]; then
    # Prefer maas-gateway.<apps-domain>: inference-gateway.* is often claimed by the
    # openshift-ai-inference LoadBalancer DNSRecord and never reaches the Route.
    printf 'maas-gateway.%s' "$domain"
    return 0
  fi
  host=$(oc get route openshift-ai-inference -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -n "$host" && "$host" != HostAlreadyClaimed ]]; then
    printf '%s' "$host"
    return 0
  fi
  for name in maas-default-gateway openshift-ai-inference; do
    host=$(oc get gateway "$name" -n "$GATEWAY_NS" \
      -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].hostname}' 2>/dev/null || true)
    if [[ -n "$host" && "$host" != "$claimed" ]]; then
      printf '%s' "$host"
      return 0
    fi
  done
  printf ''
}

maas_gateway_has_reencrypt_route() {
  local name
  for name in maas-default-gateway openshift-ai-inference; do
    if oc get route "$name" -n "$GATEWAY_NS" \
      -o jsonpath='{.spec.tls.termination}' 2>/dev/null | grep -q reencrypt; then
      return 0
    fi
  done
  return 1
}

remove_maas_gateway_https_hostname() {
  local idx="" current=""
  current=$(oc get gateway maas-default-gateway -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.listeners[?(@.protocol=="HTTPS")].hostname}' 2>/dev/null || true)
  [[ -z "$current" ]] && return 0
  idx=$(oc get gateway maas-default-gateway -n "$GATEWAY_NS" -o json 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((i for i,l in enumerate(d.get("spec",{}).get("listeners",[])) if l.get("protocol")=="HTTPS"), ""))' || true)
  [[ -z "$idx" ]] && return 1
  log "remove maas-default-gateway HTTPS hostname (reencrypt Route SNI mismatch)"
  oc patch gateway maas-default-gateway -n "$GATEWAY_NS" --type=json \
    -p "[{\"op\":\"remove\",\"path\":\"/spec/listeners/${idx}/hostname\"}]" \
    >/dev/null 2>&1 || true
}

ensure_maas_gateway_route() {
  local host="" svc="" route_svc="" route_host=""
  if [[ ! -f "${MANIFESTS}/maas-default-gateway-route.yaml" ]]; then
    return 0
  fi
  if ! oc get gateway maas-default-gateway -n "$GATEWAY_NS" >/dev/null 2>&1; then
    return 1
  fi
  svc=$(oc get svc -n "$GATEWAY_NS" \
    -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$svc" ]]; then
    echo "warning: no Service for maas-default-gateway; skip Route" >&2
    return 1
  fi
  host=$(discover_maas_route_hostname)
  if [[ -z "$host" ]]; then
    echo "warning: cannot discover hostname for maas-default-gateway Route" >&2
    return 1
  fi
  route_svc=$(oc get route maas-default-gateway -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.to.name}' 2>/dev/null || true)
  route_host=$(oc get route maas-default-gateway -n "$GATEWAY_NS" \
    -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ "$route_svc" != "$svc" || "$route_host" != "$host" ]]; then
    log "expose maas-default-gateway via Route ${host} -> ${svc}"
    sed -e "s/REPLACE_MAAS_GATEWAY_HOST/${host}/g" \
      -e "s/REPLACE_MAAS_GATEWAY_SERVICE/${svc}/g" \
      "${MANIFESTS}/maas-default-gateway-route.yaml" | oc apply -f -
  fi
  # Reencrypt Routes send internal SNI (service CA host), not the public hostname.
  # A hostname filter on the HTTPS listener causes filter_chain_not_found / 503.
  if maas_gateway_has_reencrypt_route; then
    remove_maas_gateway_https_hostname || true
  fi
  ensure_maas_bff_api_url "$host"
}

patch_maas_gateway_hostname() {
  local host="" idx="" current=""
  host=$(discover_maas_route_hostname)
  if [[ -z "$host" ]]; then
    echo "warning: cannot discover Route hostname for maas-default-gateway" >&2
    return 1
  fi
  # Reencrypt Routes send internal SNI to the gateway listener.
  # A hostname filter on the HTTPS listener causes filter_chain_not_found / 503 (RHOAI 3.5).
  if maas_gateway_has_reencrypt_route; then
    remove_maas_gateway_https_hostname || true
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
  # Prefer the serving-cert issued for the MaaS gateway Service (ClusterIP path).
  if oc get secret maas-default-gateway-service-tls -n "$GATEWAY_NS" >/dev/null 2>&1; then
    cert="maas-default-gateway-service-tls"
  else
    cert=$(discover_gateway_tls_secret)
  fi
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
  local host="" svc="" pref="" stype="" gclass="data-science-gateway-class" cert="maas-default-gateway-service-tls"
  # ClusterIP service params — without this, Gateway defaults to LoadBalancer and
  # stays Programmed=False on sandboxes with no cloud LB (AddressNotAssigned).
  if [[ -f "${MANIFESTS}/maas-default-gateway-config.yaml" ]]; then
    run oc apply -f "${MANIFESTS}/maas-default-gateway-config.yaml"
  fi
  if ! oc get gateway maas-default-gateway -n "$GATEWAY_NS" >/dev/null 2>&1; then
    # Dedicated host (maas-gateway.*) — do not copy openshift-ai-inference's
    # inference-gateway.* hostname (LoadBalancer DNSRecord conflict).
    host=$(discover_maas_route_hostname)
    if [[ -z "$host" ]]; then
      echo "warning: cannot discover hostname for maas-default-gateway" >&2
      return 1
    fi
    if [[ -f "${MANIFESTS}/maas-default-gateway.yaml" ]]; then
      if ! oc get gatewayclass "$gclass" >/dev/null 2>&1; then
        gclass="openshift-ai-inference"
      fi
      if ! oc get secret "$cert" -n "$GATEWAY_NS" >/dev/null 2>&1; then
        cert=$(discover_gateway_tls_secret)
        cert="${cert:-default-gateway-tls}"
      fi
      sed -e "s/REPLACE_MAAS_GATEWAY_HOST/${host}/" \
        -e "s/name: maas-default-gateway-service-tls/name: ${cert}/" \
        -e "s/gatewayClassName: data-science-gateway-class/gatewayClassName: ${gclass}/" \
        "${MANIFESTS}/maas-default-gateway.yaml" | oc apply -f -
    fi
  fi
  # Ensure existing gateways also use ClusterIP params (idempotent).
  if oc get gateway maas-default-gateway -n "$GATEWAY_NS" >/dev/null 2>&1 \
    && oc get configmap maas-default-gateway-config -n "$GATEWAY_NS" >/dev/null 2>&1; then
    pref=$(oc get gateway maas-default-gateway -n "$GATEWAY_NS" \
      -o jsonpath='{.spec.infrastructure.parametersRef.name}' 2>/dev/null || true)
    if [[ "$pref" != "maas-default-gateway-config" ]]; then
      log "patch maas-default-gateway infrastructure.parametersRef -> maas-default-gateway-config"
      oc patch gateway maas-default-gateway -n "$GATEWAY_NS" --type=merge \
        -p '{"spec":{"infrastructure":{"parametersRef":{"group":"","kind":"ConfigMap","name":"maas-default-gateway-config"}}}}' \
        >/dev/null 2>&1 || true
    fi
    svc=$(oc get svc -n "$GATEWAY_NS" \
      -l gateway.networking.k8s.io/gateway-name=maas-default-gateway \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -n "$svc" ]]; then
      stype=$(oc get svc "$svc" -n "$GATEWAY_NS" -o jsonpath='{.spec.type}' 2>/dev/null || true)
      if [[ "$stype" == "LoadBalancer" ]]; then
        log "recreate ${svc} as ClusterIP (LoadBalancer address pending)"
        oc delete svc "$svc" -n "$GATEWAY_NS" --wait=false >/dev/null 2>&1 || true
      fi
    fi
  fi
  patch_maas_gateway_hostname || true
  patch_maas_gateway_tls || true
  ensure_maas_gateway_route || true
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

wait_for_kuadrant_crds() {
  local timeout="${1:-600}"
  local elapsed=0
  while ((elapsed < timeout)); do
    # Unescaped CRD name — crd_registered uses `oc get crd`.
    if crd_registered 'kuadrants.kuadrant.io'; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  return 1
}

wait_for_connectivity_link() {
  wait_for_kuadrant_crds "${1:-600}"
}

ensure_connectivity_link_operator() {
  if crd_registered 'kuadrants.kuadrant.io'; then
    return 0
  fi
  if [[ ! -f "${MANIFESTS}/connectivity-link-operator.yaml" ]]; then
    die "missing ${MANIFESTS}/connectivity-link-operator.yaml (Connectivity Link Subscription)"
  fi
  info "installing Red Hat Connectivity Link (rhcl-operator)"
  run oc apply -f "${MANIFESTS}/connectivity-link-operator.yaml"
  if ! wait_for_connectivity_link 600; then
    die "Connectivity Link did not install (kuadrants.kuadrant.io CRD missing). Check Subscription rhcl-operator in openshift-operators"
  fi
  info "Connectivity Link CRDs ready"
}

ensure_kuadrant() {
  if [[ "${WINGS_SKIP_KUADRANT:-0}" == 1 ]]; then
    return 0
  fi
  ensure_connectivity_link_operator
  if ! wait_for_kuadrant_crds 120; then
    die "kuadrants.kuadrant.io CRD still missing after Connectivity Link install"
  fi
  if ! oc get kuadrant kuadrant -n "$KUADRANT_NS" >/dev/null 2>&1; then
    if [[ -f "${MANIFESTS}/kuadrant-dev.yaml" ]]; then
      run oc apply -f "${MANIFESTS}/kuadrant-dev.yaml"
    else
      die "missing ${MANIFESTS}/kuadrant-dev.yaml"
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
  run oc apply -f "${MANIFESTS}/maas-auth-subscription-redhat-maas.yaml"
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
  local upstream_key="${WINGS_MAAS_UPSTREAM_API_KEY:-}"
  local secret_file="${MANIFESTS}/secret-wings-maas-upstream-api-key.yaml"
  local example="${MANIFESTS}/secret-wings-maas-upstream-api-key.example.yaml"
  if [[ -z "$upstream_key" ]]; then
    upstream_key=$(read_secret_key wings-maas-upstream-api-key "$PROJECT" api-key)
  fi
  if [[ -z "$upstream_key" ]]; then
    upstream_key=$(read_secret_key wings-judge-llm "$PROJECT" JUDGE_API_KEY)
    if [[ -n "$upstream_key" ]] && [[ "$upstream_key" == sk-oai-* ]]; then
      upstream_key=""
    fi
  fi
  if [[ -z "$upstream_key" ]]; then
    echo "warning: WINGS_MAAS_UPSTREAM_API_KEY unset and no upstream api-key found" >&2
    echo "warning: copy ${example} to ${secret_file} or export WINGS_MAAS_UPSTREAM_API_KEY" >&2
    return 1
  fi
  if [[ -f "$secret_file" ]]; then
    run oc apply -f "$secret_file"
  elif ! oc get secret wings-maas-upstream-api-key -n "$PROJECT" >/dev/null 2>&1; then
    run oc create secret generic wings-maas-upstream-api-key \
      -n "$PROJECT" \
      --from-literal=api-key="$upstream_key"
  else
    oc set data secret/wings-maas-upstream-api-key -n "$PROJECT" "api-key=${upstream_key}" >/dev/null
  fi
  if ! oc get secret wings-maas-upstream-api-key -n "$PROJECT" >/dev/null 2>&1; then
    return 1
  fi
  oc label secret wings-maas-upstream-api-key -n "$PROJECT" \
    "app.kubernetes.io/part-of=${MAAS_PART_OF}" \
    inference.llm-d.ai/ipp-managed=true \
    inference.networking.k8s.io/bbr-managed=true \
    --overwrite >/dev/null 2>&1 || true
  if [[ -n "${WINGS_MAAS_UPSTREAM_API_KEY:-}" ]]; then
    oc set data secret/wings-maas-upstream-api-key -n "$PROJECT" \
      "api-key=${WINGS_MAAS_UPSTREAM_API_KEY}" >/dev/null
  fi
}

apply_maas_manifests() {
  local model="" out="" created_any=0
  for model in $MAAS_CATALOG_MODELS; do
    if [[ -f "${MANIFESTS}/maas-external-model-${model}.yaml" ]]; then
      out=$(run oc apply -f "${MANIFESTS}/maas-external-model-${model}.yaml")
      echo "$out"
      [[ "$out" == *created* ]] && created_any=1
    fi
    if [[ -f "${MANIFESTS}/maas-modelref-${model}.yaml" ]]; then
      run oc apply -f "${MANIFESTS}/maas-modelref-${model}.yaml"
    fi
  done
  run oc apply -f "${MANIFESTS}/maas-auth-subscription-redhat-maas.yaml"
  if [[ "$created_any" == 1 ]]; then
    restart_payload_processing_stack
  fi
}

restart_payload_processing_stack() {
  # ai-gateway-payload-processing's payload-processing/payload-pre-processing pods
  # (openshift-ingress) keep an in-memory model store built by watching
  # ExternalModel/ExternalProvider CRs, and use it to resolve the inference path
  # (/{project}/{model}/v1/...) to a provider + injected upstream credential. When
  # those ExternalModel CRs are deleted and recreated with new UIDs -- e.g. after
  # `uninstall.sh --all` wipes them and install.sh recreates them -- while these pods
  # keep running (RHOAI's modelsAsAService component doesn't restart them), the model
  # store goes stale: gateway inference then 404s (unresolved path) or 401s ("no api
  # key passed in", credential never injected) even though the CRs report Ready.
  # Restart so the pods rebuild their watch caches against the fresh CRs.
  if oc get deployment payload-processing -n openshift-ingress >/dev/null 2>&1; then
    log "restarting payload-processing/payload-pre-processing so they rebuild their stale ExternalModel watch cache"
    run oc rollout restart deployment/payload-processing deployment/payload-pre-processing -n openshift-ingress
    oc rollout status deployment/payload-processing -n openshift-ingress --timeout=120s >/dev/null 2>&1 || true
    oc rollout status deployment/payload-pre-processing -n openshift-ingress --timeout=120s >/dev/null 2>&1 || true
  fi
}

wait_for_one_maas_modelref_ready() {
  local model="$1"
  local timeout="${2:-600}"
  local elapsed=0 phase=""
  while ((elapsed < timeout)); do
    phase=$(oc get maasmodelref "$model" -n "$PROJECT" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ -z "$phase" ]]; then
      phase=$(oc get maasmodelref "$model" -n "$PROJECT" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    fi
    if [[ "$phase" == "Ready" || "$phase" == "True" ]]; then
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "warning: MaaSModelRef/${model} not Ready after ${timeout}s (phase=${phase})" >&2
  return 1
}

wait_for_maas_modelref_ready() {
  local timeout="${1:-600}"
  local model="" failed=0
  # Primary judge model first (blocks install path), then remaining catalog models.
  wait_for_one_maas_modelref_ready "$MAAS_MODEL" "$timeout" || failed=1
  for model in $MAAS_CATALOG_MODELS; do
    if [[ "$model" == "$MAAS_MODEL" ]]; then
      continue
    fi
    wait_for_one_maas_modelref_ready "$model" "$timeout" || failed=1
  done
  return "$failed"
}

discover_maas_gateway_host() {
  local host="" name
  # Prefer OpenShift Route host (public DNS) over ClusterIP gateway addresses.
  host=$(discover_maas_route_hostname)
  if [[ -n "$host" ]]; then
    printf '%s' "$host"
    return 0
  fi
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

discover_maas_httproute_path() {
  local model="${1:-$MAAS_MODEL}"
  local path="" name
  # RHOAI 3.5 ExternalModel routes are named <model>, not maas-<model>.
  for name in "$model" "maas-${model}"; do
    path=$(oc get httproute "$name" -n "$PROJECT" -o json 2>/dev/null \
      | python3 -c '
import json, sys
d = json.load(sys.stdin)
want = "/'"$PROJECT"'/'"$model"'"
for rule in d.get("spec", {}).get("rules", []) or []:
  for m in rule.get("matches") or []:
    p = (m.get("path") or {}).get("value") or ""
    if p == want or p.startswith(want + "/"):
      print(p.rstrip("/"))
      raise SystemExit
# fallback: first PathPrefix that is not "/"
for rule in d.get("spec", {}).get("rules", []) or []:
  for m in rule.get("matches") or []:
    p = (m.get("path") or {}).get("value") or ""
    if p and p != "/":
      print(p.rstrip("/"))
      raise SystemExit
' || true)
    if [[ -n "$path" ]]; then
      printf '%s' "$path"
      return 0
    fi
  done
  printf '/%s/%s' "$PROJECT" "$model"
}

discover_maas_judge_base_url() {
  local path="" host="" endpoint=""
  host=$(discover_maas_gateway_host)
  path=$(discover_maas_httproute_path "$MAAS_MODEL")
  path=${path#/}
  if [[ -n "$host" && -n "$path" ]]; then
    # Always prefer the public Route host. ModelRef status.endpoint may still
    # advertise inference-gateway.* (openshift-ai-inference LB DNS), which does
    # not reach ClusterIP maas-default-gateway.
    printf 'https://%s/%s/v1' "$host" "$path"
    return 0
  fi
  endpoint=$(oc get maasmodelref "$MAAS_MODEL" -n "$PROJECT" \
    -o jsonpath='{.status.endpoint}' 2>/dev/null || true)
  if [[ -n "$endpoint" && -n "$path" ]]; then
    endpoint=${endpoint%/}
    printf '%s/%s/v1' "$endpoint" "$path"
    return 0
  fi
  printf ''
}

mint_maas_api_key_via_portforward() {
  local token="" body="" key="" pf_pid="" user=""
  token=$(oc whoami -t 2>/dev/null || true)
  user=$(oc whoami 2>/dev/null || true)
  if [[ -z "$token" || -z "$user" ]]; then
    return 1
  fi
  oc port-forward -n redhat-ai-gateway-infra svc/maas-api 18443:8443 >/dev/null 2>&1 &
  pf_pid=$!
  local ready=0 i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -sk --max-time 2 "https://127.0.0.1:18443/health" >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "$ready" != 1 ]]; then
    kill "$pf_pid" >/dev/null 2>&1 || true
    wait "$pf_pid" 2>/dev/null || true
    return 1
  fi
  # Group header must be JSON array (Authorino format), not a bare group name.
  body=$(curl -fsSk --max-time 20 -X POST "https://127.0.0.1:18443/v1/api-keys" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -H "X-MaaS-Username: ${user}" \
    -H 'X-MaaS-Group: ["system:authenticated"]' \
    -d "{\"name\":\"wings-judge\",\"subscription\":\"${MAAS_SUBSCRIPTION}\",\"expiresIn\":\"90d\"}" \
    2>/dev/null || true)
  kill "$pf_pid" >/dev/null 2>&1 || true
  wait "$pf_pid" 2>/dev/null || true
  if [[ -z "$body" ]]; then
    return 1
  fi
  key=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)
  if [[ -z "$key" || "$key" != sk-oai-* ]]; then
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
  # Via Gateway+Authorino: do NOT send X-MaaS-* — Authorino injects them from the
  # bearer token. Client-supplied identity headers are rejected (HTTP 403).
  if [[ -n "$gateway_host" ]]; then
    body=$(curl -fsSk --max-time 20 -X POST "https://${gateway_host}/maas-api/v1/api-keys" \
      -H "Authorization: Bearer ${token}" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"wings-judge\",\"subscription\":\"${MAAS_SUBSCRIPTION}\",\"expiresIn\":\"90d\"}" \
      2>/dev/null || true)
    key=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("key",""))' 2>/dev/null || true)
    if [[ -n "$key" && "$key" == sk-oai-* ]]; then
      printf '%s' "$key"
      return 0
    fi
  fi
  # Port-forward bypasses Authorino — must inject identity headers manually.
  key=$(mint_maas_api_key_via_portforward || true)
  if [[ -n "$key" ]]; then
    printf '%s' "$key"
    return 0
  fi
  echo "warning: MaaS API key mint failed (gateway Authorino path or port-forward)" >&2
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
  # Workshop upstream via gateway often needs >20s; OpenShift router may 504 near 30s.
  code=$(curl -fsSk --max-time 45 -o /dev/null -w '%{http_code}' \
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
  if [[ -n "${WINGS_JUDGE_API_KEY:-}" ]]; then
    api_key="${WINGS_JUDGE_API_KEY}"
    maas_api_key="${WINGS_JUDGE_API_KEY}"
  fi
  # Minted gateway keys (sk-oai-*) only work on the local MaaS gateway — never fall
  # back to workshop upstream for those. Workshop fallback is for upstream tokens only.
  if [[ "$api_key" != sk-oai-* ]] && ! maas_inference_probe "$base_url" "$api_key"; then
    local upstream_key=""
    upstream_key=$(read_secret_key wings-maas-upstream-api-key "$PROJECT" api-key)
    if [[ -n "$upstream_key" ]]; then
      echo "warning: in-cluster MaaS gateway inference failed; using workshop direct for MAAS_* and JUDGE_*" >&2
      maas_base_url=$(workshop_direct_base_url)
      maas_api_key="$upstream_key"
      base_url="$maas_base_url"
      api_key="$upstream_key"
    fi
  fi
  if [[ "$api_key" == sk-oai-* ]] && ! maas_inference_probe "$base_url" "$api_key"; then
    echo "warning: minted sk-oai key saved but gateway probe failed (check Route maas-default-gateway)" >&2
  fi
  oc create secret generic wings-judge-llm \
    -n "$PROJECT" \
    --from-literal=MAAS_MODEL="$MAAS_MODEL" \
    --from-literal=MAAS_BASE_URL="$maas_base_url" \
    --from-literal=MAAS_API_KEY="$maas_api_key" \
    --from-literal=JUDGE_BASE_URL="$base_url" \
    --from-literal=JUDGE_MODEL="$MAAS_MODEL" \
    --from-literal=JUDGE_API_KEY="$api_key" \
    --dry-run=client -o yaml | oc apply -f -
  oc label secret wings-judge-llm -n "$PROJECT" app.kubernetes.io/part-of="$MAAS_PART_OF" \
    --overwrite >/dev/null 2>&1 || true
}

discover_maastenantconfig_name() {
  if ! crd_registered 'maastenantconfigs\.maas\.opendatahub\.io'; then
    return 1
  fi
  oc get maastenantconfig -n "$MAAS_NS" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

enable_maas_tenant_telemetry() {
  local name="" capture_user="true"
  name=$(discover_maastenantconfig_name || true)
  if [[ -z "$name" ]]; then
    log "skip MaaS tenant telemetry (no MaasTenantConfig in ${MAAS_NS})"
    return 1
  fi
  # The RHOAI-shipped "Usage" dashboard (dashboard-3-maas-usage-admin) hard-codes
  # user!="" on every panel, including the plain totals -- without the per-user
  # Limitador "user" counter label, the whole dashboard (not just drill-down)
  # renders zeros. Default to capturing it so the demo's token-consumption
  # dashboard works out of the box; set WINGS_MAAS_CAPTURE_USER=0 to opt out
  # for privacy/cardinality-sensitive clusters (dashboard totals will then
  # read 0, by RHOAI's own dashboard design, not a WINGS bug).
  [[ "${WINGS_MAAS_CAPTURE_USER:-1}" == 0 ]] && capture_user="false"
  log "patch MaasTenantConfig ${name}: telemetry.enabled=true (captureUser=${capture_user})"
  oc patch maastenantconfig "$name" -n "$MAAS_NS" --type=merge -p '{
    "spec": {
      "telemetry": {
        "enabled": true,
        "metrics": {
          "captureModelUsage": true,
          "captureUser": '"${capture_user}"',
          "captureGroup": false
        }
      }
    }
  }' >/dev/null 2>&1
}

discover_maas_config_name() {
  if ! crd_registered 'configs\.maas\.opendatahub\.io'; then
    return 1
  fi
  oc get configs.maas.opendatahub.io -n "$MAAS_NS" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

enable_maas_usage_logging() {
  local name=""
  name=$(discover_maas_config_name || true)
  if [[ -z "$name" ]]; then
    log "skip MaaS usageLogging (no configs.maas.opendatahub.io in ${MAAS_NS})"
    return 1
  fi
  log "patch MaaS Config ${name}: usageLogging=true"
  oc patch configs.maas.opendatahub.io "$name" -n "$MAAS_NS" --type=merge \
    -p '{"spec":{"usageLogging":true}}' >/dev/null 2>&1
}

ensure_limitador_redis() {
  run oc apply -f "${MANIFESTS}/limitador-redis.yaml"
  wait_for_pod_grep "$REDIS_LIMITADOR_NS" "^redis-" 180 0 || true
  if ! oc get namespace "$KUADRANT_NS" >/dev/null 2>&1; then
    echo "warning: skip Limitador Redis Secret — ${KUADRANT_NS} namespace missing" >&2
    return 1
  fi
  run oc apply -f "${MANIFESTS}/limitador-redis-secret.yaml"
  local current=""
  current=$(oc get limitador limitador -n "$KUADRANT_NS" \
    -o jsonpath='{.spec.storage.redis.configSecretRef.name}' 2>/dev/null || true)
  if [[ "$current" == "redis-config" ]]; then
    log "Limitador already using Redis storage"
    return 0
  fi
  log "patch Limitador storage -> redis-config (counters survive pod restarts)"
  oc patch limitador limitador -n "$KUADRANT_NS" --type=merge -p \
    '{"spec":{"storage":{"redis":{"configSecretRef":{"name":"redis-config"}}}}}' \
    >/dev/null 2>&1
}

enable_maas_observability() {
  if [[ "${WINGS_SKIP_OBSERVABILITY:-0}" == 1 ]]; then
    log "skip MaaS observability hooks (WINGS_SKIP_OBSERVABILITY=1)"
    return 0
  fi
  enable_maas_tenant_telemetry || echo "warning: MaaS tenant telemetry not enabled" >&2
  enable_maas_usage_logging || echo "warning: MaaS usageLogging not enabled" >&2
  ensure_limitador_redis || echo "warning: Limitador Redis persistence not configured" >&2
}

enable_maas() {
  if [[ "${WINGS_SKIP_MAAS:-0}" == 1 ]]; then
    log "skip MaaS (WINGS_SKIP_MAAS=1)"
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
  ensure_genai_dashboard_prereqs || true
  enable_maas_observability || true
  local host="" base_url="" maas_key=""
  host=$(discover_maas_gateway_host)
  base_url=$(discover_maas_judge_base_url)
  if [[ -z "$base_url" ]]; then
    echo "warning: could not discover MaaS judge base URL" >&2
    return 0
  fi
  maas_key=$(mint_maas_api_key "$host" || true)
  if [[ -z "$maas_key" ]]; then
    maas_key=$(read_secret_key wings-judge-llm "$PROJECT" JUDGE_API_KEY)
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
  ensure_maas_gateway_api_key_secret || true
  sync_llm_endpoint_configmap || true
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
  local secret="${MANIFESTS}/secret-wings-judge-llm.yaml"
  local example="${MANIFESTS}/secret-wings-judge-llm.example.yaml"
  if [[ ! -f "$secret" ]]; then
    secret="$example"
  fi
  if ! oc get secret wings-judge-llm -n "$PROJECT" >/dev/null 2>&1; then
    oc apply -f "$secret"
  else
    echo "warning: secret/wings-judge-llm already exists — not re-applying ${secret}" >&2
    echo "warning: partial yaml would drop MAAS_* keys; use install.sh MaaS patch or oc set env" >&2
  fi
  if [[ -n "${WINGS_JUDGE_API_KEY:-}" ]]; then
    oc set env "secret/wings-judge-llm" -n "$PROJECT" "JUDGE_API_KEY=${WINGS_JUDGE_API_KEY}"
  fi
  local key_b64=""
  key_b64=$(oc get secret wings-judge-llm -n "$PROJECT" -o jsonpath='{.data.JUDGE_API_KEY}' 2>/dev/null || true)
  if [[ -z "$key_b64" ]]; then
    echo "warning: JUDGE_API_KEY is empty on secret/wings-judge-llm — Module 4 judges will fail." >&2
    echo "warning: oc set env secret/wings-judge-llm -n ${PROJECT} JUDGE_API_KEY='<token>'" >&2
    echo "warning: or export WINGS_JUDGE_API_KEY and re-run install.sh" >&2
  fi
}

ensure_workbench_judge_mount() {
  run oc apply -f "${MANIFESTS}/workbench-wings-demo.yaml"
}

resolve_evalhub_openai_base_url() {
  local judge_key="" upstream_key="" gateway_url="" maas_url="" workshop_url=""
  judge_key=$(read_secret_key wings-judge-llm "$PROJECT" JUDGE_API_KEY)
  upstream_key=$(read_secret_key wings-maas-upstream-api-key "$PROJECT" api-key)
  maas_url=$(read_secret_key wings-judge-llm "$PROJECT" MAAS_BASE_URL)
  gateway_url=$(discover_maas_judge_base_url)
  workshop_url=$(workshop_direct_base_url)
  # Local gateway accepts minted sk-oai keys; workshop upstream token does not.
  if [[ -n "$gateway_url" && "$judge_key" == sk-oai-* ]] && maas_inference_probe "$gateway_url" "$judge_key"; then
    printf '%s' "$gateway_url"
    return 0
  fi
  if [[ -n "$maas_url" && "$judge_key" == sk-oai-* ]] && maas_inference_probe "$maas_url" "$judge_key"; then
    printf '%s' "$maas_url"
    return 0
  fi
  if [[ -n "$workshop_url" && -n "$upstream_key" ]] && maas_inference_probe "$workshop_url" "$upstream_key"; then
    echo "warning: in-cluster MaaS gateway unreachable; EvalHub will use workshop direct" >&2
    printf '%s' "$workshop_url"
    return 0
  fi
  if [[ -n "$maas_url" ]]; then
    printf '%s' "$maas_url"
    return 0
  fi
  if [[ -n "$gateway_url" ]]; then
    printf '%s' "$gateway_url"
    return 0
  fi
  printf '%s' "$workshop_url"
}

sync_llm_endpoint_configmap() {
  local model="" url=""
  run oc apply -f "${MANIFESTS}/configmap-wings-llm-endpoint.yaml"
  model=$(read_secret_key wings-judge-llm "$PROJECT" MAAS_MODEL)
  url=$(resolve_evalhub_openai_base_url)
  if [[ -z "$model" || -z "$url" ]]; then
    log "skip wings-llm-endpoint sync (MAAS_MODEL or EvalHub endpoint URL missing)"
    return 0
  fi
  oc patch configmap wings-llm-endpoint -n "$PROJECT" --type merge -p \
    "{\"data\":{\"model_name\":\"${model}\",\"openai_base_url\":\"${url}\",\"notes\":\"EvalHub endpoint auto-selected; workshop fallback when in-cluster gateway probe fails\"}}" \
    >/dev/null
  info "wings-llm-endpoint: model=${model} url=${url}"
}

ensure_maas_gateway_api_key_secret() {
  # Minted sk-oai keys for the local gateway — separate from workshop upstream IPP secret.
  local judge_key=""
  judge_key=$(read_secret_key wings-judge-llm "$PROJECT" JUDGE_API_KEY)
  if [[ "$judge_key" != sk-oai-* ]]; then
    judge_key=$(read_secret_key wings-judge-llm "$PROJECT" MAAS_API_KEY)
  fi
  if [[ "$judge_key" != sk-oai-* ]]; then
    log "skip wings-maas-gateway-api-key (no minted sk-oai JUDGE/MAAS key)"
    return 1
  fi
  oc create secret generic wings-maas-gateway-api-key \
    -n "$PROJECT" \
    --from-literal=api-key="$judge_key" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
  oc label secret wings-maas-gateway-api-key -n "$PROJECT" \
    "app.kubernetes.io/part-of=${MAAS_PART_OF}" --overwrite >/dev/null 2>&1 || true
  info "MaaS gateway auth: wings-maas-gateway-api-key (minted sk-oai)"
}

ensure_evalhub_model_auth_secret() {
  local api_key=""
  # Never overwrite workshop upstream with minted sk-oai — ExternalModels need upstream.
  api_key=$(read_secret_key wings-maas-upstream-api-key "$PROJECT" api-key)
  if [[ -z "$api_key" ]]; then
    log "skip EvalHub upstream auth secret (wings-maas-upstream-api-key empty)"
    ensure_maas_gateway_api_key_secret || true
    return 1
  fi
  oc label secret wings-maas-upstream-api-key -n "$PROJECT" \
    "app.kubernetes.io/part-of=${MAAS_PART_OF}" \
    inference.llm-d.ai/ipp-managed=true \
    inference.networking.k8s.io/bbr-managed=true \
    --overwrite >/dev/null 2>&1 || true
  ensure_maas_gateway_api_key_secret || true
  info "EvalHub model auth: wings-maas-upstream-api-key (upstream) + gateway secret if minted"
}

apply_evalhub_manifests() {
  sync_llm_endpoint_configmap
  ensure_evalhub_model_auth_secret || true
  if [[ -f "${MANIFESTS}/evalhub-rbac-wings.yaml" ]]; then
    run oc apply -f "${MANIFESTS}/evalhub-rbac-wings.yaml"
  fi
  # EvalHub MLFLOW_TRACKING_URI points at this workspace-header proxy — it must
  # exist before eval jobs try to log to MLflow.
  if [[ -f "${MANIFESTS}/mlflow-workspace-proxy.yaml" ]]; then
    run oc apply -f "${MANIFESTS}/mlflow-workspace-proxy.yaml"
    wait_for_pod_grep "$PROJECT" "wings-mlflow-ws-proxy" 180 0 || true
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
  if [[ -n "${WINGS_LLM_STORAGE_URI:-}" && "${WINGS_LLM_STORAGE_URI}" != "REPLACE_ME" ]]; then
    printf '%s' "${WINGS_LLM_STORAGE_URI}"
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
    | WINGS_LLM_MODEL="$LLM_MODEL" WINGS_PROJECT="$PROJECT" python3 "$INSTANTIATE_SR" \
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
    die "no storageUri: set WINGS_LLM_STORAGE_URI"
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
  run oc delete evalhub evalhub -n "$PROJECT" --ignore-not-found=true
  run oc delete configmap wings-llm-endpoint -n "$PROJECT" --ignore-not-found=true
  if [[ -f "${MANIFESTS}/mlflow-workspace-proxy.yaml" ]]; then
    run oc delete -f "${MANIFESTS}/mlflow-workspace-proxy.yaml" --ignore-not-found=true
  fi
  if [[ -f "${MANIFESTS}/evalhub-rbac-wings.yaml" ]]; then
    run oc delete -f "${MANIFESTS}/evalhub-rbac-wings.yaml" --ignore-not-found=true
  fi
}

delete_judge_secret() {
  run oc delete secret wings-judge-llm -n "$PROJECT" --ignore-not-found=true
}

purge_mlflow_cr() {
  local cr="${WINGS_MLFLOW_CR:-mlflow}"
  oc delete mlflow "$cr" --ignore-not-found=true 2>/dev/null \
    || run oc delete mlflow "$cr" -n "$MLFLOW_NS" --ignore-not-found=true
}

purge_evalhub_demo_jobs() {
  if crd_registered 'evaluations\.redhat\.com'; then
    run oc delete evaluation wings-demo-lm-eval -n "$PROJECT" --ignore-not-found=true
    run oc delete evaluation wings-demo-garak -n "$PROJECT" --ignore-not-found=true
  fi
  if crd_registered 'lmevaljobs\.trustyai\.opendatahub\.io'; then
    run oc delete lmevaljob wings-demo-lm-eval -n "$PROJECT" --ignore-not-found=true
  fi
}

purge_evalhub_resources() {
  purge_evalhub_demo_jobs
  delete_evalhub_manifests
}

purge_maas_resources() {
  local model=""
  for model in $MAAS_CATALOG_MODELS; do
    run oc delete maasmodelref "$model" -n "$PROJECT" --ignore-not-found=true
    run oc delete externalmodel "$model" -n "$PROJECT" --ignore-not-found=true
  done
  run oc delete maassubscription "$MAAS_SUBSCRIPTION" -n "$MAAS_NS" --ignore-not-found=true
  run oc delete maasauthpolicy "$MAAS_SUBSCRIPTION" -n "$MAAS_NS" --ignore-not-found=true
  run oc delete secret wings-maas-upstream-api-key -n "$PROJECT" --ignore-not-found=true
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
  run oc delete -f "${MANIFESTS}/ogx-server-wings.yaml" --ignore-not-found=true
  run oc delete -f "${MANIFESTS}/ogx-postgres-dev.yaml" --ignore-not-found=true
}

# ---------------------------------------------------------------------------
# Observability purge (uninstall --all): reverse every step enable_observability
# / enable_maas_observability performed, so a clean cluster results — unlike
# Service Mesh/Connectivity Link (cluster-wide, kept across --all), WINGS owns
# the observability stack end-to-end for this demo and removes it fully.
# ---------------------------------------------------------------------------

purge_maas_tenant_telemetry() {
  local name=""
  name=$(discover_maastenantconfig_name || true)
  [[ -z "$name" ]] && return 0
  run oc patch maastenantconfig "$name" -n "$MAAS_NS" --type=merge \
    -p '{"spec":{"telemetry":{"enabled":false}}}'
}

purge_maas_usage_logging() {
  local name=""
  name=$(discover_maas_config_name || true)
  [[ -z "$name" ]] && return 0
  run oc patch configs.maas.opendatahub.io "$name" -n "$MAAS_NS" --type=merge \
    -p '{"spec":{"usageLogging":false}}'
}

purge_usage_logging_backend() {
  run oc delete -f "${MANIFESTS}/maas-usage-logging-lokistack.yaml" --ignore-not-found=true
  run oc delete -f "${MANIFESTS}/maas-usage-logging-minio.yaml" --ignore-not-found=true
  run oc delete -f "${MANIFESTS}/maas-usage-logging-minio-secret.yaml" --ignore-not-found=true
}

purge_limitador_redis() {
  if oc get limitador limitador -n "$KUADRANT_NS" >/dev/null 2>&1; then
    run oc patch limitador limitador -n "$KUADRANT_NS" --type=merge \
      -p '{"spec":{"storage":null}}'
  fi
  run oc delete -f "${MANIFESTS}/limitador-redis-secret.yaml" --ignore-not-found=true
  run oc delete -f "${MANIFESTS}/limitador-redis.yaml" --ignore-not-found=true
}

revert_dsci_observability_metrics() {
  if ! oc get dsci "$DSCI_NAME" >/dev/null 2>&1; then
    return 0
  fi
  log "revert DSCI ${DSCI_NAME} monitoring.metrics/traces to pre-WINGS state"
  oc patch dsci "$DSCI_NAME" --type=merge -p '{
    "spec": {
      "monitoring": {
        "metrics": {"replicas": null, "storage": null, "exporters": null},
        "traces": null,
        "alerting": null
      }
    }
  }' >/dev/null 2>&1 || true
}

purge_observability_operators() {
  # loki-operator.yaml's namespace (openshift-operators-redhat) is a shared,
  # Red Hat-conventional namespace other operators may already use -- never
  # delete it unless WINGS itself created it (see apply_operator_manifest_ns_aware).
  sed "s/REPLACE_LOKI_CHANNEL/stable/" "${MANIFESTS}/loki-operator.yaml" \
    | purge_operator_manifest_ns_aware "$LOKI_OPERATOR_NS"
  purge_operator_manifest_ns_aware "$COO_NS" < "${MANIFESTS}/cluster-observability-operator.yaml"
  purge_operator_manifest_ns_aware "$OTEL_NS" < "${MANIFESTS}/opentelemetry-operator.yaml"
  purge_operator_manifest_ns_aware "$TEMPO_NS" < "${MANIFESTS}/tempo-operator.yaml"
}

revert_user_workload_monitoring() {
  if ! oc get configmap cluster-monitoring-config -n openshift-monitoring >/dev/null 2>&1; then
    return 0
  fi
  if uwm_configmap_owned_by_wings; then
    log "delete cluster-monitoring-config (created by WINGS install)"
    run oc delete configmap cluster-monitoring-config -n openshift-monitoring --ignore-not-found=true
    return 0
  fi
  local added=""
  added=$(oc get configmap cluster-monitoring-config -n openshift-monitoring \
    -o jsonpath='{.metadata.annotations.wings-demo/added-enable-user-workload}' 2>/dev/null || true)
  if [[ "$added" == "true" ]]; then
    log "remove enableUserWorkload key added by WINGS install (CM pre-existed)"
    python3 - <<'PY'
import subprocess
existing = subprocess.run(
    ["oc", "get", "configmap", "cluster-monitoring-config", "-n", "openshift-monitoring",
     "-o", "jsonpath={.data.config\\.yaml}"],
    capture_output=True, text=True,
)
body = existing.stdout if existing.returncode == 0 else ""
lines = [l for l in body.splitlines() if not l.strip().startswith("enableUserWorkload:")]
new_body = "\n".join(lines) + ("\n" if lines else "")
import json
patch = {"data": {"config.yaml": new_body}}
subprocess.run(
    ["oc", "patch", "configmap", "cluster-monitoring-config", "-n", "openshift-monitoring",
     "--type=merge", "-p", json.dumps(patch)],
    capture_output=True, text=True,
)
PY
    oc annotate configmap cluster-monitoring-config -n openshift-monitoring \
      wings-demo/added-enable-user-workload- >/dev/null 2>&1 || true
  fi
}

purge_observability_resources() {
  purge_maas_tenant_telemetry
  purge_maas_usage_logging
  purge_usage_logging_backend
  purge_limitador_redis
  revert_dsci_observability_metrics
  purge_observability_operators
  revert_user_workload_monitoring
}
