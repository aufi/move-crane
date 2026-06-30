# Backube Projects Comparison: pvc-transfer vs VolSync

**Date:** 2026-06-30  
**Research Focus:** Understanding backube's approach to PVC data transfer and what can work without an operator

## Executive Summary

**backube** is a GitHub organization focused on Kubernetes storage tools. Their two main projects for PVC data movement are:

1. **pvc-transfer** - Go library (building blocks, NO operator)
2. **VolSync** - Kubernetes operator (continuous replication, REQUIRES operator)

**Key Finding:** Crane currently uses **pvc-transfer** (the library), which is the right choice for a CLI tool. However, **VolSync's "mover" architecture** offers valuable insights for improving crane's transfer capabilities.

---

## 1. Repository Comparison

| Aspect | pvc-transfer | VolSync |
|--------|-------------|---------|
| **Type** | Go library | Kubernetes operator |
| **License** | Apache 2.0 | AGPL 3.0 (API: Apache 2.0) |
| **Stars** | 4 | 982 |
| **Status** | Inactive (last update Aug 2022) | Active (v0.16.0, June 2026) |
| **Maturity** | Unknown | Alpha |
| **Requires Operator** | ❌ NO | ✅ YES |
| **Use Case** | One-time migrations | Continuous replication & backup |
| **Who Uses It** | Crane, other migration tools | Production data protection |

---

## 2. pvc-transfer (Library)

### What It Is

A **Go library** providing reusable components for PVC data transfer. It's what **crane currently uses**.

```
github.com/backube/pvc-transfer v0.0.0-20220810121213-5f9e29a1f6e5
```

### Architecture

```
pvc-transfer/
├── endpoint/          # Endpoint abstractions (Ingress, Route)
│   ├── ingress/      # Nginx Ingress endpoint
│   └── route/        # OpenShift Route endpoint
├── transfer/         # Transfer orchestration
│   └── rsync/        # rsync-based transfer
├── transport/        # Transport layer
│   └── stunnel/      # TLS tunnel via stunnel
└── internal/utils/   # Utilities
```

### What crane Uses From It

From `crane/cmd/transfer-pvc/transfer-pvc.go`:

```go
import (
    "github.com/backube/pvc-transfer/endpoint"
    ingressendpoint "github.com/backube/pvc-transfer/endpoint/ingress"
    routeendpoint "github.com/backube/pvc-transfer/endpoint/route"
    "github.com/backube/pvc-transfer/transfer"
    rsynctransfer "github.com/backube/pvc-transfer/transfer/rsync"
    "github.com/backube/pvc-transfer/transport"
    stunneltransport "github.com/backube/pvc-transfer/transport/stunnel"
)
```

**Crane uses:**
1. **Endpoint abstraction** - Creates Ingress/Route for destination
2. **rsync transfer** - Pod templates and rsync options
3. **stunnel transport** - TLS tunnel setup between clusters
4. **Transfer orchestration** - Coordinates the overall process

### How It Works (as used by crane)

```
1. Destination:
   - Create endpoint (Route/Ingress)
   - Create stunnel server Pod (TLS tunnel)
   - Create rsync server Pod (receives data)

2. Source:
   - Create stunnel client Pod
   - Create rsync client Pod (sends data)
   
3. Transfer:
   - rsync client → stunnel client → stunnel server → rsync server
   - Data flows: source PVC → destination PVC
```

### Issues with pvc-transfer

| Issue | Impact | Severity |
|-------|--------|----------|
| **Unmaintained** | Last commit Aug 2022 (4+ years old) | 🔴 Critical |
| **No releases** | Using commit hash, no semantic versioning | 🟡 High |
| **No updates** | Missing modern features (resume, bandwidth limit) | 🟡 High |
| **Limited scope** | Only rsync, no rclone/restic support | 🟠 Medium |
| **Basic options** | Minimal rsync configuration | 🟠 Medium |

**Recommendation:** Fork or vendor pvc-transfer, as discussed in TRANSFER_PVC_RECOMMENDATIONS.md

---

## 3. VolSync (Operator)

### What It Is

A **Kubernetes operator** for continuous asynchronous PVC replication and backup.

**Latest version:** v0.16.0 (June 2026)  
**Maturity:** Alpha  
**License:** AGPL 3.0 (operator), Apache 2.0 (CRD APIs)

### Architecture

