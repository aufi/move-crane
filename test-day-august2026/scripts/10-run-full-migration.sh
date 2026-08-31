#!/usr/bin/env bash
#
# 10-run-full-migration.sh
# Orchestrate a complete stateful migration end to end, calling the numbered
# step scripts in order. Every sub-step echoes the exact commands it runs, so the
# combined output is a full, auditable transcript of the migration.
#
# Intended to be captured with the `script` utility for a verbatim terminal
# transcript, e.g.:
#   script -q -e -c scripts/10-run-full-migration.sh runs/migration-$(date +%Y%m%d-%H%M%S).log
#
# Assumes: 02-login-clusters.sh has been run (kubeconfig-src / kubeconfig-tgt
# exist) and the app already exists on the source (03-deploy-app-src.sh).
#
# Config via env:
#   NAMESPACE        namespace on both clusters (default: wordpress)
#   TRANSFER_SCRIPT  which PVC-transfer step to run (default: 07-transfer-pvc.sh
#                    for direct/route transfer; use 11-transfer-pvc-indirect.sh
#                    for indirect transfer via S3 cloud storage)
#   CRANE_BIN        migration binary to test (default: crane). Inherited by every
#                    sub-step, so `CRANE_BIN=mta-ops scripts/10-...` runs the whole
#                    flow against the downstream build.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="${REPO_DIR}/scripts"
NAMESPACE="${NAMESPACE:-wordpress}"
TRANSFER_SCRIPT="${TRANSFER_SCRIPT:-07-transfer-pvc.sh}"
CRANE_BIN="${CRANE_BIN:-crane}"
export CRANE_BIN
KC_SRC="${REPO_DIR}/kubeconfig-src"
KC_TGT="${REPO_DIR}/kubeconfig-tgt"

banner() {
  echo
  echo "############################################################"
  echo "# $*"
  echo "############################################################"
  echo
}

echo "Full migration run — $(date -Is)"
echo "namespace: ${NAMESPACE}"
echo "binary:    ${CRANE_BIN}"

# --- STEP 0: make sure the source is a live, valid app and capture its seed ----
banner "STEP 0a: ensure source app is running (scale to 1)"
KUBECONFIG="${KC_SRC}" oc -n "${NAMESPACE}" scale deployment wordpress wordpress-mysql --replicas=1
KUBECONFIG="${KC_SRC}" oc -n "${NAMESPACE}" rollout status deployment/wordpress-mysql --timeout=300s
KUBECONFIG="${KC_SRC}" oc -n "${NAMESPACE}" rollout status deployment/wordpress --timeout=300s

banner "STEP 0b: capture sample-post seed id from the source install Job"
SEED_ID="$(KUBECONFIG="${KC_SRC}" oc -n "${NAMESPACE}" logs job/wordpress-install 2>/dev/null \
  | grep 'WORDPRESS_SEED_ID=' | cut -d= -f2 | tr -d '[:space:]' || true)"
echo "source seed id: ${SEED_ID:-<unknown>}"

banner "STEP 0c: validate the SOURCE app"
KUBECONFIG="${KC_SRC}" WORDPRESS_SEED_ID="${SEED_ID}" PORT=18080 bash "${SCRIPTS}/04-validate-app.sh"

# --- STEP 1: non-destructive crane pipeline ------------------------------------
banner "STEP 1: crane export -> transform -> apply (source)"
bash "${SCRIPTS}/05-crane-export-transform-apply.sh"

# --- STEP 2: merge kubeconfigs for transfer-pvc --------------------------------
banner "STEP 2: merge kubeconfigs (contexts src / tgt)"
bash "${SCRIPTS}/06-merge-kubeconfig.sh"

# --- STEP 3: migrate PVC data --------------------------------------------------
banner "STEP 3: transfer-pvc via ${TRANSFER_SCRIPT} (scales source down, copies both PVCs)"
bash "${SCRIPTS}/${TRANSFER_SCRIPT}"

# --- STEP 4: deploy migrated manifests to target -------------------------------
banner "STEP 4: apply crane output to the TARGET"
bash "${SCRIPTS}/08-apply-target.sh"

# --- STEP 5: validate on target (exact seed carried from source) ---------------
banner "STEP 5: validate the TARGET app (exact seed #${SEED_ID:-?})"
KUBECONFIG="${KC_TGT}" WORDPRESS_SEED_ID="${SEED_ID}" PORT=18081 bash "${SCRIPTS}/04-validate-app.sh"

banner "MIGRATION COMPLETE"
echo "Source seed #${SEED_ID:-?} served by the target => data migrated intact."
echo "Finished — $(date -Is)"
