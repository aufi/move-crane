# PVC Local Export/Import - Laptop Storage

**Date:** 2026-07-03  
**Status:** Proposal Extension  
**Purpose:** Add local filesystem export/import to `crane transfer-pvc` (save to laptop running crane CLI)

---

## Executive Summary

Extend `crane transfer-pvc` to support export/import to **local filesystem** on the machine running crane CLI.

**Use cases:**
- Quick backup to laptop before major changes
- Offline transfer via USB drive / external disk
- Air-gapped environments (no cloud connectivity)
- Development/testing without cloud storage

---

## Architecture

### Export to Local Filesystem (PVC → Laptop)

```
┌─────────────────────────────────┐         ┌──────────────────┐
│  Kubernetes Cluster             │         │  Laptop          │
│                                 │         │                  │
│  ┌───────────────────────────┐ │         │  crane CLI       │
│  │  Temp Pod: rsync-server   │ │         │                  │
│  │  - Mounts PVC (ReadOnly)  │ │◀────────│  Pulls data via  │
│  │  - Runs rsyncd daemon     │ │  rsync  │  rsync           │
│  │  - Port-forwarded         │ │         │                  │
│  └───────────────────────────┘ │         │  Saves to:       │
│            ▲                    │         │  /tmp/backup/    │
│            │                    │         │  or              │
│     ┌──────┴────────┐          │         │  ~/backups/      │
│     │  PVC: mydata  │          │         │  mydata.tar.gz   │
│     └───────────────┘          │         │                  │
└─────────────────────────────────┘         └──────────────────┘
```

### Import from Local Filesystem (Laptop → PVC)

```
┌─────────────────────────────────┐         ┌──────────────────┐
│  Kubernetes Cluster             │         │  Laptop          │
│                                 │         │                  │
│  ┌───────────────────────────┐ │         │  crane CLI       │
│  │  Temp Pod: rsync-client   │ │         │                  │
│  │  - Mounts PVC (ReadWrite) │ │◀────────│  Pushes data via │
│  │  - Receives from crane    │ │  rsync  │  rsync           │
│  │  - Port-forwarded         │ │         │                  │
│  └───────────────────────────┘ │         │  Reads from:     │
│            │                    │         │  ~/backups/      │
│     ┌──────▼────────┐          │         │  mydata.tar.gz   │
│     │  PVC: mydata  │          │         │                  │
│     └───────────────┘          │         │                  │
└─────────────────────────────────┘         └──────────────────┘
```

---

## CLI Interface

### Export to Local File

```bash
# Export to local file (tar.gz)
crane transfer-pvc export \
  --pvc-name=postgres-data \
  --pvc-namespace=production \
  --context=prod-cluster \
  --destination=local:///tmp/backups/postgres-2026-07-03.tar.gz \
  --compress

# Alternative: Use filesystem path directly (no "local://" prefix)
crane transfer-pvc export \
  --pvc-name=postgres-data \
  --context=prod-cluster \
  --destination=/tmp/backups/postgres-2026-07-03.tar.gz \
  --compress

# Export to current directory
crane transfer-pvc export \
  --pvc-name=app-data \
  --context=cluster \
  --destination=./app-data-backup.tar.gz
```

### Import from Local File

```bash
# Import from local file
crane transfer-pvc import \
  --source=local:///tmp/backups/postgres-2026-07-03.tar.gz \
  --pvc-name=postgres-restored \
  --pvc-namespace=recovery \
  --context=dr-cluster \
  --create-pvc \
  --storage-class=fast-ssd \
  --pvc-size=100Gi

# Alternative: Use filesystem path directly
crane transfer-pvc import \
  --source=/tmp/backups/postgres-2026-07-03.tar.gz \
  --pvc-name=postgres-restored \
  --context=dr-cluster \
  --create-pvc
```

### Export to Directory (uncompressed)

