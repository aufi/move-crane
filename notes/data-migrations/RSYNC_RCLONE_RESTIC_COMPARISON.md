# rsync vs rclone vs restic: Understanding the Differences

**Date:** 2026-06-30  
**Question:** What's the relationship between rsync, rclone, and restic? Can we skip restic?

## TL;DR - Quick Answer

**They are THREE DIFFERENT TOOLS for different purposes:**

| Tool | Primary Purpose | Relationship | crane Needs It? |
|------|----------------|--------------|-----------------|
| **rsync** | **Sync files** between two locations | Original sync tool (1996) | ✅ YES (already uses) |
| **rclone** | **Sync files** between two locations | Modern rsync alternative (2012) | ✅ YES (should add) |
| **restic** | **Backup** with deduplication & snapshots | Backup tool, NOT sync tool | ❌ NO (different use case) |

**Answer:** Yes, you can skip restic for PVC migration! It's a backup tool, not a migration/sync tool.

---

## 1. Detailed Comparison

### 1.1 rsync - The Original (1996)

**What it does:**
```bash
# Copy/sync files from A to B
rsync -avz /source/ user@dest:/target/

# Key feature: only transfers CHANGED blocks
# If file exists on dest, sends only the diff
```

**Purpose:** File synchronization

**Architecture:**
- Single-threaded
- Delta-transfer algorithm (only sends changes)
- Rolling checksums to detect changes
- Over SSH or custom protocol (rsync daemon)

**Pros:**
- ✅ Proven, reliable (30 years old)
- ✅ Delta-transfer (efficient for small changes)
- ✅ Preserves permissions, timestamps, symlinks
- ✅ Available everywhere

**Cons:**
- ❌ Single-threaded (slow for many files)
- ❌ No built-in cloud storage support
- ❌ No built-in encryption (needs stunnel/SSH)
- ❌ Resume support is basic (--partial)

**crane uses rsync today** ✅

---

### 1.2 rclone - Modern rsync for Cloud (2012)

**What it does:**
```bash
# Same as rsync, but modern and with cloud support
rclone sync /source/ dest:/target/

# Can sync to cloud storage
rclone sync /source/ s3:my-bucket/path/
rclone sync /source/ gcs:my-bucket/path/
rclone sync /source/ azure:container/path/
```

**Purpose:** File synchronization (same as rsync)

**Architecture:**
- **Multi-threaded** (default: 4 parallel transfers)
- Checksum-based (MD5, SHA1, etc.)
- Over HTTP/HTTPS or cloud APIs
- Built-in for 40+ cloud providers
- **Written in Go** - can be used as a library!

**Pros:**
- ✅ **Multi-threaded** (4-16x faster than rsync for many files)
- ✅ Cloud storage support (S3, GCS, Azure, etc.)
- ✅ Built-in retry and resume
- ✅ Built-in bandwidth limiting
- ✅ Better progress reporting
- ✅ Built-in encryption
- ✅ **Can be used as Go library** - no external binary needed!

**Cons:**
- ❌ Larger binary (~60MB vs rsync 1MB)
- ❌ No delta-transfer algorithm (transfers whole files)
  - **Note:** For PVC migration, this doesn't matter (initial transfer anyway)
- ⚠️ **If using as external binary:** Not available in RHEL base repositories - requires EPEL
  - **Solution:** Use as Go library instead (recommended for crane)

**Relationship to rsync:**
- **rclone is NOT built on rsync**
- **rclone is an alternative TO rsync**
- Think: "rsync reimagined for the cloud era"

**crane integration options:**
1. ✅ **RECOMMENDED:** Import as Go library (`github.com/rclone/rclone`)
   - Eliminates all dependency issues
   - Compiled into crane binary
   - Better integration
2. ⚠️ **Alternative:** Call as external binary
   - Requires EPEL on RHEL/CentOS
   - Or use upstream container images

**crane should add rclone** ✅

---

### 1.3 restic - Backup Tool (2014)

**What it does:**
```bash
# NOT sync - it's BACKUP with snapshots
restic backup /source/

# Creates deduplicated, encrypted snapshots
restic snapshots
# snapshot 1a2b3c4d of /source at 2026-06-30 10:00
# snapshot 5e6f7g8h of /source at 2026-06-30 11:00
# snapshot 9i0j1k2l of /source at 2026-06-30 12:00

# Restore from specific snapshot
restic restore 1a2b3c4d --target /restore/
```

