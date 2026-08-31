#!/usr/bin/env bash
#
# 04-validate-app.sh
# Validate a deployed WordPress instance (HTTP 200 + expected sample content),
# reusing the upstream test-app/wordpress/validate.sh. Works against any cluster
# by pointing kubectl at the right kubeconfig + namespace and extracting the
# install job's seed ID for an exact-instance check.
#
# Config via env:
#   NAMESPACE   namespace of the app (default: wordpress)
#   KUBECONFIG  defaults to repo kubeconfig-src
#   PORT        local port-forward port (default: 18080)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${REPO_DIR}/test-app/wordpress"
NAMESPACE="${NAMESPACE:-wordpress}"
export KUBECONFIG="${KUBECONFIG:-${REPO_DIR}/kubeconfig-src}"

echo "== context =="
echo "kubeconfig: ${KUBECONFIG}"
echo "server:     $(oc whoami --show-server)"
echo "namespace:  ${NAMESPACE}"

# Pin the namespace on the current context so the upstream validate.sh (which
# uses the active namespace) targets the right project.
oc config set-context --current --namespace="${NAMESPACE}" >/dev/null

echo
echo "== resolve WordPress seed ID =="
# Priority: explicit WORDPRESS_SEED_ID from the environment (needed on the target,
# where crane suspends the install Job so its logs are unavailable), otherwise
# extract it from the install Job logs (works on the source).
SEED_ID="${WORDPRESS_SEED_ID:-}"
if [[ -n "${SEED_ID}" ]]; then
  echo "seed id: ${SEED_ID} (from environment)"
else
  SEED_ID="$(oc logs job/wordpress-install -n "${NAMESPACE}" 2>/dev/null \
    | grep 'WORDPRESS_SEED_ID=' | cut -d= -f2 | tr -d '[:space:]' || true)"
  if [[ -n "${SEED_ID}" ]]; then
    echo "seed id: ${SEED_ID} (from install Job logs)"
  else
    echo "seed id: (not found — exact-instance check will be skipped)"
  fi
fi

echo
echo "== run upstream validate.sh =="
WORDPRESS_SEED_ID="${SEED_ID}" PORT="${PORT:-18080}" bash "${APP_DIR}/validate.sh"
