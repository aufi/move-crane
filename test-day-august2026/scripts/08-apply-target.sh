#!/usr/bin/env bash
#
# 08-apply-target.sh
# Deploy the migrated application to the TARGET cluster by applying the crane
# output into the target namespace, where the PVCs have already been provisioned
# and populated by transfer-pvc. PVC storage classes must be mapped during
# transform to match the destination class.
#
# The install Job is idempotent (exits early when WordPress is already installed),
# so re-applying it against the migrated database is a no-op and does not create
# a new sample post.
#
# Config via env:
#   NAMESPACE   target namespace (default: wordpress)
#   KUBECONFIG  defaults to repo kubeconfig-tgt (current context = target)
#   WORK_SUFFIX suffix for the generated output directory (default: empty)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-wordpress}"
WORK_SUFFIX="${WORK_SUFFIX:-}"
export KUBECONFIG="${KUBECONFIG:-${REPO_DIR}/kubeconfig-tgt}"
OUTPUT_YAML="${REPO_DIR}/output${WORK_SUFFIX}/output.yaml"

[[ -f "${OUTPUT_YAML}" ]] || { echo "FAIL: ${OUTPUT_YAML} not found (run 05 first)"; exit 1; }

echo "== context =="
echo "kubeconfig: ${KUBECONFIG}"
echo "server:     $(oc whoami --show-server)"
echo "namespace:  ${NAMESPACE}"

echo
echo "== target PVCs (must already exist, from 07-transfer-pvc.sh) =="
oc -n "${NAMESPACE}" get pvc 2>&1

echo
echo "== apply crane output =="
oc apply -f "${OUTPUT_YAML}"

echo
echo "== wait for readiness =="
oc wait --for=condition=available --timeout=300s deployment/wordpress-mysql -n "${NAMESPACE}"
oc wait --for=condition=available --timeout=300s deployment/wordpress       -n "${NAMESPACE}"
if [[ "$(oc get job/wordpress-install -n "${NAMESPACE}" -o jsonpath='{.spec.suspend}')" == "true" ]]; then
  echo "install Job is suspended by transform; skipping completion wait"
else
  oc wait --for=condition=complete --timeout=300s job/wordpress-install -n "${NAMESPACE}" || true
fi

echo
echo "== resources =="
oc get all,pvc -n "${NAMESPACE}" 2>&1

echo
echo "OK: application deployed to target. Validate with:"
echo "   KUBECONFIG=${REPO_DIR}/kubeconfig-tgt ${REPO_DIR}/scripts/04-validate-app.sh"
