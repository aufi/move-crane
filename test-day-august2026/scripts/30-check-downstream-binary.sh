#!/usr/bin/env bash
#
# 30-check-downstream-binary.sh
# SEPARATE check for the DOWNSTREAM migration binary (e.g. mta-ops), verifying the
# ways it is expected to differ from upstream crane. This does NOT run the data
# migration itself (that is the same flow — run scripts 01/05/07/08/... with
# CRANE_BIN=<binary>); it asserts the downstream-specific contract:
#
#   A) Command surface — ONLY these subcommands are offered:
#        export, transform, apply, validate, transfer-pvc
#      and the upstream-only extras are ABSENT:
#        plugin-manager, convert, skopeo-sync-gen, tunnel-api
#   B) Embedded transform plugins — Kubernetes, OpenShift and Builds/Shipwright are
#      all built in (no external --plugin-dir; in particular Shipwright must NOT be
#      added externally). Enumerated from a `transform` run in a clean CWD.
#   C) Transfer image — the transfer-pvc default container image is a downstream
#      image NOT hosted on quay.io. Its name is echoed to the log.
#
# The checks are written against the DOWNSTREAM expectation. Running this against
# upstream `crane` is expected to FAIL every check (crane offers the extra
# commands, embeds only the Kubernetes plugin, and defaults to a quay.io image) —
# that failure is the documented upstream/downstream diff, not a script bug.
#
# Config via env:
#   CRANE_BIN   binary to check (default: crane). Set to mta-ops once available:
#                 CRANE_BIN=mta-ops scripts/30-check-downstream-binary.sh
#
# Read-only, no cluster access needed.

set -uo pipefail

CRANE_BIN="${CRANE_BIN:-crane}"

# Downstream contract.
REQUIRED_CMDS=(export transform apply validate transfer-pvc)
FORBIDDEN_CMDS=(plugin-manager convert skopeo-sync-gen tunnel-api)
# Embedded plugin categories: label -> case-insensitive regex over plugin names.
PLUGIN_LABELS=(Kubernetes OpenShift "Builds/Shipwright")
PLUGIN_REGEX=("kubernetes" "openshift" "shipwright|build")

fail=0
note() { echo "  $*"; }

CRANE_PATH="$(command -v "${CRANE_BIN}" || true)"
if [[ -z "${CRANE_PATH}" ]]; then
  echo "FAIL: '${CRANE_BIN}' not found in \$PATH"
  exit 1
fi
echo "== downstream binary check: ${CRANE_BIN} (${CRANE_PATH}) =="

# ---------------------------------------------------------------------------
# A) Command surface
# ---------------------------------------------------------------------------
echo
echo "== A) available commands =="
HELP_OUT="$("${CRANE_BIN}" --help 2>&1)"
# Grab the command names from the "Available Commands:" block (first token per line).
CMDS="$(printf '%s\n' "${HELP_OUT}" \
  | sed -n '/Available Commands:/,/^[A-Za-z].*:$/p' \
  | grep -E '^[[:space:]]+[a-z]' \
  | awk '{print $1}')"
# Ignore cobra's built-in helpers that every binary has.
has_cmd() { grep -qxF "$1" <<<"${CMDS}"; }

echo "reported commands: $(echo ${CMDS} | tr '\n' ' ')"
echo "-- required (must be present):"
for c in "${REQUIRED_CMDS[@]}"; do
  if has_cmd "${c}"; then note "OK    present: ${c}"; else note "FAIL  missing: ${c}"; fail=1; fi
done
echo "-- upstream-only (must be absent downstream):"
for c in "${FORBIDDEN_CMDS[@]}"; do
  if has_cmd "${c}"; then note "FAIL  present (should be absent): ${c}"; fail=1; else note "OK    absent: ${c}"; fi
done

# ---------------------------------------------------------------------------
# B) Embedded transform plugins (no external plugin dir)
# ---------------------------------------------------------------------------
echo
echo "== B) embedded transform plugins (no external --plugin-dir) =="
# `transform` picks up ./plugins relative to the CWD, so run it from a clean temp
# dir with an empty plugin-dir to see ONLY what is embedded in the binary.
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/export/resources/demo-ns" "${WORK}/noplugins"
cat > "${WORK}/export/resources/demo-ns/ConfigMap_v1_demo-ns_demo.yaml" <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo
  namespace: demo-ns
data:
  foo: bar
YAML

TRANSFORM_OUT="$(cd "${WORK}" && "${CRANE_BIN}" transform \
  --export-dir "${WORK}/export" \
  --transform-dir "${WORK}/transform" \
  --plugin-dir "${WORK}/noplugins" \
  --overwrite 2>&1)"

# Default stages are created for every discovered plugin; parse their names.
EMBEDDED="$(printf '%s\n' "${TRANSFORM_OUT}" \
  | grep -oE 'Creating default stage for plugin: [A-Za-z0-9_.-]+' \
  | sed 's/.*: //' | sort -u)"
echo "embedded plugins: $(echo ${EMBEDDED} | tr '\n' ' ')"
for i in "${!PLUGIN_LABELS[@]}"; do
  label="${PLUGIN_LABELS[$i]}"; rx="${PLUGIN_REGEX[$i]}"
  if grep -qiE "${rx}" <<<"${EMBEDDED}"; then
    note "OK    embedded: ${label} ($(grep -iE "${rx}" <<<"${EMBEDDED}" | tr '\n' ' '))"
  else
    note "FAIL  not embedded: ${label}"; fail=1
  fi
done

# ---------------------------------------------------------------------------
# C) Transfer image (not on quay.io)
# ---------------------------------------------------------------------------
echo
echo "== C) transfer-pvc default image =="
PVC_HELP="$("${CRANE_BIN}" transfer-pvc --help 2>&1)"
XFER_IMAGE="$(printf '%s\n' "${PVC_HELP}" \
  | grep -- '--source-image' \
  | grep -oE 'default "[^"]+"' | sed 's/default "//; s/"$//')"
[[ -n "${XFER_IMAGE}" ]] || XFER_IMAGE="$(printf '%s\n' "${PVC_HELP}" \
  | grep -- '--destination-image' \
  | grep -oE 'default "[^"]+"' | sed 's/default "//; s/"$//')"
echo "transfer image (default): ${XFER_IMAGE:-<not found>}"
if [[ -z "${XFER_IMAGE}" ]]; then
  note "FAIL  could not determine transfer image default"; fail=1
elif grep -qi 'quay\.io' <<<"${XFER_IMAGE}"; then
  note "FAIL  transfer image is on quay.io (${XFER_IMAGE}) — expected a downstream registry"; fail=1
else
  note "OK    transfer image is off quay.io: ${XFER_IMAGE}"
fi

# ---------------------------------------------------------------------------
echo
if [[ "${fail}" -eq 0 ]]; then
  echo "RESULT: PASS — '${CRANE_BIN}' matches the downstream contract"
  exit 0
else
  echo "RESULT: FAIL — '${CRANE_BIN}' does not match the downstream contract (see above)"
  echo "         (this is EXPECTED when checking upstream 'crane')"
  exit 1
fi
