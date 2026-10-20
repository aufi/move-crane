#!/usr/bin/env bash
# Create a local KubeVirt source cluster for Crane migration tests.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-kubevirt-source}"
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-docker}"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-8192}"
KUBEVIRT_VERSION="${KUBEVIRT_VERSION:-}"

for command in minikube kubectl curl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "FAIL: '${command}' is required" >&2
    exit 1
  fi
done

if [[ -z "${KUBEVIRT_VERSION}" ]]; then
  KUBEVIRT_VERSION="$(curl --fail --silent --show-error --location \
    https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)"
fi

if [[ -z "${KUBEVIRT_VERSION}" ]]; then
  echo "FAIL: could not determine a KubeVirt version" >&2
  exit 1
fi

echo "== start Minikube profile ${MINIKUBE_PROFILE} =="
minikube start \
  --profile "${MINIKUBE_PROFILE}" \
  --driver "${MINIKUBE_DRIVER}" \
  --cpus "${MINIKUBE_CPUS}" \
  --memory "${MINIKUBE_MEMORY}"

echo "== install KubeVirt ${KUBEVIRT_VERSION} =="
kubectl --context "${MINIKUBE_PROFILE}" apply -f \
  "https://github.com/kubevirt/kubevirt/releases/download/${KUBEVIRT_VERSION}/kubevirt-operator.yaml"
kubectl --context "${MINIKUBE_PROFILE}" wait \
  --for=condition=Established \
  --timeout=180s \
  crd/kubevirts.kubevirt.io
kubectl --context "${MINIKUBE_PROFILE}" apply -f "${ROOT_DIR}/manifests/kubevirt.yaml"
kubectl --context "${MINIKUBE_PROFILE}" -n kubevirt wait \
  --for=condition=Available \
  --timeout=600s \
  kubevirt/kubevirt
kubectl --context "${MINIKUBE_PROFILE}" wait \
  --for=condition=Established \
  --timeout=180s \
  crd/virtualmachines.kubevirt.io

echo
echo "KubeVirt is ready on kubectl context '${MINIKUBE_PROFILE}'."
echo "KubeVirt version: ${KUBEVIRT_VERSION}"
