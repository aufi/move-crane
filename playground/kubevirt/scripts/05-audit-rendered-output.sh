#!/usr/bin/env bash
# Inspect rendered manifests for KubeVirt runtime metadata that must not migrate.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-${ROOT_DIR}/migration}"
OUTPUT="${WORK_DIR}/output/output.yaml"

[[ -f "${OUTPUT}" ]] || { echo "FAIL: ${OUTPUT} not found; run 04 first" >&2; exit 1; }

echo "== rendered kinds =="
rg '^kind:' "${OUTPUT}"

echo "== KubeVirt finalizers =="
if rg -n 'kubevirt.io/(virtualMachineControllerFinalize|foregroundDeleteVirtualMachine)' "${OUTPUT}"; then
  echo "WARN: rendered VM resources retain source KubeVirt finalizers."
  echo "      Crane needs a KubeVirt-aware transform to remove controller-owned metadata."
else
  echo "OK: no KubeVirt runtime finalizers found."
fi
