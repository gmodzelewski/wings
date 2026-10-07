#!/usr/bin/env bash
set -euo pipefail
WINGS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec python3 "${WINGS_ROOT}/scripts/check_demo.py" "$@"
