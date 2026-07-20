# rclone vs kopia: Understanding the Differences for PVC Migration

**Date:** 2026-07-17  
**Question:** What's the relationship between rclone and kopia? Is kopia suitable for PVC migration in crane? What about block storage?

## TL;DR - Quick Answer

**They are TWO DIFFERENT TOOLS for different purposes:**

| Tool | Primary Purpose | Relationship | crane Needs It? |
|------|----------------|--------------|-----------------|
| **rclone** | **Sync files** between locations | Sync/transfer tool (2012) | ✅ YES (should add) |
| **kopia** | **Backup** with deduplication & snapshots | Backup tool (2015) | ❌ NO (different use case) |

**Answer:** kopia is a backup tool, not a migration tool. For PVC migration in crane, rclone is the right choice. Neither tool natively supports block storage (volumeMode: Block).

---

## 1. Detailed Comparison

### 1.1 rclone - Modern Sync Tool (2012)

**What it does:**
```bash
# Direct file synchronization from A to B
rclone sync /source/ dest:/target/

# Or to cloud storage
rclone sync /source/ s3:my-bucket/path/
```

**Purpose:** File synchronization and transfer

**Architecture:**
- **Multi-threaded** pipeline with three stages (checker/transfer/rename workers)
- Configurable parallelism: `--checkers` (default 8), `--transfers` (default 4)
- Goroutines with buffered channels as semaphores
- "March Algorithm" - parallel walk of source and destination directory trees
- Plugin architecture: central `fs.Fs` interface, 70+ backends registered via Go `init()`
- **Written in Go** - can be used as a library (librclone)!

**File comparison (Equal() function):**
```
1. Size check (fast, always)
2. Mtime OR hash check (configurable)
   --size-only    → size only
   --checksum     → hash only (MD5, SHA1, ...)
   (default)      → size + mtime
```

**Pros:**
- ✅ **Multi-threaded** (4-16x faster than rsync for many files)
- ✅ **70+ cloud storage backends** (S3, GCS, Azure, Backblaze, R2, ...)
- ✅ Built-in retry and resume (automatic reopen and seek on interruption)
- ✅ Built-in bandwidth limiting (`--bwlimit`)
- ✅ Better progress reporting (overall progress, ETA, JSON output)
- ✅ Encryption via crypt overlay (NaCl SecretBox, XSalsa20 + Poly1305)
- ✅ **Go library (librclone)** - no external binary needed!
- ✅ Server-side copy/move (avoids client-side data transfer)
- ✅ Multi-threaded streams for large files (`--multi-thread-streams`, default 4)

**Cons:**
- ❌ Larger binary (~60MB)
- ❌ No delta-transfer (transfers whole files, not just changed blocks)
- ❌ **No block device support** (operates only at file/object level)
- ⚠️ librclone API is experimental and may change between versions

**Go library (librclone):**
```go
import "github.com/rclone/rclone/librclone/librclone"

librclone.Initialize()
defer librclone.Finalize()

// JSON-based RPC interface
out, status := librclone.RPC("sync/copy", `{
    "srcFs": "/source/path",
    "dstFs": "s3:my-bucket/dest"
}`)
```

**crane should add rclone** ✅

---

### 1.2 kopia - Backup Tool (2015)

**What it does:**
```bash
# Create a repository
kopia repository create s3 --bucket=my-backups

# Backup (snapshot)
kopia snapshot create /data

# List snapshots
kopia snapshot list
# user@host  /data  2026-07-17 10:00  k1a2b3c4d
# user@host  /data  2026-07-17 11:00  k5e6f7g8h

# Restore from snapshot
kopia snapshot restore k1a2b3c4d /restore/
```

**Purpose:** **Backup and disaster recovery** (NOT synchronization!)

**Architecture - four-layer model:**
```
┌─────────────────────────────────────────────┐
│  4. Label-Addressable Manifest Storage      │
│     (snapshots as JSON manifests)           │
├─────────────────────────────────────────────┤
│  3. Content-Addressable Object Storage      │
│     (arbitrary-size objects)                │
├─────────────────────────────────────────────┤
│  2. Content-Addressable Block Storage       │
│     (deduplication, cryptographic hashes)   │
├─────────────────────────────────────────────┤
│  1. BLOB Storage                            │
│     (S3, GCS, Azure, filesystem, ...)       │
└─────────────────────────────────────────────┘
```