```
┌─────────────────────────────────────────────────┐
│  VolSync Operator (volsync-system namespace)   │
│                                                 │
│  Reconciles:                                    │
│  - ReplicationSource                            │
│  - ReplicationDestination                       │
│                                                 │
│  Creates "Mover" Pods in user namespaces        │
└─────────────────────────────────────────────────┘
                    │
                    ├─────────────┬─────────────┬─────────────┐
                    ▼             ▼             ▼             ▼
              ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌──────────┐
              │  Rsync  │   │ Rclone  │   │ Restic  │   │Syncthing │
              │  Mover  │   │  Mover  │   │  Mover  │   │  Mover   │
              └─────────┘   └─────────┘   └─────────┘   └──────────┘
```

### Supported "Movers" (Replication Methods)

VolSync supports **5 different movers**:

| Mover | Use Case | Direction | Technology |
|-------|----------|-----------|------------|
| **Rsync-TLS** | 1:1 DR/mirroring | Push (source → dest) | rsync + stunnel |
| **Rsync-SSH** | 1:1 DR/mirroring | Push | rsync + SSH |
| **Rclone** | 1:many distribution | Push | rclone (cloud/S3) |
| **Restic** | Backups | Push | restic (dedupe backups) |
| **Syncthing** | Many:many live sync | Bidirectional | syncthing |

### Rsync-TLS Mover (Most Similar to crane)

**How it works:**

```yaml
# Destination cluster
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: database
  namespace: dest-ns
spec:
  rsyncTLS:
    serviceType: LoadBalancer  # or ClusterIP
    copyMethod: Snapshot       # or Direct, Clone
    capacity: 10Gi
    accessModes:
      - ReadWriteOnce
    storageClassName: fast-ssd
    keySecret: tls-key
```

```yaml
# Source cluster
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: database
  namespace: source-ns
spec:
  sourcePVC: postgres-data
  trigger:
    schedule: "*/30 * * * *"  # Every 30 minutes
  rsyncTLS:
    address: database.dest.example.com
    keySecret: tls-key
    copyMethod: Clone
```

**What the operator does:**

1. **Destination:**
   - Creates Service (LoadBalancer/ClusterIP)
   - Creates Pod running: **rsync daemon + stunnel server**
   - Waits for connections

2. **Source:**
   - On trigger (schedule/manual):
     - Creates snapshot/clone of source PVC
     - Creates Pod running: **rsync client + stunnel client**
     - Transfers only changed data
     - Cleans up snapshot

**Very similar to what crane does!** But automated and continuous.

### Rclone Mover (Interesting Alternative)

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: data-backup
spec:
  sourcePVC: app-data
  trigger:
    schedule: "0 */6 * * *"  # Every 6 hours
  rclone:
    rcloneConfigSection: my-s3-bucket
    rcloneDestPath: /backups/app-data
    rcloneConfig: rclone-secret
    copyMethod: Snapshot
```

**Advantages:**
- Multi-threaded transfers (faster than rsync)
- Cloud storage support (S3, GCS, Azure Blob)
- Built-in bandwidth limiting
- Built-in resume support
- Better progress reporting

**This is what I recommended in TRANSFER_PVC_RECOMMENDATIONS.md!**

### Restic Mover (Backup-focused)

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationSource
metadata:
  name: database-backup
spec:
  sourcePVC: postgres-data
  trigger:
    schedule: "0 2 * * *"  # Daily at 2am
  restic:
    pruneIntervalDays: 7
    repository: s3-backup-repo
    retain:
      hourly: 24
      daily: 7
      weekly: 4
      monthly: 12
    copyMethod: Clone
```

**Features:**
- Deduplication (saves space)
- Incremental backups
- Encryption
- Retention policies
- Multi-destination support

---

## 4. What Can Work WITHOUT an Operator?

### From pvc-transfer (Already Working in crane)

✅ **Everything** - it's a library, not an operator

```go
// No operator needed, just import and use
import "github.com/backube/pvc-transfer/transfer/rsync"

rsyncClient, err := rsynctransfer.NewClient(
    ctx, client, pvcList, stunnelClient, logger, 
    "rsync-client", labels, nil, options)
```

**Used in crane today** ✅

### From VolSync (Requires operator)

❌ **VolSync operator** - Cannot run without operator

The VolSync operator is **required** because:
- Reconciles CRDs (ReplicationSource, ReplicationDestination)
- Manages Pod lifecycle (create, monitor, cleanup)
- Handles scheduling and triggers
- Creates Services and endpoints
- Manages snapshots/clones
- Monitors and reports status

**BUT:** We can learn from and replicate VolSync's **mover pattern**:

#### What We Can Replicate in crane (Without Operator)

**1. Mover Pod Architecture**

