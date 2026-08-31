#!/usr/bin/env bash
#
# 03-deploy-app-src.sh
# Deploy the stateful WordPress test app into a namespace on the SOURCE cluster.
# Uses the locally saved manifests in test-app/wordpress (kustomize + secretGenerator).
#
# Idempotent: reuses an existing .env and re-applies the kustomize overlay.
#
# Config via env:
#   NAMESPACE   target namespace (default: wordpress)
#   KUBECONFIG  defaults to repo kubeconfig-src

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${REPO_DIR}/test-app/wordpress"
NAMESPACE="${NAMESPACE:-wordpress}"
export KUBECONFIG="${KUBECONFIG:-${REPO_DIR}/kubeconfig-src}"

echo "== context =="
echo "kubeconfig: ${KUBECONFIG}"
echo "server:     $(oc whoami --show-server)"
echo "namespace:  ${NAMESPACE}"
echo "app dir:    ${APP_DIR}"

echo
echo "== ensure namespace =="
oc create namespace "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

echo
echo "== seed secrets (.env) =="
ENV_FILE="${APP_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  umask 077
  cat > "${ENV_FILE}" <<EOF
MYSQL_ROOT_PASSWORD=$(openssl rand -base64 16)
MYSQL_WORDPRESS_PASSWORD=$(openssl rand -base64 16)
WORDPRESS_ADMIN_PASSWORD=$(openssl rand -base64 12)
EOF
  echo "created ${ENV_FILE}"
else
  echo "reusing existing ${ENV_FILE}"
fi
chmod 600 "${ENV_FILE}"

echo
echo "== apply kustomize overlay =="
oc apply -k "${APP_DIR}" -n "${NAMESPACE}"

echo
echo "== wait for readiness =="
oc wait --for=condition=available --timeout=300s deployment/wordpress-mysql -n "${NAMESPACE}"
oc wait --for=condition=available --timeout=300s deployment/wordpress       -n "${NAMESPACE}"
oc wait --for=condition=complete  --timeout=300s job/wordpress-install       -n "${NAMESPACE}"

echo
echo "== resources =="
oc get all,pvc,secret,configmap -n "${NAMESPACE}"

echo
echo "OK: WordPress deployed to '${NAMESPACE}' on $(oc whoami --show-server)"