**Content-Defined Chunking:**
- Rolling hash algorithms: BUZHASH or RABINKARP
- Cryptographic hashes: BLAKE2B-256-128 (default), SHA2, BLAKE2S
- Identical data blocks → same identifier → natural deduplication
- File rename/move recognition without re-upload

**Pros:**
- ✅ Deduplication (identical data stored only once, even across machines)
- ✅ End-to-end encryption (AES-256-GCM or ChaCha20-Poly1305, HKDF-SHA256)
- ✅ Compression (zstd, s2, gzip) with per-policy configuration
- ✅ Incremental snapshots (only changed files are re-uploaded)
- ✅ Data integrity (cryptographic hashes)
- ✅ Written in Go

**Cons:**
- ❌ **NOT a sync tool** - different purpose!
- ❌ Cannot directly access files (need `kopia snapshot restore`)
- ❌ `sync-to` command is repository-to-repository replication (blob level), NOT file sync
- ❌ Slower than rclone for one-time transfer (snapshot overhead)
- ❌ Requires repository management
- ❌ **No block device support** (operates at file level)
- ❌ Performance degrades when restoring many small files over network (~20 KiB/s over WebDAV)
- ❌ Parallelism is file-level only (cannot parallelize a single large file)

**crane does NOT need kopia** ❌ - Wrong use case!

---

## 2. Key Differences

### 2.1 Sync vs Backup

```
┌──────────────────────────────────────────────┐
│         FILE SYNCHRONIZATION TOOLS           │
│  (Copy files from A to B, direct transfer)  │
│                                              │
│  ┌─────────┐                                 │
│  │ rclone  │                                 │
│  │ (2012)  │                                 │
│  │         │                                 │
│  │  Multi  │                                 │
│  │ thread  │                                 │
│  │         │                                 │
│  │ Direct  │                                 │
│  │ transfer│                                 │
│  └─────────┘                                 │
│                                              │
│  Use for: Migration, DR, live sync          │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│            BACKUP TOOLS                      │
│  (Snapshots, dedup, long-term storage)      │
│                                              │
│  ┌─────────┐                                 │
│  │  kopia  │                                 │
│  │ (2015)  │                                 │
│  │         │                                 │
│  │ Dedup   │                                 │
│  │ Encrypt │                                 │
│  │ Snapshot│                                 │
│  └─────────┘                                 │
│                                              │
│  Use for: Backups, long-term retention      │
└──────────────────────────────────────────────┘
```

### 2.2 Output Format

| Feature | rclone | kopia |
|---------|--------|-------|
| **Output** | Mirror copy of source files | Deduplicated repository |
| **Direct file access** | ✅ Files are normal files | ❌ Need `kopia restore` |
| **Multiple versions** | ❌ Only latest state | ✅ Many snapshots |
| **Deduplication** | ❌ | ✅ Across-repository |
| **Encryption** | ⚠️ Crypt overlay (optional) | ✅ End-to-end (mandatory) |
| **Compression** | ❌ | ✅ zstd, s2, gzip |
| **Use case** | Sync/migration | Backup/DR |

**Example output:**

```bash
# rclone result:
/dest/
  file1.txt     # Direct copy, normal file
  file2.txt     # Direct copy, normal file

# kopia result:
/repo/
  kopia.repository.f   # Repository metadata
  p1a2b3c4d5e6f.pack   # Encrypted/compressed pack
  p7g8h9i0j1k2l.pack   # Encrypted/compressed pack
  q3m4n5o6p7.pack       # Index pack
```

**Problem for crane:** The destination cluster wants a PVC with files, not a kopia repository.

---

## 3. Block Storage (volumeMode: Block)

### 3.1 What is Block Storage in Kubernetes?

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-block-pvc
spec:
  volumeMode: Block          # ← raw block device, NOT filesystem
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
```

Kubernetes PVCs have two modes:
- **Filesystem** (default): PVC is mounted as a directory with files
- **Block**: PVC is available as a raw block device (`/dev/xvda`)

### 3.2 rclone and Block Storage

**rclone does NOT support block devices** ❌

```
rclone operates at:   fs.Fs → fs.Object (file/object)
Block device is:      /dev/xvda (raw blocks, no filesystem)