VolSync's "mover Pods" are just regular Kubernetes Pods that run transfer tools. We can create the same Pods using client-go (which crane already does):

```go
// Crane already does this via pvc-transfer library!
rsyncServer, err := rsynctransfer.NewServer(
    ctx, destClient, logger, destPVCList, 
    stunnelServer, endpoint, labels, nil, podOptions)
```

**2. Multiple Transfer Engines**

We can add rclone/restic support to crane **without an operator**:

```go
// Proposed: crane/pkg/transfer/engines/
type TransferEngine interface {
    CreateSource(ctx, client, pvc) error
    CreateDestination(ctx, client, pvc) error
    Execute(ctx) error
    Cleanup(ctx) error
}

// Implementations:
type RsyncEngine struct { ... }   // Existing
type RcloneEngine struct { ... }  // NEW
type ResticEngine struct { ... }  // NEW
```

**3. CopyMethod Strategies**

VolSync supports 3 copy methods:
- **Snapshot** - Create VolumeSnapshot first (safest)
- **Clone** - Create PVC clone (faster)
- **Direct** - Transfer from live PVC (risky)

Crane could add these **without an operator**:

```go
// Add to crane transfer-pvc flags
--copy-method=snapshot  // Create snapshot first
--copy-method=clone     // Clone PVC before transfer
--copy-method=direct    // Transfer live (current behavior)
```

**4. Configuration Abstraction**

VolSync's secret-based config (for rclone, restic) can be replicated:

```bash
# User creates Secret with rclone config
kubectl create secret generic rclone-config \
  --from-file=rclone.conf=/path/to/rclone.conf

# Crane reads it and uses rclone
crane transfer-pvc \
  --engine=rclone \
  --rclone-config-secret=rclone-config \
  --rclone-dest=s3:my-bucket/path
```

---

## 5. Key Learnings from VolSync for crane

### 5.1 Multi-Engine Architecture

**VolSync approach:**
```
Operator → Detects mover type → Creates appropriate mover Pod
          (rsync/rclone/restic/syncthing)
```

**crane can do (without operator):**
```
CLI flag → Select engine → Create appropriate Pods
          (rsync/rclone/restic)
```

**Implementation:**

```go
// crane/pkg/transfer/engine.go
type Engine string

const (
    EngineRsync  Engine = "rsync"
    EngineRclone Engine = "rclone"
    EngineRestic Engine = "restic"
)

func (t *TransferPVCCommand) Run() error {
    var engine TransferEngine
    
    switch t.Engine {
    case EngineRsync:
        engine = rsync.New(t.Config)
    case EngineRclone:
        engine = rclone.New(t.Config)
    case EngineRestic:
        engine = restic.New(t.Config)
    default:
        return fmt.Errorf("unknown engine: %s", t.Engine)
    }
    
    return engine.Execute(ctx)
}
```

### 5.2 Pod Templates with Resource Limits

**VolSync allows:**
```yaml
spec:
  rsyncTLS:
    moverResources:
      limits:
        cpu: "2"
        memory: 4Gi
      requests:
        cpu: "1"
        memory: 2Gi
```

**crane should add:**
```bash
crane transfer-pvc \
  --mover-cpu-limit=2 \
  --mover-memory-limit=4Gi \
  --mover-cpu-request=1 \
  --mover-memory-request=2Gi
```

### 5.3 Snapshot-Based Transfer (Safer)

**VolSync:**
```yaml
spec:
  rsyncTLS:
    copyMethod: Snapshot  # Create snapshot first, transfer from snapshot
```

**Why this is better:**
- Source PVC can keep running
- Consistent point-in-time copy
- No risk of partial writes

**crane implementation:**
```bash
crane transfer-pvc \
  --copy-method=snapshot \
  --volume-snapshot-class=csi-snapclass \
  --pvc-name=postgres-data
```

**Code:**
```go
if t.CopyMethod == "snapshot" {
    // 1. Create VolumeSnapshot
    snapshot := &snapshotv1.VolumeSnapshot{
        ObjectMeta: metav1.ObjectMeta{
            Name:      fmt.Sprintf("%s-transfer", pvcName),
            Namespace: namespace,
        },
        Spec: snapshotv1.VolumeSnapshotSpec{
            Source: snapshotv1.VolumeSnapshotSource{
                PersistentVolumeClaimName: &pvcName,
            },
            VolumeSnapshotClassName: &t.VolumeSnapshotClass,
        },
    }
    
    // 2. Wait for snapshot ready
    // 3. Create temporary PVC from snapshot
    // 4. Transfer from temp PVC
    // 5. Delete temp PVC and snapshot
}
```

