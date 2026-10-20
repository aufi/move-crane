#!/usr/bin/env bash
# Check the source state that a later Crane migration must preserve.

set -euo pipefail

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-kubevirt-source}"
NAMESPACE="${NAMESPACE:-crane-kubevirt}"

context=(--context "${MINIKUBE_PROFILE}" -n "${NAMESPACE}")

for vm in web-vm configured-vm stopped-vm; do
  kubectl "${context[@]}" get "vm/${vm}" >/dev/null
done

for vm in web-vm configured-vm; do
  phase="$(kubectl "${context[@]}" get "vmi/${vm}" -o jsonpath='{.status.phase}')"
  if [[ "${phase}" != "Running" ]]; then
    echo "FAIL: VMI '${vm}' has phase '${phase}', expected 'Running'" >&2
    exit 1
  fi
done

run_strategy="$(kubectl "${context[@]}" get vm/stopped-vm -o jsonpath='{.spec.runStrategy}')"
if [[ "${run_strategy}" != "Halted" ]]; then
  echo "FAIL: VM 'stopped-vm' has runStrategy '${run_strategy}', expected 'Halted'" >&2
  exit 1
fi

if kubectl "${context[@]}" get vmi/stopped-vm >/dev/null 2>&1; then
  echo "FAIL: VM 'stopped-vm' unexpectedly has a VMI" >&2
  exit 1
fi

echo "OK: source VMs are ready for Crane export."
kubectl "${context[@]}" get vm,vmi
