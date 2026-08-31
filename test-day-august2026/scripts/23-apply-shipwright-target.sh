#!/usr/bin/env bash
#
# 23-apply-shipwright-target.sh
# Apply the converted Shipwright Build to the TARGET cluster, then run a BuildRun
# to prove the converted Build actually builds and pushes an image.
#
# Steps:
#   1) ensure target namespace
#   2) apply output-bc/output.yaml (the Shipwright Build)
#   3) wait for Shipwright to register the Build (spec accepted)
#   4) grant the namespace "pipeline" SA push access to the internal registry
#   5) create a BuildRun and wait for its terminal result
#   6) verify the pushed image digest matches the ImageStreamTag
#
# NOTE on naming: both build.openshift.io and shipwright.io expose a "builds"
# resource, so "oc get build" resolves to the OpenShift one. Always use the
# fully-qualified builds.shipwright.io / buildruns.shipwright.io here.
#
# Config via env:
#   NAMESPACE     namespace on the target (default: bc-demo)
#   BUILD_NAME    Shipwright Build name    (default: sample-nodejs)
#   SA            ServiceAccount for the BuildRun (default: pipeline)
#   BUILD_TIMEOUT terminal wait budget     (default: 900s)
#   WORK_SUFFIX   suffix of the generated output dir (default: -bc). Must match
#                 the suffix used with 22-crane-buildconfig-convert.sh.
#
# Docker/buildah extras (set both for the buildah-shipwright-managed-push case):
#   GRANT_PRIVILEGED_SCC  "true" grants the SA the "privileged" SCC. The buildah
#                         ClusterBuildStrategy runs a privileged build container,
#                         which the default pipelines-scc forbids. Not needed for
#                         the S2I (source-to-image) strategies.
#   SETUP_INTERNAL_PUSH   "true" builds a dockerconfigjson pushSecret from the
#                         SA's own auto-created dockercfg secret (the token that
#                         already works against the internal registry), annotates
#                         it for Tekton, and sets it as the Build's output
#                         pushSecret. Shipwright's image-processing push step
#                         (used by *-shipwright-managed-push strategies) needs an
#                         annotated push secret; the raw SA dockercfg secret is
#                         ignored by Tekton creds-init because it lacks the
#                         tekton.dev/docker-0 annotation → otherwise 401.
#                         The S2I redhat builder reads the SA token directly, so
#                         it does not need this.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-bc-demo}"
BUILD_NAME="${BUILD_NAME:-sample-nodejs}"
SA="${SA:-pipeline}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-900s}"
WORK_SUFFIX="${WORK_SUFFIX:--bc}"
GRANT_PRIVILEGED_SCC="${GRANT_PRIVILEGED_SCC:-false}"
SETUP_INTERNAL_PUSH="${SETUP_INTERNAL_PUSH:-false}"
INTERNAL_REGISTRY="${INTERNAL_REGISTRY:-image-registry.openshift-image-registry.svc:5000}"
PUSH_SECRET_NAME="${PUSH_SECRET_NAME:-internal-registry-push}"
OUTPUT="${REPO_DIR}/output${WORK_SUFFIX}/output.yaml"
export KUBECONFIG="${REPO_DIR}/kubeconfig-tgt"

echo "== target =="
echo "server: $(oc whoami --show-server)"
echo "namespace: ${NAMESPACE}, build: ${BUILD_NAME}, sa: ${SA}"

echo
echo "== 1) ensure namespace =="
oc create namespace "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

echo
echo "== 2) apply the converted Shipwright Build =="
oc apply -f "${OUTPUT}"

echo
echo "== 3) wait for the Build to be registered =="
oc wait --for=jsonpath='{.status.registered}'=True "builds.shipwright.io/${BUILD_NAME}" -n "${NAMESPACE}" --timeout=120s
oc get "builds.shipwright.io/${BUILD_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='registered={.status.registered} reason={.status.reason}{"\n"}'

echo
echo "== 4) grant the ${SA} SA push access to the internal registry =="
# The pipeline SA is auto-created by the OpenShift Pipelines operator per
# namespace and carries a dockercfg secret for the internal registry; the
# system:image-builder role lets it push imagestreams in this namespace.
oc policy add-role-to-user system:image-builder -z "${SA}" -n "${NAMESPACE}"

if [[ "${GRANT_PRIVILEGED_SCC}" == "true" ]]; then
  echo
  echo "== 4a) grant the ${SA} SA the privileged SCC (buildah build container) =="
  oc adm policy add-scc-to-user privileged -z "${SA}" -n "${NAMESPACE}"
fi