```bash
# Export as directory structure (useful for inspection/modification)
crane transfer-pvc export \
  --pvc-name=app-data \
  --context=cluster \
  --destination=local:///tmp/backups/app-data/ \
  --format=directory

# Later: Import from directory
crane transfer-pvc import \
  --source=local:///tmp/backups/app-data/ \
  --pvc-name=app-data-restored \
  --context=cluster
```

---

## Implementation

### Destination URL Parsing

```go
// pkg/transfer/storage/parser.go
package storage

import (
    "fmt"
    "net/url"
    "strings"
)

type DestinationType int

const (
    DestinationLocal DestinationType = iota
    DestinationS3
    DestinationGCS
    DestinationAzure
)

type Destination struct {
    Type     DestinationType
    Path     string
    Bucket   string
    Adapter  Adapter  // nil for local
}

func ParseDestination(dest string) (*Destination, error) {
    // Check for explicit local:// prefix
    if strings.HasPrefix(dest, "local://") {
        return &Destination{
            Type: DestinationLocal,
            Path: strings.TrimPrefix(dest, "local://"),
        }, nil
    }
    
    // Check if it's a filesystem path (starts with / or ./ or ~/)
    if strings.HasPrefix(dest, "/") || 
       strings.HasPrefix(dest, "./") || 
       strings.HasPrefix(dest, "~/") {
        return &Destination{
            Type: DestinationLocal,
            Path: dest,
        }, nil
    }
    
    // Parse as URL
    u, err := url.Parse(dest)
    if err != nil {
        return nil, fmt.Errorf("invalid destination: %w", err)
    }
    
    switch u.Scheme {
    case "s3":
        return &Destination{
            Type:   DestinationS3,
            Bucket: u.Host,
            Path:   strings.TrimPrefix(u.Path, "/"),
        }, nil
    
    case "gcs":
        return &Destination{
            Type:   DestinationGCS,
            Bucket: u.Host,
            Path:   strings.TrimPrefix(u.Path, "/"),
        }, nil
    
    case "azure":
        return &Destination{
            Type:   DestinationAzure,
            Bucket: u.Host,
            Path:   strings.TrimPrefix(u.Path, "/"),
        }, nil
    
    default:
        return nil, fmt.Errorf("unsupported scheme: %s", u.Scheme)
    }
}
```

---

### Export to Local File

