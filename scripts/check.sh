#!/usr/bin/env bash
set -euo pipefail
WINGS3_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec python3 "${WINGS3_ROOT}/scripts/check_demo.py" "$@"