### 5.4 Metrics and Observability

**VolSync exposes Prometheus metrics:**
- `volsync_missed_intervals_total` - Missed replication intervals
- `volsync_replication_duration_seconds` - Transfer duration
- `volsync_volume_out_of_sync_seconds` - Time since last successful sync

**crane could add:**
```go
// crane/pkg/metrics/transfer.go
var (
    transferDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "crane_transfer_duration_seconds",
            Help: "Duration of PVC transfers",
        },
        []string{"source_cluster", "dest_cluster", "engine"},
    )
    
    transferBytesTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "crane_transfer_bytes_total",
            Help: "Total bytes transferred",
        },
        []string{"source_cluster", "dest_cluster"},
    )
)
```

---

## 6. Comparison: crane vs VolSync Approaches

| Feature | crane (current) | VolSync | crane (could add) |
|---------|----------------|---------|-------------------|
| **Requires operator** | ❌ NO | ✅ YES | ❌ NO |
| **Transfer engine** | rsync only | rsync/rclone/restic/syncthing | rsync/rclone/restic |
| **Continuous sync** | ❌ Manual re-run | ✅ Scheduled | ⚠️ CronJob (see SIMPLE_JOB_PROPOSAL.md) |
| **Snapshot support** | ❌ NO | ✅ YES | ✅ Can add |
| **Multi-threaded** | ❌ rsync is single-thread | ✅ rclone is parallel | ✅ Add rclone engine |
| **Bandwidth limit** | ❌ NO | ✅ YES | ✅ Easy to add |
| **Resume support** | ❌ NO | ✅ YES (rclone) | ✅ Add rclone engine |
| **Cloud targets** | ❌ NO | ✅ YES (rclone → S3/GCS/Azure) | ✅ Add rclone engine |
| **Dedup backups** | ❌ NO | ✅ YES (restic) | ✅ Add restic engine |
| **TLS encryption** | ✅ YES (stunnel) | ✅ YES | ✅ Already has |
| **Resource limits** | ❌ Hardcoded | ✅ User-configurable | ✅ Should add |
| **Metrics** | ❌ NO | ✅ Prometheus | ✅ Should add |
| **CLI usage** | ✅ Simple | ❌ Need CRs | ✅ Keep simple |
| **Complexity** | 🟢 Low | 🔴 High (operator) | 🟡 Medium |

**Conclusion:** crane can implement most of VolSync's features **without an operator**, by:
1. Adding rclone/restic engines
2. Adding snapshot-based copy method
3. Making resource limits configurable
4. Exposing metrics

---

## 7. Detailed: VolSync's Rsync-TLS Mover vs crane

### Similarities (What crane already does)

Both use the same architecture:

```
Destination:
  Service (LoadBalancer/Route) 
    ↓
  stunnel server Pod (TLS tunnel)
    ↓
  rsync daemon Pod (receives data)

Source:
  rsync client Pod (sends data)
    ↓
  stunnel client Pod (TLS tunnel)
    ↓
  Connects to destination Service
```

**crane implementation (via pvc-transfer):**
```go
// Destination
endpoint := createEndpoint(...)           // Route or Ingress
stunnelServer := stunneltransport.NewServer(...)
rsyncServer := rsynctransfer.NewServer(...)

// Source
stunnelClient := stunneltransport.NewClient(...)
rsyncClient := rsynctransfer.NewClient(...)
```

**VolSync implementation (operator-managed):**
```yaml
# Operator creates same Pods, but via CRD reconciliation
kind: ReplicationDestination
spec:
  rsyncTLS: { ... }
```

### Differences

| Aspect | crane | VolSync Rsync-TLS Mover |
|--------|-------|-------------------------|
| **Orchestration** | CLI invocation | Operator reconciliation |
| **Scheduling** | Manual / CronJob | Built-in triggers |
| **Copy method** | Direct (live PVC) | Snapshot/Clone/Direct |
| **Cleanup** | Manual (garbage collect) | Automatic |
| **Status** | Logs only | CR status + metrics |
| **Resume** | ❌ Start over | ⚠️ Depends on copyMethod |
| **Multi-cluster** | 2 contexts required | Built-in multi-cluster |

### What crane Could Learn

**1. Copy Methods**

VolSync's snapshot approach is **much safer**:

```yaml
# VolSync
spec:
  rsyncTLS:
    copyMethod: Snapshot  # Safe: snapshot → transfer → cleanup
```

vs crane current behavior:
```bash
# crane transfers directly from live PVC
# Risk: partial writes, torn data if app is writing
```

