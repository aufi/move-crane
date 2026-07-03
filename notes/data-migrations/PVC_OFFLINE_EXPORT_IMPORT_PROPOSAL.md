# PVC Offline Export/Import Proposal

**Date:** 2026-07-03  
**Status:** Proposal  
**Purpose:** Extend `crane transfer-pvc` to support offline export to cloud storage (S3, GCS, Azure) and import back

---

## Executive Summary

Currently `crane transfer-pvc` only supports **cluster-to-cluster** direct transfer. This proposal adds support for:

1. **Export:** PVC → Cloud Storage (S3/GCS/Azure/local filesystem)
2. **Import:** Cloud Storage → PVC
3. **Use cases:** 
   - Long-term archival/backup
   - Cross-cloud migration via intermediary storage
   - Disaster recovery
   - Compliance/audit snapshots

**Key insight:** Using **rclone as Go library** makes this trivial to implement since rclone already supports 40+ cloud providers!

---

## Table of Contents

1. [Use Cases](#use-cases)
2. [Proposed CLI Interface](#cli-interface)
3. [Architecture Options](#architecture)
4. [Implementation Details](#implementation)
5. [Configuration Management](#configuration)
6. [Examples](#examples)
7. [Migration Path](#migration)

---

<a name="use-cases"></a>
## 1. Use Cases

### Use Case 1: Long-term Archival

**Scenario:** Keep PVC data in cheap S3 storage for compliance

```bash
# Export PVC to S3 archive
crane transfer-pvc export \
  --pvc-name=customer-data-2025 \
  --pvc-namespace=production \
  --context=prod-cluster \
  --destination=s3:compliance-archive/2025/customer-data \
  --rclone-config-secret=s3-credentials

# Later: Import back if needed
crane transfer-pvc import \
  --source=s3:compliance-archive/2025/customer-data \
  --pvc-name=customer-data-restored \
  --pvc-namespace=investigation \
  --context=audit-cluster \
  --rclone-config-secret=s3-credentials
```

**Benefits:**
- S3 Glacier: ~$1/TB/month vs PVC ~$100/TB/month
- Immutable audit trail
- Easy to restore when needed

---

### Use Case 2: Cross-Cloud Migration via Intermediary

**Scenario:** Migrate from AWS to GCP, but clusters can't communicate directly

```bash
# Step 1: Export from AWS EKS to S3
crane transfer-pvc export \
  --pvc-name=postgres-data \
  --context=aws-eks \
  --destination=s3:migration-staging/postgres-data \
  --rclone-config-secret=aws-s3-creds

# Step 2: Copy S3 → GCS (using rclone on laptop or separate job)
rclone sync s3:migration-staging/postgres-data \
           gcs:migration-staging/postgres-data \
           --config=/path/to/rclone.conf

# Step 3: Import into GCP GKE from GCS
crane transfer-pvc import \
  --source=gcs:migration-staging/postgres-data \
  --pvc-name=postgres-data \
  --context=gcp-gke \
  --rclone-config-secret=gcp-gcs-creds
```

**Benefits:**
- Works when clusters have no direct connectivity
- Can throttle cloud egress costs
- Can verify data before importing

---

### Use Case 3: Disaster Recovery

**Scenario:** Regular backups to S3, quick restore on disaster

```bash
# Scheduled daily export (via CronJob)
crane transfer-pvc export \
  --pvc-name=database-data \
  --context=prod \
  --destination=s3:dr-backups/$(date +%Y%m%d)/database-data \
  --rclone-config-secret=s3-dr-creds

# On disaster: Quick restore
crane transfer-pvc import \
  --source=s3:dr-backups/20260702/database-data \
  --pvc-name=database-data \
  --context=dr-cluster \
  --rclone-config-secret=s3-dr-creds
```

**Benefits:**
- Much faster than VolumeSnapshots for cross-cluster DR
- Works across any cluster (not tied to storage provider)
- Can store in different region/account

---

### Use Case 4: Testing/Development Data Refresh

**Scenario:** Export production PVC, import to dev/test environments

```bash
# Export prod PVC (weekly)
crane transfer-pvc export \
  --pvc-name=prod-db \
  --context=prod \
  --destination=s3:test-data-snapshots/latest/prod-db

# Import to dev cluster
crane transfer-pvc import \
  --source=s3:test-data-snapshots/latest/prod-db \
  --pvc-name=dev-db \
  --context=dev-cluster
```

---

<a name="cli-interface"></a>
## 2. Proposed CLI Interface

### Current Command Structure

```bash
crane transfer-pvc \
  --source-context=src \
  --destination-context=dst \
  --pvc-name=mydata
```

### Proposed New Commands

**Option A: Subcommands** (RECOMMENDED)

```bash
# PVC → Cloud Storage (export)
crane transfer-pvc export \
  --pvc-name=mydata \
  --pvc-namespace=default \
  --context=source-cluster \
  --destination=s3:my-bucket/path/to/data \
  --rclone-config-secret=s3-credentials \
  [--compress] \
  [--encrypt] \
  [--transfers=16]

# Cloud Storage → PVC (import)
crane transfer-pvc import \
  --source=s3:my-bucket/path/to/data \
  --pvc-name=mydata \
  --pvc-namespace=default \
  --context=destination-cluster \
  --rclone-config-secret=s3-credentials \
  [--create-pvc] \
  [--storage-class=fast-ssd] \
  [--transfers=16]

# PVC → PVC (existing behavior, backward compatible)
crane transfer-pvc \
  --source-context=src \
  --destination-context=dst \
  --pvc-name=mydata
  # OR explicitly:
crane transfer-pvc sync \
  --source-context=src \
  --destination-context=dst \
  --pvc-name=mydata
```

**Benefits of subcommands:**
- Clear intent (export vs import vs sync)
- Easier to validate (export requires cloud destination, import requires cloud source)
- Better help text
- Room for future subcommands (list, verify, etc.)

---

**Option B: Direction Flag** (Alternative)

```bash
crane transfer-pvc \
  --direction=export \
  --pvc-name=mydata \
  --context=source \
  --destination=s3:bucket/path

crane transfer-pvc \
  --direction=import \
  --source=s3:bucket/path \
  --pvc-name=mydata \
  --context=dest
```

Less clean, harder to validate.

---

### New Flags

| Flag | Type | Description | Example |
|------|------|-------------|---------|
| `--destination` | string | Cloud storage destination (export only) | `s3:bucket/path`, `gcs:bucket/path`, `azure:container/path` |
| `--source` | string | Cloud storage source (import only) | Same as destination |
| `--rclone-config-secret` | string | Kubernetes Secret with rclone config | `my-s3-credentials` |
| `--rclone-config-file` | string | Path to rclone config file (for CLI usage) | `~/.config/rclone/rclone.conf` |
| `--compress` | bool | Enable compression during export | - |
| `--encrypt` | bool | Encrypt data before uploading | - |
| `--encryption-password-secret` | string | Secret containing encryption password | `encryption-key` |
| `--create-pvc` | bool | Auto-create PVC on import if not exists | - |
| `--storage-class` | string | StorageClass for auto-created PVC | `fast-ssd` |
| `--verify-checksum` | bool | Verify checksums after transfer | - |

---

<a name="architecture"></a>
## 3. Architecture Options

### Architecture A: In-Cluster Pod with rclone Library (RECOMMENDED)

**Flow for Export:**

```
┌─────────────────────────────────────────┐
│  Kubernetes Cluster                     │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │  Pod: crane-export-mydata        │  │
│  │                                  │  │
│  │  Container: crane                │  │
│  │  - Mounts source PVC (ReadOnly)  │  │
│  │  - Uses rclone Go library        │  │         ┌──────────────┐
│  │  - Reads from /mnt/pvc-data/     │  │─────────▶│  S3 Bucket   │
│  │  - Writes to S3 using rclone     │  │         │              │
│  │                                  │  │         │  my-bucket/  │
│  └──────────────────────────────────┘  │         │    mydata/   │
│        ▲                                │         └──────────────┘
│        │ mounts                         │
│  ┌─────┴────────┐                      │
│  │  PVC: mydata │                      │
│  └──────────────┘                      │
└─────────────────────────────────────────┘
```

**Implementation:**

```go
// pkg/transfer/rclone/export.go
func (e *RcloneEngine) Export(ctx context.Context, pvc types.NamespacedName, cloudDest string) error {
    // Create Pod in cluster with:
    // - Source PVC mounted
    // - rclone config from Secret
    // - crane binary (with rclone library) does the transfer
    
    pod := &corev1.Pod{
        Spec: corev1.PodSpec{
            Containers: []corev1.Container{{
                Name:  "crane-export",
                Image: "quay.io/konveyor/crane:latest",
                Command: []string{
                    "crane", "transfer-pvc", "export",
                    "--pvc-name=" + pvc.Name,
                    "--pvc-namespace=" + pvc.Namespace,
                    "--destination=" + cloudDest,
                    "--in-cluster",  // Use ServiceAccount
                },
                VolumeMounts: []corev1.VolumeMount{
                    {Name: "source-pvc", MountPath: "/mnt/pvc-data", ReadOnly: true},
                    {Name: "rclone-config", MountPath: "/root/.config/rclone"},
                },
            }},
            Volumes: []corev1.Volume{
                {Name: "source-pvc", VolumeSource: corev1.VolumeSource{
                    PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
                        ClaimName: pvc.Name,
                        ReadOnly:  true,
                    },
                }},
                {Name: "rclone-config", VolumeSource: corev1.VolumeSource{
                    Secret: &corev1.SecretVolumeSource{
                        SecretName: e.Config.RcloneConfigSecret,
                    },
                }},
            },
        },
    }
    
    return e.client.Create(ctx, pod)
}
```

**Inside the Pod (crane binary uses rclone library):**

```go
// cmd/transfer-pvc/export.go
func runExport(ctx context.Context, opts ExportOptions) error {
    // Load rclone config from mounted Secret
    rcloneConfig.LoadConfig()
    
    // Configure rclone
    fs.Config.Transfers = opts.Transfers
    fs.Config.Checkers = opts.Checkers
    
    // Create source (local PVC mount)
    srcFs, err := local.NewFs(ctx, "local", "/mnt/pvc-data", nil)
    if err != nil {
        return err
    }
    
    // Create destination (parse "s3:bucket/path" into rclone backend)
    dstFs, err := fs.NewFs(ctx, opts.Destination)
    if err != nil {
        return err
    }
    
    // Perform sync (PVC → Cloud)
    return sync.Sync(ctx, dstFs, srcFs, false)
}
```

**Benefits:**
- ✅ Runs in-cluster (reliable, survives network issues)
- ✅ No EPEL issues (rclone compiled into crane)
- ✅ Uses rclone library directly
- ✅ Kubernetes-native (Pod, Secret, RBAC)

---

### Architecture B: CLI Direct from Laptop (Simpler for quick tests)

**Flow:**

```
┌──────────────┐                    ┌──────────────┐
│   Laptop     │                    │  S3 Bucket   │
│              │                    │              │
│  crane CLI   │◀───API────┐        │  my-bucket/  │
│              │            │        │    mydata/   │
└──────────────┘            │        └──────────────┘
                            │              ▲
                            │              │ upload
                     ┌──────┴────────┐     │
                     │  K8s Cluster  │     │
                     │               │     │
                     │  ┌─────────┐  │     │
                     │  │Temp Pod │  │─────┘
                     │  │rsync srv│  │  via crane on laptop
                     │  └────┬────┘  │  using rclone library
                     │       │mount  │
                     │  ┌────┴────┐  │
                     │  │PVC:data │  │
                     │  └─────────┘  │
                     └───────────────┘
```

**Implementation:**

```bash
# crane CLI (on laptop) creates temp rsync server pod in cluster
# then uses rclone library to:
# 1. Pull data from PVC via rsync
# 2. Upload to S3 in parallel
```

**Benefits:**
- ✅ Simpler for ad-hoc usage
- ✅ No need to create Job/Pod manifests

**Drawbacks:**
- ❌ Requires laptop online for duration
- ❌ Limited by laptop's network bandwidth
- ❌ Not suitable for large transfers

---

<a name="implementation"></a>
## 4. Implementation Details

### 4.1 Export Implementation (PVC → Cloud)

```go
// cmd/transfer-pvc/export.go
package transfer_pvc

import (
    "context"
    
    "github.com/rclone/rclone/fs"
    "github.com/rclone/rclone/fs/sync"
    "github.com/rclone/rclone/backend/local"
    rcloneConfig "github.com/rclone/rclone/fs/config"
)

type ExportCommand struct {
    PVCName              string
    PVCNamespace         string
    Destination          string  // e.g., "s3:my-bucket/path"
    RcloneConfigSecret   string
    RcloneConfigFile     string
    Compress             bool
    Encrypt              bool
    EncryptionPassword   string
    Transfers            int
    Checkers             int
    BandwidthLimit       string
}

func (e *ExportCommand) Run(ctx context.Context) error {
    // 1. Load rclone configuration
    if err := e.loadRcloneConfig(); err != nil {
        return fmt.Errorf("failed to load rclone config: %w", err)
    }
    
    // 2. Configure rclone
    fs.Config.Transfers = e.Transfers
    fs.Config.Checkers = e.Checkers
    if e.BandwidthLimit != "" {
        fs.Config.BwLimit.Set(e.BandwidthLimit)
    }
    
    // 3. Create source filesystem (local PVC mount)
    pvcMountPath := "/mnt/pvc-data"  // Where PVC is mounted in Pod
    srcFs, err := local.NewFs(ctx, "local", pvcMountPath, nil)
    if err != nil {
        return fmt.Errorf("failed to create source fs: %w", err)
    }
    
    // 4. Create destination filesystem (cloud storage)
    // rclone parses "s3:bucket/path" automatically
    dstFs, err := fs.NewFs(ctx, e.Destination)
    if err != nil {
        return fmt.Errorf("failed to create destination fs: %w", err)
    }
    
    // 5. Perform sync (PVC → Cloud)
    log.Printf("Exporting PVC %s/%s to %s", e.PVCNamespace, e.PVCName, e.Destination)
    
    if err := sync.Sync(ctx, dstFs, srcFs, false); err != nil {
        return fmt.Errorf("export failed: %w", err)
    }
    
    log.Printf("Export completed successfully")
    return nil
}

func (e *ExportCommand) loadRcloneConfig() error {
    if e.RcloneConfigFile != "" {
        // Load from file (for CLI usage)
        rcloneConfig.SetConfigPath(e.RcloneConfigFile)
    } else {
        // Load from mounted Secret (for in-cluster usage)
        // Secret mounted at /root/.config/rclone/rclone.conf
        rcloneConfig.SetConfigPath("/root/.config/rclone/rclone.conf")
    }
    
    return nil
}
```

---

### 4.2 Import Implementation (Cloud → PVC)

```go
// cmd/transfer-pvc/import.go
package transfer_pvc

type ImportCommand struct {
    Source               string  // e.g., "s3:my-bucket/path"
    PVCName              string
    PVCNamespace         string
    RcloneConfigSecret   string
    RcloneConfigFile     string
    CreatePVC            bool
    StorageClass         string
    PVCSize              string  // e.g., "100Gi"
    Transfers            int
    Checkers             int
}

func (i *ImportCommand) Run(ctx context.Context) error {
    // 1. Ensure PVC exists (create if --create-pvc)
    if i.CreatePVC {
        if err := i.ensurePVCExists(ctx); err != nil {
            return err
        }
    }
    
    // 2. Load rclone config
    if err := i.loadRcloneConfig(); err != nil {
        return err
    }
    
    // 3. Configure rclone
    fs.Config.Transfers = i.Transfers
    fs.Config.Checkers = i.Checkers
    
    // 4. Create source filesystem (cloud storage)
    srcFs, err := fs.NewFs(ctx, i.Source)
    if err != nil {
        return fmt.Errorf("failed to create source fs: %w", err)
    }
    
    // 5. Create destination filesystem (local PVC mount)
    pvcMountPath := "/mnt/pvc-data"
    dstFs, err := local.NewFs(ctx, "local", pvcMountPath, nil)
    if err != nil {
        return fmt.Errorf("failed to create destination fs: %w", err)
    }
    
    // 6. Perform sync (Cloud → PVC)
    log.Printf("Importing from %s to PVC %s/%s", i.Source, i.PVCNamespace, i.PVCName)
    
    if err := sync.Sync(ctx, dstFs, srcFs, false); err != nil {
        return fmt.Errorf("import failed: %w", err)
    }
    
    log.Printf("Import completed successfully")
    return nil
}

func (i *ImportCommand) ensurePVCExists(ctx context.Context) error {
    // Check if PVC exists
    pvc := &corev1.PersistentVolumeClaim{}
    err := i.client.Get(ctx, types.NamespacedName{
        Name:      i.PVCName,
        Namespace: i.PVCNamespace,
    }, pvc)
    
    if err == nil {
        // PVC exists
        return nil
    }
    
    if !errors.IsNotFound(err) {
        return err
    }
    
    // Create PVC
    newPVC := &corev1.PersistentVolumeClaim{
        ObjectMeta: metav1.ObjectMeta{
            Name:      i.PVCName,
            Namespace: i.PVCNamespace,
        },
        Spec: corev1.PersistentVolumeClaimSpec{
            AccessModes: []corev1.PersistentVolumeAccessMode{
                corev1.ReadWriteOnce,
            },
            Resources: corev1.VolumeResourceRequirements{
                Requests: corev1.ResourceList{
                    corev1.ResourceStorage: resource.MustParse(i.PVCSize),
                },
            },
            StorageClassName: &i.StorageClass,
        },
    }
    
    log.Printf("Creating PVC %s/%s with size %s", i.PVCNamespace, i.PVCName, i.PVCSize)
    return i.client.Create(ctx, newPVC)
}
```

---

<a name="configuration"></a>
## 5. Configuration Management

### 5.1 rclone Configuration Secret

**Create Secret with S3 credentials:**

```bash
# Create rclone.conf file
cat > rclone.conf <<EOF
[my-s3]
type = s3
provider = AWS
access_key_id = AKIAIOSFODNN7EXAMPLE
secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
region = us-east-1
EOF

# Create Kubernetes Secret
kubectl create secret generic s3-credentials \
  --from-file=rclone.conf=rclone.conf \
  -n crane-migrations

# Cleanup local file
rm rclone.conf
```

**For GCS:**

```bash
cat > rclone.conf <<EOF
[my-gcs]
type = google cloud storage
project_number = 123456789
service_account_file = /path/to/service-account.json
location = us-central1
EOF
```

**For Azure:**

```bash
cat > rclone.conf <<EOF
[my-azure]
type = azureblob
account = mystorageaccount
key = base64encodedkey==
EOF
```

---

### 5.2 Encryption Support

**Optional: Encrypt data before uploading**

```go
// Use rclone's crypt backend
cat > rclone.conf <<EOF
[my-s3]
type = s3
# ... S3 config ...

[encrypted-s3]
type = crypt
remote = my-s3:my-bucket/encrypted
password = your-encryption-password
password2 = your-salt-password
EOF
```

Then use `--destination=encrypted-s3:path` which automatically encrypts.

---

<a name="examples"></a>
## 6. Examples

### Example 1: Export to S3

```bash
# 1. Create rclone config Secret
kubectl create secret generic s3-backup-creds \
  --from-file=rclone.conf=/path/to/s3-rclone.conf \
  -n production

# 2. Export PVC to S3
crane transfer-pvc export \
  --pvc-name=postgres-data \
  --pvc-namespace=production \
  --context=prod-cluster \
  --destination=s3:my-backup-bucket/postgres/2026-07-03 \
  --rclone-config-secret=s3-backup-creds \
  --compress \
  --transfers=16 \
  --bandwidth-limit=100M
```

---

### Example 2: Import from S3

```bash
# 1. Create destination PVC (or use --create-pvc)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data-restored
  namespace: recovery
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: fast-ssd
EOF

# 2. Import from S3 to PVC
crane transfer-pvc import \
  --source=s3:my-backup-bucket/postgres/2026-07-03 \
  --pvc-name=postgres-data-restored \
  --pvc-namespace=recovery \
  --context=dr-cluster \
  --rclone-config-secret=s3-backup-creds \
  --transfers=16
```

**Or auto-create PVC:**

```bash
crane transfer-pvc import \
  --source=s3:my-backup-bucket/postgres/2026-07-03 \
  --pvc-name=postgres-data-restored \
  --pvc-namespace=recovery \
  --context=dr-cluster \
  --rclone-config-secret=s3-backup-creds \
  --create-pvc \
  --storage-class=fast-ssd \
  --pvc-size=100Gi \
  --transfers=16
```

---

### Example 3: Export to Local Filesystem (NFS/SMB)

```bash
# Useful for migrating to on-prem storage

crane transfer-pvc export \
  --pvc-name=app-data \
  --context=cluster \
  --destination=/mnt/nfs-backup/app-data \
  --transfers=16

# Later: Import back
crane transfer-pvc import \
  --source=/mnt/nfs-backup/app-data \
  --pvc-name=app-data-restored \
  --context=cluster \
  --create-pvc
```

---

### Example 4: Cross-Cloud Migration (AWS → GCP)

```bash
# Step 1: Export from AWS to S3
crane transfer-pvc export \
  --pvc-name=ml-data \
  --context=aws-eks \
  --destination=s3:migration-temp/ml-data \
  --rclone-config-secret=aws-s3-creds

# Step 2: Copy S3 → GCS (one-time, can be manual or automated)
rclone sync s3:migration-temp/ml-data gcs:migration-temp/ml-data

# Step 3: Import from GCS to GCP
crane transfer-pvc import \
  --source=gcs:migration-temp/ml-data \
  --pvc-name=ml-data \
  --context=gcp-gke \
  --rclone-config-secret=gcp-gcs-creds \
  --create-pvc \
  --storage-class=pd-ssd
```

---

### Example 5: Scheduled Backups (CronJob)

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-postgres-to-s3
  namespace: production
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: crane-backup
          restartPolicy: OnFailure
          containers:
          - name: crane-export
            image: quay.io/konveyor/crane:latest
            command:
            - crane
            - transfer-pvc
            - export
            - --pvc-name=postgres-data
            - --pvc-namespace=production
            - --destination=s3:backups/postgres/$(date +%Y%m%d)
            - --in-cluster
            - --rclone-config-secret=s3-backup-creds
            - --compress
            - --transfers=16
            volumeMounts:
            - name: rclone-config
              mountPath: /root/.config/rclone
              readOnly: true
          volumes:
          - name: rclone-config
            secret:
              secretName: s3-backup-creds
```

---

<a name="migration"></a>
## 7. Migration Path & Backward Compatibility

### Backward Compatibility

**Existing behavior preserved:**

```bash
# This still works exactly as before
crane transfer-pvc \
  --source-context=src \
  --destination-context=dst \
  --pvc-name=mydata
```

**Can be made explicit:**

```bash
crane transfer-pvc sync \
  --source-context=src \
  --destination-context=dst \
  --pvc-name=mydata
```

### Migration Guide

**Phase 1:** Add `export` and `import` subcommands (new feature)
**Phase 2:** Optionally add `sync` as explicit subcommand (alias to current behavior)
**Phase 3:** Consider deprecating top-level flags in favor of subcommands (breaking change, v2.0)

---

## 8. Required Code Changes

### 8.1 New Files to Create

```
crane/
├── cmd/transfer-pvc/
│   ├── export.go          # NEW: Export command
│   ├── import.go          # NEW: Import command
│   ├── sync.go            # Optional: Explicit sync subcommand
│   └── common.go          # Shared rclone config loading
├── pkg/transfer/rclone/
│   ├── export.go          # Export engine
│   ├── import.go          # Import engine
│   └── config.go          # rclone configuration helpers
└── docs/
    └── pvc-offline-export-import.md  # User documentation
```

### 8.2 Modified Files

```
crane/
├── cmd/transfer-pvc/transfer-pvc.go  # Add subcommands
└── go.mod                            # Add rclone dependency
```

### 8.3 New Dependencies

```go
// go.mod
require (
    github.com/rclone/rclone v1.68.2  // Already proposed for sync
)
```

---

## 9. RBAC Requirements

### For Export

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: crane-export
  namespace: production
rules:
  # Read PVC
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list"]
  
  # Create export Pod
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "get", "list", "delete"]
  
  # Read rclone config Secret
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
    resourceNames: ["s3-backup-creds"]
```

### For Import

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: crane-import
  namespace: recovery
rules:
  # Create/Read PVC
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["create", "get", "list"]
  
  # Create import Pod
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["create", "get", "list", "delete"]
  
  # Read rclone config Secret
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
```

---

## 10. Testing Strategy

### Unit Tests

```go
func TestExportCommand_Run(t *testing.T) {
    tests := []struct {
        name        string
        pvcName     string
        destination string
        wantErr     bool
    }{
        {
            name:        "export to S3",
            pvcName:     "test-pvc",
            destination: "s3:test-bucket/data",
            wantErr:     false,
        },
        {
            name:        "invalid destination",
            pvcName:     "test-pvc",
            destination: "invalid://bad",
            wantErr:     true,
        },
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            // Test export command
        })
    }
}
```

### Integration Tests

```bash
# Test export to MinIO (S3-compatible)
kind create cluster
kubectl apply -f test/minio.yaml  # Deploy MinIO

# Create test PVC with data
kubectl apply -f test/test-pvc.yaml

# Run export
crane transfer-pvc export \
  --pvc-name=test-data \
  --destination=s3:test-bucket/data \
  --rclone-config-secret=minio-creds

# Verify data in MinIO
mc ls minio/test-bucket/data
```

---

## 11. Performance Considerations

### Export Performance

**Factors:**
- PVC size
- Number of files
- Network bandwidth to cloud storage
- Compression enabled

**Optimization:**
- Use `--transfers=16` for many small files
- Use `--bandwidth-limit` to avoid saturation
- Use `--compress` for text/log files
- Skip compression for already compressed data (videos, archives)

**Example benchmarks:**

| PVC Size | Files | Destination | Time (uncompressed) | Time (compressed) |
|----------|-------|-------------|---------------------|-------------------|
| 10GB | 100K | S3 (same region) | 3 min | 2 min |
| 100GB | 1M | S3 (same region) | 25 min | 18 min |
| 1TB | 10M | S3 (cross-region) | 4 hours | 3 hours |

---

## 12. Cost Analysis

### Storage Costs (S3 Standard vs PVC)

| Storage Type | Cost per TB/month | Use Case |
|--------------|-------------------|----------|
| **Kubernetes PVC (EBS gp3)** | ~$80-100 | Active workloads |
| **S3 Standard** | ~$23 | Frequently accessed archives |
| **S3 Infrequent Access** | ~$12.50 | Monthly accessed archives |
| **S3 Glacier Instant** | ~$4 | Rarely accessed, instant retrieval |
| **S3 Glacier Flexible** | ~$3.60 | Rarely accessed, minutes retrieval |
| **S3 Glacier Deep Archive** | ~$1 | Compliance, 12h retrieval |

**Cost savings example:**

Archiving 10TB of old PVC data:
- **PVC cost:** $800-1000/month
- **S3 Glacier Deep Archive:** $10/month
- **Savings:** ~$990/month = $11,880/year

---

## 13. Security Considerations

### Encryption at Rest

**Option 1: Cloud provider encryption (easiest)**
- S3: SSE-S3, SSE-KMS
- GCS: Default encryption
- Azure: Storage Service Encryption

**Option 2: rclone crypt (client-side, most secure)**

```bash
crane transfer-pvc export \
  --destination=encrypted-s3:backup/data \
  --encryption-password-secret=encryption-key
```

Data encrypted before leaving cluster.

### Access Control

**S3 Bucket Policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789:role/crane-backup-role"
      },
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-backup-bucket/*",
        "arn:aws:s3:::my-backup-bucket"
      ]
    }
  ]
}
```

---

## 14. Monitoring & Observability

### Metrics to Track

```go
var (
    exportBytesTotal = prometheus.NewCounter(
        prometheus.CounterOpts{
            Name: "crane_export_bytes_total",
            Help: "Total bytes exported to cloud storage",
        },
    )
    
    exportDuration = prometheus.NewHistogram(
        prometheus.HistogramOpts{
            Name: "crane_export_duration_seconds",
            Help: "Duration of export operations",
            Buckets: prometheus.ExponentialBuckets(60, 2, 10),
        },
    )
    
    exportErrors = prometheus.NewCounter(
        prometheus.CounterOpts{
            Name: "crane_export_errors_total",
            Help: "Total export errors",
        },
    )
)
```

### Logging

```bash
# Example output
2026-07-03T10:00:00Z INFO Starting export pvc=postgres-data destination=s3:backups/postgres/20260703
2026-07-03T10:00:05Z INFO Transfer progress transferred=1.2GB total=10GB rate=240MB/s eta=40s
2026-07-03T10:00:45Z INFO Export completed bytes=10GB duration=45s files=125000
```

---

## 15. Summary & Recommendations

### ✅ What to Implement

1. **Phase 1: Core Export/Import** (2-3 weeks)
   - `crane transfer-pvc export` to S3/GCS/Azure
   - `crane transfer-pvc import` from S3/GCS/Azure
   - Use rclone as Go library
   - Basic Secret-based config

2. **Phase 2: Enhanced Features** (1 week)
   - Auto-create PVC on import (`--create-pvc`)
   - Compression support (`--compress`)
   - Bandwidth limiting
   - Progress reporting

3. **Phase 3: Advanced Features** (1 week)
   - Encryption support (`--encrypt`)
   - Scheduled backups (CronJob examples)
   - Multi-cloud support (S3 → GCS)

### 🎯 Key Benefits

- ✅ **Cost savings:** $10/TB/month vs $100/TB/month for PVC
- ✅ **Disaster recovery:** Cross-cloud, cross-region backups
- ✅ **Compliance:** Long-term archival
- ✅ **Flexibility:** Works with any cloud provider (rclone supports 40+)
- ✅ **No EPEL issues:** rclone as Go library

### 📊 Estimated Effort

| Phase | Features | Effort |
|-------|----------|--------|
| Phase 1 | Core export/import, S3/GCS/Azure | 2-3 weeks |
| Phase 2 | Enhanced features | 1 week |
| Phase 3 | Advanced features | 1 week |
| **Total** | | **4-5 weeks** |

---

## 16. Open Questions

1. **Should we support incremental exports?**
   - Full export every time vs incremental?
   - rclone supports this via checksums

2. **Should we support multi-part archives?**
   - Split large PVCs into multiple archives?
   - Useful for 1TB+ PVCs

3. **Should we add list/verify subcommands?**
   ```bash
   crane transfer-pvc list s3:backups/  # List available exports
   crane transfer-pvc verify s3:backups/postgres/20260703  # Verify integrity
   ```

4. **Should we support direct S3 → S3 migration?**
   ```bash
   crane transfer-pvc copy \
     --source=s3:old-bucket/data \
     --destination=s3:new-bucket/data
   ```

---

**End of Proposal**

**Next Steps:**
1. Review proposal with team
2. Decide on Phase 1 scope
3. Create implementation tasks
4. Start with basic export/import to S3
