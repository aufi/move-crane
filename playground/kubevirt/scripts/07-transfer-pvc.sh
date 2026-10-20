#!/usr/bin/env bash
# Transfer the configured VM data disk after stopping the source VM.

set -euo pipefail

SOURCE_CONTEXT="${SOURCE_CONTEXT:-minikube}"
TARGET_CONTEXT="${TARGET_CONTEXT:-kubevirt-target}"
NAMESPACE="${NAMESPACE:-crane-kubevirt}"
CRANE_BIN="${CRANE_BIN:-crane}"
DEST_STORAGE_CLASS="${DEST_STORAGE_CLASS:-standard}"
SUBDOMAIN="${SUBDOMAIN:-}"
INGRESS_CLASS="${INGRESS_CLASS:-nginx}"

[[ -n "${SUBDOMAIN}" ]] || {
  echo "FAIL: SUBDOMAIN is required for the nginx-ingress endpoint" >&2
  echo "Example: SUBDOMAIN=<target-minikube-ip>.nip.io $0" >&2
  exit 1
}

echo "Stopping configured-vm before copying its ReadWriteOnce data disk."
kubectl --context "${SOURCE_CONTEXT}" -n "${NAMESPACE}" patch vm/configured-vm \
  --type=merge -p '{"spec":{"runStrategy":"Halted"}}'
kubectl --context "${SOURCE_CONTEXT}" -n "${NAMESPACE}" wait \
  --for=delete --timeout=300s vmi/configured-vm

"${CRANE_BIN}" transfer-pvc \
  --source-context "${SOURCE_CONTEXT}" \
  --destination-context "${TARGET_CONTEXT}" \
  --pvc-name configured-data \
  --pvc-namespace "${NAMESPACE}" \
  --endpoint nginx-ingress \
  --subdomain "${SUBDOMAIN}" \
  --ingress-class "${INGRESS_CLASS}" \
  --dest-storage-class "${DEST_STORAGE_CLASS}" \
  --dest-storage-requests 1Gi \
  --verify
