# PVC Offline Export/Import using rsync - Alternative Proposal

**Date:** 2026-07-03  
**Status:** Alternative Proposal  
**Purpose:** Extend `crane transfer-pvc` for offline export/import **without rclone dependency**

---

## Executive Summary

This proposal provides an alternative to the rclone-based approach, using **existing rsync** + minimal new libraries for cloud storage access.

**Key differences from rclone proposal:**
- ✅ Reuses existing rsync infrastructure
- ✅ Minimal new dependencies (AWS SDK, GCS SDK, Azure SDK only)
- ✅ Smaller code footprint
- ❌ No multi-threaded transfers (rsync limitation)
- ❌ Separate implementation per cloud provider

---

## Table of Contents

1. [Architecture Overview](#architecture)
2. [Cloud Storage Adapters](#adapters)
3. [Implementation Approach](#implementation)
4. [CLI Interface](#cli)
5. [Code Structure](#code-structure)
6. [Dependencies](#dependencies)
7. [Comparison with rclone Approach](#comparison)

---

<a name="architecture"></a>
## 1. Architecture Overview

### Export Flow (PVC → Cloud Storage)

```
┌─────────────────────────────────────────────┐
│  Kubernetes Cluster                         │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │  Pod: crane-export-mydata             │ │
│  │                                       │ │
│  │  1. rsync → local tar archive         │ │
│  │     /mnt/pvc → /tmp/archive.tar       │ │
│  │                                       │ │
│  │  2. Cloud SDK uploads tar             │ │         ┌──────────────┐
│  │     AWS SDK / GCS SDK / Azure SDK     │ │────────▶│  S3 Bucket   │
│  │     /tmp/archive.tar → s3://bucket    │ │         │              │
│  │                                       │ │         │  backup.tar  │
│  └───────────────────────────────────────┘ │         └──────────────┘
│        ▲                                    │
│        │ mount (ReadOnly)                   │
│  ┌─────┴────────┐                          │
│  │  PVC: mydata │                          │
│  └──────────────┘                          │
└─────────────────────────────────────────────┘
```

### Import Flow (Cloud Storage → PVC)

```
┌─────────────────────────────────────────────┐
│  Kubernetes Cluster                         │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │  Pod: crane-import-mydata             │ │
│  │                                       │ │         ┌──────────────┐
│  │  1. Cloud SDK downloads tar           │ │◀────────│  S3 Bucket   │
│  │     s3://bucket → /tmp/archive.tar    │ │         │              │
│  │                                       │ │         │  backup.tar  │
│  │  2. Extract to PVC                    │ │         └──────────────┘
│  │     /tmp/archive.tar → /mnt/pvc       │ │
│  │                                       │ │
│  └───────────────────────────────────────┘ │
│        │ mount (ReadWrite)                  │
│  ┌─────▼────────┐                          │
│  │  PVC: mydata │                          │
│  └──────────────┘                          │
└─────────────────────────────────────────────┘
```

---

<a name="adapters"></a>
## 2. Cloud Storage Adapters

### Adapter Interface

```go
// pkg/transfer/storage/adapter.go
package storage

import (
    "context"
    "io"
)

// Adapter provides interface to cloud storage providers
type Adapter interface {
    // Upload uploads data stream to cloud storage
    Upload(ctx context.Context, key string, reader io.Reader) error
    
    // Download downloads data from cloud storage
    Download(ctx context.Context, key string, writer io.Writer) error
    
    // ListObjects lists objects with given prefix
    ListObjects(ctx context.Context, prefix string) ([]ObjectInfo, error)
    
    // GetObjectInfo returns metadata about object
    GetObjectInfo(ctx context.Context, key string) (*ObjectInfo, error)
    
    // DeleteObject deletes object from storage
    DeleteObject(ctx context.Context, key string) error
}

type ObjectInfo struct {
    Key          string
    Size         int64
    LastModified time.Time
    ETag         string
}

// ParseStorageURL parses URL like "s3://bucket/path" into adapter
func ParseStorageURL(url string, credentials interface{}) (Adapter, error) {
    // Parse scheme (s3://, gcs://, azure://)
    // Create appropriate adapter
}
```

---

### S3 Adapter Implementation

```go
// pkg/transfer/storage/s3.go
package storage

import (
    "context"
    "io"
    
    "github.com/aws/aws-sdk-go-v2/aws"
    "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/s3"
    "github.com/aws/aws-sdk-go-v2/feature/s3/manager"
)

type S3Adapter struct {
    client   *s3.Client
    uploader *manager.Uploader
    bucket   string
}

func NewS3Adapter(bucket, region string, creds aws.Credentials) (*S3Adapter, error) {
    cfg, err := config.LoadDefaultConfig(context.Background(),
        config.WithRegion(region),
        config.WithCredentialsProvider(aws.CredentialsProviderFunc(
            func(ctx context.Context) (aws.Credentials, error) {
                return creds, nil
            },
        )),
    )
    if err != nil {
        return nil, err
    }
    
    client := s3.NewFromConfig(cfg)
    uploader := manager.NewUploader(client)
    
    return &S3Adapter{
        client:   client,
        uploader: uploader,
        bucket:   bucket,
    }, nil
}

func (s *S3Adapter) Upload(ctx context.Context, key string, reader io.Reader) error {
    _, err := s.uploader.Upload(ctx, &s3.PutObjectInput{
        Bucket: aws.String(s.bucket),
        Key:    aws.String(key),
        Body:   reader,
    })
    return err
}

func (s *S3Adapter) Download(ctx context.Context, key string, writer io.Writer) error {
    downloader := manager.NewDownloader(s.client)
    
    _, err := downloader.Download(ctx, 
        &awsWriterAt{writer: writer},
        &s3.GetObjectInput{
            Bucket: aws.String(s.bucket),
            Key:    aws.String(key),
        },
    )
    return err
}

// awsWriterAt wraps io.Writer to implement io.WriterAt for AWS SDK
type awsWriterAt struct {
    writer io.Writer
}

func (w *awsWriterAt) WriteAt(p []byte, off int64) (n int, err error) {
    // For streaming upload, ignore offset and just write sequentially
    return w.writer.Write(p)
}
```

---

### GCS Adapter Implementation

```go
// pkg/transfer/storage/gcs.go
package storage

import (
    "context"
    "io"
    
    "cloud.google.com/go/storage"
    "google.golang.org/api/option"
)

type GCSAdapter struct {
    client *storage.Client
    bucket string
}

func NewGCSAdapter(bucket string, credentialsJSON []byte) (*GCSAdapter, error) {
    ctx := context.Background()
    client, err := storage.NewClient(ctx, 
        option.WithCredentialsJSON(credentialsJSON))
    if err != nil {
        return nil, err
    }
    
    return &GCSAdapter{
        client: client,
        bucket: bucket,
    }, nil
}

func (g *GCSAdapter) Upload(ctx context.Context, key string, reader io.Reader) error {
    obj := g.client.Bucket(g.bucket).Object(key)
    writer := obj.NewWriter(ctx)
    
    if _, err := io.Copy(writer, reader); err != nil {
        writer.Close()
        return err
    }
    
    return writer.Close()
}

func (g *GCSAdapter) Download(ctx context.Context, key string, writer io.Writer) error {
    obj := g.client.Bucket(g.bucket).Object(key)
    reader, err := obj.NewReader(ctx)
    if err != nil {
        return err
    }
    defer reader.Close()
    
    _, err = io.Copy(writer, reader)
    return err
}
```

---

### Azure Adapter Implementation

```go
// pkg/transfer/storage/azure.go
package storage

import (
    "context"
    "io"
    
    "github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
)

type AzureAdapter struct {
    client        *azblob.Client
    containerName string
}

func NewAzureAdapter(accountName, accountKey, containerName string) (*AzureAdapter, error) {
    credential, err := azblob.NewSharedKeyCredential(accountName, accountKey)
    if err != nil {
        return nil, err
    }
    
    serviceURL := fmt.Sprintf("https://%s.blob.core.windows.net/", accountName)
    client, err := azblob.NewClientWithSharedKeyCredential(serviceURL, credential, nil)
    if err != nil {
        return nil, err
    }
    
    return &AzureAdapter{
        client:        client,
        containerName: containerName,
    }, nil
}

func (a *AzureAdapter) Upload(ctx context.Context, key string, reader io.Reader) error {
    _, err := a.client.UploadStream(ctx,
        a.containerName,
        key,
        reader,
        nil,
    )
    return err
}

func (a *AzureAdapter) Download(ctx context.Context, key string, writer io.Writer) error {
    resp, err := a.client.DownloadStream(ctx, a.containerName, key, nil)
    if err != nil {
        return err
    }
    defer resp.Body.Close()
    
    _, err = io.Copy(writer, resp.Body)
    return err
}
```

---

<a name="implementation"></a>
## 3. Implementation Approach

### Export Implementation

```go
// cmd/transfer-pvc/export.go
package transfer_pvc

import (
    "archive/tar"
    "compress/gzip"
    "context"
    "io"
    "os"
    "os/exec"
    "path/filepath"
    
    "github.com/konveyor/crane/pkg/transfer/storage"
)

type ExportCommand struct {
    PVCName        string
    PVCNamespace   string
    Destination    string  // "s3://bucket/path" or "gcs://bucket/path"
    Compress       bool
    RsyncFlags     []string
}

func (e *ExportCommand) Run(ctx context.Context) error {
    // 1. Parse destination URL
    adapter, archivePath, err := storage.ParseStorageURL(e.Destination)
    if err != nil {
        return fmt.Errorf("invalid destination: %w", err)
    }
    
    // 2. Create temporary archive using rsync + tar
    tempArchive := "/tmp/pvc-export.tar"
    if e.Compress {
        tempArchive += ".gz"
    }
    
    if err := e.createArchive(ctx, tempArchive); err != nil {
        return fmt.Errorf("failed to create archive: %w", err)
    }
    defer os.Remove(tempArchive)
    
    // 3. Upload to cloud storage
    log.Printf("Uploading archive to %s", e.Destination)
    
    file, err := os.Open(tempArchive)
    if err != nil {
        return err
    }
    defer file.Close()
    
    if err := adapter.Upload(ctx, archivePath, file); err != nil {
        return fmt.Errorf("upload failed: %w", err)
    }
    
    log.Printf("Export completed successfully")
    return nil
}

func (e *ExportCommand) createArchive(ctx context.Context, archivePath string) error {
    pvcMountPath := "/mnt/pvc-data"
    
    // Create archive file
    archiveFile, err := os.Create(archivePath)
    if err != nil {
        return err
    }
    defer archiveFile.Close()
    
    var archiveWriter io.Writer = archiveFile
    
    // Add gzip compression if requested
    if e.Compress {
        gzipWriter := gzip.NewWriter(archiveFile)
        defer gzipWriter.Close()
        archiveWriter = gzipWriter
    }
    
    // Create tar archive
    tarWriter := tar.NewWriter(archiveWriter)
    defer tarWriter.Close()
    
    // Walk PVC directory and add files to tar
    return filepath.Walk(pvcMountPath, func(path string, info os.FileInfo, err error) error {
        if err != nil {
            return err
        }
        
        // Create tar header
        header, err := tar.FileInfoHeader(info, "")
        if err != nil {
            return err
        }
        
        // Set relative path
        relPath, err := filepath.Rel(pvcMountPath, path)
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
```

---

### Import Implementation

```go
// cmd/transfer-pvc/import.go
package transfer_pvc

import (
    "archive/tar"
    "compress/gzip"
    "context"
    "io"
    "os"
    "path/filepath"
)

type ImportCommand struct {
    Source          string  // "s3://bucket/path"
    PVCName         string
    PVCNamespace    string
    CreatePVC       bool
    StorageClass    string
    PVCSize         string
}

func (i *ImportCommand) Run(ctx context.Context) error {
    // 1. Ensure PVC exists
    if i.CreatePVC {
        if err := i.ensurePVCExists(ctx); err != nil {
            return err
        }
    }
    
    // 2. Parse source URL
    adapter, archivePath, err := storage.ParseStorageURL(i.Source)
    if err != nil {
        return fmt.Errorf("invalid source: %w", err)
    }
    
    // 3. Download archive to temp file
    tempArchive := "/tmp/pvc-import.tar"
    defer os.Remove(tempArchive)
    
    log.Printf("Downloading archive from %s", i.Source)
    
    file, err := os.Create(tempArchive)
    if err != nil {
        return err
    }
    defer file.Close()
    
    if err := adapter.Download(ctx, archivePath, file); err != nil {
        return fmt.Errorf("download failed: %w", err)
    }
    
    // 4. Extract archive to PVC
    if err := i.extractArchive(ctx, tempArchive); err != nil {
        return fmt.Errorf("extraction failed: %w", err)
    }
    
    log.Printf("Import completed successfully")
    return nil
}

func (i *ImportCommand) extractArchive(ctx context.Context, archivePath string) error {
    pvcMountPath := "/mnt/pvc-data"
    
    // Open archive
    file, err := os.Open(archivePath)
    if err != nil {
        return err
    }
    defer file.Close()
    
    var archiveReader io.Reader = file
    
    // Detect and handle gzip compression
    if filepath.Ext(archivePath) == ".gz" {
        gzipReader, err := gzip.NewReader(file)
        if err != nil {
            return err
        }
        defer gzipReader.Close()
        archiveReader = gzipReader
    }
    
    // Extract tar archive
    tarReader := tar.NewReader(archiveReader)
    
    for {
        header, err := tarReader.Next()
        if err == io.EOF {
            break
        }
        if err != nil {
            return err
        }
        
        // Construct target path
        targetPath := filepath.Join(pvcMountPath, header.Name)
        
        switch header.Typeflag {
        case tar.TypeDir:
            // Create directory
            if err := os.MkdirAll(targetPath, os.FileMode(header.Mode)); err != nil {
                return err
            }
            
        case tar.TypeReg:
            // Create parent directory if needed
            if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
                return err
            }
            
            // Extract file
            outFile, err := os.Create(targetPath)
            if err != nil {
                return err
            }
            
            if _, err := io.Copy(outFile, tarReader); err != nil {
                outFile.Close()
                return err
            }
            outFile.Close()
            
            // Set permissions
            if err := os.Chmod(targetPath, os.FileMode(header.Mode)); err != nil {
                return err
            }
        }
    }
    
    return nil
}
```

---

<a name="cli"></a>
## 4. CLI Interface

### Export Command

```bash
crane transfer-pvc export \
  --pvc-name=postgres-data \
  --pvc-namespace=production \
  --context=prod-cluster \
  --destination=s3://backup-bucket/postgres/2026-07-03.tar.gz \
  --s3-credentials-secret=aws-creds \
  --compress
```

### Import Command

```bash
crane transfer-pvc import \
  --source=s3://backup-bucket/postgres/2026-07-03.tar.gz \
  --pvc-name=postgres-restored \
  --pvc-namespace=recovery \
  --context=dr-cluster \
  --s3-credentials-secret=aws-creds \
  --create-pvc \
  --storage-class=fast-ssd \
  --pvc-size=100Gi
```

### Credentials via Secret

**S3:**
```bash
kubectl create secret generic aws-creds \
  --from-literal=access-key-id=AKIAIOSFODNN7EXAMPLE \
  --from-literal=secret-access-key=wJalrXUtnFEMI/K7MDENG... \
  --from-literal=region=us-east-1
```

**GCS:**
```bash
kubectl create secret generic gcs-creds \
  --from-file=service-account.json=/path/to/sa.json
```

**Azure:**
```bash
kubectl create secret generic azure-creds \
  --from-literal=account-name=mystorageaccount \
  --from-literal=account-key=base64key==
```

---

<a name="code-structure"></a>
## 5. Code Structure

```
crane/
├── cmd/transfer-pvc/
│   ├── export.go              # NEW: Export command
│   ├── import.go              # NEW: Import command
│   └── transfer-pvc.go        # Modified: Add subcommands
│
├── pkg/transfer/
│   └── storage/
│       ├── adapter.go         # NEW: Interface definition
│       ├── s3.go              # NEW: S3 adapter
│       ├── gcs.go             # NEW: GCS adapter
│       ├── azure.go           # NEW: Azure adapter
│       └── parser.go          # NEW: URL parser
│
└── go.mod                     # Modified: Add cloud SDKs
```

---

<a name="dependencies"></a>
## 6. Dependencies

### Required Go Dependencies

```go
// go.mod
require (
    // AWS S3
    github.com/aws/aws-sdk-go-v2 v1.30.0
    github.com/aws/aws-sdk-go-v2/config v1.27.0
    github.com/aws/aws-sdk-go-v2/service/s3 v1.58.0
    github.com/aws/aws-sdk-go-v2/feature/s3/manager v1.17.0
    
    // Google Cloud Storage
    cloud.google.com/go/storage v1.43.0
    
    // Azure Blob Storage
    github.com/Azure/azure-sdk-for-go/sdk/storage/azblob v1.3.2
)
```

**Comparison with rclone:**
- rclone library: ~40-50MB binary increase
- Cloud SDKs only: ~10-15MB binary increase

---

<a name="comparison"></a>
## 7. Comparison: rsync+SDKs vs rclone

| Aspect | rsync + Cloud SDKs (this proposal) | rclone library |
|--------|-----------------------------------|----------------|
| **Binary size increase** | ~10-15MB | ~40-50MB |
| **Transfer speed** | Single-threaded (rsync) | Multi-threaded (16 parallel) |
| **Cloud providers** | S3, GCS, Azure only | 40+ providers |
| **Code complexity** | Medium (3 adapters) | Low (1 rclone call) |
| **Existing code reuse** | High (uses existing rsync) | None (new engine) |
| **Archive format** | tar/tar.gz (standard) | rclone sync (directory structure) |
| **Incremental sync** | No (full archive each time) | Yes (via checksums) |
| **Resume support** | No (download whole archive) | Yes (built-in) |
| **Compression** | gzip (single-threaded) | Multi-threaded compression |
| **Dependencies** | 3 cloud SDKs | 1 rclone library |

---

## 8. Alternative: Hybrid Approach

Combine both approaches - let user choose:

```bash
# rsync-based (tar archive)
crane transfer-pvc export \
  --engine=rsync \
  --destination=s3://bucket/archive.tar.gz

# rclone-based (sync directory structure)
crane transfer-pvc export \
  --engine=rclone \
  --destination=s3://bucket/path/
```

**Benefits:**
- rsync: Proven, smaller footprint, tar archives
- rclone: Faster, incremental, more cloud providers

**Implementation:**

```go
type ExportEngine interface {
    Export(ctx context.Context, pvcPath, destination string) error
}

type RsyncTarEngine struct {
    adapter storage.Adapter
}

type RcloneLibraryEngine struct {
    config RcloneConfig
}
```

---

## 9. Recommendations

### When to use rsync+SDKs approach:

✅ **Use this if:**
- Want minimal binary size increase
- Only need S3/GCS/Azure support
- Prefer standard tar/tar.gz archives
- Want to reuse existing rsync infrastructure
- Single-threaded transfer is acceptable

### When to use rclone library approach:

✅ **Use this if:**
- Need multi-threaded transfers (5-10x faster)
- Need incremental sync support
- Want 40+ cloud providers
- Want resume/retry built-in
- Binary size is not a concern

### Recommended Hybrid Strategy:

**Phase 1:** Implement rsync+SDKs (this proposal)
- Smaller scope, faster to deliver
- Proves concept with minimal changes
- S3/GCS/Azure covers 90% of use cases

**Phase 2:** Add rclone as alternative engine
- Advanced users can opt-in to rclone
- Better performance for large transfers
- More cloud providers

**Implementation:**
```bash
# Default: rsync-based
crane transfer-pvc export --destination=s3://bucket/archive.tar.gz

# Opt-in to rclone
crane transfer-pvc export --engine=rclone --destination=s3://bucket/path/
```

---

## 10. Implementation Estimate

| Phase | Features | Effort |
|-------|----------|--------|
| **Phase 1** | Storage adapter interface | 2 days |
| **Phase 2** | S3 adapter implementation | 2 days |
| **Phase 3** | GCS adapter implementation | 2 days |
| **Phase 4** | Azure adapter implementation | 2 days |
| **Phase 5** | Export command (tar creation) | 3 days |
| **Phase 6** | Import command (tar extraction) | 3 days |
| **Phase 7** | Testing & documentation | 3 days |
| **Total** | | **2.5 weeks** |

**Faster than rclone approach** (2.5 weeks vs 4-5 weeks) because:
- Reuses existing rsync knowledge
- Simpler adapter pattern
- Fewer features (no incremental, no multi-threading)

---

## 11. Example Usage

### Backup to S3

```bash
# 1. Create AWS credentials Secret
kubectl create secret generic aws-backup-creds \
  --from-literal=access-key-id=$AWS_ACCESS_KEY_ID \
  --from-literal=secret-access-key=$AWS_SECRET_ACCESS_KEY \
  --from-literal=region=us-east-1

# 2. Export PVC to S3
crane transfer-pvc export \
  --pvc-name=postgres-data \
  --pvc-namespace=production \
  --context=prod-cluster \
  --destination=s3://my-backups/postgres/2026-07-03.tar.gz \
  --s3-credentials-secret=aws-backup-creds \
  --compress

# 3. Later: Import from S3
crane transfer-pvc import \
  --source=s3://my-backups/postgres/2026-07-03.tar.gz \
  --pvc-name=postgres-restored \
  --pvc-namespace=recovery \
  --context=dr-cluster \
  --s3-credentials-secret=aws-backup-creds \
  --create-pvc \
  --storage-class=gp3 \
  --pvc-size=100Gi
```

---

## 12. Summary

**This proposal provides a simpler alternative** to the rclone-based approach:

✅ **Advantages:**
- Smaller binary size increase (~10-15MB vs ~40-50MB)
- Reuses existing rsync infrastructure
- Standard tar/tar.gz archives (portable)
- Faster to implement (2.5 weeks vs 4-5 weeks)
- Minimal new dependencies (3 cloud SDKs)

❌ **Disadvantages:**
- Single-threaded (slower for many files)
- No incremental sync
- Only S3/GCS/Azure (vs 40+ providers)
- No built-in resume/retry

**Recommended strategy:** Start with this approach (simpler, faster), optionally add rclone later for advanced use cases.

---

**Full rclone-based proposal:** [PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md](PVC_OFFLINE_EXPORT_IMPORT_PROPOSAL.md)
