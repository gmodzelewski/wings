#!/usr/bin/env bash
# WINGS demo install.
set -euo pipefail

WINGS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/wings_lib.sh
source "${WINGS_ROOT}/scripts/wings_lib.sh"

SKIP_LLM=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--skip-llm]

Install WINGS demo (MLflow, EvalHub, workbench, LLM, pip deps).

Environment: WINGS_PROJECT, WINGS_LLM_STORAGE_URI, WINGS_DSC_NAME,
             WINGS_JUDGE_API_KEY (override judge secret after MaaS key mint),
             WINGS_MAAS_UPSTREAM_API_KEY (workshop token for all ExternalModels; never commit),
             WINGS_MAAS_CATALOG_MODELS (default: gpt-oss-120b gpt-oss-20b llama-scout-17b qwen36-35b-a3b),
             WINGS_SKIP_OGX, WINGS_SKIP_MCP, WINGS_SKIP_SERVICEMESH,
             WINGS_SKIP_OBSERVABILITY (skip Usage/token-consumption dashboard stack),
             WINGS_MAAS_CAPTURE_USER=0 (disable per-user MaaS metric labelling; on by default -- the Usage dashboard totals need it)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-llm) SKIP_LLM=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

need_oc
enable_mlflow_operator
enable_evalhub_operator
enable_garak
enable_observability
apply_manifests
enable_maas
enable_genai_studio
apply_evalhub_manifests
install_llm
clone_repo
pip_install

info "install complete"
