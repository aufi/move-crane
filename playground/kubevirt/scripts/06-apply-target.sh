#!/usr/bin/env bash
# Apply rendered manifests after PVC content has been transferred separately.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_CONTEXT="${TARGET_CONTEXT:-kubevirt-target}"
NAMESPACE="${NAMESPACE:-crane-kubevirt}"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/migration}"
OUTPUT="${WORK_DIR}/output/output.yaml"

[[ -f "${OUTPUT}" ]] || { echo "FAIL: ${OUTPUT} not found; run 04 first" >&2; exit 1; }

kubectl --context "${TARGET_CONTEXT}" create namespace "${NAMESPACE}" --dry-run=client -o yaml | \
  kubectl --context "${TARGET_CONTEXT}" apply -f -
kubectl --context "${TARGET_CONTEXT}" -n "${NAMESPACE}" apply -f "${OUTPUT}"

for vm in web-vm configured-vm; do
  kubectl --context "${TARGET_CONTEXT}" -n "${NAMESPACE}" wait \
    --for=create --timeout=300s "vmi/${vm}"
  kubectl --context "${TARGET_CONTEXT}" -n "${NAMESPACE}" wait \
    --for=condition=Ready --timeout=300s "vmi/${vm}"
done

kubectl --context "${TARGET_CONTEXT}" -n "${NAMESPACE}" get vm,vmi,pvc
