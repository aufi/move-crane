#!/usr/bin/env bash
#
# 11-transfer-pvc-indirect.sh
# Migrate persistent volume state from source to target with crane transfer-pvc
# using INDIRECT transfer through S3-compatible cloud storage (instead of the
# direct rsync-over-route path used by 07-transfer-pvc.sh).
#
# Source uploads the data to an S3 bucket; target downloads it from there. No
# route/tunnel between the clusters is used. crane creates temporary Secrets from
# the local rclone.conf on both clusters.
#
# Steps:
#   1) ensure target namespace exists
#   2) scale down the source app (consistent copy, releases RWO volumes)
#   3) transfer each PVC via --cloud-storage
#
# Uses the merged kubeconfig (contexts: src, tgt) from 06-merge-kubeconfig.sh.
#
# Config via env:
#   NAMESPACE          namespace on both clusters (default: wordpress)
#   DEST_STORAGE_CLASS destination storage class (default: gp3-csi)
#   DEST_STORAGE_REQ   destination PVC size      (default: 1Gi)
#   RCLONE_CONF        path to rclone.conf       (default: <repo>/rclone.conf)
#   CLOUD_REMOTE       rclone remote name        (default: remote)
#   CLOUD_BUCKET       S3 bucket name            (required)
#   ENCRYPT            "true" to enable client-side encryption (default: false)
#   RUNS               how many times to run the transfer (default: 1). With
#                      RUNS=2 the transfer is repeated after the first pass and
#                      each run is timed. transfer-pvc tolerates an existing
#                      destination PVC, so the second run should copy only the
#                      delta and be faster. See findings/08.
#   KEEP_CLOUD_DATA    "true" passes --keep-cloud-data so the staged data is NOT
#                      purged from the bucket after each transfer. Combined with
#                      RUNS=2 this makes the second run's *upload* incremental too
#                      (rclone skips unchanged objects), not just the destination
#                      download — a bigger second-run speedup. Default: false
#                      (crane cleans the cloud staging after each transfer).
#   CRANE_BIN          migration binary to test (default: crane). Set to the
#                      downstream build (e.g. mta-ops) to run the same flow.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-wordpress}"
DEST_STORAGE_CLASS="${DEST_STORAGE_CLASS:-gp3-csi}"
DEST_STORAGE_REQ="${DEST_STORAGE_REQ:-1Gi}"
RCLONE_CONF="${RCLONE_CONF:-${REPO_DIR}/rclone.conf}"
CLOUD_REMOTE="${CLOUD_REMOTE:-remote}"
CLOUD_BUCKET="${CLOUD_BUCKET:-}"
ENCRYPT="${ENCRYPT:-false}"
RUNS="${RUNS:-1}"
KEEP_CLOUD_DATA="${KEEP_CLOUD_DATA:-false}"
CRANE_BIN="${CRANE_BIN:-crane}"
export KUBECONFIG="${REPO_DIR}/kubeconfig-merged"

PVCS=(mysql-pv-claim wordpress-pv-claim)
SRC_DEPLOYMENTS=(wordpress wordpress-mysql)

[[ -f "${RCLONE_CONF}" ]] || { echo "FAIL: rclone config not found: ${RCLONE_CONF}"; exit 1; }
[[ -n "${CLOUD_BUCKET}" ]] || { echo "FAIL: CLOUD_BUCKET is required (S3 bucket name)"; exit 1; }

echo "== contexts =="
echo "src -> $(oc --context src whoami --show-server)"
echo "tgt -> $(oc --context tgt whoami --show-server)"
echo "cloud: ${CLOUD_REMOTE}:${CLOUD_BUCKET} (rclone.conf: ${RCLONE_CONF}, encrypt: ${ENCRYPT})"

echo
echo "== 1) ensure target namespace '${NAMESPACE}' =="
oc --context tgt create namespace "${NAMESPACE}" --dry-run=client -o yaml | oc --context tgt apply -f -

echo
echo "== 2) scale down source app (release RWO volumes, consistent copy) =="
for d in "${SRC_DEPLOYMENTS[@]}"; do
  oc --context src -n "${NAMESPACE}" scale deployment "${d}" --replicas=0
done
for d in "${SRC_DEPLOYMENTS[@]}"; do
  echo "waiting for ${d} pods to terminate..."
  oc --context src -n "${NAMESPACE}" rollout status deployment "${d}" --timeout=120s || true
done
oc --context src -n "${NAMESPACE}" wait --for=delete pod -l app=wordpress --timeout=120s || true
echo "source pods:"
oc --context src -n "${NAMESPACE}" get pods 2>&1

transfer_all_pvcs() {  # $1 = run number (for logging)
  local run_no="$1"
  local extra_flags=()
  [[ "${ENCRYPT}" == "true" ]] && extra_flags+=(--encrypt)
  [[ "${KEEP_CLOUD_DATA}" == "true" ]] && extra_flags+=(--keep-cloud-data)
  for pvc in "${PVCS[@]}"; do
    echo
    echo "--- transfer-pvc (indirect): ${pvc} (run ${run_no}/${RUNS}) ---"
    set -x
    "${CRANE_BIN}" transfer-pvc \
      --source-context src \
      --destination-context tgt \
      --pvc-name "${pvc}:${pvc}" \
      --pvc-namespace "${NAMESPACE}:${NAMESPACE}" \
      --cloud-storage "${CLOUD_REMOTE}:${CLOUD_BUCKET}/${NAMESPACE}-${pvc}" \
      --rclone-config-file "${RCLONE_CONF}" \
      --dest-storage-class "${DEST_STORAGE_CLASS}" \
      --dest-storage-requests "${DEST_STORAGE_REQ}" \
      "${extra_flags[@]}" \
      --verify
    { set +x; } 2>/dev/null
  done
}

echo
echo "== 3) transfer PVCs via cloud storage (indirect), RUNS=${RUNS} =="
declare -a RUN_SECS
for ((r = 1; r <= RUNS; r++)); do
  echo
  echo "########## transfer run ${r}/${RUNS} ##########"
  start="$(date +%s.%N)"
  transfer_all_pvcs "${r}"
  end="$(date +%s.%N)"
  RUN_SECS[r]="$(awk "BEGIN{printf \"%.1f\", ${end}-${start}}")"
  echo ">> run ${r} duration: ${RUN_SECS[r]}s"
done

echo
echo "== target PVCs after transfer =="
oc --context tgt -n "${NAMESPACE}" get pvc 2>&1

echo
echo "== timing summary (indirect via cloud storage, encrypt=${ENCRYPT}, keep-cloud-data=${KEEP_CLOUD_DATA}) =="
for ((r = 1; r <= RUNS; r++)); do echo "  run ${r}: ${RUN_SECS[r]}s"; done
if ((RUNS >= 2)); then
  awk "BEGIN{ if (${RUN_SECS[2]}+0 < ${RUN_SECS[1]}+0) \
    printf \"OK: second run faster (%.1fs -> %.1fs); only the delta was staged/downloaded\n\", ${RUN_SECS[1]}, ${RUN_SECS[2]}; \
    else printf \"NOTE: second run not faster (%.1fs -> %.1fs)\n\", ${RUN_SECS[1]}, ${RUN_SECS[2]} }"
fi

echo
echo "OK: PVC data transferred to target via cloud storage (source left scaled to 0 = cutover)"
