#!/usr/bin/env bash
#
# 05-crane-export-transform-apply.sh
# Run the non-destructive crane pipeline against the SOURCE cluster:
#   1) crane export    — dump namespace resources to export/
#   2) crane transform — generate kustomize patches in transform/
#   3) crane apply     — render clean manifests to output/output.yaml
#
# These steps only read the source cluster and write files to disk; nothing is
# applied to any cluster here. Idempotent via --overwrite.
#
# The exact crane commands are echoed so they can also be run manually.
#
# Config via env:
#   NAMESPACE   source namespace (default: wordpress)
#   KUBECONFIG  defaults to repo kubeconfig-src
#   CRANE_BIN   migration binary to test (default: crane). Set to the downstream
#               build (e.g. mta-ops) to run the exact same flow against it.
#   WORK_SUFFIX suffix for generated export/transform/output directories (default: empty)
#   PVC_STORAGE_CLASS_MAP  KubernetesPlugin storage class map, e.g.
#                          standard:crc-csi-hostpath-provisioner

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-wordpress}"
CRANE_BIN="${CRANE_BIN:-crane}"
WORK_SUFFIX="${WORK_SUFFIX:-}"
PVC_STORAGE_CLASS_MAP="${PVC_STORAGE_CLASS_MAP:-}"
export KUBECONFIG="${KUBECONFIG:-${REPO_DIR}/kubeconfig-src}"

EXPORT_DIR="${REPO_DIR}/export${WORK_SUFFIX}"
TRANSFORM_DIR="${REPO_DIR}/transform${WORK_SUFFIX}"
OUTPUT_DIR="${REPO_DIR}/output${WORK_SUFFIX}"

echo "== context =="
echo "kubeconfig: ${KUBECONFIG}"
echo "server:     $(oc whoami --show-server)"
echo "namespace:  ${NAMESPACE}"

echo
echo "== 1) crane export =="
set -x
"${CRANE_BIN}" export \
  --kubeconfig "${KUBECONFIG}" \
  -n "${NAMESPACE}" \
  --export-dir "${EXPORT_DIR}" \
  --overwrite
{ set +x; } 2>/dev/null
echo "exported resources:"
ls -1 "${EXPORT_DIR}/resources/${NAMESPACE}" 2>/dev/null || ls -1R "${EXPORT_DIR}"

echo
echo "== 2) crane transform =="
stage_optionals=()
if [[ -n "${PVC_STORAGE_CLASS_MAP}" ]]; then
  stage_optionals+=(--stage-optionals "KubernetesPlugin={\"pvc-storage-class-map\":\"${PVC_STORAGE_CLASS_MAP}\"}")
fi
set -x
"${CRANE_BIN}" transform \
  --export-dir "${EXPORT_DIR}" \
  --transform-dir "${TRANSFORM_DIR}" \
  "${stage_optionals[@]}" \
  --overwrite
{ set +x; } 2>/dev/null
echo "transform stages:"
ls -1 "${TRANSFORM_DIR}"

echo
echo "== 3) crane apply =="
set -x
"${CRANE_BIN}" apply \
  --transform-dir "${TRANSFORM_DIR}" \
  --output-dir "${OUTPUT_DIR}" \
  --ordered \
  --overwrite
{ set +x; } 2>/dev/null

echo
echo "== output =="
ls -1 "${OUTPUT_DIR}"
echo
echo "resource kinds in output:"
grep -hE '^kind:' "${OUTPUT_DIR}"/*.yaml 2>/dev/null | sort | uniq -c || true

echo
echo "OK: export/transform/apply complete (nothing applied to any cluster)"
