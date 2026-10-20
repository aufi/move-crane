#!/usr/bin/env bash
# Render KubeVirt VM manifests from the source cluster without changing a cluster.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_CONTEXT="${SOURCE_CONTEXT:-minikube}"
NAMESPACE="${NAMESPACE:-crane-kubevirt}"
CRANE_BIN="${CRANE_BIN:-crane}"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/migration}"

for command in kubectl "${CRANE_BIN}"; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "FAIL: '${command}' is required" >&2
    exit 1
  fi
done

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"

echo "== export from ${SOURCE_CONTEXT}/${NAMESPACE} =="
"${CRANE_BIN}" export \
  --context "${SOURCE_CONTEXT}" \
  --namespace "${NAMESPACE}" \
  --export-dir "${WORK_DIR}/export" \
  --include-gk PersistentVolumeClaim \
  --include-gk kubevirt.io/VirtualMachine \
  --overwrite

echo "== transform =="
"${CRANE_BIN}" transform \
  --export-dir "${WORK_DIR}/export" \
  --transform-dir "${WORK_DIR}/transform" \
  --overwrite

echo "== render =="
"${CRANE_BIN}" apply \
  --transform-dir "${WORK_DIR}/transform" \
  --output-dir "${WORK_DIR}/output" \
  --ordered \
  --overwrite

echo "Rendered manifest: ${WORK_DIR}/output/output.yaml"