```go
// cmd/transfer-pvc/export_local.go
package transfer_pvc

import (
    "archive/tar"
    "compress/gzip"
    "context"
    "fmt"
    "io"
    "os"
    "os/exec"
    "path/filepath"
)

type LocalExportCommand struct {
    PVCName      string
    PVCNamespace string
    Context      string
    Destination  string  // Local file path
    Compress     bool
    Format       string  // "archive" or "directory"
}

func (e *LocalExportCommand) Run(ctx context.Context) error {
    // 1. Expand ~ to home directory
    destPath, err := expandPath(e.Destination)
    if err != nil {
        return err
    }
    
    // 2. Create destination directory if needed
    destDir := filepath.Dir(destPath)
    if err := os.MkdirAll(destDir, 0755); err != nil {
        return fmt.Errorf("failed to create destination directory: %w", err)
    }
    
    if e.Format == "directory" {
        return e.exportAsDirectory(ctx, destPath)
    }
    
    return e.exportAsArchive(ctx, destPath)
}

func (e *LocalExportCommand) exportAsArchive(ctx context.Context, destPath string) error {
    // 1. Create temporary rsync server pod in cluster
    pod, cleanup, err := e.createRsyncServerPod(ctx)
    if err != nil {
        return fmt.Errorf("failed to create rsync server: %w", err)
    }
    defer cleanup()
    
    // 2. Port-forward to rsync server
    stopCh := make(chan struct{})
    defer close(stopCh)
    
    localPort, err := e.setupPortForward(ctx, pod, stopCh)
    if err != nil {
        return fmt.Errorf("failed to setup port-forward: %w", err)
    }
    
    log.Printf("Port-forwarding established on localhost:%d", localPort)
    
    // 3. Create local archive file
    archiveFile, err := os.Create(destPath)
    if err != nil {
        return err
    }
    defer archiveFile.Close()
    
    var archiveWriter io.Writer = archiveFile
    
    // 4. Add compression if requested
    if e.Compress || filepath.Ext(destPath) == ".gz" {
        gzipWriter := gzip.NewWriter(archiveFile)
        defer gzipWriter.Close()
        archiveWriter = gzipWriter
    }
    
    tarWriter := tar.NewWriter(archiveWriter)
    defer tarWriter.Close()
    
    // 5. Pull data from cluster via rsync
    log.Printf("Pulling data from PVC %s/%s to %s", e.PVCNamespace, e.PVCName, destPath)
    
    return e.rsyncPullToTar(ctx, localPort, tarWriter)
}

func (e *LocalExportCommand) rsyncPullToTar(ctx context.Context, localPort int, tarWriter *tar.Writer) error {
    // Create temporary directory to receive rsync data
    tempDir, err := os.MkdirTemp("", "crane-export-*")
    if err != nil {
        return err
    }
    defer os.RemoveAll(tempDir)
    
    // Run rsync to pull data from cluster to temp directory
    rsyncCmd := exec.CommandContext(ctx, "rsync",
        "-avz",
        "--progress",
        fmt.Sprintf("rsync://crane@localhost:%d/data/", localPort),
        tempDir+"/",
    )
    rsyncCmd.Stdout = os.Stdout
    rsyncCmd.Stderr = os.Stderr
    
    if err := rsyncCmd.Run(); err != nil {
        return fmt.Errorf("rsync failed: %w", err)
    }
    
    // Add files from temp directory to tar archive
    return filepath.Walk(tempDir, func(path string, info os.FileInfo, err error) error {
        if err != nil {
            return err
        }
        
        // Create tar header
        header, err := tar.FileInfoHeader(info, "")
        if err != nil {
            return err
        }
        
        // Set relative path
        relPath, err := filepath.Rel(tempDir, path)
        if err != nil {
            return err
        }
        header.Name = relPath
        
        // Write header
        if err := tarWriter.WriteHeader(header); err != nil {
            return err
        }
        
        // Write file content (if regular file)
        if info.Mode().IsRegular() {
            file, err := os.Open(path)
            if err != nil {
                return err
            }
            defer file.Close()
            
            if _, err := io.Copy(tarWriter, file); err != nil {
                return err
            }
        }
        
        return nil
    })
}

func (e *LocalExportCommand) exportAsDirectory(ctx context.Context, destPath string) error {
    // Create destination directory
    if err := os.MkdirAll(destPath, 0755); err != nil {
        return err
    }
    
    // Create temporary rsync server pod
    pod, cleanup, err := e.createRsyncServerPod(ctx)
    if err != nil {
        return err
    }
    defer cleanup()
    
    // Port-forward
    stopCh := make(chan struct{})
    defer close(stopCh)
    
    localPort, err := e.setupPortForward(ctx, pod, stopCh)
    if err != nil {
        return err
    }
    
    // Rsync directly to destination directory
    log.Printf("Pulling data from PVC %s/%s to directory %s", 
        e.PVCNamespace, e.PVCName, destPath)
    
    rsyncCmd := exec.CommandContext(ctx, "rsync",
        "-avz",
        "--progress",
        fmt.Sprintf("rsync://crane@localhost:%d/data/", localPort),
        destPath+"/",
    )
    rsyncCmd.Stdout = os.Stdout
    rsyncCmd.Stderr = os.Stderr
    
    return rsyncCmd.Run()
}

func expandPath(path string) (string, error) {
    if strings.HasPrefix(path, "~/") {
        home, err := os.UserHomeDir()
        if err != nil {
            return "", err
        }
        return filepath.Join(home, path[2:]), nil
    }
    return filepath.Abs(path)
}
```

---

### Import from Local File