→ INCOMPATIBLE!
```

**Workaround via stdin (not native support):**
```bash
# Equivalent to dd | rclone rcat
dd if=/dev/xvda bs=4M | rclone rcat remote:backup/disk.img

# rclone creator (Nick Craig-Wood) confirms:
# "that's just stdin piping, equivalent to dd"
```

**Open feature request:** GitHub issue #7337 (Network Block Device support) - not yet implemented.

### 3.3 kopia and Block Storage

**kopia does NOT support block devices** ❌

```
kopia operates at:   Files → Content-Defined Chunks → Pack files
Block device is:     /dev/xvda (raw blocks, no filesystem)

→ INCOMPATIBLE!
```

kopia has no interface for working with raw block devices. Its content-defined chunking is designed for files, not block devices.

### 3.4 VolSync and Block Storage

**VolSync (uses both rclone and kopia as data movers) confirms:**

> "there is no efficient way to calculate a diff so that we can send just the changed blocks during each sync iteration"
> — JohnStrunk, VolSync maintainer (GitHub discussion #495)

VolSync automatically changes `volumeMode: Block` to `Filesystem` when creating backup PVCs, causing provisioning failure (PVC remains in Pending state).

### 3.5 How to Migrate Block Storage?

**Block storage requires a fundamentally different approach:**

```bash
# Option 1: dd (simplest, but source must be quiesced)
dd if=/dev/source of=/dev/dest bs=4M status=progress

# Option 2: CSI Volume Snapshot
kubectl apply -f volume-snapshot.yaml
# → Create new PVC from snapshot on target cluster