**Improvement:**
```bash
crane transfer-pvc \
  --copy-method=snapshot \
  --pvc-name=postgres-data

# OR for stateful apps that need downtime anyway:
crane transfer-pvc \
  --copy-method=direct \
  --scale-down-source \  # Scale down first
  --pvc-name=postgres-data
```

**2. Resource Configuration**

```bash
# Current crane: hardcoded resource limits
# VolSync: user-configurable

crane transfer-pvc \
  --mover-resources='{"limits":{"cpu":"2","memory":"4Gi"}}' \
  --pvc-name=large-dataset
```

**3. Service Types**

```yaml
# VolSync allows both
spec:
  rsyncTLS:
    serviceType: LoadBalancer  # Public cloud
    # OR
    serviceType: ClusterIP      # Private network
```

crane currently only supports:
- Route (OpenShift)
- Ingress (Kubernetes)

**Could add:**
```bash
crane transfer-pvc \
  --endpoint=service \
  --service-type=LoadBalancer \
  --pvc-name=mydata
```

---

## 8. rclone Engine: Deep Dive

### Why rclone is Better Than rsync for Some Use Cases

| Feature | rsync | rclone |
|---------|-------|--------|
| **Threads** | Single-threaded | Multi-threaded (default: 4) |
| **Large files** | Good | Excellent (chunked) |
| **Many small files** | Slow (serial) | Fast (parallel) |
| **Cloud storage** | ❌ NO | ✅ S3, GCS, Azure, etc. |
| **Bandwidth limit** | ⚠️ Via flag | ✅ Built-in, granular |
| **Resume** | ⚠️ With --partial | ✅ Native support |
| **Progress** | Basic | Detailed (per-file) |
| **Retries** | Manual | ✅ Automatic with backoff |
| **Checksums** | MD5 | Multiple (MD5, SHA1, etc.) |

### VolSync's Rclone Implementation

**Destination (rclone config in Secret):**
```ini
# rclone.conf
[dest-s3]
type = s3
provider = AWS
env_auth = false
access_key_id = AKIA...
secret_access_key = ...
region = us-east-1
```

```yaml
kind: ReplicationDestination
spec:
  rclone:
    rcloneConfigSection: dest-s3
    rcloneDestPath: /backups/myapp
    rcloneConfig: rclone-secret
    accessModes: [ReadWriteOnce]
    capacity: 100Gi
```

**Source:**
```yaml
kind: ReplicationSource
spec:
  sourcePVC: app-data
  rclone:
    rcloneConfigSection: dest-s3
    rcloneDestPath: /backups/myapp
    rcloneConfig: rclone-secret
    copyMethod: Snapshot
```

**What the mover does:**
```bash
# Mover Pod runs:
rclone sync /source /dest \
  --config /etc/rclone/rclone.conf \
  --transfers 4 \
  --checkers 8 \
  --stats 1s \
  --progress
```

### How crane Could Implement This

**Without operator, using Job:**

```bash
# 1. Create Secret with rclone config
kubectl create secret generic rclone-config \
  --from-file=rclone.conf=./my-rclone.conf \
  -n crane-transfers

# 2. Run transfer
crane transfer-pvc \
  --engine=rclone \
  --source-context=prod \
  --pvc-name=app-data \
  --pvc-namespace=apps \
  --rclone-config-secret=rclone-config \
  --rclone-dest-section=my-s3 \
  --rclone-dest-path=/backups/app-data
```

**Implementation:**

```go
// crane/pkg/transfer/engines/rclone/rclone.go
type RcloneEngine struct {
    SourcePVC         string
    DestSection       string
    DestPath          string
    ConfigSecret      string
    Transfers         int  // Parallel transfers
    Checkers          int  // Parallel checksums
}

func (r *RcloneEngine) Execute(ctx context.Context) error {
    // 1. Create source mover Pod that mounts:
    //    - Source PVC at /source
    //    - rclone-config Secret at /etc/rclone
    
    // 2. Run rclone in Pod:
    cmd := []string{
        "rclone", "sync", "/source", 
        fmt.Sprintf("%s:%s", r.DestSection, r.DestPath),
        "--config", "/etc/rclone/rclone.conf",
        "--transfers", strconv.Itoa(r.Transfers),
        "--checkers", strconv.Itoa(r.Checkers),
        "--stats", "1s",
        "--progress",
        "--verbose",
    }
    
    // 3. Stream logs, parse progress
    // 4. Cleanup Pod
}
```

**Benefits for crane users:**

