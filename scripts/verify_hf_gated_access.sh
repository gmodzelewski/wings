#!/usr/bin/env bash
# Verify a namespace HuggingFace secret can download gated model files (not just authenticate).
#
# EvalHub logs "HF_TOKEN set from model auth secret" when the secret is wired, but jobs still
# fail with a gated-repo 403 if the token's HF account has not accepted the model license.
set -euo pipefail

PROJECT="${WINGS3_PROJECT:-my-first-model}"
HF_SECRET="${WINGS3_HF_SECRET:-hf-token}"
MODEL="${WINGS3_HF_GATED_MODEL:-meta-llama/Llama-3.2-3B-Instruct}"
LMES_IMAGE="${WINGS3_LMES_JOB_IMAGE:-registry.redhat.io/rhoai/odh-ta-lmes-job-rhel9@sha256:ebbf8deb41bd0ce2b6a6fa593ffbdfcc10a53a888c1b887b4119cf43aea1b8d6}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Checks that Secret ${HF_SECRET} (key hf-token) can download files from gated model ${MODEL}.

Options:
  --project NS       Namespace (default: ${PROJECT})
  --secret NAME      Secret name (default: ${HF_SECRET})
  --model ID         Gated HF model id (default: ${MODEL})
  -h, --help         Show this help
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --secret) HF_SECRET="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

command -v oc >/dev/null || die "oc not on PATH"
oc whoami >/dev/null || die "oc whoami failed; log in first"
oc get secret "$HF_SECRET" -n "$PROJECT" >/dev/null 2>&1 \
  || die "secret/${HF_SECRET} not found in ${PROJECT}"

pod="hf-gate-check-$(date +%s)"
overrides=$(cat <<EOF
{
  "spec": {
    "restartPolicy": "Never",
    "containers": [{
      "name": "check",
      "image": "${LMES_IMAGE}",
      "command": ["python3", "-c", "from pathlib import Path\\nfrom huggingface_hub import HfApi, hf_hub_download\\nimport sys\\ntok=Path('/var/run/secrets/model/hf-token').read_text().strip()\\napi=HfApi(token=tok)\\nwho=api.whoami()\\nprint('account', who.get('name', who.get('id')))\\ntry:\\n    hf_hub_download('${MODEL}', 'config.json', token=tok)\\n    print('download_ok')\\nexcept Exception as e:\\n    print('download_fail', type(e).__name__)\\n    print(str(e).splitlines()[0])\\n    sys.exit(1)"],
      "volumeMounts": [{
        "name": "m",
        "mountPath": "/var/run/secrets/model",
        "readOnly": true
      }]
    }],
    "volumes": [{
      "name": "m",
      "projected": {
        "sources": [{
          "secret": {
            "name": "${HF_SECRET}",
            "items": [{"key": "hf-token", "path": "hf-token"}]
          }
        }]
      }
    }]
  }
}
EOF
)

echo "Checking ${PROJECT}/${HF_SECRET} → ${MODEL}"
if ! oc run "$pod" -n "$PROJECT" --rm -i --restart=Never \
  --image="$LMES_IMAGE" --overrides="$overrides" 2>&1 | tee /tmp/hf-gate-check.log; then
  echo >&2
  echo "FAIL: token is present but cannot download gated files for ${MODEL}." >&2
  echo "  1. Log into HuggingFace as the same account as the token." >&2
  echo "  2. Open https://huggingface.co/${MODEL} and click Agree and access repository." >&2
  echo "  3. Re-create the secret if you rotated the token after accepting the license." >&2
  echo "Demo workaround (no Llama license): ./scripts/submit_evalhub_eval_run.sh --tokenizer gpt2 --benchmark arc_easy" >&2
  exit 1
fi

if ! grep -q download_ok /tmp/hf-gate-check.log; then
  die "unexpected verifier output (no download_ok)"
fi

echo "OK: ${HF_SECRET} can download ${MODEL}"