```go
// cmd/transfer-pvc/import_local.go
package transfer_pvc

import (
    "archive/tar"
    "compress/gzip"
    "context"
    "fmt"
    "io"
    "os"
    "os/exec"
    "path/filepath"
    "strings"
)

type LocalImportCommand struct {
    Source          string  // Local file path
    PVCName         string
    PVCNamespace    string
    Context         string
    CreatePVC       bool
    StorageClass    string
    PVCSize         string
}

func (i *LocalImportCommand) Run(ctx context.Context) error {
    // 1. Expand ~ to home directory
    sourcePath, err := expandPath(i.Source)
    if err != nil {
        return err
    }
    
    // 2. Check if source exists
    sourceInfo, err := os.Stat(sourcePath)
    if err != nil {
        return fmt.Errorf("source not found: %w", err)
    }
    
    // 3. Ensure PVC exists
    if i.CreatePVC {
        if err := i.ensurePVCExists(ctx); err != nil {
            return err
        }
    }
    
    // 4. Import based on source type
    if sourceInfo.IsDir() {
        return i.importFromDirectory(ctx, sourcePath)
    }
    
    return i.importFromArchive(ctx, sourcePath)
}

func (i *LocalImportCommand) importFromArchive(ctx context.Context, sourcePath string) error {
    // 1. Create temporary directory to extract archive
    tempDir, err := os.MkdirTemp("", "crane-import-*")
    if err != nil {
        return err
    }
    defer os.RemoveAll(tempDir)
    
    // 2. Extract archive to temp directory
    log.Printf("Extracting archive %s", sourcePath)
    
    if err := i.extractArchive(sourcePath, tempDir); err != nil {
        return fmt.Errorf("extraction failed: %w", err)
    }
    
    // 3. Push to cluster via rsync
    return i.importFromDirectory(ctx, tempDir)
}

func (i *LocalImportCommand) importFromDirectory(ctx context.Context, sourcePath string) error {
    // 1. Create temporary rsync client pod in cluster
    pod, cleanup, err := i.createRsyncClientPod(ctx)
    if err != nil {
        return err
    }
    defer cleanup()
    
    // 2. Port-forward
    stopCh := make(chan struct{})
    defer close(stopCh)
    
    localPort, err := i.setupPortForward(ctx, pod, stopCh)
    if err != nil {
        return err
    }
    
    log.Printf("Port-forwarding established on localhost:%d", localPort)
    
    // 3. Push data to cluster via rsync
    log.Printf("Pushing data from %s to PVC %s/%s", 
        sourcePath, i.PVCNamespace, i.PVCName)
    
    rsyncCmd := exec.CommandContext(ctx, "rsync",
        "-avz",
        "--progress",
        sourcePath+"/",
        fmt.Sprintf("rsync://crane@localhost:%d/data/", localPort),
    )
    rsyncCmd.Stdout = os.Stdout
    rsyncCmd.Stderr = os.Stderr
    
    return rsyncCmd.Run()
}

func (i *LocalImportCommand) extractArchive(archivePath, destDir string) error {
    file, err := os.Open(archivePath)
    if err != nil {
        return err
    }
    defer file.Close()
    
    var archiveReader io.Reader = file
    
    // Handle gzip compression
    if strings.HasSuffix(archivePath, ".gz") || strings.HasSuffix(archivePath, ".tgz") {
        gzipReader, err := gzip.NewReader(file)
        if err != nil {
            return err
        }
        defer gzipReader.Close()
        archiveReader = gzipReader
    }
    
    // Extract tar
    tarReader := tar.NewReader(archiveReader)
    
    for {
        header, err := tarReader.Next()
        if err == io.EOF {
            break
        }
        if err != nil {
            return err
        }
        
        targetPath := filepath.Join(destDir, header.Name)
        
        switch header.Typeflag {
        case tar.TypeDir:
            if err := os.MkdirAll(targetPath, os.FileMode(header.Mode)); err != nil {
                return err
            }
        
        case tar.TypeReg:
            if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
                return err
            }
            
            outFile, err := os.Create(targetPath)
            if err != nil {
                return err
            }
            
            if _, err := io.Copy(outFile, tarReader); err != nil {
                outFile.Close()
                return err
            }
            outFile.Close()
            
            if err := os.Chmod(targetPath, os.FileMode(header.Mode)); err != nil {
                return err
            }
        }
    }
    
    return nil
}
```