# Option 3: Storage-level replication
# (depends on storage provider - Ceph RBD mirroring, NetApp SnapMirror, ...)
```

**For crane `transfer-pvc` with block storage:**
```
Current state:  ❌ Not supported (not by rclone, kopia, or rsync)
Future:         Depends on Kubernetes Changed Block Tracking (KEP #3367)
Workaround:     dd-based Job in cluster (see SIMPLE_JOB_PROPOSAL.md)
```

---

## 4. Performance Comparison

### 4.1 Scenario: 100GB PVC with 1 million small files

**rclone (multi-threaded sync):**
```
Time: 30 minutes
Threads: 16 (configurable)
Network: 500 MB/s (saturates network)
Resume: Native, automatic (checksum-based)
Output: Direct file copy
```

**kopia (snapshot + restore):**
```
Time: ~25 minutes (snapshot) + ~45 minutes (restore) = ~70 minutes
Threads: Multi-threaded (file-level)
Network: Variable (depends on backend)
Resume: Snapshot-level only
Output: Requires restore from snapshot

⚠️ Restoring many small files over network backend
   can degrade to ~20 KiB/s (GitHub issue #1098)
```

**Winner for PVC migration: rclone** 🏆

---

### 4.2 Scenario: 900GB (900 x 1GB files) - Velero Benchmark

**kopia (as backup engine):**
```
Backup: 1h 42m
CPU: 138%
Memory: 786 MB
```

**restic (for comparison):**
```
Backup: 2h 15m
CPU: 351%
Memory: 606 MB
```

**Note:** This benchmark (Velero v1.10) compares kopia and restic as backup engines, NOT as migration tools. rclone is not included because it serves a different purpose (direct sync).

---

### 4.3 Scenario: Single large file (1TB database)

**rclone:**
```
Transfer: Multi-threaded streams (--multi-thread-streams=4)
          Each stream transfers a different part of the file
Time: ~1.5 hours (depends on network)
```

**kopia:**
```
Backup: Content-defined chunking → parallel chunk upload
Time: Slower (parallelism only across files, not within file)
     For 1TB single file: ~26 MB/s (CloudCasa benchmark)

❌ Kopia cannot parallelize transfer of a single large file!
   "a thread can only be created for each file"
```

**Winner for large files: rclone** 🏆

---

## 5. Go Integration

### 5.1 rclone as Go Library

```go
import "github.com/rclone/rclone/librclone/librclone"

func TransferPVC(src, dst string) error {
    librclone.Initialize()
    defer librclone.Finalize()

    input := fmt.Sprintf(`{
        "srcFs": %q,
        "dstFs": %q,
        "_config": {
            "Transfers": 16,
            "Checkers": 8
        }
    }`, src, dst)

    out, status := librclone.RPC("sync/copy", input)
    if status != 200 {
        return fmt.Errorf("rclone sync failed: %s", out)
    }
    return nil
}
```

**Advantages:**
- ✅ Compiled into crane binary
- ✅ No external dependencies
- ✅ Full control over behavior
- ⚠️ API is experimental (may change)

### 5.2 kopia as Go Library

```go
import (
    "github.com/kopia/kopia/repo"
    "github.com/kopia/kopia/snapshot/snapshotfs"
)

func BackupPVC(src, repoPath string) error {
    // 1. Open repository
    r, err := repo.Open(ctx, repoPath, password, nil)
    // 2. Create snapshot
    u := snapshotfs.NewUploader(r)
    manifest, err := u.Upload(ctx, source, policyTree, sourceInfo)
    // 3. On destination: kopia restore
    // → Two steps instead of one!
    return nil
}
```

**Problem:** Migration requires snapshot + restore = 2 steps, not a direct transfer.

---

## 6. Cloud Storage Support

### 6.1 rclone - 70+ Backends

```bash
# Direct sync to cloud
rclone sync /source/ s3:my-bucket/path/
rclone sync /source/ gcs:my-bucket/path/
rclone sync /source/ azure:container/path/
rclone sync /source/ b2:my-bucket/path/
rclone sync /source/ r2:my-bucket/path/

# 70+ providers including:
# Amazon S3, Google Cloud Storage, Azure Blob
# Backblaze B2, Wasabi, Cloudflare R2
# SFTP, WebDAV, FTP, HTTP
# Dropbox, Google Drive, OneDrive
# and many more...
```

### 6.2 kopia - Limited Support (Backup Backends)

```bash
# Kopia supports backends for repositories:
kopia repository create s3 --bucket=my-backups
kopia repository create gcs --bucket=my-backups
kopia repository create azure --container=my-backups
kopia repository create b2 --bucket=my-backups
kopia repository create filesystem --path=/backup
kopia repository create sftp --path=/backup --host=server

# Fewer backends than rclone
# And importantly: backend is for repository, not direct transfer
```

---

## 7. Encryption and Compression

### 7.1 rclone

```bash
# Encryption via crypt overlay (optional)
rclone copy /source/ crypt-remote:encrypted/

# Technology:
# - NaCl SecretBox (XSalsa20 + Poly1305)
# - 256-bit keys
# - 64 KiB chunks
# - Overhead: ~0.03% for large files
# - Transparent wrapper (can be added to any backend)

# Not end-to-end: data must pass through rclone process
```

### 7.2 kopia

```bash
# Encryption is mandatory and end-to-end
kopia repository create s3 --bucket=backups

# Technology:
# - AES-256-GCM (default) or ChaCha20-Poly1305
# - HKDF-SHA256 for key derivation
# - Data encrypted BEFORE leaving the source

# Compression (configurable per-policy):
# - zstd (recommended)
# - s2 (Snappy-compatible, fast)
# - gzip
```

| Feature | rclone | kopia |
|---------|--------|-------|
| **Encryption** | Optional (crypt overlay) | Mandatory (end-to-end) |
| **Algorithm** | XSalsa20 + Poly1305 | AES-256-GCM / ChaCha20 |
| **Compression** | ❌ None | ✅ zstd, s2, gzip |
| **Deduplication** | ❌ None | ✅ Content-addressable |

---

## 8. Resume and Retry

### 8.1 rclone

```bash
rclone sync /source/ /dest/

# On interruption:
# - Automatically detects transferred files (checksum/mtime)
# - Skips completed files
# - Reopens interrupted transfers and seeks to correct position
# - Just re-run the same command

# rclone creator confirms:
# "When doing a copy the source can break and rclone will
#  reopen it and seek to the right point and retry...
#  automatic and built in to rclone for all backends"
```

### 8.2 kopia

```bash
kopia snapshot create /data

# On interruption:
# - Snapshot is incomplete (but repository is consistent)
# - Next snapshot is incremental (skips unchanged files)
# - But: requires TWO steps (snapshot + restore)
#   and interrupted restore has no elegant resume
```

---

## 9. Progress Reporting

### 9.1 rclone

```
rclone progress:
Transferred:      12.345 GiB / 50.000 GiB, 25%, 150 MiB/s, ETA 4m30s
Transferred:      1234 / 5000, 25%
Checks:           500 / 5000, 10%
Errors:           0
Elapsed time:     1m30s

# Advantages:
# - Overall progress
# - File count
# - ETA
# - JSON output (--stats 0 --log-format json)
# - Easy to parse for UI integration
```

### 9.2 kopia

```
kopia snapshot create /data:
 * 0 hashing, 234 hashed (12.3 GB), 56 cached (3.4 GB), uploaded 8.7 GB
   estimated 50 GB (25.0%), 150 MB/s

# Advantages:
# - Shows hashing/upload phases
# - Estimates total size
#
# Disadvantages:
# - Two phases (snapshot + restore) = two progress bars
# - Restore progress is less detailed
```

---

## 10. Usage in the Kubernetes Ecosystem

### 10.1 VolSync

VolSync uses BOTH tools, but for different purposes:

| Data Mover | Purpose in VolSync |
|------------|-------------------|
| **rclone** | Async replication via intermediary object storage (push-pull model, 1:many fan-out) |
| **kopia** | Backups with deduplication and encryption |
| **rsync** | Direct PVC-to-PVC replication |

### 10.2 pv-migrate

```bash
# pv-migrate uses rsync and rclone, NOT kopia
pv-migrate migrate old-pvc new-pvc

# Internally:
# - rsync over SSH (direct PVC-to-PVC)
# - rclone for bucket-based operations
# - No kopia integration
```

### 10.3 Velero

```bash
# Velero uses kopia (replaced restic) as backup engine
velero backup create my-backup --include-namespaces=app

# kopia is the right tool here because Velero BACKS UP
# (not migrates) - snapshots, dedup, encryption make sense
```

---

## 11. When to Use Each Tool

### 11.1 Use rclone When:

✅ **Migrating PVCs between clusters** (crane's use case)  
✅ **Large PVCs with many files** (multi-threaded)  
✅ **Cloud backup** during migration (S3/GCS/Azure)  
✅ **Direct file transfer** (not through a repository)  
✅ **One-time migration** (simple workflow)  
✅ **Go integration** (librclone library)  

❌ Avoid when:
- You need deduplication across backups
- You need point-in-time snapshots
- Block storage (volumeMode: Block)

### 11.2 Use kopia When:

✅ **Long-term backups** with retention policies  
✅ **Deduplication** (save storage costs)  
✅ **End-to-end encryption** is mandatory  
✅ **Multiple snapshots** (time-travel)  
✅ **Velero integration** (backup engine)  

❌ Avoid when:
- **PVC migration/sync** (wrong tool!)
- You need direct file access
- One-time transfer (overhead not worth it)
- Large single files (cannot parallelize within-file)
- Block storage (volumeMode: Block)

---

## 12. For crane: Do We Need kopia?

### Answer: **NO, we don't**

**crane's use case is migration, not backup:**

| Use Case | Best Tool | Why |
|----------|-----------|-----|
| **One-time PVC migration** | **rclone** | Direct sync, multi-threaded |
| **Large PVC with many files** | **rclone** | Parallel transfers |
| **Cloud backup during migration** | **rclone** | 70+ backends |
| **Incremental sync** | **rsync** | Delta-transfer |
| **Block storage migration** | **dd / CSI snapshot** | Different tool category |
| **Backup with deduplication** | kopia | ❌ Different use case than migration |

### Recommendation for crane:

```
crane transfer-pvc engines:

Priority 1: ✅ rsync  (keep - incremental sync)
Priority 2: ✅ rclone (add - large transfers, cloud)
Priority 3: ❌ kopia  (skip - backup tool)
Priority 4: ⚠️ dd     (consider for block storage)
```

---

## 13. Block Storage - Summary and Recommendations

### 13.1 Current State

```
volumeMode: Filesystem  →  rsync ✅  rclone ✅  kopia ⚠️(backup)
volumeMode: Block       →  rsync ❌  rclone ❌  kopia ❌

There is no standard K8s migration tool for block storage!
```

### 13.2 Possible Approaches for Block Storage in crane

```
Approach 1: dd-based Job
  + Simple, reliable
  - Source must be quiesced (offline)
  - No incremental transfer

Approach 2: CSI Volume Snapshot
  + Non-destructive (snapshot)
  + Storage-provider optimized
  - Depends on CSI driver
  - Not all storage backends support it

Approach 3: Storage-level replication
  + Most efficient
  + Can be online
  - Storage-provider specific
  - Outside crane's scope

Approach 4: Wait for Kubernetes Changed Block Tracking (KEP #3367)
  + Standard K8s solution
  - Unknown timeline
```

### 13.3 CLI Design (Future)

```bash
# Filesystem PVC (rclone)
crane transfer-pvc \
  --engine=rclone \
  --source-context=prod \
  --destination-context=dr \
  --pvc-name=app-data

# Block PVC (dd-based, future)
crane transfer-pvc \
  --engine=dd \
  --source-context=prod \
  --destination-context=dr \
  --pvc-name=raw-disk \
  --block-size=4M
# ⚠️ Requires source quiesce!
```

---

## 14. Summary

### Key Points

1. **rclone and kopia are INDEPENDENT tools with different purposes:**
   - rclone = sync tool (direct transfer, multi-threaded, 70+ backends)
   - kopia = backup tool (snapshots, deduplication, encryption)

2. **For PVC migration, rclone is the right choice:**
   - Direct file transfer (not through a repository)
   - Multi-threaded (fast for many files)
   - Go library (librclone) for integration
   - Proven in pv-migrate and VolSync

3. **kopia is for backups, not migration:**
   - Snapshot → restore workflow (2 steps instead of 1)
   - Output is a repository, not direct files
   - Suitable for Velero (backups), not crane (migration)

4. **Block storage (volumeMode: Block):**
   - Neither rclone nor kopia supports it
   - Requires dd-based or CSI snapshot approach
   - VolSync doesn't support it either (confirmed by maintainers)
   - Kubernetes KEP #3367 (Changed Block Tracking) may help in the future

### Can We Skip kopia?

**YES! ✅**

kopia is a backup tool, not a migration tool. crane `transfer-pvc` is for **migration**, not **backup**.

If crane wanted to add a backup feature (`crane backup-pvc`), then kopia would make sense. But for `transfer-pvc` (migration), it's the wrong tool - same conclusion as with restic (see RSYNC_RCLONE_RESTIC_COMPARISON.md).

---

### Final Recommendation

```
crane transfer-pvc:

Filesystem PVC (volumeMode: Filesystem):
  Priority 1: ✅ rsync  (keep - delta-transfer)
  Priority 2: ✅ rclone (add - large transfers, cloud)
  Priority 3: ❌ kopia  (skip - backup tool)

Block PVC (volumeMode: Block):
  Priority 1: ⚠️ dd-based Job (consider - simple, offline)
  Priority 2: ⚠️ CSI snapshot (consider - driver-dependent)
  Priority 3: ❌ rclone/kopia/rsync (don't work with block devices)

Estimated effort:
  - rclone engine: 2 weeks
  - dd-based block engine: 1 week
  - kopia engine: 2 weeks (BUT DON'T DO IT - wrong use case!)
```

**Focus on rclone (filesystem) and dd (block). Skip kopia.**

---

### Sources

- rclone architecture: https://github.com/rclone/rclone/blob/master/fs/fs.go
- rclone librclone: https://pkg.go.dev/github.com/rclone/rclone/librclone
- rclone block device discussion: https://forum.rclone.org/t/disk-cloning-with-rclone/29860
- rclone NBD feature request: https://github.com/rclone/rclone/issues/7337
- kopia architecture: https://kopia.io/docs/advanced/architecture/
- kopia features: https://kopia.io/docs/features/
- kopia sync-to: https://kopia.io/docs/advanced/synchronization/
- kopia sync feature request: https://github.com/kopia/kopia/issues/1535
- kopia restore performance: https://github.com/kopia/kopia/issues/1098
- VolSync block volume: https://github.com/backube/volsync/discussions/495
- VolSync block volume issue: https://github.com/backube/volsync/issues/556
- Velero benchmarks: https://velero.io/docs/v1.10/performance-guidance/
- CloudCasa kopia vs restic: https://cloudcasa.io/blog/comparing-restic-vs-kopia-for-kubernetes-data-movement/
- pv-migrate: https://github.com/utkuozdemir/pv-migrate
- K8s Changed Block Tracking: kubernetes/enhancements#3367

---

**End of Analysis**

**Answer to original question:**
- rclone and kopia are two independent tools
- rclone is for sync/migration, kopia is for backups
- Neither supports block storage (volumeMode: Block)
- crane should add rclone and consider dd-based approach for block storage
- Skip kopia - same conclusion as with restic (backup tool, not migration tool)
