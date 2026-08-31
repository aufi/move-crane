#!/usr/bin/env bash
#
# 02-login-clusters.sh
# Log in to the source and target clusters and store each session in its own
# kubeconfig file (kubeconfig-src / kubeconfig-tgt) next to this repo.
# Keeping them separate lets later steps (e.g. transfer-pvc) reference both
# clusters at once without context switching.
#
# Idempotent: re-running just refreshes the sessions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_SRC="${SCRIPT_DIR}/kubeconfig-src"
KUBECONFIG_TGT="${SCRIPT_DIR}/kubeconfig-tgt"

# Cluster coordinates and credentials come from the environment so nothing
# sensitive is committed. Set them before running (e.g. export in your shell or
# source a local, git-ignored .env.clusters file):
#   SRC_SERVER / SRC_USER / SRC_PASS  and  TGT_SERVER / TGT_USER / TGT_PASS
SRC_SERVER="${SRC_SERVER:?set SRC_SERVER (source cluster API URL)}"
SRC_USER="${SRC_USER:-kubeadmin}"
SRC_PASS="${SRC_PASS:?set SRC_PASS (source cluster password)}"

TGT_SERVER="${TGT_SERVER:?set TGT_SERVER (target cluster API URL)}"
TGT_USER="${TGT_USER:-kubeadmin}"
TGT_PASS="${TGT_PASS:?set TGT_PASS (target cluster password)}"

echo "== login: source cluster =="
KUBECONFIG="${KUBECONFIG_SRC}" oc login \
  --server="${SRC_SERVER}" \
  -u "${SRC_USER}" -p "${SRC_PASS}" \
  --insecure-skip-tls-verify=true
echo "kubeconfig: ${KUBECONFIG_SRC}"

echo
echo "== login: target cluster =="
KUBECONFIG="${KUBECONFIG_TGT}" oc login \
  --server="${TGT_SERVER}" \
  -u "${TGT_USER}" -p "${TGT_PASS}" \
  --insecure-skip-tls-verify=true
echo "kubeconfig: ${KUBECONFIG_TGT}"

echo
echo "== verify: source =="
KUBECONFIG="${KUBECONFIG_SRC}" oc whoami
KUBECONFIG="${KUBECONFIG_SRC}" oc whoami --show-server

echo
echo "== verify: target =="
KUBECONFIG="${KUBECONFIG_TGT}" oc whoami
KUBECONFIG="${KUBECONFIG_TGT}" oc whoami --show-server

echo
echo "OK: both clusters reachable"
echo "Use: KUBECONFIG=${KUBECONFIG_SRC} oc ...   (source)"
echo "     KUBECONFIG=${KUBECONFIG_TGT} oc ...   (target)"
