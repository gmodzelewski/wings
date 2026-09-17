#!/usr/bin/env bash
# Reconcile wings3-judge-llm after manual edits (probes gateway, falls back to workshop).
set -euo pipefail
WINGS3_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/wings3_lib.sh
source "${WINGS3_ROOT}/scripts/wings3_lib.sh"
need_oc
base_url=$(discover_maas_judge_base_url)
key=$(read_secret_key wings3-judge-llm "$PROJECT" JUDGE_API_KEY)
if [[ -z "$key" ]]; then
  host=$(discover_maas_gateway_host)
  key=$(mint_maas_api_key "$host" || true)
fi
if [[ -z "$base_url" ]]; then
  die "could not discover MaaS base URL"
fi
patch_judge_secret_for_maas "$base_url" "${key:-}"
info "reconciled secret/wings3-judge-llm in ${PROJECT}"
