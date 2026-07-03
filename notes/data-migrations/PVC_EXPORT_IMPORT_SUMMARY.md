# PVC Offline Export/Import - Executive Summary

**Date:** 2026-07-03  
**Proposal:** [PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md](PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md)

---

## Overview

Extend `crane transfer-pvc` to support **offline export to cloud storage** (S3/GCS/Azure) and **import back to PVC**.

**Current:** PVC ↔ PVC (cluster-to-cluster)  
**Proposed:** PVC → Cloud Storage → PVC

---

## Key Use Cases

1. **Long-term archival** - Store old PVC data in cheap S3 Glacier (~$1/TB/month vs PVC ~$100/TB/month)
2. **Cross-cloud migration** - AWS → S3 → GCS → GCP (when clusters can't communicate)
3. **Disaster recovery** - Regular backups to S3, quick restore on failure
4. **Dev/Test refresh** - Export prod data, import to dev environments

---

## Proposed CLI Interface

### Export (PVC → Cloud)

```bash
crane transfer-pvc export \
  --pvc-name=postgres-data \
  --pvc-namespace=production \
  --context=prod-cluster \
  --destination=s3:backup-bucket/postgres/2026-07-03 \
  --rclone-config-secret=s3-credentials \
  --compress \
  --transfers=16
```

### Import (Cloud → PVC)

```bash
crane transfer-pvc import \
  --source=s3:backup-bucket/postgres/2026-07-03 \
  --pvc-name=postgres-restored \
  --pvc-namespace=recovery \
  --context=dr-cluster \
  --rclone-config-secret=s3-credentials \
  --create-pvc \
  --storage-class=fast-ssd \
  --pvc-size=100Gi
```

### Existing functionality preserved

```bash
crane transfer-pvc \
  --source-context=src \
  --destination-context=dst \
  --pvc-name=data
```

---

## Technical Implementation

**Uses rclone as Go library** (no external binary, no EPEL issues):

```go
import (
    "github.com/rclone/rclone/fs/sync"
    "github.com/rclone/rclone/backend/local"
)

// Export: PVC → Cloud
srcFs := local.NewFs(ctx, "local", "/mnt/pvc-data", nil)
dstFs := fs.NewFs(ctx, "s3:bucket/path")  // rclone parses cloud destination
sync.Sync(ctx, dstFs, srcFs, false)

// Import: Cloud → PVC (reverse direction)
```

**Architecture:** In-cluster Pod mounts PVC + uses rclone library to transfer to/from cloud.

---

## Configuration

Credentials via Kubernetes Secret:

```bash
# Create rclone config
cat > rclone.conf <<EOF
[my-s3]
type = s3
access_key_id = AKIAIOSFODNN7EXAMPLE
secret_access_key = wJalrXUtnFEMI/K7MDENG...
region = us-east-1
EOF

# Create Secret
kubectl create secret generic s3-creds --from-file=rclone.conf
```

---

## Benefits

- **💰 Cost savings:** $1-10/TB/month (S3 Glacier) vs $100/TB/month (PVC)
- **🔄 Cross-cloud migration:** Works when clusters can't communicate
- **📜 Compliance:** Long-term immutable archives
- **🌍 Multi-cloud:** Supports 40+ cloud providers via rclone
- **✅ No EPEL issues:** rclone as Go library, compiled into crane
- **🔐 Secure:** Encryption at rest, client-side encryption support
- **⚡ Fast:** Multi-threaded (16 parallel transfers by default)

---

## Implementation Estimate

| Phase | Features | Effort |
|-------|----------|--------|
| **Phase 1** | Core export/import to S3/GCS/Azure | 2-3 weeks |
| **Phase 2** | Auto-create PVC, compression, bandwidth limiting | 1 week |
| **Phase 3** | Encryption, scheduled backups (CronJob) | 1 week |
| **Total** | | **4-5 weeks** |

---

**Full details:** [PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md](PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md)
