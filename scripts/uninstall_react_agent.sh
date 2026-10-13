#!/usr/bin/env bash
# Standalone ReAct agent uninstall (also invoked from scripts/uninstall.sh).
set -euo pipefail

WINGS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/wings_lib.sh
source "${WINGS_ROOT}/scripts/wings_lib.sh"

PURGE_OPERATOR=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--operator]

Remove the LangGraph ReAct agent Helm release, Sandbox, AgentProfile, and secret
from ${PROJECT}. With --operator, also remove the wings-owned
agent-sandbox-operator Subscription (and namespace if wings-owned).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --operator) PURGE_OPERATOR=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

need_oc
purge_react_agent_resources
if [[ "$PURGE_OPERATOR" == 1 ]]; then
  purge_agent_sandbox_operator
fi
info "uninstall_react_agent complete"
