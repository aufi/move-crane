#!/usr/bin/env bash
#
# 21-deploy-buildconfig-src.sh
# Deploy the sample S2I BuildConfig to the SOURCE cluster (OpenShift supports
# build.openshift.io natively). This is the resource the plugin converts to a
# Shipwright Build. We only need the BuildConfig object to exist for export; we
# do not need to run an OpenShift build on the source.
#
# Config via env:
#   NAMESPACE  namespace for the BuildConfig (default: bc-demo)
#   BC_FILE    BuildConfig manifest to deploy
#              (default: test-app/buildconfig/sample-nodejs-buildconfig.yaml)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-bc-demo}"
BC_FILE="${BC_FILE:-${REPO_DIR}/test-app/buildconfig/sample-nodejs-buildconfig.yaml}"
export KUBECONFIG="${REPO_DIR}/kubeconfig-src"

echo "== source =="
echo "server: $(oc whoami --show-server)"
echo "namespace: ${NAMESPACE}"

echo
echo "== ensure namespace =="
oc create namespace "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

echo
echo "== apply BuildConfig =="
oc apply -n "${NAMESPACE}" -f "${BC_FILE}"

echo
echo "== BuildConfig on source =="
oc get buildconfig -n "${NAMESPACE}" 2>&1
echo
echo "OK: BuildConfig present on the source (ready to export)."
