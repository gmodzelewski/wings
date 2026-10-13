#!/usr/bin/env bash
# Standalone ReAct agent install (also invoked from scripts/install.sh).
set -euo pipefail

WINGS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/wings_lib.sh
source "${WINGS_ROOT}/scripts/wings_lib.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Build and deploy the LangGraph ReAct agent into ${PROJECT}, register Sandbox +
AgentProfile for AI Hub / Playground, and ensure agent-sandbox-operator is installed.

Environment: WINGS_PROJECT, WINGS_LLM_MODEL, WINGS_SKIP_AGENT,
             WINGS_AGENTIC_STARTER_KITS_REF (default: rhoai-3.6),
             WINGS_AGENTIC_STARTER_KITS_URL, WINGS_AGENTIC_STARTER_KITS_DIR
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

deploy_react_agent
info "install_react_agent complete"
