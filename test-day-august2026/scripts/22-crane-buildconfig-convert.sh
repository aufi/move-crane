#!/usr/bin/env bash
#
# 22-crane-buildconfig-convert.sh
# Convert the source BuildConfig to a Shipwright Build with the crane pipeline and
# the crane-plugin-buildconfig-to-shipwright plugin. Non-destructive (reads the
# source, writes only local dirs).
#
#   export  : crane export -n <ns> --include-gk build.openshift.io/BuildConfig
#             (only the relevant resource is pulled, not the whole namespace)
#   transform: crane transform BuildConfigPlugin  (plugin invoked by name)
#   apply   : crane apply -> output-bc/output.yaml
#
# The plugin has no live cluster access, so ImageStream references are resolved
# offline via --optional-flags:
#   - imagestream-mapping resolves the S2I builder ImageStreamTag to a concrete,
#     publicly pullable UBI image.
#   - the output ImageStreamTag is left to the plugin's internal-registry fallback,
#     which resolves to image-registry.openshift-image-registry.svc:5000/<ns>/<name>
#     — i.e. the TARGET cluster's own internal registry once the Build is applied
#     there. No registry-mapping needed.
#
# Config via env:
#   NAMESPACE       source/target namespace   (default: bc-demo)
#   BUILDER_IMAGE   concrete S2I builder image (default: UBI9 nodejs-20)
#   OPTIONAL_FLAGS  crane transform --optional-flags JSON. If unset, a default is
#                   built for the S2I nodejs case (imagestream-mapping for the
#                   builder). Override it for the Docker/buildah case, e.g.:
#                     OPTIONAL_FLAGS='{"default-build-strategy":"docker=buildah-strategy-managed-push","insecure-registries":"image-registry.openshift-image-registry.svc:5000"}'
#   WORK_SUFFIX     suffix for the generated dirs (default: -bc). Use a distinct
#                   suffix (e.g. -bc-docker) to keep multiple cases side by side.
#   PLUGIN_SRC      plugin source checkout    (default: ./crane-plugin-buildconfig-to-shipwright-sources)
#   CRANE_BIN       migration binary to test  (default: crane). Set to the
#                   downstream build (e.g. mta-ops) to run the same conversion.
#   SKIP_PLUGIN_BUILD  "true" skips building/adding the external BuildConfig
#                   plugin and drops --plugin-dir, so the conversion relies on the
#                   binary's EMBEDDED Builds/Shipwright plugin. Use this for the
#                   downstream build (mta-ops), where Shipwright is embedded and
#                   must not be added externally. Default: false (upstream crane
#                   has no embedded BuildConfig plugin, so it is built + added).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-bc-demo}"
BUILDER_IMAGE="${BUILDER_IMAGE:-registry.access.redhat.com/ubi9/nodejs-20:latest}"
PLUGIN_SRC="${PLUGIN_SRC:-${REPO_DIR}/crane-plugin-buildconfig-to-shipwright-sources}"
PLUGIN_DIR="${REPO_DIR}/plugins"
CRANE_BIN="${CRANE_BIN:-crane}"
SKIP_PLUGIN_BUILD="${SKIP_PLUGIN_BUILD:-false}"
WORK_SUFFIX="${WORK_SUFFIX:--bc}"
EXPORT_DIR="${REPO_DIR}/export${WORK_SUFFIX}"
TRANSFORM_DIR="${REPO_DIR}/transform${WORK_SUFFIX}"
OUTPUT_DIR="${REPO_DIR}/output${WORK_SUFFIX}"
KC_SRC="${REPO_DIR}/kubeconfig-src"

# Default optional-flags: resolve the S2I builder ImageStreamTag to a concrete
# image. Override via the OPTIONAL_FLAGS env for other cases (e.g. Docker/buildah).
# (Set separately rather than via ${VAR:-{...}} — inline JSON braces confuse the
# bash default-value parser and append a stray '}'.)
if [[ -z "${OPTIONAL_FLAGS:-}" ]]; then
  IMAGESTREAM_MAPPING="openshift/nodejs:20-ubi9=${BUILDER_IMAGE}"
  OPTIONAL_FLAGS="{\"imagestream-mapping\":\"${IMAGESTREAM_MAPPING}\"}"
fi

if [[ "${SKIP_PLUGIN_BUILD}" == "true" ]]; then
  echo "== 1) skip external plugin build (relying on ${CRANE_BIN}'s embedded Builds/Shipwright plugin) =="
else
  echo "== 1) build the plugin =="
  mkdir -p "${PLUGIN_DIR}"
  ( cd "${PLUGIN_SRC}" && GOTOOLCHAIN=auto go build -o "${PLUGIN_DIR}/crane-plugin-buildconfig-to-shipwright" . )
  echo "plugin: $(ls -la "${PLUGIN_DIR}/crane-plugin-buildconfig-to-shipwright" | awk '{print $5, $NF}')"
fi

echo
echo "== 2) crane export (only build.openshift.io/BuildConfig via --include-gk) =="
set -x
"${CRANE_BIN}" export \
  --kubeconfig "${KC_SRC}" \
  -n "${NAMESPACE}" \
  --include-gk build.openshift.io/BuildConfig \
  --export-dir "${EXPORT_DIR}" \
  --overwrite
{ set +x; } 2>/dev/null
echo "exported resources:"
find "${EXPORT_DIR}/resources" -type f 2>/dev/null | sed 's#.*/resources/#  #'

echo
echo "== 3) crane transform BuildConfigPlugin =="
# With SKIP_PLUGIN_BUILD=true, drop --plugin-dir so the embedded plugin is used.
plugin_dir_flag=(--plugin-dir "${PLUGIN_DIR}")
[[ "${SKIP_PLUGIN_BUILD}" == "true" ]] && plugin_dir_flag=()
set -x
"${CRANE_BIN}" transform BuildConfigPlugin \
  --export-dir "${EXPORT_DIR}" \
  --transform-dir "${TRANSFORM_DIR}" \
  "${plugin_dir_flag[@]}" \
  --optional-flags "${OPTIONAL_FLAGS}" \
  --overwrite
{ set +x; } 2>/dev/null

echo
echo "== 4) crane apply =="
set -x
"${CRANE_BIN}" apply \
  --transform-dir "${TRANSFORM_DIR}" \
  --output-dir "${OUTPUT_DIR}" \
  --overwrite
{ set +x; } 2>/dev/null

echo
echo "== generated Shipwright Build =="
grep -rl "shipwright.io/v1beta1" "${OUTPUT_DIR}" 2>/dev/null | while read -r f; do
  echo "--- ${f} ---"; cat "${f}"
done

echo
echo "OK: BuildConfig converted to a Shipwright Build in ${OUTPUT_DIR}."
