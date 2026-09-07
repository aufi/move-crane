#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-demo-buildconfig}"

oc delete namespace "${NAMESPACE}" --ignore-not-found
rm -rf "${ROOT_DIR}/export" "${ROOT_DIR}/transform" "${ROOT_DIR}/output"
echo "OK: demo namespace and generated local artifacts were removed."