```bash
# Scenario 1: Cloud backup while migrating
crane transfer-pvc \
  --engine=rclone \
  --source-context=prod \
  --pvc-name=postgres-data \
  --rclone-dest-section=s3-backup \
  --rclone-dest-path=/backups/postgres/$(date +%Y-%m-%d)

# Scenario 2: Parallel transfer for many files
crane transfer-pvc \
  --engine=rclone \
  --source-context=prod \
  --destination-context=dr \
  --pvc-name=ml-training-data \
  --rclone-transfers=16 \  # 16 parallel file transfers!
  --rclone-checkers=32     # Much faster than rsync
```

---

## 9. Recommendations for crane

### 9.1 Short-term (Can Do Without Operator)

**Priority 1: Fix pvc-transfer dependency issues**
- Fork backube/pvc-transfer to github.com/migtools/pvc-transfer
- Add semantic versioning
- Implement missing features (bandwidth limit, resume)

**Priority 2: Add rclone engine**
- Implement `--engine=rclone` flag
- Support rclone config via Secret
- Enable parallel transfers
- Much better for large PVCs with many files

**Priority 3: Add snapshot-based copy**
- Implement `--copy-method=snapshot`
- Create VolumeSnapshot before transfer
- Transfer from snapshot (safer)
- Cleanup snapshot after

**Priority 4: Make resource limits configurable**
```bash
crane transfer-pvc \
  --mover-cpu-limit=2 \
  --mover-memory-limit=4Gi
```

**Priority 5: Add metrics**
- Prometheus metrics for duration, bytes, success/failure
- Export from Job (Pushgateway pattern)

### 9.2 Medium-term (Job-based, No Operator)

**Priority 1: Job template generator**
```bash
crane transfer-pvc generate-job \
  --pvc-name=mydata \
  --engine=rclone > job.yaml
```

**Priority 2: Enhanced CLI for Job mode**
```bash
crane transfer-pvc submit \
  --pvc-name=mydata \
  --engine=rclone
# Creates Job in cluster, watches status
```

**Priority 3: CronJob for incremental sync**
```bash
crane transfer-pvc schedule \
  --pvc-name=mydata \
  --interval=30m
# Creates CronJob, shows how to finalize
```

### 9.3 Long-term (If Operator Becomes Necessary)

**Only consider operator if:**
- Users demand continuous replication (not just migrations)
- Need complex scheduling/triggers
- Want GitOps-friendly CRDs
- Need multi-tenancy with RBAC per-transfer

**But for migration tool, Job-based approach is sufficient!**

---

## 10. Concrete Implementation Plan

### Phase 1: Fix Current Issues (Week 1-2)

```bash
# Fork pvc-transfer
git clone https://github.com/backube/pvc-transfer migtools-pvc-transfer
cd migtools-pvc-transfer
git remote add upstream https://github.com/backube/pvc-transfer

# Add semantic versioning
git tag v0.1.0

# Fix crane dependency
# In crane/go.mod:
# Replace: github.com/backube/pvc-transfer v0.0.0-20220810121213-5f9e29a1f6e5
# With:    github.com/migtools/pvc-transfer v0.1.0
```

**Add missing features to pvc-transfer:**
```go
// migtools-pvc-transfer/transfer/rsync/options.go

// Add bandwidth limiting
type BandwidthLimit string

func (b BandwidthLimit) ApplyTo(opts *CommandOptions) error {
    if string(b) != "" {
        opts.Extras = append(opts.Extras, "--bwlimit="+string(b))
    }
    return nil
}

// Add resume support
type ResumeSupport bool

func (r ResumeSupport) ApplyTo(opts *CommandOptions) error {
    if bool(r) {
        opts.Extras = append(opts.Extras, "--partial", "--partial-dir=.rsync-partial")
    }
    return nil
}

// Add optimization
type Optimization struct {
    BlockSize      int64
    Compress       bool
    CompressLevel  int
}

func (o Optimization) ApplyTo(opts *CommandOptions) error {
    if o.BlockSize > 0 {
        opts.Extras = append(opts.Extras, fmt.Sprintf("--block-size=%d", o.BlockSize))
    }
    if o.Compress {
        opts.Extras = append(opts.Extras, "--compress")
        if o.CompressLevel > 0 {
            opts.Extras = append(opts.Extras, fmt.Sprintf("--compress-level=%d", o.CompressLevel))
        }
    }
    return nil
}
```

### Phase 2: Add rclone Engine (Week 3-4)

