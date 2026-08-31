#!/usr/bin/env bash
#
# 09-cleanup-target.sh
# Remove the migrated application from the TARGET cluster so a full migration can
# be re-run from a clean state. Deletes the whole namespace, which removes the
# Deployments, Services, Secrets, ConfigMaps, the transferred PVCs, and any
# leftover transfer-pvc artifacts (rsync pods, routes) in it.
#
# Idempotent: succeeds even if the namespace is already gone.
#
# Config via env:
#   NAMESPACE   namespace to delete (default: wordpress)
#   KUBECONFIG  defaults to repo kubeconfig-tgt

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-wordpress}"
export KUBECONFIG="${KUBECONFIG:-${REPO_DIR}/kubeconfig-tgt}"

echo "== context =="
echo "kubeconfig: ${KUBECONFIG}"
echo "server:     $(oc whoami --show-server)"
echo "namespace:  ${NAMESPACE}"

echo
echo "== before cleanup =="
oc get all,pvc,route -n "${NAMESPACE}" 2>&1 || true

echo
echo "== delete namespace '${NAMESPACE}' =="
oc delete namespace "${NAMESPACE}" --wait=true --ignore-not-found=true

echo
echo "== verify gone =="
if oc get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "WARN: namespace still present (may be terminating)"
  oc get namespace "${NAMESPACE}" 2>&1
else
  echo "OK: namespace '${NAMESPACE}' removed from $(oc whoami --show-server)"
fi
