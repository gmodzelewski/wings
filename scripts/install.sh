#!/usr/bin/env bash
# WINGS3 demo install.
set -euo pipefail

WINGS3_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/wings3_lib.sh
source "${WINGS3_ROOT}/scripts/wings3_lib.sh"

SKIP_LLM=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--skip-llm]

Install WINGS3 demo (MLflow, EvalHub, workbench, LLM, pip deps).

Environment: WINGS3_PROJECT, WINGS3_LLM_STORAGE_URI, WINGS3_DSC_NAME,
             WINGS3_JUDGE_API_KEY (override judge secret after MaaS key mint),
             WINGS3_MAAS_UPSTREAM_API_KEY (workshop token for ExternalModel),
             WINGS3_SKIP_OGX, WINGS3_SKIP_MCP, WINGS3_SKIP_SERVICEMESH
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
apply_manifests
enable_maas
enable_genai_studio
apply_evalhub_manifests
install_llm
clone_repo
pip_install

info "install complete"