```go
// crane/pkg/transfer/engine.go
package transfer

type Engine interface {
    CreateSourceMover(ctx context.Context, client client.Client, pvc *corev1.PersistentVolumeClaim) error
    CreateDestinationMover(ctx context.Context, client client.Client, pvc *corev1.PersistentVolumeClaim) error
    WaitForCompletion(ctx context.Context) error
    GetProgress() (*Progress, error)
    Cleanup(ctx context.Context) error
}

// crane/pkg/transfer/rclone/engine.go
package rclone

type RcloneEngine struct {
    SourceClient      client.Client
    DestClient        client.Client
    Config            RcloneConfig
    Logger            logr.Logger
}

type RcloneConfig struct {
    ConfigSecret    string
    DestSection     string
    DestPath        string
    Transfers       int
    Checkers        int
    BandwidthLimit  string
}

func (r *RcloneEngine) CreateSourceMover(ctx context.Context, client client.Client, pvc *corev1.PersistentVolumeClaim) error {
    // Create Pod with:
    // - PVC mounted at /source
    // - rclone-config Secret mounted at /etc/rclone
    // - Command: rclone sync /source <dest> --config /etc/rclone/rclone.conf ...
    
    pod := &corev1.Pod{
        ObjectMeta: metav1.ObjectMeta{
            Name:      fmt.Sprintf("rclone-mover-%s", pvc.Name),
            Namespace: pvc.Namespace,
            Labels: map[string]string{
                "app.kubernetes.io/name":      "crane",
                "app.kubernetes.io/component": "rclone-mover",
            },
        },
        Spec: corev1.PodSpec{
            RestartPolicy: corev1.RestartPolicyNever,
            Containers: []corev1.Container{
                {
                    Name:  "rclone",
                    Image: "rclone/rclone:latest",
                    Command: r.buildRcloneCommand(),
                    VolumeMounts: []corev1.VolumeMount{
                        {
                            Name:      "source-data",
                            MountPath: "/source",
                            ReadOnly:  true,
                        },
                        {
                            Name:      "rclone-config",
                            MountPath: "/etc/rclone",
                            ReadOnly:  true,
                        },
                    },
                },
            },
            Volumes: []corev1.Volume{
                {
                    Name: "source-data",
                    VolumeSource: corev1.VolumeSource{
                        PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
                            ClaimName: pvc.Name,
                            ReadOnly:  true,
                        },
                    },
                },
                {
                    Name: "rclone-config",
                    VolumeSource: corev1.VolumeSource{
                        Secret: &corev1.SecretVolumeSource{
                            SecretName: r.Config.ConfigSecret,
                        },
                    },
                },
            },
        },
    }
    
    return client.Create(ctx, pod)
}

func (r *RcloneEngine) buildRcloneCommand() []string {
    cmd := []string{
        "rclone", "sync", "/source",
        fmt.Sprintf("%s:%s", r.Config.DestSection, r.Config.DestPath),
        "--config", "/etc/rclone/rclone.conf",
        "--transfers", strconv.Itoa(r.Config.Transfers),
        "--checkers", strconv.Itoa(r.Config.Checkers),
        "--stats", "1s",
        "--progress",
        "--verbose",
    }
    
    if r.Config.BandwidthLimit != "" {
        cmd = append(cmd, "--bwlimit", r.Config.BandwidthLimit)
    }
    
    return cmd
}
```

**Usage:**
```bash
crane transfer-pvc \
  --engine=rclone \
  --source-context=prod \
  --pvc-name=app-data \
  --rclone-config-secret=my-rclone-config \
  --rclone-dest-section=s3-backup \
  --rclone-dest-path=/backups/app-data \
  --rclone-transfers=8 \
  --bandwidth-limit=100M
```

### Phase 3: Add Snapshot Support (Week 5)

