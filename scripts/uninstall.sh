#!/usr/bin/env bash
# WINGS demo uninstall.
set -euo pipefail

WINGS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/wings_lib.sh
source "${WINGS_ROOT}/scripts/wings_lib.sh"

PURGE_ALL=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--all]

Default: delete workbench and the LangGraph ReAct agent (Helm, Sandbox,
         AgentProfile, secret, build artifacts).
--all:   full demo reset (keeps InferenceService; also removes the
         observability stack this install added — COO/OpenTelemetry/Tempo/
         Loki operators, MinIO+LokiStack usage logging, Redis Limitador
         persistence, User Workload Monitoring, and DSCI metrics/traces —
         and the wings-owned Agent Sandbox operator Subscription).
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
purge_react_agent_resources

if [[ "$PURGE_ALL" == 1 ]]; then
  purge_ogx_resources
  purge_maas_resources
  purge_mlflow_cr
  purge_evalhub_resources
  delete_judge_secret
  purge_observability_resources
  purge_agent_sandbox_operator
fi

info "uninstall complete"
