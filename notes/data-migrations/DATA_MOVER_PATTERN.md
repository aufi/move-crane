# Data Mover Pattern: Migrating Large PVC Data with Minimal Outage

**Date:** 2026-07-20
**Status:** Recommended practice
**Related:** [STATEFUL_FLOW.md](STATEFUL_FLOW.md), [TRANSFER_PVC_RECOMMENDATIONS.md](TRANSFER_PVC_RECOMMENDATIONS.md), [RCLONE_IMPLEMENTATION_NOTES.md](RCLONE_IMPLEMENTATION_NOTES.md)

## The Problem

Migrating stateful Kubernetes workloads means moving persistent data — often tens or hundreds of gigabytes — between clusters. A naive approach (stop source, copy everything, start target) causes downtime proportional to data size. A 200GB PVC over a 100MB/s link takes ~35 minutes of pure transfer time. With setup overhead and verification, that easily becomes an hour-long outage.

The **data mover pattern** is an operational approach that reduces this outage to the time it takes to transfer only the final delta — typically seconds to a few minutes — regardless of total data size.

## Core Idea: Separate Bulk Transfer from Cutover

The pattern splits PVC migration into two distinct phases:

```
Phase 1: BACKGROUND SYNC (source workload still running)
  ├── Deploy a mover Pod alongside the source PVC
  ├── Copy bulk data to destination (hours, but no outage)
  ├── Optionally repeat to keep delta small
  └── Source application continues serving traffic

Phase 2: CUTOVER (brief outage window)
  ├── Quiesce source workload (scale to 0 or read-only)
  ├── Final delta sync (seconds to minutes)
  ├── Start target workload
  └── Redirect traffic to target
```

**Downtime = Phase 2 only**, which is bounded by the size of changes since the last sync, not by total PVC size.

This is the same approach used by database migration tools (pg_dump + streaming replication + failover), VM live migration (pre-copy memory pages + final stop-and-copy), and storage replication systems (initial seed + continuous journal replay).

## What Is a Data Mover Pod?

A data mover is a short-lived Kubernetes Pod that:

1. Mounts the source PVC (read-only when possible)
2. Connects to a destination (another PVC, cloud storage, or a remote mover Pod)
3. Runs a transfer tool (rsync, rclone, dd)
4. Exits when the copy is complete

The mover Pod is disposable — it carries no state of its own. If it fails, a new one can be created. If the transfer needs to resume, the transfer tool handles it (rsync's delta-transfer, rclone's checksum-based skip).

```
Source Cluster                         Destination Cluster
┌─────────────────────┐                ┌─────────────────────┐
│                     │                │                     │
│  ┌───────────────┐  │   TLS tunnel   │  ┌───────────────┐  │
│  │  Source PVC   │  │   (stunnel)    │  │   Dest PVC    │  │
│  │  /data (50GB) │  │                │  │  /data (empty)│  │
│  └───────┬───────┘  │                │  └───────┬───────┘  │
│          │ mount     │                │          │ mount     │
│  ┌───────┴───────┐  │                │  ┌───────┴───────┐  │
│  │  Mover Pod    │──┼───────────────►│  │  Mover Pod    │  │
│  │  (rsync       │  │  Ingress/Route │  │  (rsync       │  │
│  │   client)     │  │                │  │   server)     │  │
│  └───────────────┘  │                │  └───────────────┘  │
│                     │                │                     │
│  ┌───────────────┐  │                │                     │
│  │  App Pod      │  │                │                     │
│  │  (still       │  │                │                     │
│  │   running!)   │  │                │                     │
│  └───────────────┘  │                │                     │
└─────────────────────┘                └─────────────────────┘
```

The application Pod and the mover Pod both mount the same source PVC. The mover reads data and sends it to the destination. The application keeps serving traffic. This is safe because:

- The mover reads the PVC, it does not write to it.
- rsync and rclone handle files that change mid-transfer by detecting size/mtime differences and re-transferring on the next pass.
- The final cutover sync happens after the application is stopped, so no more changes occur.

## How Crane Uses This Pattern

### Step-by-Step Workflow

#### 1. Initial Sync (No Outage)

The user starts the first data transfer while the source workload is still running:

```bash
crane transfer-pvc \
  --source-context prod-cluster \
  --destination-context dr-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp
```

Crane creates mover Pods in both clusters, sets up a TLS tunnel between them, and starts rsync. This copies the bulk of the data. For a 200GB PVC, this takes a few hours depending on network bandwidth.

The source application keeps running. Users see no interruption.

#### 2. Repeat Sync to Shrink the Delta (Optional, No Outage)

If the initial sync took hours and the application kept writing data, the delta could be significant. Running the transfer again copies only what changed:

