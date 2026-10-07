#!/usr/bin/env bash
# Rotate the workshop MaaS upstream API key and verify the provider accepts it.
# Never commit the token. Prefer: export WINGS_MAAS_UPSTREAM_API_KEY='sk-oai-…'
set -euo pipefail

PROJECT="${WINGS_PROJECT:-my-first-model}"
SECRET="${WINGS_MAAS_UPSTREAM_SECRET:-wings-maas-upstream-api-key}"
PROVIDER="${WINGS_EXTERNAL_PROVIDER:-qwen36-35b-a3b}"
MODEL="${WINGS_EXTERNAL_MODEL:-qwen36-35b-a3b}"
UPSTREAM_HOST="${WINGS_MAAS_UPSTREAM_HOST:-maas-rhdp.apps.maas.redhatworkshops.io}"
KEY="${WINGS_MAAS_UPSTREAM_API_KEY:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--key sk-oai-…] [--project NS]

Replace Secret ${SECRET} api-key, keep inference.llm-d.ai/ipp-managed=true,
optionally restore ExternalProvider endpoint to the workshop host, and probe
POST /v1/chat/completions until HTTP 200.

Env:
  WINGS_MAAS_UPSTREAM_API_KEY   required unless --key is passed
  WINGS_PROJECT                 default ${PROJECT}
  WINGS_MAAS_UPSTREAM_HOST      default ${UPSTREAM_HOST}
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key) KEY="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --host) UPSTREAM_HOST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

[[ -n "$KEY" ]] || die "set WINGS_MAAS_UPSTREAM_API_KEY or pass --key"
[[ "$KEY" == sk-oai-* ]] || die "key must start with sk-oai-"
command -v oc >/dev/null || die "oc not on PATH"
oc whoami >/dev/null || die "oc whoami failed"

if ! oc get secret "$SECRET" -n "$PROJECT" >/dev/null 2>&1; then
  oc create secret generic "$SECRET" -n "$PROJECT" \
    --from-literal=api-key="$KEY" \
    --dry-run=client -o yaml | oc apply -f -
else
  oc set data secret/"$SECRET" -n "$PROJECT" "api-key=${KEY}"
fi
oc label secret "$SECRET" -n "$PROJECT" inference.llm-d.ai/ipp-managed=true --overwrite

# Prefer workshop upstream when rotating a real key (undo lab stub redirect).
if oc get externalprovider "$PROVIDER" -n "$PROJECT" >/dev/null 2>&1; then
  oc patch externalprovider "$PROVIDER" -n "$PROJECT" --type=merge \
    -p "{\"spec\":{\"endpoint\":\"${UPSTREAM_HOST}\",\"auth\":{\"type\":\"apikey\",\"secretRef\":{\"name\":\"${SECRET}\"}}}}"
fi

echo "Probing https://${UPSTREAM_HOST}/v1/chat/completions …"
tmp=$(mktemp)
code=$(curl -sk -o "$tmp" -w '%{http_code}' \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":4}" \
  "https://${UPSTREAM_HOST}/v1/chat/completions")
echo "HTTP ${code}"
if [[ "$code" != "200" ]]; then
  head -c 400 "$tmp"; echo
  rm -f "$tmp"
  die "upstream still rejecting key (HTTP ${code}) — get a fresh workshop token"
fi
rm -f "$tmp"
echo "OK: upstream accepted key; Secret ${PROJECT}/${SECRET} updated."
echo "Hard-refresh Gen AI Studio → Playground / AI asset endpoints if Qwen still shows Unavailable."