---

## Usage Examples

### Example 1: Quick Backup Before Upgrade

```bash
# Backup to laptop before cluster upgrade
crane transfer-pvc export \
  --pvc-name=important-data \
  --context=prod \
  --destination=~/backups/prod-important-data-$(date +%Y%m%d).tar.gz \
  --compress

# If upgrade fails, restore quickly
crane transfer-pvc import \
  --source=~/backups/prod-important-data-20260703.tar.gz \
  --pvc-name=important-data \
  --context=prod
```

---

### Example 2: Offline Transfer via USB Drive

```bash
# On source cluster (connected laptop)
crane transfer-pvc export \
  --pvc-name=database-data \
  --context=source-cluster \
  --destination=/mnt/usb-drive/database-backup.tar.gz \
  --compress

# Physically move USB drive to air-gapped environment

# On target cluster (different laptop, air-gapped)
crane transfer-pvc import \
  --source=/mnt/usb-drive/database-backup.tar.gz \
  --pvc-name=database-data \
  --context=airgapped-cluster \
  --create-pvc \
  --storage-class=local-path \
  --pvc-size=100Gi
```

---

### Example 3: Export for Inspection/Modification

```bash
# Export as directory (not compressed)
crane transfer-pvc export \
  --pvc-name=config-data \
  --context=prod \
  --destination=~/temp/config-data/ \
  --format=directory

# Modify files locally
cd ~/temp/config-data/
vim application.yaml
# ... make changes ...

# Import modified data back
crane transfer-pvc import \
  --source=~/temp/config-data/ \
  --pvc-name=config-data-modified \
  --context=test-cluster \
  --create-pvc
```

---

### Example 4: Development Data Snapshot

```bash
# Developer: Pull production data to laptop for local development
crane transfer-pvc export \
  --pvc-name=prod-db \
  --context=prod-cluster \
  --destination=./prod-db-snapshot.tar.gz

# Import to local kind cluster
crane transfer-pvc import \
  --source=./prod-db-snapshot.tar.gz \
  --pvc-name=dev-db \
  --context=kind-dev-cluster \
  --create-pvc \
  --storage-class=standard
```

---

## Advantages of Local Export/Import

### ✅ Benefits

1. **No cloud dependency** - Works in air-gapped environments
2. **Quick ad-hoc backups** - Save to laptop before risky operations
3. **Physical transfer** - USB drive for offline migration
4. **Inspection & modification** - Export, edit, re-import
5. **Cost-free storage** - No S3/GCS costs
6. **Privacy** - Data never leaves your infrastructure
7. **Simple debugging** - Extract and inspect files locally

### ⚠️ Limitations

1. **Laptop must stay online** - During entire transfer
2. **Network speed** - Limited by laptop's connection to cluster
3. **Disk space** - Laptop must have enough space for archive
4. **No incremental** - Full export each time
5. **Single-threaded** - rsync limitation

---

## Integration with Existing Proposals

### Unified CLI Interface

All three approaches use same commands:

```bash
# Local filesystem
crane transfer-pvc export --destination=/tmp/backup.tar.gz

# Cloud storage (rsync + SDKs)
crane transfer-pvc export --destination=s3://bucket/backup.tar.gz

# Cloud storage (rclone library)
crane transfer-pvc export --engine=rclone --destination=s3://bucket/path/
```

### Automatic Detection