```bash
# Same command — rsync detects what already exists at the destination
crane transfer-pvc \
  --source-context prod-cluster \
  --destination-context dr-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp
```

Each repeat is faster because rsync uses delta-transfer — it checksums blocks and sends only the differences. After a few passes, the delta shrinks to whatever changed in the last few minutes.

For automated repetition, this can be wrapped in a Kubernetes CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-sync
  namespace: crane-system
spec:
  schedule: "*/30 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: crane
            image: quay.io/konveyor/crane:latest
            command:
            - crane
            - transfer-pvc
            - --source-context=prod-cluster
            - --destination-context=dr-cluster
            - --pvc-name=postgres-data
            - --pvc-namespace=myapp
          restartPolicy: OnFailure
```

#### 3. Quiesce and Final Sync (Outage Starts)

When the delta is small enough for the planned maintenance window, stop the source workload:

```bash
# Scale down source — OUTAGE STARTS HERE
kubectl scale deployment postgres --replicas=0 \
  -n myapp --context prod-cluster

# Wait for pods to terminate
kubectl wait --for=delete pod -l app=postgres \
  -n myapp --context prod-cluster --timeout=60s
```

Run the final sync. With the application stopped, no new data is being written, so this is a complete and consistent copy:

```bash
crane transfer-pvc \
  --source-context prod-cluster \
  --destination-context dr-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp
```

This final pass transfers only the delta since the last sync — typically seconds to a few minutes of data.

#### 4. Start Target and Redirect Traffic (Outage Ends)

```bash
# Start the workload on the target cluster
kubectl apply -f postgres-deployment.yaml --context dr-cluster

# Verify the application is running and data is intact
kubectl exec -n myapp -c postgres \
  $(kubectl get pod -n myapp -l app=postgres -o name --context dr-cluster) \
  --context dr-cluster -- psql -c 'SELECT count(*) FROM orders;'

# Redirect traffic (DNS, load balancer, etc.)
# OUTAGE ENDS HERE
```

**Total outage = time to scale down + final delta sync + target startup + traffic redirect**

For a 200GB PVC that was pre-synced, this is typically 2-10 minutes instead of 35+ minutes.

## Choosing the Right Transfer Engine

The pattern is engine-agnostic — the operational workflow is the same regardless of which tool runs inside the mover Pod. The choice of engine affects performance and capabilities:

| Scenario | Recommended Engine | Why |
|----------|-------------------|-----|
| Incremental sync (repeated passes) | **rsync** | Delta-transfer sends only changed blocks, not whole files |
| Initial bulk copy of many files | **rclone** | Multi-threaded (16 parallel transfers vs rsync's 1) |
| Transfer to/from cloud storage (S3, GCS) | **rclone** | 70+ cloud backends built in |
| Block storage (volumeMode: Block) | **dd** | rsync and rclone only work with filesystems |
| Single large file (database dump) | **rclone** | Multi-threaded streams within a single file |
| Slow or unreliable network | **rsync** with compression | `--compress` reduces traffic 40-70% |

For crane, the recommended default strategy is:

1. **First pass:** rclone (faster initial copy due to parallelism)
2. **Subsequent passes:** rsync (delta-transfer only sends changed blocks)
3. **Final cutover pass:** rsync (smallest possible delta, proven reliable)

See [RSYNC_RCLONE_RESTIC_COMPARISON.md](RSYNC_RCLONE_RESTIC_COMPARISON.md) for detailed technology comparison.

## Handling Common Scenarios

### Large StatefulSet (Multiple PVCs)

A StatefulSet with 3 replicas creates 3 PVCs. Transfer them in parallel:

```bash
# Parallel initial sync (all 3 PVCs at once)
for i in 0 1 2; do
  crane transfer-pvc \
    --source-context prod-cluster \
    --destination-context dr-cluster \
    --pvc-name data-kafka-$i \
    --pvc-namespace kafka &
done
wait

# Scale down source StatefulSet
kubectl scale statefulset kafka --replicas=0 -n kafka --context prod-cluster

# Parallel final sync
for i in 0 1 2; do
  crane transfer-pvc \
    --source-context prod-cluster \
    --destination-context dr-cluster \
    --pvc-name data-kafka-$i \
    --pvc-namespace kafka &
done
wait

# Start target StatefulSet
kubectl apply -f kafka-statefulset.yaml --context dr-cluster
```

**Outage = scale-down + final delta sync of all 3 PVCs (parallel) + startup**

### Cross-Cloud Migration (Different Storage Classes)

When migrating between cloud providers, storage classes differ. The PVC must exist at the destination with the correct storage class before the mover Pod can write to it:

```bash
# Create destination PVC with the target cloud's storage class
cat <<EOF | kubectl apply --context gcp-gke -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: myapp
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard-rwo
  resources:
    requests:
      storage: 200Gi
