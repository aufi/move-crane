#!/usr/bin/env bash
# Apply the KubeVirt resources used as a Crane migration source.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-kubevirt-source}"
NAMESPACE="${NAMESPACE:-crane-kubevirt}"
VM_TIMEOUT="${VM_TIMEOUT:-300s}"

if ! kubectl config get-contexts -o name | grep -qxF "${MINIKUBE_PROFILE}"; then
  echo "FAIL: kubectl context '${MINIKUBE_PROFILE}' does not exist" >&2
  exit 1
fi

kubectl --context "${MINIKUBE_PROFILE}" apply -f "${ROOT_DIR}/manifests/test-vms.yaml"

for vm in web-vm configured-vm; do
  echo "== wait for ${vm} =="
  kubectl --context "${MINIKUBE_PROFILE}" -n "${NAMESPACE}" wait \
    --for=create \
    --timeout="${VM_TIMEOUT}" \
    "vmi/${vm}"
  kubectl --context "${MINIKUBE_PROFILE}" -n "${NAMESPACE}" wait \
    --for=condition=Ready \
    --timeout="${VM_TIMEOUT}" \
    "vmi/${vm}"
done

echo
kubectl --context "${MINIKUBE_PROFILE}" -n "${NAMESPACE}" get vm,vmi
