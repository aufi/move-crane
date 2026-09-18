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
#   KUBECONFIG_SRC  source cluster kubeconfig (default: repo kubeconfig-src)
#   DISABLE_TRIGGERS  remove BuildConfig triggers before deployment (default: true)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-bc-demo}"
BC_FILE="${BC_FILE:-${REPO_DIR}/test-app/buildconfig/sample-nodejs-buildconfig.yaml}"
DISABLE_TRIGGERS="${DISABLE_TRIGGERS:-true}"
export KUBECONFIG="${KUBECONFIG_SRC:-${REPO_DIR}/kubeconfig-src}"

echo "== source =="
echo "server: $(oc whoami --show-server)"
echo "namespace: ${NAMESPACE}"

echo
echo "== ensure namespace =="
oc create namespace "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

echo
echo "== apply BuildConfig =="
# The saved fixtures include their original namespace. Use Kustomize rather than
# relying on kubectl's --namespace, which rejects a conflicting manifest value.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
cp "${BC_FILE}" "${WORK_DIR}/buildconfig.yaml"
cat > "${WORK_DIR}/kustomization.yaml" <<EOF
resources:
- buildconfig.yaml
namespace: ${NAMESPACE}
EOF
if [[ "${DISABLE_TRIGGERS}" == "true" ]]; then
  cat >> "${WORK_DIR}/kustomization.yaml" <<'EOF'
patches:
- target:
    group: build.openshift.io
    version: v1
    kind: BuildConfig
  patch: |-
    - op: replace
      path: /spec/triggers
      value: []
EOF
fi
oc apply -k "${WORK_DIR}"

echo
echo "== BuildConfig on source =="
oc get buildconfig -n "${NAMESPACE}" 2>&1
echo
echo "OK: BuildConfig present on the source (ready to export)."
