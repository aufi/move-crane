#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-wordpress-instructions-demo}"
CRANE_BIN="${CRANE_BIN:-mta-ops}"
WORDPRESS_DEPLOY_SCRIPT="${WORDPRESS_DEPLOY_SCRIPT:-${ROOT_DIR}/../../test-day-august2026/scripts/03-deploy-app-src.sh}"

command -v "${CRANE_BIN}" >/dev/null || {
  echo "FAIL: mta-ops binary not found or not executable: ${CRANE_BIN}" >&2
  exit 1
}
[[ -x "${WORDPRESS_DEPLOY_SCRIPT}" ]] || {
  echo "FAIL: WordPress deploy script not found or not executable: ${WORDPRESS_DEPLOY_SCRIPT}" >&2
  exit 1
}

NAMESPACE="${NAMESPACE}" "${WORDPRESS_DEPLOY_SCRIPT}"

rm -rf "${ROOT_DIR}/export" "${ROOT_DIR}/transform" "${ROOT_DIR}/output"

"${CRANE_BIN}" export -n "${NAMESPACE}" \
  --export-dir "${ROOT_DIR}/export" \
  --overwrite
"${CRANE_BIN}" transform \
  --export-dir "${ROOT_DIR}/export" \
  --transform-dir "${ROOT_DIR}/transform" \
  --instructions-file "${ROOT_DIR}/instructions.yaml"
"${CRANE_BIN}" apply \
  --transform-dir "${ROOT_DIR}/transform" \
  --output-dir "${ROOT_DIR}/output" \
  --overwrite

echo "Rendered manifest: ${ROOT_DIR}/output/output.yaml"