if [[ "${SETUP_INTERNAL_PUSH}" == "true" ]]; then
  echo
  echo "== 4b) wire an annotated internal-registry pushSecret for the Build =="
  # Reuse the token from the SA's auto-created dockercfg secret (it already works
  # against the internal registry) and expose it as an annotated dockerconfigjson
  # secret so Tekton creds-init picks it up for the image-processing push step.
  SA_SECRET="$(oc get sa "${SA}" -n "${NAMESPACE}" \
    -o jsonpath='{.imagePullSecrets[*].name} {.secrets[*].name}' \
    | tr ' ' '\n' | grep dockercfg | head -1)"
  if [[ -z "${SA_SECRET}" ]]; then
    echo "FAIL: no dockercfg secret found on SA ${SA}"; exit 1
  fi
  echo "source SA dockercfg secret: ${SA_SECRET}"
  TMP_DCJ="$(mktemp)"
  oc get secret "${SA_SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.\.dockercfg}' \
    | base64 -d | python3 -c 'import json,sys; json.dump({"auths": json.load(sys.stdin)}, sys.stdout)' \
    > "${TMP_DCJ}"
  oc create secret generic "${PUSH_SECRET_NAME}" -n "${NAMESPACE}" \
    --type=kubernetes.io/dockerconfigjson \
    --from-file=.dockerconfigjson="${TMP_DCJ}" \
    --dry-run=client -o yaml | oc apply -f -
  rm -f "${TMP_DCJ}"
  oc annotate secret "${PUSH_SECRET_NAME}" -n "${NAMESPACE}" \
    "tekton.dev/docker-0=https://${INTERNAL_REGISTRY}" --overwrite
  oc patch "builds.shipwright.io/${BUILD_NAME}" -n "${NAMESPACE}" --type=merge \
    -p "{\"spec\":{\"output\":{\"pushSecret\":\"${PUSH_SECRET_NAME}\"}}}"
fi

echo
echo "== 5) create a BuildRun and wait for the terminal result =="
BR="$(oc create -n "${NAMESPACE}" -o jsonpath='{.metadata.name}' -f - <<EOF
apiVersion: shipwright.io/v1beta1
kind: BuildRun
metadata:
  generateName: ${BUILD_NAME}-run-
spec:
  build:
    name: ${BUILD_NAME}
  serviceAccount: ${SA}
EOF
)"
echo "BuildRun: ${BR}"
status=""; deadline=$((SECONDS + ${BUILD_TIMEOUT%s}))
while [[ "${SECONDS}" -lt "${deadline}" ]]; do
  status="$(oc get "buildruns.shipwright.io/${BR}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}' 2>/dev/null || true)"
  reason="$(oc get "buildruns.shipwright.io/${BR}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].reason}' 2>/dev/null || true)"
  echo "  status=${status:-?} reason=${reason:-?}"
  [[ "${status}" == "True" || "${status}" == "False" ]] && break
  sleep 15
done
if [[ "${status}" != "True" ]]; then
  echo "FAIL: BuildRun did not succeed (status=${status:-<timeout>})"
  oc get "buildruns.shipwright.io/${BR}" -n "${NAMESPACE}" \
    -o jsonpath='{range .status.conditions[?(@.type=="Succeeded")]}{.reason}: {.message}{end}{"\n"}' 2>&1 || true
  oc get pods -n "${NAMESPACE}" 2>&1
  exit 1
fi
echo "OK: BuildRun ${BR} Succeeded"

echo
echo "== 6) verify the pushed image =="
DIGEST="$(oc get "buildruns.shipwright.io/${BR}" -n "${NAMESPACE}" -o jsonpath='{.status.output.digest}' 2>&1)"
echo "BuildRun output digest: ${DIGEST}"
oc get imagestream -n "${NAMESPACE}" 2>&1
# The output ImageStreamTag comes from the Build's output image, NOT the Build
# name (they differ when the BuildConfig output name != BuildConfig name, e.g.
# the docker case: build "ruby-hello-world-docker" pushes image "ruby-hello-world").
OUT_IMAGE="$(oc get "builds.shipwright.io/${BUILD_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.output.image}' 2>/dev/null)"
IST="$(basename "${OUT_IMAGE}")"          # e.g. ruby-hello-world:latest
[[ "${IST}" == *:* ]] || IST="${IST}:latest"
echo "output ImageStreamTag:  ${IST}"
# The internal-registry import controller populates the ImageStreamTag a moment
# after the push completes — retry briefly to avoid a race.
IST_DIGEST=""
for _ in $(seq 1 12); do
  IST_DIGEST="$(oc get imagestreamtag "${IST}" -n "${NAMESPACE}" \
    -o jsonpath='{.image.dockerImageReference}' 2>/dev/null | sed 's/.*@//')"
  [[ -n "${IST_DIGEST}" ]] && break
  sleep 5
done
echo "ImageStreamTag digest:  ${IST_DIGEST}"
if [[ -n "${DIGEST}" && "${DIGEST}" == "${IST_DIGEST}" ]]; then
  echo
  echo "# CONVERSION VERIFIED: BuildConfig -> Shipwright Build -> BuildRun built and pushed ${IST}@${DIGEST}"
else
  echo "WARN: digest mismatch or missing (BuildRun=${DIGEST}, ImageStreamTag=${IST_DIGEST})"
  exit 1
fi
