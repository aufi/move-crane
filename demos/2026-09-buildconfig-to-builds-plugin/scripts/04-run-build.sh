#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-demo-buildconfig}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-900s}"
INTERNAL_REGISTRY="${INTERNAL_REGISTRY:-image-registry.openshift-image-registry.svc:5000}"
PUSH_SECRET_NAME="${PUSH_SECRET_NAME:-internal-registry-push}"
BUILD_NAMES=(sample-nodejs sample-nodejs-webhook ruby-hello-world-docker)
IMAGE_STREAM_TAGS=(sample-nodejs:latest sample-nodejs-webhook:latest ruby-hello-world:latest)

oc apply -f "${ROOT_DIR}/output/resources/${NAMESPACE}"
for build_name in "${BUILD_NAMES[@]}"; do
  oc wait --for=jsonpath='{.status.registered}'=True "builds.shipwright.io/${build_name}" -n "${NAMESPACE}" --timeout=120s
done

# The Pipelines-provided account needs permission to push the resulting image.
oc policy add-role-to-user system:image-builder -z pipeline -n "${NAMESPACE}"
# The demo source-to-image strategy runs Kaniko as root with Linux capabilities.
# Scope this exception to the local CRC demo account; do not use it in production.
oc adm policy add-scc-to-user privileged -z pipeline -n "${NAMESPACE}"

# Shipwright's image-processing step only consumes credentials from a Tekton
# annotated dockerconfigjson secret. The OpenShift-generated dockercfg secret
# has a valid token but the legacy format and no Tekton annotation.
SA_SECRET="$(oc get sa pipeline -n "${NAMESPACE}" \
  -o jsonpath='{.imagePullSecrets[*].name} {.secrets[*].name}' \
  | tr ' ' '\n' | grep 'dockercfg' | head -n 1 || true)"
[[ -n "${SA_SECRET}" ]] || { echo "FAIL: no dockercfg secret found for ServiceAccount pipeline" >&2; exit 1; }
DOCKER_CONFIG="$(mktemp)"
trap 'rm -f "${DOCKER_CONFIG}"' EXIT
{
  printf '{"auths":'
  oc get secret "${SA_SECRET}" -n "${NAMESPACE}" -o jsonpath='{.data.\.dockercfg}' | base64 -d
  printf '}'
} > "${DOCKER_CONFIG}"
oc create secret generic "${PUSH_SECRET_NAME}" -n "${NAMESPACE}" \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson="${DOCKER_CONFIG}" \
  --dry-run=client -o yaml | oc apply -f -
oc annotate secret "${PUSH_SECRET_NAME}" -n "${NAMESPACE}" \
  "tekton.dev/docker-0=https://${INTERNAL_REGISTRY}" --overwrite
for index in "${!BUILD_NAMES[@]}"; do
  build_name="${BUILD_NAMES[${index}]}"
  image_stream_tag="${IMAGE_STREAM_TAGS[${index}]}"
  oc patch "builds.shipwright.io/${build_name}" -n "${NAMESPACE}" --type=merge \
    -p "{\"spec\":{\"output\":{\"pushSecret\":\"${PUSH_SECRET_NAME}\"}}}"

  BUILD_RUN="$(oc create -n "${NAMESPACE}" -o jsonpath='{.metadata.name}' -f - <<YAML
apiVersion: shipwright.io/v1beta1
kind: BuildRun
metadata:
  generateName: ${build_name}-
spec:
  build:
    name: ${build_name}
  serviceAccount: pipeline
YAML
)"

  echo "BuildRun: ${BUILD_RUN}"
  deadline=$((SECONDS + ${BUILD_TIMEOUT%s}))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    status="$(oc get "buildruns.shipwright.io/${BUILD_RUN}" -n "${NAMESPACE}" \
      -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}')"
    if [[ "${status}" == "True" ]]; then
      break
    fi
    if [[ "${status}" == "False" ]]; then
      oc get "buildruns.shipwright.io/${BUILD_RUN}" -n "${NAMESPACE}" \
        -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].reason}: {.status.conditions[?(@.type=="Succeeded")].message}{"\n"}' >&2
      exit 1
    fi
    sleep 10
  done
  [[ "${status}" == "True" ]] || { echo "FAIL: BuildRun timed out after ${BUILD_TIMEOUT}" >&2; exit 1; }
  oc get "buildruns.shipwright.io/${BUILD_RUN}" -n "${NAMESPACE}" \
    -o jsonpath="${build_name} digest={.status.output.digest}{\"\\n\"}"
  oc get imagestreamtag "${image_stream_tag}" -n "${NAMESPACE}" \
    -o jsonpath="${image_stream_tag} image={.image.dockerImageReference}{\"\\n\"}"
done
