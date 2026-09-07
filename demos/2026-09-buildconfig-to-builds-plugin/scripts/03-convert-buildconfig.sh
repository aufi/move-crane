#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-demo-buildconfig}"
CRANE_BIN="${CRANE_BIN:-mta-ops}"
EXPORT_DIR="${ROOT_DIR}/export"
TRANSFORM_DIR="${ROOT_DIR}/transform"
OUTPUT_DIR="${ROOT_DIR}/output"
OPTIONAL_FLAGS='{"imagestream-mapping":"openshift/nodejs:18-ubi8=registry.access.redhat.com/ubi9/nodejs-18:latest"}'

command -v "${CRANE_BIN}" >/dev/null || { echo "FAIL: CRANE_BIN is not on PATH: ${CRANE_BIN}. Run scripts/01-check-prerequisites.sh first." >&2; exit 1; }

oc create namespace "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
oc apply -n "${NAMESPACE}" -f "${ROOT_DIR}/manifests/buildconfig.yaml"
oc apply -n "${NAMESPACE}" -f "${ROOT_DIR}/manifests/buildconfig-nodejs-webhook.yaml"
oc apply -n "${NAMESPACE}" -f "${ROOT_DIR}/manifests/buildconfig-ruby-docker.yaml"

"${CRANE_BIN}" export -n "${NAMESPACE}" \
  --include-gk build.openshift.io/BuildConfig \
  --export-dir "${EXPORT_DIR}" --overwrite
"${CRANE_BIN}" transform BuildConfigPlugin \
  --export-dir "${EXPORT_DIR}" --transform-dir "${TRANSFORM_DIR}" \
  --optional-flags "${OPTIONAL_FLAGS}" --overwrite
"${CRANE_BIN}" apply --transform-dir "${TRANSFORM_DIR}" --output-dir "${OUTPUT_DIR}" --overwrite

for build_name in sample-nodejs sample-nodejs-webhook ruby-hello-world-docker; do
  BUILD_FILE="$(grep -rl "^  name: ${build_name}$" "${OUTPUT_DIR}/resources" | head -n 1)"
  [[ -n "${BUILD_FILE}" ]] || { echo "FAIL: plugin did not generate Shipwright Build ${build_name}" >&2; exit 1; }
  echo "Generated Build: ${BUILD_FILE}"
done
echo "Inspect conversion warnings before applying the output."
