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
             WINGS3_JUDGE_API_KEY (hosted MaaS token for Module 4 judges)
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
apply_evalhub_manifests
install_llm
clone_repo
pip_install

info "install complete"
