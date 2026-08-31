#!/usr/bin/env bash
#
# 20-install-openshift-builds-operator.sh
# Prepare the TARGET cluster to accept the Shipwright Build resources produced by
# crane-plugin-buildconfig-to-shipwright.
#
# Neither cluster ships Shipwright by default (both have BuildConfig natively).
# On OpenShift, Shipwright is delivered by the "OpenShift Builds" operator
# (downstream Shipwright), which itself requires Tekton via the "OpenShift
# Pipelines" operator. This script installs both operators via OLM, enables
# Shipwright through the OpenShiftBuild CR, and installs the ClusterBuildStrategies
# the plugin targets (buildah / source-to-image) — the downstream operator does
# NOT ship sample strategies (unlike upstream sample-strategies.yaml), so we apply
# them ourselves from shipwright/clusterbuildstrategies/.
#
# Order matters: Pipelines (Tekton) must be Ready BEFORE the OpenShiftBuild CR is
# reconciled, otherwise the ShipwrightBuild reconcile fails with "tekton operator
# not installed" and drops into a long exponential backoff.
#
# Idempotent: re-running only creates what's missing and re-waits.
#
# Config via env:
#   BUILDS_CHANNEL      openshift-builds subscription channel   (default: latest)
#   PIPELINES_CHANNEL   openshift-pipelines subscription channel(default: latest)
#   NS                  builds operator install namespace       (default: openshift-builds)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDS_CHANNEL="${BUILDS_CHANNEL:-latest}"
PIPELINES_CHANNEL="${PIPELINES_CHANNEL:-latest}"
NS="${NS:-openshift-builds}"
CBS_DIR="${REPO_DIR}/shipwright/clusterbuildstrategies"
export KUBECONFIG="${REPO_DIR}/kubeconfig-tgt"

# Wait until a Subscription reports an installedCSV, then until that CSV Succeeds.
wait_csv() {
  local sub="$1" ns="$2" csv=""
  for _ in $(seq 1 60); do
    csv="$(oc get subscription "${sub}" -n "${ns}" -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
    [[ -n "${csv}" ]] && break
    echo "  waiting for ${sub} installedCSV..."; sleep 5
  done
  [[ -n "${csv}" ]] || { echo "FAIL: ${sub} has no installedCSV"; return 1; }
  echo "  installedCSV: ${csv}"
  oc wait --for=jsonpath='{.status.phase}'=Succeeded "csv/${csv}" -n "${ns}" --timeout=300s
}

echo "== target =="
echo "server: $(oc whoami --show-server)"

# --- 1) OpenShift Pipelines (Tekton) — prerequisite for Shipwright -------------
echo
echo "== 1) OpenShift Pipelines operator (Tekton) =="
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator-rh
  namespace: openshift-operators
spec:
  channel: ${PIPELINES_CHANNEL}
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
wait_csv openshift-pipelines-operator-rh openshift-operators
echo "  waiting for tekton.dev API..."
for _ in $(seq 1 60); do
  oc api-resources --api-group=tekton.dev 2>/dev/null | grep -q pipelineruns && break; sleep 5
done

# --- 2) OpenShift Builds operator (downstream Shipwright) ----------------------
echo
echo "== 2) OpenShift Builds operator (namespace + OperatorGroup + Subscription) =="
oc create namespace "${NS}" --dry-run=client -o yaml | oc apply -f -
# AllNamespaces install mode => OperatorGroup with no spec.targetNamespaces.
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-builds-operator
  namespace: ${NS}
spec: {}
EOF
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-builds-operator
  namespace: ${NS}
spec:
  channel: ${BUILDS_CHANNEL}
  name: openshift-builds-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
wait_csv openshift-builds-operator "${NS}"

# --- 3) Enable Shipwright via the OpenShiftBuild CR ----------------------------
echo
echo "== 3) enable Shipwright (OpenShiftBuild/cluster) =="
oc apply -f - <<EOF
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
EOF

echo "  waiting for shipwright.io API + build controller..."
for _ in $(seq 1 60); do
  oc api-resources --api-group=shipwright.io 2>/dev/null | grep -q clusterbuildstrategies && break; sleep 5
done
oc rollout status deployment/shipwright-build-controller -n "${NS}" --timeout=300s

# --- 4) Install ClusterBuildStrategies (downstream ships none) -----------------
echo
echo "== 4) ClusterBuildStrategies (buildah / source-to-image) =="
oc apply -f "${CBS_DIR}/" 2>&1
echo
oc get clusterbuildstrategy 2>&1

echo
echo "OK: OpenShift Builds (Shipwright) + Pipelines (Tekton) installed and ready on the target."