EOF

# Transfer data (same workflow as above)
crane transfer-pvc \
  --source-context aws-eks \
  --destination-context gcp-gke \
  --pvc-name postgres-data \
  --pvc-namespace myapp
```

The data mover pattern does not depend on storage class compatibility — it operates at the filesystem level (files and directories), not at the block level.

### Offline / Air-Gapped Transfer

When there is no direct network path between clusters, the pattern adapts to use intermediate storage:

```
Source Cluster → Mover Pod → Cloud Storage (S3) → Mover Pod → Destination Cluster
```

```bash
# Export PVC data to S3 (from source cluster)
crane transfer-pvc \
  --source-context prod-cluster \
  --engine=rclone \
  --pvc-name postgres-data \
  --rclone-dest=s3:migration-bucket/postgres-data/

# Import PVC data from S3 (to destination cluster)
crane transfer-pvc \
  --destination-context dr-cluster \
  --engine=rclone \
  --pvc-name postgres-data \
  --rclone-source=s3:migration-bucket/postgres-data/
```

See [PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md](PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md) for full proposal.

## How This Pattern Fits into the Crane Migration Workflow

The data mover pattern operates alongside crane's manifest migration workflow, not as a replacement:

```
                    ┌─────────────────────────────────────┐
                    │     Manifest Migration              │
                    │     (crane export/transform/apply)  │
                    │                                     │
                    │  1. crane export                    │
                    │  2. crane transform                 │
                    │  3. crane apply (creates empty PVCs)│
                    └──────────────┬──────────────────────┘
                                   │
    ┌──────────────────────────────┼──────────────────────────────┐
    │  Data Mover Pattern          │                              │
    │                              ▼                              │
    │  4. Background sync    ─── no outage ───                    │
    │  5. Repeat sync        ─── no outage ───                    │
    │  6. Quiesce source     ─── OUTAGE STARTS ───                │
    │  7. Final delta sync   ─── outage ───                       │
    │  8. Start target       ─── OUTAGE ENDS ───                  │
    └─────────────────────────────────────────────────────────────┘
```

Steps 1-3 handle Kubernetes resource definitions (Deployments, Services, ConfigMaps, PVCs). They create the "shape" of the application on the target cluster, including empty PVCs.

Steps 4-8 are the data mover pattern. They fill those empty PVCs with actual data, using the sync-then-cutover approach to minimize outage.

## Outage Time Comparison

| Approach | 50GB PVC | 200GB PVC | 500GB PVC |
|----------|----------|-----------|-----------|
| **Stop-and-copy** (no pre-sync) | ~10 min | ~35 min | ~1.5 hours |
| **Data mover** (1 pre-sync pass) | ~2-3 min | ~3-5 min | ~5-10 min |
| **Data mover** (CronJob, synced every 30 min) | ~30 sec | ~1-2 min | ~2-5 min |

Assumptions: 100 MB/s sustained transfer, ~1% data change rate per hour, plus 1-2 min overhead for scale-down and startup.

The data mover pattern makes outage time nearly independent of total data size.

## Relation to VolSync

VolSync, maintained by the backube organization, formalizes this pattern as a Kubernetes operator. It defines `ReplicationSource` and `ReplicationDestination` CRDs and manages mover Pods automatically, supporting scheduled replication with rsync, rclone, restic, and syncthing as transfer engines.

Crane borrows the same operational pattern but does not require an operator:

| Aspect | Crane | VolSync |
|--------|-------|---------|
| Use case | One-time migration | Continuous replication |
| Orchestrator | CLI command or Kubernetes Job | Operator (controller-runtime) |
| Scheduling | User-driven or CronJob | Built-in cron triggers |
| Movers | Same concept — short-lived Pods | Same concept |
| Requires installation | Just the crane binary | Operator + CRDs |
| Complexity | Low | High |

For migration (move data once, then done), crane's lightweight approach is sufficient. For ongoing data protection or DR replication, VolSync is the better fit.

See [BACKUBE_COMPARISON.md](BACKUBE_COMPARISON.md) for detailed VolSync analysis.

## Summary

The data mover pattern is a recommended operational practice for migrating Kubernetes PVC data with minimal outage:

1. **Pre-sync data in the background** while the source workload continues serving traffic.
2. **Repeat syncs** to keep the delta small (optionally via CronJob).
3. **Quiesce and do a final sync** during a short maintenance window.
4. **Start the target workload** and redirect traffic.

This decouples total data size from outage duration. A 500GB PVC migration has the same outage window as a 5GB one — only the background sync phase takes longer.

Crane implements this pattern through `crane transfer-pvc`, which creates mover Pods using rsync (today) and rclone (planned). The pattern works the same whether crane runs from a user's laptop, a Kubernetes Job, or a CI/CD pipeline.
