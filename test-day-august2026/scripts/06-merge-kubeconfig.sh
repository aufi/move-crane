#!/usr/bin/env bash
#
# 06-merge-kubeconfig.sh
# Merge kubeconfig-src + kubeconfig-tgt into a single kubeconfig-merged with two
# clean context names: "src" and "tgt". crane transfer-pvc needs both the source
# and destination contexts in one kubeconfig (see findings/02).
#
# Idempotent: regenerates kubeconfig-merged from the two per-cluster files.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KC_SRC="${REPO_DIR}/kubeconfig-src"
KC_TGT="${REPO_DIR}/kubeconfig-tgt"
KC_MERGED="${REPO_DIR}/kubeconfig-merged"

for f in "${KC_SRC}" "${KC_TGT}"; do
  [[ -f "$f" ]] || { echo "FAIL: missing $f (run 02-login-clusters.sh first)"; exit 1; }
done

SRC_CTX="$(KUBECONFIG="${KC_SRC}" oc config current-context)"
TGT_CTX="$(KUBECONFIG="${KC_TGT}" oc config current-context)"

echo "== source context: ${SRC_CTX}"
echo "== target context: ${TGT_CTX}"

echo
echo "== flatten-merge into ${KC_MERGED} =="
KUBECONFIG="${KC_SRC}:${KC_TGT}" oc config view --flatten > "${KC_MERGED}"
chmod 600 "${KC_MERGED}"

echo
echo "== rename contexts to src / tgt =="
# Remove any pre-existing src/tgt from earlier runs, then (re)create them.
KUBECONFIG="${KC_MERGED}" oc config delete-context src >/dev/null 2>&1 || true
KUBECONFIG="${KC_MERGED}" oc config delete-context tgt >/dev/null 2>&1 || true
KUBECONFIG="${KC_MERGED}" oc config rename-context "${SRC_CTX}" src
KUBECONFIG="${KC_MERGED}" oc config rename-context "${TGT_CTX}" tgt
KUBECONFIG="${KC_MERGED}" oc config use-context src >/dev/null

echo
echo "== verify =="
echo "src -> $(KUBECONFIG="${KC_MERGED}" oc --context src whoami --show-server)"
echo "tgt -> $(KUBECONFIG="${KC_MERGED}" oc --context tgt whoami --show-server)"

echo
echo "OK: merged kubeconfig ready: ${KC_MERGED}"
echo "Use: KUBECONFIG=${KC_MERGED} oc --context src|tgt ..."
