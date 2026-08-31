#!/usr/bin/env bash
#
# 01-check-versions.sh
# Verify the migration build under test (alpha, from $PATH) is available and
# reports the expected version. Idempotent, read-only. No cluster login needed.
#
# Config via env:
#   CRANE_BIN                migration binary to test (default: crane). Set to the
#                            downstream build (e.g. mta-ops) to check that one.
#   EXPECTED_CRANE_VERSION   version string to assert (default: v0.11.0-alpha.1).
#                            The strict assertion runs only when CRANE_BIN is
#                            'crane'; for a downstream binary the version is just
#                            printed (its version string differs).

set -euo pipefail

CRANE_BIN="${CRANE_BIN:-crane}"
EXPECTED_CRANE_VERSION="${EXPECTED_CRANE_VERSION:-v0.11.0-alpha.1}"

echo "== ${CRANE_BIN} binary =="
CRANE_PATH="$(command -v "${CRANE_BIN}" || true)"
if [[ -z "${CRANE_PATH}" ]]; then
  echo "FAIL: '${CRANE_BIN}' not found in \$PATH"
  exit 1
fi
echo "path: ${CRANE_PATH}"

echo
echo "== ${CRANE_BIN} version =="
"${CRANE_BIN}" version

echo
echo "== version check =="
if [[ "$(basename "${CRANE_BIN}")" != "crane" ]]; then
  echo "SKIP: downstream binary '${CRANE_BIN}', version printed above (no strict assertion)"
elif "${CRANE_BIN}" version | grep -q "Version: ${EXPECTED_CRANE_VERSION}"; then
  echo "OK: crane == ${EXPECTED_CRANE_VERSION}"
else
  echo "WARN: expected version ${EXPECTED_CRANE_VERSION}, see output above"
  exit 1
fi

echo
echo "== companion tools =="
for tool in oc kubectl; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf "%-8s %s\n" "$tool:" "$(command -v "$tool")"
  else
    printf "%-8s %s\n" "$tool:" "MISSING (not in \$PATH)"
  fi
done