**Purpose:** **Backup and disaster recovery** (NOT synchronization!)

**Architecture:**
- Creates immutable snapshots
- **Deduplication** - identical data blocks stored once
- **Encryption** - all data encrypted by default
- Repository-based (stores in a repository, not direct copy)
- Incremental backups

**Key Differences from rsync/rclone:**

| Feature | rsync/rclone | restic |
|---------|-------------|--------|
| **Output** | Mirror copy of source | Deduplicated repository |
| **Multiple versions** | ❌ Only latest | ✅ Many snapshots |
| **Deduplication** | ❌ | ✅ |
| **Direct access** | ✅ Files are normal files | ❌ Need restic to restore |
| **Use case** | Sync/migration | Backup/DR |

**Example:**

```bash
# rsync/rclone result:
/dest/
  file1.txt     # Latest version
  file2.txt     # Latest version

# restic result:
/repo/
  data/
    1a2b3c4d    # Encrypted chunk
    5e6f7g8h    # Encrypted chunk
  snapshots/
    snapshot1   # Metadata for snapshot 1
    snapshot2   # Metadata for snapshot 2
```

**Pros:**
- ✅ Deduplication (saves space)
- ✅ Multiple snapshots (time-travel)
- ✅ Encryption
- ✅ Integrity checking

**Cons:**
- ❌ **NOT a sync tool** - different purpose!
- ❌ Cannot directly access files (need restic restore)
- ❌ Slower than rsync/rclone for one-time copy
- ❌ Requires repository management

**crane does NOT need restic** ❌ - Wrong use case!

---

## 2. Relationship Between the Three

### They Are NOT Related - Just Different Tools

```
┌──────────────────────────────────────────────┐
│         FILE SYNCHRONIZATION TOOLS           │
│  (Copy files from A to B, keep in sync)     │
│                                              │
│  ┌─────────┐              ┌─────────┐       │
│  │  rsync  │              │ rclone  │       │
│  │  (1996) │              │ (2012)  │       │
│  │         │              │         │       │
│  │ Single  │              │  Multi  │       │
│  │ thread  │              │ thread  │       │
│  │         │              │         │       │
│  │ Delta   │              │  Full   │       │
│  │ transfer│              │  file   │       │
│  └─────────┘              └─────────┘       │
│                                              │
│  Use for: Migration, DR, live sync          │
└──────────────────────────────────────────────┘

┌──────────────────────────────────────────────┐
│            BACKUP TOOLS                      │
│  (Create snapshots, dedup, long-term store) │
│                                              │
│  ┌─────────┐                                 │
│  │ restic  │                                 │
│  │ (2014)  │                                 │
│  │         │                                 │
│  │ Dedup   │                                 │
│  │ Encrypt │                                 │
│  │ Snapshot│                                 │
│  └─────────┘                                 │
│                                              │
│  Use for: Backups, long-term retention      │
└──────────────────────────────────────────────┘
```

**They are alternatives/complements, NOT dependencies:**
- rsync and rclone are **alternatives** (do the same thing differently)
- restic is **complementary** (different use case)

---

## 3. When to Use Each Tool

### 3.1 Use rsync When:

