#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDS_NAMESPACE="${BUILDS_NAMESPACE:-openshift-builds}"

wait_for_csv() {
  local subscription="$1" namespace="$2" csv=""
  for _ in $(seq 1 120); do
    csv="$(oc get subscription "${subscription}" -n "${namespace}" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    [[ -n "${csv}" ]] && break
    sleep 5
  done
  [[ -n "${csv}" ]] || { echo "FAIL: ${subscription} has no installedCSV" >&2; exit 1; }
  oc wait --for=jsonpath='{.status.phase}'=Succeeded "csv/${csv}" -n "${namespace}" --timeout=300s
}

wait_for_api_resource() {
  local group="$1" resource="$2"
  for _ in $(seq 1 60); do
    if oc api-resources --api-group="${group}" -o name 2>/dev/null | grep -qx "${resource}.${group}"; then
      return
    fi
    sleep 5
  done
  echo "FAIL: ${resource}.${group} API is not available" >&2
  exit 1
}

oc whoami >/dev/null

oc apply -f - <<'YAML'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator-rh
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
YAML
wait_for_csv openshift-pipelines-operator-rh openshift-operators
wait_for_api_resource tekton.dev pipelineruns

oc create namespace "${BUILDS_NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
oc apply -f - <<YAML
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-builds-operator
  namespace: ${BUILDS_NAMESPACE}
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-builds-operator
  namespace: ${BUILDS_NAMESPACE}
spec:
  channel: latest
  name: openshift-builds-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
YAML
wait_for_csv openshift-builds-operator "${BUILDS_NAMESPACE}"

oc apply -f - <<'YAML'
apiVersion: operator.openshift.io/v1alpha1
kind: OpenShiftBuild
metadata:
  name: cluster
spec:
  sharedResource:
    state: Enabled
  shipwright:
    build:
      state: Enabled
YAML

wait_for_api_resource shipwright.io builds
oc rollout status deployment/shipwright-build-controller -n "${BUILDS_NAMESPACE}" --timeout=300s
oc apply -f "${ROOT_DIR}/manifests/clusterbuildstrategy-source-to-image.yaml"
oc get clusterbuildstrategies.shipwright.io source-to-image

echo "OK: OpenShift Pipelines and OpenShift Builds are ready."
