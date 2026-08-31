#!/usr/bin/env bash
#
# 07-transfer-pvc.sh
# Migrate persistent volume state from source to target with crane transfer-pvc.
# transfer-pvc creates the destination PVC and rsyncs the data over an OpenShift
# route. See findings/02 for why this is a separate step from apply.
#
# Steps:
#   1) ensure target namespace exists
#   2) scale down the source app so the RWO volumes are released and the data is
#      consistent (MySQL especially must not be copied while running)
#   3) transfer each PVC (mysql-pv-claim, wordpress-pv-claim)
#
# Uses the merged kubeconfig (contexts: src, tgt) from 06-merge-kubeconfig.sh.
#
# Config via env:
#   NAMESPACE          namespace on both clusters (default: wordpress)
#   DEST_STORAGE_CLASS destination storage class (default: gp3-csi)
#   DEST_STORAGE_REQ   destination PVC size     (default: 1Gi)
#   RUNS               how many times to run the transfer (default: 1). With
#                      RUNS=2 the transfer is repeated after the first pass and
#                      each run is timed: transfer-pvc tolerates an existing
#                      destination PVC (Create ignores AlreadyExists) and rsync is
#                      incremental, so the second run should copy only changes and
#                      be faster. See findings/08.
#   CRANE_BIN          migration binary to test (default: crane). Set to the
#                      downstream build (e.g. mta-ops) to run the same flow.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-wordpress}"
DEST_STORAGE_CLASS="${DEST_STORAGE_CLASS:-gp3-csi}"
DEST_STORAGE_REQ="${DEST_STORAGE_REQ:-1Gi}"
RUNS="${RUNS:-1}"
CRANE_BIN="${CRANE_BIN:-crane}"
export KUBECONFIG="${REPO_DIR}/kubeconfig-merged"

PVCS=(mysql-pv-claim wordpress-pv-claim)
SRC_DEPLOYMENTS=(wordpress wordpress-mysql)

echo "== contexts =="
echo "src -> $(oc --context src whoami --show-server)"
echo "tgt -> $(oc --context tgt whoami --show-server)"

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
  for pvc in "${PVCS[@]}"; do
    echo
    echo "--- transfer-pvc: ${pvc} (run ${run_no}/${RUNS}) ---"
    set -x
    "${CRANE_BIN}" transfer-pvc \
      --source-context src \
      --destination-context tgt \
      --pvc-name "${pvc}:${pvc}" \
      --pvc-namespace "${NAMESPACE}:${NAMESPACE}" \
      --endpoint route \
      --dest-storage-class "${DEST_STORAGE_CLASS}" \
      --dest-storage-requests "${DEST_STORAGE_REQ}" \
      --verify
    { set +x; } 2>/dev/null
  done
}

echo
echo "== 3) transfer PVCs (direct rsync over route), RUNS=${RUNS} =="
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
echo "== timing summary (direct rsync) =="
for ((r = 1; r <= RUNS; r++)); do echo "  run ${r}: ${RUN_SECS[r]}s"; done
if ((RUNS >= 2)); then
  awk "BEGIN{ if (${RUN_SECS[2]}+0 < ${RUN_SECS[1]}+0) \
    printf \"OK: second run faster (%.1fs -> %.1fs); incremental rsync copied only changes\n\", ${RUN_SECS[1]}, ${RUN_SECS[2]}; \
    else printf \"NOTE: second run not faster (%.1fs -> %.1fs)\n\", ${RUN_SECS[1]}, ${RUN_SECS[2]} }"
fi

echo
echo "OK: PVC data transferred to target (source app left scaled to 0 = cutover)"