✅ **Migrating PVCs between clusters** (crane's use case)  
✅ Delta-transfer matters (small changes to large files)  
✅ Simple deployment (rsync is everywhere)  
✅ Small to medium datasets  

❌ Avoid when:
- Many small files (slow, single-threaded)
- Need cloud storage target
- Need better resume support

**Example: crane transfer-pvc today**
```bash
crane transfer-pvc \
  --source-context=prod \
  --destination-context=dr \
  --pvc-name=postgres-data
# Uses rsync internally
```

---

### 3.2 Use rclone When:

✅ **Large PVCs with many files** (multi-threaded = faster)  
✅ **Cloud backup** (S3, GCS, Azure Blob)  
✅ **Need resume/retry** (built-in)  
✅ Better bandwidth control  

❌ Avoid when:
- Delta-transfer critical (rclone transfers whole files)
  - **Note:** For initial PVC migration, this doesn't matter!

**Example: crane with rclone (proposed)**
```bash
# Cluster-to-cluster (faster than rsync for many files)
crane transfer-pvc \
  --engine=rclone \
  --source-context=prod \
  --destination-context=dr \
  --pvc-name=ml-training-data \
  --rclone-transfers=16  # 16 parallel transfers!

# OR: Backup to cloud
crane transfer-pvc \
  --engine=rclone \
  --source-context=prod \
  --pvc-name=postgres-data \
  --rclone-dest=s3:my-backup-bucket/postgres/
```

---

### 3.3 Use restic When:

✅ **Long-term backups** with retention policies  
✅ Need **deduplication** (save storage costs)  
✅ Need **multiple snapshots** (time-travel)  
✅ Backup to cloud with **encryption**  

❌ Avoid when:
- **PVC migration/sync** (wrong tool!)
- Need direct file access
- One-time copy (overhead not worth it)

**Example: PVC backup to S3 (NOT migration!)**
```bash
# NOT for crane transfer-pvc
# This is for backup, not migration

restic -r s3:my-backup-bucket/postgres init
restic -r s3:my-backup-bucket/postgres backup /data

# Later: restore from snapshot
restic -r s3:my-backup-bucket/postgres snapshots
restic -r s3:my-backup-bucket/postgres restore abc123 --target /restore
```

---

## 4. Performance Comparison

### 4.1 Scenario: 100GB PVC with 1 million small files

**rsync (single-threaded):**
```
Time: 4 hours
Threads: 1
Network: 50 MB/s (limited by single thread)
Resume: Basic (--partial)
```

**rclone (multi-threaded):**
```
Time: 30 minutes
Threads: 16 (configurable)
Network: 500 MB/s (saturates network)
Resume: Native, automatic
```

**restic (backup, not sync):**
```
Time: 2 hours (first backup)
       20 minutes (incremental)
Threads: Multi-threaded
Space: 60GB (with deduplication)
Access: Need restic restore (cannot mount directly)

NOT COMPARABLE - different use case!
```

**Winner for PVC migration: rclone** 🏆

---

### 4.2 Scenario: 500GB database (1 large file, daily small changes)

**rsync (delta-transfer):**
```
Initial: 2 hours (transfer whole file)
Daily: 5 minutes (only changed blocks)

✅ Excellent for incremental sync!
```

**rclone (full file transfer):**
```
Initial: 1.5 hours (multi-threaded)
Daily: 1.5 hours (transfers whole file again)

❌ No delta-transfer - not efficient for small changes
```

**restic (backup):**
```
Initial: 3 hours (encrypted, deduplicated)
Daily: 10 minutes (incremental, deduplicated)
Space: 200GB total for 7 daily snapshots

✅ Excellent for backups, but cannot use for live sync
```

**Winner for daily incremental sync: rsync** 🏆  
**Winner for backup: restic** 🏆

---

## 5. For crane: Do We Need All Three?

### Answer: **NO, we don't need restic**

**crane's use cases:**

| Use Case | Best Tool | Why |
|----------|-----------|-----|
| **One-time PVC migration** | rclone or rsync | Sync tools, not backup |
| **Large PVC with many files** | **rclone** | Multi-threaded |
| **Incremental sync (B1.2)** | **rsync** | Delta-transfer |
| **Cloud backup during migration** | **rclone** | S3/GCS support |
| **Backup with retention** | restic | ❌ Different use case |

**Recommendation:**

```
crane transfer-pvc should support:

✅ rsync  - Keep (already has, good for incremental)
✅ rclone - Add (better for initial large transfers)
❌ restic - Skip (backup tool, not migration tool)
```

---

## 6. Detailed: Why rclone is Better Than rsync for Initial PVC Migration

### 6.1 Multi-threaded Transfers

**rsync:**
```
Files: [====]-------  25%  (1 file at a time)
       ├─ file1.bin  [====]-------  Processing...
       ├─ file2.bin  waiting...
       ├─ file3.bin  waiting...
       └─ file4.bin  waiting...
```

**rclone (--transfers=4):**
```
Files: [==========]  75%  (4 files simultaneously)
       ├─ file1.bin  [====]-------  Processing...
       ├─ file2.bin  [======]-----  Processing...
       ├─ file3.bin  [===]--------  Processing...
       └─ file4.bin  [=====]------  Processing...
```

**Result:** 4-16x faster for many files

---

### 6.2 Better Resume Support

**rsync:**
```bash
rsync --partial --partial-dir=.rsync-partial /source/ /dest/

# If interrupted:
# - Partial files saved in .rsync-partial/
# - Need to re-run same command
# - Sometimes fails to resume properly
```

**rclone:**
```bash
rclone sync /source/ /dest/

# If interrupted:
# - Automatically detects transferred files
# - Skips completed files (checksum-based)
# - Resumes partial files
# - Just re-run, it figures it out
```

---

### 6.3 Built-in Bandwidth Limiting

**rsync:**
```bash
rsync --bwlimit=10M /source/ /dest/

# Limitation: applies to TOTAL, not per-file
# With large files, can't saturate network efficiently
```

**rclone:**
```bash
rclone sync /source/ /dest/ --bwlimit=10M

# Better: per-connection limiting
# With --transfers=4, each gets fair share
# Can also do time-based: --bwlimit=10M --bwlimit-file=20M
```

---

### 6.4 Better Progress Reporting

**rsync:**
```
rsync progress:
  1,234,567,890  99%   10.50MB/s    0:00:01

# Problems:
# - Only shows current file
# - No overall progress
# - Hard to parse
```

**rclone:**
```
rclone progress:
Transferred:      12.345 GiB / 50.000 GiB, 25%, 150 MiB/s, ETA 4m30s
Transferred:      1234 / 5000, 25%
Checks:           500 / 5000, 10%
Errors:           0
Elapsed time:     1m30s

# Much better:
# - Overall progress
# - File count
# - ETA
# - JSON output available
```

---

### 6.5 Cloud Storage Support

**rsync:**
```bash
# Cannot sync directly to S3/GCS
# Need intermediate VM or special setup
rsync /source/ user@ec2-instance:/data/
# Then separately: aws s3 sync /data/ s3://bucket/
```

**rclone:**
```bash
# Direct cloud sync
rclone sync /source/ s3:my-bucket/path/

# 40+ cloud providers supported:
- Amazon S3
- Google Cloud Storage
- Azure Blob Storage
- Backblaze B2
- Wasabi
- Cloudflare R2
- And many more...
```

**Useful for crane:**
```bash
# Backup PVC to cloud during migration
crane transfer-pvc \
  --engine=rclone \
  --source-context=prod \
  --pvc-name=critical-data \
  --rclone-dest=s3:disaster-recovery-bucket/$(date +%Y-%m-%d)/
```

---

## 7. Why NOT restic for crane

### 7.1 Incompatible Output Format

**crane needs:**
```
Source PVC → Destination PVC
/data/file1.txt → /data/file1.txt (direct copy)
```

**restic produces:**
```
Source PVC → Restic Repository
/data/file1.txt → /repo/data/abc123def456 (encrypted chunk)

# Destination CANNOT mount this directly!
# Need restic restore to get files back
```

**Problem:** Destination cluster wants a PVC with files, not a restic repository.

---

### 7.2 Extra Steps Required

**With rsync/rclone:**
```bash
crane transfer-pvc → Direct copy → Done! ✅
```

**With restic:**
```bash
Step 1: crane transfer-pvc → Create restic backup
Step 2: On destination: restic restore → Restore files
Step 3: Clean up repository

# 3 steps instead of 1! ❌
```

---

### 7.3 Not Designed for Migration

**restic is designed for:**
- Long-term backup storage
- Multiple snapshots over time
- Deduplication across snapshots
- Point-in-time recovery

**crane is designed for:**
- One-time migration
- Direct copy
- Minimal overhead
- Fast transfer

**Mismatch!**

---

### 7.4 When restic WOULD Make Sense

**IF crane added a "backup" feature (separate from migration):**

```bash
# Hypothetical: NOT for migration, but for backup
crane backup-pvc \
  --source-context=prod \
  --pvc-name=postgres-data \
  --restic-repo=s3:backups/postgres \
  --retention-daily=7 \
  --retention-weekly=4

# This would create deduplicated backups
# But it's a DIFFERENT feature than transfer-pvc!
```

**But for `transfer-pvc` (migration), restic is wrong tool.**

---

## 8. Recommendation for crane

### 8.1 Implement Two Engines

```go
type TransferEngine string

const (
    EngineRsync  TransferEngine = "rsync"   // ✅ Keep
    EngineRclone TransferEngine = "rclone"  // ✅ Add
    // EngineRestic - DON'T ADD (wrong use case)
)
```

**When to use each:**

| Scenario | Recommended Engine | Why |
|----------|-------------------|-----|
| **Initial large migration** | **rclone** | Multi-threaded, faster |
| **Many small files** | **rclone** | Parallel transfers |
| **Incremental sync (B1.2)** | **rsync** | Delta-transfer |
| **Cloud backup** | **rclone** | S3/GCS support |
| **Small PVC (<10GB)** | **rsync** | Simpler, already works |
| **Large database (incremental)** | **rsync** | Delta-transfer for daily changes |

---

### 8.2 CLI Examples

**Default (rsync):**
```bash
crane transfer-pvc \
  --source-context=prod \
  --destination-context=dr \
  --pvc-name=postgres-data
# Uses rsync by default (backward compatible)
```

**Explicit rclone for large transfer:**
```bash
crane transfer-pvc \
  --engine=rclone \
  --rclone-transfers=16 \
  --source-context=prod \
  --destination-context=dr \
  --pvc-name=ml-training-data
# 16 parallel transfers, much faster
```

**Incremental sync (rsync better):**
```bash
# Initial
crane transfer-pvc \
  --engine=rsync \
  --pvc-name=database

# Later (only changed blocks)
crane transfer-pvc \
  --engine=rsync \
  --pvc-name=database
# rsync delta-transfer is efficient
```

**Cloud backup (rclone):**
```bash
crane transfer-pvc \
  --engine=rclone \
  --source-context=prod \
  --pvc-name=critical-data \
  --rclone-dest=s3:backup-bucket/$(date +%Y-%m-%d)/
```

---

### 8.3 Auto-Select Engine (Smart Default)

```go
func (t *TransferPVCCommand) selectEngine() TransferEngine {
    // If user specified engine, use it
    if t.Engine != "" {
        return t.Engine
    }
    
    // If destination is cloud (rclone-dest specified), use rclone
    if t.RcloneDest != "" {
        return EngineRclone
    }
    
    // If incremental sync (PVC already exists on dest), use rsync
    destPVC := &corev1.PersistentVolumeClaim{}
    err := t.destClient.Get(ctx, 
        client.ObjectKey{Name: t.PVC.Name.destination, Namespace: t.PVC.Namespace.destination},
        destPVC)
    if err == nil {
        // Dest PVC exists - incremental sync
        return EngineRsync
    }
    
    // For initial large transfer, prefer rclone
    // (could check PVC size here, but rclone is generally better)
    return EngineRclone
}
```

---

## 9. Summary

### Key Points

1. **rsync, rclone, restic are INDEPENDENT tools:**
   - rsync = sync tool (old, single-threaded, delta-transfer)
   - rclone = sync tool (modern, multi-threaded, cloud support)
   - restic = backup tool (snapshots, dedup, encryption)

2. **rsync and rclone are ALTERNATIVES** (do the same thing)
   - Use rsync for: incremental sync, small changes, delta-transfer
   - Use rclone for: initial large transfer, many files, cloud storage

3. **restic is DIFFERENT PURPOSE** (backup, not sync)
   - Use restic for: long-term backups, retention policies
   - Do NOT use for: PVC migration (wrong tool!)

4. **For crane:**
   - ✅ Keep rsync (already works, good for incremental)
   - ✅ Add rclone (better for initial large transfers)
   - ❌ Skip restic (backup tool, not migration tool)

### Can We Skip restic?

**YES! ✅**

restic is a backup tool, not a migration/sync tool. crane transfer-pvc is for **migration**, not **backup**.

If crane wanted to add a `backup-pvc` feature in the future, then restic would make sense. But for `transfer-pvc`, it's the wrong tool.

---

### Final Recommendation

```
crane transfer-pvc engines:

Priority 1: ✅ rsync (keep - already works)
Priority 2: ✅ rclone (add - better for large transfers)
Priority 3: ❌ restic (skip - wrong use case)

Estimated effort:
- rclone engine: 2 weeks
- restic engine: 2 weeks (but don't do it - wrong use case!)
```

**Focus on rclone, skip restic.**

---

**End of Analysis**

**Answer to original question:**
- rsync, rclone, restic are three independent tools
- rsync and rclone are alternatives for sync/migration
- restic is for backup, not migration
- crane should add rclone, skip restic