```go
// pkg/transfer/storage/parser.go
func ParseDestination(dest string) (*Destination, error) {
    // 1. Check for local filesystem path
    if isLocalPath(dest) {
        return &Destination{Type: DestinationLocal, Path: dest}, nil
    }
    
    // 2. Check for cloud URL
    if strings.Contains(dest, "://") {
        return parseCloudURL(dest)
    }
    
    return nil, fmt.Errorf("invalid destination")
}

func isLocalPath(dest string) bool {
    return strings.HasPrefix(dest, "/") ||
           strings.HasPrefix(dest, "./") ||
           strings.HasPrefix(dest, "~/") ||
           strings.HasPrefix(dest, "local://")
}
```

---

## Implementation Estimate

| Task | Effort |
|------|--------|
| URL parser enhancement (local path detection) | 2 hours |
| Port-forward setup helper | 4 hours |
| Export to local file (tar.gz) | 1 day |
| Import from local file (tar.gz) | 1 day |
| Export to local directory | 4 hours |
| Import from local directory | 4 hours |
| Testing & documentation | 1 day |
| **Total** | **3 days** |

**Very quick to add** because:
- Reuses existing rsync infrastructure
- No new dependencies (uses stdlib archive/tar, compress/gzip)
- Port-forwarding already used in crane

---

## Complete Feature Matrix

| Destination | rclone Library | rsync + SDKs | rsync + Local |
|-------------|---------------|--------------|---------------|
| **Local filesystem** | ✅ (via rclone local backend) | ❌ | ✅ (this proposal) |
| **S3** | ✅ | ✅ | ❌ |
| **GCS** | ✅ | ✅ | ❌ |
| **Azure** | ✅ | ✅ | ❌ |
| **40+ providers** | ✅ | ❌ | ❌ |
| **Multi-threaded** | ✅ | ❌ | ❌ |
| **Air-gapped** | ✅ | ❌ | ✅ |
| **No cloud costs** | ✅ | ❌ | ✅ |
| **Incremental** | ✅ | ❌ | ❌ |

---

## Security Considerations

### Local File Permissions

```go
// Ensure exported files have appropriate permissions
func createSecureArchive(path string) (*os.File, error) {
    // Create with restrictive permissions (0600 = rw-------)
    return os.OpenFile(path, os.O_CREATE|os.O_WRONLY, 0600)
}
```

### Encryption at Rest

```bash
# User can encrypt locally after export
crane transfer-pvc export \
  --destination=~/backup.tar.gz \
  --context=cluster

# Encrypt with GPG
gpg --symmetric --cipher-algo AES256 ~/backup.tar.gz
# Creates: ~/backup.tar.gz.gpg

# Later: Decrypt and import
gpg --decrypt ~/backup.tar.gz.gpg > ~/backup.tar.gz
crane transfer-pvc import --source=~/backup.tar.gz
```

---

## Recommended Implementation Order

### Phase 1: Local Export/Import (3 days)
- Export PVC → local tar.gz
- Import local tar.gz → PVC
- Directory format support

### Phase 2: Cloud Storage (2.5 weeks)
- rsync + cloud SDKs (S3, GCS, Azure)
- OR rclone library approach

### Phase 3: Enhanced Features (1 week)
- Progress reporting
- Bandwidth limiting
- Resume support (for cloud)
- Incremental sync (for rclone)

---

## Summary

**Local export/import is the simplest and fastest feature to implement:**

✅ **Advantages:**
- Only 3 days implementation
- No new dependencies
- Reuses existing rsync infrastructure
- Works in air-gapped environments
- No cloud costs

✅ **Perfect for:**
- Quick backups before risky operations
- Physical offline transfer (USB drive)
- Air-gapped migrations
- Development/testing workflows
- Privacy-sensitive data

**Recommended:** Implement this FIRST (3 days), then add cloud storage support later.

---

**Related proposals:**
- [PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md](PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md) - rclone-based (cloud + local)
- [PVC_EXPORT_IMPORT_RSYNC_PROPOSAL.md](PVC_EXPORT_IMPORT_RSYNC_PROPOSAL.md) - rsync + cloud SDKs
