#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CRANE_BIN="mta-ops"
CRANE_BIN="${CRANE_BIN:-${DEFAULT_CRANE_BIN}}"

command -v crc >/dev/null
command -v oc >/dev/null
command -v "${CRANE_BIN}" >/dev/null

crc status
oc whoami
oc whoami --show-server

"${CRANE_BIN}" version
"${CRANE_BIN}" transform list-plugins | grep -q '^Plugin: BuildConfigPlugin '
echo "OK: mta-ops and cluster prerequisites are available."
