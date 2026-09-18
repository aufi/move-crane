#!/usr/bin/env bash
#
# Create the test-day kubeconfigs from already configured local kubectl contexts.
# Defaults target a Minikube source and a CRC OpenShift destination.
#
# Config via env:
#   SRC_CONTEXT  source context (default: minikube)
#   TGT_CONTEXT  target context (default: crc-admin)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_CONTEXT="${SRC_CONTEXT:-minikube}"
TGT_CONTEXT="${TGT_CONTEXT:-crc-admin}"
KUBECONFIG_SRC="${REPO_DIR}/kubeconfig-src"
KUBECONFIG_TGT="${REPO_DIR}/kubeconfig-tgt"

for context in "${SRC_CONTEXT}" "${TGT_CONTEXT}"; do
  if ! kubectl config get-contexts -o name | grep -qxF "${context}"; then
    echo "FAIL: kubectl context '${context}' does not exist"
    exit 1
  fi
done

echo "== source: ${SRC_CONTEXT} -> ${KUBECONFIG_SRC} =="
kubectl config view --context "${SRC_CONTEXT}" --flatten --minify --raw > "${KUBECONFIG_SRC}"
chmod 600 "${KUBECONFIG_SRC}"

echo "== target: ${TGT_CONTEXT} -> ${KUBECONFIG_TGT} =="
kubectl config view --context "${TGT_CONTEXT}" --flatten --minify --raw > "${KUBECONFIG_TGT}"
chmod 600 "${KUBECONFIG_TGT}"

echo
echo "== verify =="
KUBECONFIG="${KUBECONFIG_SRC}" kubectl cluster-info
KUBECONFIG="${KUBECONFIG_TGT}" kubectl cluster-info

echo
echo "== merge contexts for transfer-pvc =="
bash "${REPO_DIR}/scripts/06-merge-kubeconfig.sh"