```go
// crane/cmd/transfer-pvc/transfer-pvc.go

type CopyMethod string

const (
    CopyMethodDirect   CopyMethod = "direct"
    CopyMethodSnapshot CopyMethod = "snapshot"
    CopyMethodClone    CopyMethod = "clone"
)

func (t *TransferPVCCommand) preparePVC(pvc *corev1.PersistentVolumeClaim) (*corev1.PersistentVolumeClaim, func() error, error) {
    switch t.CopyMethod {
    case CopyMethodDirect:
        // Current behavior: transfer directly from PVC
        return pvc, func() error { return nil }, nil
        
    case CopyMethodSnapshot:
        // 1. Create VolumeSnapshot
        snapshot := &snapshotv1.VolumeSnapshot{...}
        if err := t.srcClient.Create(ctx, snapshot); err != nil {
            return nil, nil, err
        }
        
        // 2. Wait for snapshot ready
        if err := waitForSnapshotReady(snapshot); err != nil {
            return nil, nil, err
        }
        
        // 3. Create temporary PVC from snapshot
        tempPVC := &corev1.PersistentVolumeClaim{
            ObjectMeta: metav1.ObjectMeta{
                Name: fmt.Sprintf("%s-transfer-temp", pvc.Name),
            },
            Spec: corev1.PersistentVolumeClaimSpec{
                DataSource: &corev1.TypedLocalObjectReference{
                    APIGroup: ptr.String("snapshot.storage.k8s.io"),
                    Kind:     "VolumeSnapshot",
                    Name:     snapshot.Name,
                },
                // ... rest of spec
            },
        }
        if err := t.srcClient.Create(ctx, tempPVC); err != nil {
            return nil, nil, err
        }
        
        // 4. Return temp PVC and cleanup function
        cleanup := func() error {
            // Delete temp PVC
            t.srcClient.Delete(ctx, tempPVC)
            // Delete snapshot
            t.srcClient.Delete(ctx, snapshot)
            return nil
        }
        
        return tempPVC, cleanup, nil
        
    case CopyMethodClone:
        // Similar to snapshot, but use PVC clone
        // ...
    }
}
```

**Usage:**
```bash
# Safe: snapshot first, then transfer
crane transfer-pvc \
  --copy-method=snapshot \
  --volume-snapshot-class=csi-snapclass \
  --source-context=prod \
  --pvc-name=postgres-data

# Risky but faster: transfer from live PVC
crane transfer-pvc \
  --copy-method=direct \
  --source-context=prod \
  --pvc-name=postgres-data
```

---

## 11. Summary: Key Takeaways

### What We Learned from backube

1. **pvc-transfer** (library)
   - ✅ crane uses it correctly (it's a library, not operator)
   - ⚠️ Unmaintained since Aug 2022
   - ⚠️ Missing modern features
   - 🎯 **Action:** Fork and enhance

2. **VolSync** (operator)
   - ❌ Cannot use without operator
   - ✅ Can learn from its architecture
   - ✅ Mover pattern is replicable
   - ✅ rclone engine is superior for many use cases
   - 🎯 **Action:** Replicate movers in crane (without operator)

### What crane Should Do

**WITHOUT operator (recommended):**

1. **Fix pvc-transfer dependency**
   - Fork to github.com/migtools/pvc-transfer
   - Add semantic versioning
   - Add missing features (bandwidth, resume, optimization)

2. **Add rclone engine**
   - Multi-threaded transfers (much faster)
   - Better for large datasets
   - Cloud storage support
   - Built-in resume and retry

3. **Add snapshot support**
   - `--copy-method=snapshot` for safety
   - Transfer from snapshot, not live PVC
   - Automatic cleanup

4. **Run in cluster as Job**
   - See SIMPLE_JOB_PROPOSAL.md
   - Use CronJob for incremental sync
   - No operator needed

**WITH operator (only if really needed):**

5. **Consider operator only if:**
   - Users demand continuous replication
   - Need GitOps-friendly CRDs
   - Want complex multi-tenancy
   
   But for migration tool, **Job is sufficient!**

### Comparison Matrix

| Feature | crane (current) | crane (enhanced, no operator) | VolSync (with operator) |
|---------|----------------|-------------------------------|------------------------|
| Transfer engine | rsync | rsync + rclone + restic | rsync + rclone + restic + syncthing |
| Requires operator | ❌ | ❌ | ✅ |
| CLI usage | ✅ Simple | ✅ Simple | ❌ Need CRs |
| Multi-threaded | ❌ | ✅ (rclone) | ✅ (rclone) |
| Snapshot support | ❌ | ✅ Can add | ✅ |
| Continuous sync | ⚠️ CronJob | ✅ CronJob | ✅ Built-in |
| Cloud targets | ❌ | ✅ (rclone) | ✅ (rclone) |
| Complexity | 🟢 Low | 🟡 Medium | 🔴 High |
| Maintenance | 🟡 Fork pvc-transfer | 🟡 Maintain engines | 🔴 Maintain operator |

**Recommendation:** Enhance crane **without** operator, using learnings from VolSync's mover architecture.

---

**End of Analysis**

Key repositories analyzed:
- https://github.com/backube/pvc-transfer
- https://github.com/backube/volsync
- https://volsync.readthedocs.io

**Effort to implement recommendations:** 5-6 weeks
- Week 1-2: Fork pvc-transfer, add features
- Week 3-4: Implement rclone engine
- Week 5: Add snapshot support
- Week 6: Polish and testing
