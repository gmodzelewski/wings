#!/usr/bin/env bash
# WINGS3 demo uninstall.
set -euo pipefail

WINGS3_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/wings3_lib.sh
source "${WINGS3_ROOT}/scripts/wings3_lib.sh"

PURGE_ALL=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--all]

Default: delete workbench only.
--all:   full demo reset (keeps InferenceService and operators).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) PURGE_ALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

need_oc

delete_workbench_resources

if [[ "$PURGE_ALL" == 1 ]]; then
  purge_ogx_resources
  purge_maas_resources
  purge_mlflow_cr
  purge_evalhub_resources
  delete_judge_secret
fi

info "uninstall complete"
