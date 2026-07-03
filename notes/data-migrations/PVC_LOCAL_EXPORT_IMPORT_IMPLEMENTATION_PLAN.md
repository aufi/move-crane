# PVC Local Export/Import - Implementation Plan

**Date:** 2026-07-03  
**Estimated Effort:** 3 days (1 developer)  
**Proposal:** [PVC_LOCAL_EXPORT_IMPORT.md](PVC_LOCAL_EXPORT_IMPORT.md)

---

## Overview

Implementation plan for adding local filesystem export/import to `crane transfer-pvc`.

**Goal:** Enable users to export PVC data to their laptop and import it back.

**Deliverables:**
- `crane transfer-pvc export --destination=/path/to/file.tar.gz`
- `crane transfer-pvc import --source=/path/to/file.tar.gz`
- Support for both archive (tar.gz) and directory formats
- Comprehensive tests and documentation

---

## Table of Contents

1. [Day 1: Foundation & Export](#day-1)
2. [Day 2: Import & Testing](#day-2)
3. [Day 3: Polish & Documentation](#day-3)
4. [File Structure](#file-structure)
5. [Testing Strategy](#testing)
6. [Success Criteria](#success-criteria)

---

<a name="day-1"></a>
## Day 1: Foundation & Export (8 hours)

### Morning (4 hours): Infrastructure Setup

#### Task 1.1: Create package structure (30 min)

```bash
# Create new directories
mkdir -p pkg/transfer/local
mkdir -p cmd/transfer-pvc/testdata

# Files to create:
# pkg/transfer/local/export.go
# pkg/transfer/local/import.go
# pkg/transfer/local/portforward.go
# pkg/transfer/local/archive.go
```

**Checklist:**
- [ ] Create directory structure
- [ ] Add package documentation
- [ ] Update go.mod if needed (should not require new dependencies)

---

#### Task 1.2: Implement path parsing and validation (1 hour)

**File:** `pkg/transfer/local/path.go`

```go
package local

import (
    "fmt"
    "os"
    "path/filepath"
    "strings"
)

// ParseDestination parses and validates a local filesystem path
func ParseDestination(dest string) (string, error) {
    // Remove "local://" prefix if present
    path := strings.TrimPrefix(dest, "local://")
    
    // Expand ~ to home directory
    if strings.HasPrefix(path, "~/") {
        home, err := os.UserHomeDir()
        if err != nil {
            return "", fmt.Errorf("cannot expand ~: %w", err)
        }
        path = filepath.Join(home, path[2:])
    }
    
    // Convert to absolute path
    absPath, err := filepath.Abs(path)
    if err != nil {
        return "", fmt.Errorf("invalid path: %w", err)
    }
    
    return absPath, nil
}

// IsLocalPath checks if destination is a local filesystem path
func IsLocalPath(dest string) bool {
    return strings.HasPrefix(dest, "/") ||
           strings.HasPrefix(dest, "./") ||
           strings.HasPrefix(dest, "../") ||
           strings.HasPrefix(dest, "~/") ||
           strings.HasPrefix(dest, "local://")
}

// EnsureDirectory creates directory if it doesn't exist
func EnsureDirectory(path string) error {
    dir := filepath.Dir(path)
    return os.MkdirAll(dir, 0755)
}
```

**Tests:** `pkg/transfer/local/path_test.go`

```go
func TestParseDestination(t *testing.T) {
    tests := []struct {
        name    string
        dest    string
        wantErr bool
    }{
        {"absolute path", "/tmp/backup.tar.gz", false},
        {"relative path", "./backup.tar.gz", false},
        {"home path", "~/backups/data.tar.gz", false},
        {"local prefix", "local:///tmp/backup.tar.gz", false},
    }
    
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := ParseDestination(tt.dest)
            if (err != nil) != tt.wantErr {
                t.Errorf("ParseDestination() error = %v, wantErr %v", err, tt.wantErr)
            }
            if !tt.wantErr && !filepath.IsAbs(got) {
                t.Errorf("ParseDestination() = %v, want absolute path", got)
            }
        })
    }
}
```

**Checklist:**
- [ ] Implement ParseDestination()
- [ ] Implement IsLocalPath()
- [ ] Implement EnsureDirectory()
- [ ] Write unit tests
- [ ] Test with various path formats

---

#### Task 1.3: Implement port-forwarding helper (1.5 hours)

**File:** `pkg/transfer/local/portforward.go`

```go
package local

import (
    "context"
    "fmt"
    "net/http"
    "net/url"
    
    corev1 "k8s.io/api/core/v1"
    "k8s.io/client-go/rest"
    "k8s.io/client-go/tools/portforward"
    "k8s.io/client-go/transport/spdy"
)

type PortForwarder struct {
    config    *rest.Config
    namespace string
    podName   string
    podPort   int
    
    localPort int
    stopCh    chan struct{}
    readyCh   chan struct{}
}

func NewPortForwarder(config *rest.Config, namespace, podName string, podPort int) *PortForwarder {
    return &PortForwarder{
        config:    config,
        namespace: namespace,
        podName:   podName,
        podPort:   podPort,
        stopCh:    make(chan struct{}),
        readyCh:   make(chan struct{}),
    }
}

func (pf *PortForwarder) Start(ctx context.Context) error {
    // Build URL for port-forward
    url := pf.config.Host + fmt.Sprintf(
        "/api/v1/namespaces/%s/pods/%s/portforward",
        pf.namespace,
        pf.podName,
    )
    
    transport, upgrader, err := spdy.RoundTripperFor(pf.config)
    if err != nil {
        return fmt.Errorf("failed to create round tripper: %w", err)
    }
    
    dialer := spdy.NewDialer(upgrader, &http.Client{Transport: transport}, "POST", url)
    
    // Use port 0 to get any available local port
    ports := []string{fmt.Sprintf("0:%d", pf.podPort)}
    
    fw, err := portforward.New(dialer, ports, pf.stopCh, pf.readyCh, nil, nil)
    if err != nil {
        return fmt.Errorf("failed to create port forwarder: %w", err)
    }
    
    // Start port forwarding in background
    errCh := make(chan error)
    go func() {
        if err := fw.ForwardPorts(); err != nil {
            errCh <- err
        }
    }()
    
    // Wait for ready or error
    select {
    case <-pf.readyCh:
        // Get the actual local port that was assigned
        forwardedPorts, err := fw.GetPorts()
        if err != nil {
            return fmt.Errorf("failed to get forwarded ports: %w", err)
        }
        if len(forwardedPorts) == 0 {
            return fmt.Errorf("no ports were forwarded")
        }
        pf.localPort = int(forwardedPorts[0].Local)
        return nil
    
    case err := <-errCh:
        return fmt.Errorf("port forwarding failed: %w", err)
    
    case <-ctx.Done():
        return ctx.Err()
    }
}

func (pf *PortForwarder) Stop() {
    close(pf.stopCh)
}

func (pf *PortForwarder) LocalPort() int {
    return pf.localPort
}
```

**Checklist:**
- [ ] Implement PortForwarder struct
- [ ] Implement Start() method
- [ ] Implement Stop() method
- [ ] Handle errors gracefully
- [ ] Test with actual pod

---

#### Task 1.4: Create rsync server pod helper (1 hour)

**File:** `pkg/transfer/local/rsync_server.go`

```go
package local

import (
    "context"
    "fmt"
    "time"
    
    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/apimachinery/pkg/util/wait"
    "sigs.k8s.io/controller-runtime/pkg/client"
)

const (
    rsyncPort = 8873
    serverImage = "quay.io/konveyor/rsync-transfer:latest"
)

type RsyncServerPod struct {
    client    client.Client
    namespace string
    pvcName   string
    pod       *corev1.Pod
}

func NewRsyncServerPod(client client.Client, namespace, pvcName string) *RsyncServerPod {
    return &RsyncServerPod{
        client:    client,
        namespace: namespace,
        pvcName:   pvcName,
    }
}

func (r *RsyncServerPod) Create(ctx context.Context) error {
    pod := &corev1.Pod{
        ObjectMeta: metav1.ObjectMeta{
            Name:      fmt.Sprintf("crane-export-%s", r.pvcName),
            Namespace: r.namespace,
            Labels: map[string]string{
                "app.kubernetes.io/name":      "crane",
                "app.kubernetes.io/component": "export-rsync-server",
                "crane.konveyor.io/pvc":       r.pvcName,
            },
        },
        Spec: corev1.PodSpec{
            RestartPolicy: corev1.RestartPolicyNever,
            Containers: []corev1.Container{
                {
                    Name:  "rsync-server",
                    Image: serverImage,
                    Command: []string{
                        "/usr/bin/rsync",
                        "--daemon",
                        "--no-detach",
                        "--port", fmt.Sprintf("%d", rsyncPort),
                        "--config", "/etc/rsyncd/rsyncd.conf",
                    },
                    Ports: []corev1.ContainerPort{
                        {
                            Name:          "rsync",
                            ContainerPort: rsyncPort,
                            Protocol:      corev1.ProtocolTCP,
                        },
                    },
                    VolumeMounts: []corev1.VolumeMount{
                        {
                            Name:      "data",
                            MountPath: "/data",
                            ReadOnly:  true,
                        },
                        {
                            Name:      "config",
                            MountPath: "/etc/rsyncd",
                        },
                    },
                },
            },
            Volumes: []corev1.Volume{
                {
                    Name: "data",
                    VolumeSource: corev1.VolumeSource{
                        PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
                            ClaimName: r.pvcName,
                            ReadOnly:  true,
                        },
                    },
                },
                {
                    Name: "config",
                    VolumeSource: corev1.VolumeSource{
                        ConfigMap: &corev1.ConfigMapVolumeSource{
                            LocalObjectReference: corev1.LocalObjectReference{
                                Name: "crane-rsync-config",
                            },
                        },
                    },
                },
            },
        },
    }
    
    if err := r.client.Create(ctx, pod); err != nil {
        return fmt.Errorf("failed to create pod: %w", err)
    }
    
    r.pod = pod
    
    // Wait for pod to be ready
    return r.waitForReady(ctx)
}

func (r *RsyncServerPod) waitForReady(ctx context.Context) error {
    return wait.PollImmediate(2*time.Second, 5*time.Minute, func() (bool, error) {
        pod := &corev1.Pod{}
        if err := r.client.Get(ctx, client.ObjectKey{
            Name:      r.pod.Name,
            Namespace: r.pod.Namespace,
        }, pod); err != nil {
            return false, err
        }
        
        return pod.Status.Phase == corev1.PodRunning, nil
    })
}

func (r *RsyncServerPod) Delete(ctx context.Context) error {
    if r.pod == nil {
        return nil
    }
    
    return r.client.Delete(ctx, r.pod)
}

func (r *RsyncServerPod) Name() string {
    if r.pod == nil {
        return ""
    }
    return r.pod.Name
}
```

**Checklist:**
- [ ] Implement RsyncServerPod struct
- [ ] Implement Create() method
- [ ] Implement waitForReady() with timeout
- [ ] Implement Delete() for cleanup
- [ ] Create ConfigMap for rsyncd.conf

---

### Afternoon (4 hours): Export Implementation

#### Task 1.5: Implement archive creation (2 hours)

**File:** `pkg/transfer/local/archive.go`

```go
package local

import (
    "archive/tar"
    "compress/gzip"
    "fmt"
    "io"
    "os"
    "path/filepath"
    "strings"
)

type ArchiveWriter struct {
    file       *os.File
    gzipWriter *gzip.Writer
    tarWriter  *tar.Writer
    compress   bool
}

func NewArchiveWriter(path string, compress bool) (*ArchiveWriter, error) {
    // Create file with secure permissions (0600)
    file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
    if err != nil {
        return nil, fmt.Errorf("failed to create archive: %w", err)
    }
    
    aw := &ArchiveWriter{
        file:     file,
        compress: compress,
    }
    
    var writer io.Writer = file
    
    // Add gzip compression if requested or if filename ends with .gz
    if compress || strings.HasSuffix(path, ".gz") || strings.HasSuffix(path, ".tgz") {
        aw.gzipWriter = gzip.NewWriter(file)
        writer = aw.gzipWriter
    }
    
    aw.tarWriter = tar.NewWriter(writer)
    
    return aw, nil
}

func (aw *ArchiveWriter) AddDirectory(dirPath string) error {
    return filepath.Walk(dirPath, func(path string, info os.FileInfo, err error) error {
        if err != nil {
            return err
        }
        
        // Create tar header
        header, err := tar.FileInfoHeader(info, "")
        if err != nil {
            return fmt.Errorf("failed to create header for %s: %w", path, err)
        }
        
        // Set relative path
        relPath, err := filepath.Rel(dirPath, path)
        if err != nil {
            return err
        }
        header.Name = relPath
        
        // Write header
        if err := aw.tarWriter.WriteHeader(header); err != nil {
            return fmt.Errorf("failed to write header: %w", err)
        }
        
        // Write file content (if regular file)
        if info.Mode().IsRegular() {
            file, err := os.Open(path)
            if err != nil {
                return fmt.Errorf("failed to open %s: %w", path, err)
            }
            defer file.Close()
            
            if _, err := io.Copy(aw.tarWriter, file); err != nil {
                return fmt.Errorf("failed to write file content: %w", err)
            }
        }
        
        return nil
    })
}

func (aw *ArchiveWriter) Close() error {
    var errs []error
    
    if err := aw.tarWriter.Close(); err != nil {
        errs = append(errs, err)
    }
    
    if aw.gzipWriter != nil {
        if err := aw.gzipWriter.Close(); err != nil {
            errs = append(errs, err)
        }
    }
    
    if err := aw.file.Close(); err != nil {
        errs = append(errs, err)
    }
    
    if len(errs) > 0 {
        return fmt.Errorf("errors closing archive: %v", errs)
    }
    
    return nil
}

type ArchiveReader struct {
    file       *os.File
    gzipReader *gzip.Reader
    tarReader  *tar.Reader
}

func NewArchiveReader(path string) (*ArchiveReader, error) {
    file, err := os.Open(path)
    if err != nil {
        return nil, fmt.Errorf("failed to open archive: %w", err)
    }
    
    ar := &ArchiveReader{
        file: file,
    }
    
    var reader io.Reader = file
    
    // Detect gzip compression
    if strings.HasSuffix(path, ".gz") || strings.HasSuffix(path, ".tgz") {
        ar.gzipReader, err = gzip.NewReader(file)
        if err != nil {
            file.Close()
            return nil, fmt.Errorf("failed to create gzip reader: %w", err)
        }
        reader = ar.gzipReader
    }
    
    ar.tarReader = tar.NewReader(reader)
    
    return ar, nil
}

func (ar *ArchiveReader) ExtractTo(destDir string) error {
    for {
        header, err := ar.tarReader.Next()
        if err == io.EOF {
            break
        }
        if err != nil {
            return fmt.Errorf("failed to read tar header: %w", err)
        }
        
        targetPath := filepath.Join(destDir, header.Name)
        
        // Security check: prevent path traversal
        if !strings.HasPrefix(filepath.Clean(targetPath), filepath.Clean(destDir)) {
            return fmt.Errorf("illegal file path: %s", header.Name)
        }
        
        switch header.Typeflag {
        case tar.TypeDir:
            if err := os.MkdirAll(targetPath, os.FileMode(header.Mode)); err != nil {
                return fmt.Errorf("failed to create directory %s: %w", targetPath, err)
            }
        
        case tar.TypeReg:
            if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
                return fmt.Errorf("failed to create parent directory: %w", err)
            }
            
            outFile, err := os.Create(targetPath)
            if err != nil {
                return fmt.Errorf("failed to create file %s: %w", targetPath, err)
            }
            
            if _, err := io.Copy(outFile, ar.tarReader); err != nil {
                outFile.Close()
                return fmt.Errorf("failed to write file content: %w", err)
            }
            outFile.Close()
            
            if err := os.Chmod(targetPath, os.FileMode(header.Mode)); err != nil {
                return fmt.Errorf("failed to set permissions: %w", err)
            }
        }
    }
    
    return nil
}

func (ar *ArchiveReader) Close() error {
    var errs []error
    
    if ar.gzipReader != nil {
        if err := ar.gzipReader.Close(); err != nil {
            errs = append(errs, err)
        }
    }
    
    if err := ar.file.Close(); err != nil {
        errs = append(errs, err)
    }
    
    if len(errs) > 0 {
        return fmt.Errorf("errors closing archive: %v", errs)
    }
    
    return nil
}
```

**Checklist:**
- [ ] Implement ArchiveWriter
- [ ] Implement ArchiveReader
- [ ] Add path traversal protection
- [ ] Handle file permissions correctly
- [ ] Write unit tests

---

#### Task 1.6: Implement export command (2 hours)

**File:** `pkg/transfer/local/export.go`

```go
package local

import (
    "context"
    "fmt"
    "os"
    "os/exec"
    
    "github.com/go-logr/logr"
    "k8s.io/client-go/rest"
    "sigs.k8s.io/controller-runtime/pkg/client"
)

type ExportOptions struct {
    Client       client.Client
    Config       *rest.Config
    PVCName      string
    PVCNamespace string
    Destination  string
    Compress     bool
    Logger       logr.Logger
}

type Exporter struct {
    opts ExportOptions
}

func NewExporter(opts ExportOptions) *Exporter {
    return &Exporter{opts: opts}
}

func (e *Exporter) Run(ctx context.Context) error {
    // 1. Parse and validate destination
    destPath, err := ParseDestination(e.opts.Destination)
    if err != nil {
        return err
    }
    
    e.opts.Logger.Info("Exporting PVC to local file",
        "pvc", e.opts.PVCName,
        "namespace", e.opts.PVCNamespace,
        "destination", destPath,
    )
    
    // 2. Ensure destination directory exists
    if err := EnsureDirectory(destPath); err != nil {
        return err
    }
    
    // 3. Create rsync server pod
    server := NewRsyncServerPod(e.opts.Client, e.opts.PVCNamespace, e.opts.PVCName)
    if err := server.Create(ctx); err != nil {
        return fmt.Errorf("failed to create rsync server: %w", err)
    }
    defer server.Delete(ctx)
    
    e.opts.Logger.Info("Rsync server pod created", "pod", server.Name())
    
    // 4. Setup port forwarding
    pf := NewPortForwarder(e.opts.Config, e.opts.PVCNamespace, server.Name(), rsyncPort)
    if err := pf.Start(ctx); err != nil {
        return fmt.Errorf("failed to start port forwarding: %w", err)
    }
    defer pf.Stop()
    
    e.opts.Logger.Info("Port forwarding established", "localPort", pf.LocalPort())
    
    // 5. Pull data via rsync to temp directory
    tempDir, err := os.MkdirTemp("", "crane-export-*")
    if err != nil {
        return err
    }
    defer os.RemoveAll(tempDir)
    
    if err := e.rsyncPull(ctx, pf.LocalPort(), tempDir); err != nil {
        return fmt.Errorf("rsync failed: %w", err)
    }
    
    // 6. Create archive
    e.opts.Logger.Info("Creating archive", "destination", destPath)
    
    archive, err := NewArchiveWriter(destPath, e.opts.Compress)
    if err != nil {
        return err
    }
    defer archive.Close()
    
    if err := archive.AddDirectory(tempDir); err != nil {
        return fmt.Errorf("failed to create archive: %w", err)
    }
    
    e.opts.Logger.Info("Export completed successfully")
    
    return nil
}

func (e *Exporter) rsyncPull(ctx context.Context, localPort int, destDir string) error {
    cmd := exec.CommandContext(ctx, "rsync",
        "-avz",
        "--progress",
        fmt.Sprintf("rsync://crane@localhost:%d/data/", localPort),
        destDir+"/",
    )
    
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    
    return cmd.Run()
}
```

**Checklist:**
- [ ] Implement Exporter struct
- [ ] Implement Run() method
- [ ] Add proper logging
- [ ] Handle cleanup on error
- [ ] Test end-to-end export

---

**Day 1 Summary:**
- ✅ Path parsing and validation
- ✅ Port forwarding helper
- ✅ Rsync server pod creation
- ✅ Archive creation/extraction
- ✅ Export command implementation

---

<a name="day-2"></a>
## Day 2: Import & Testing (8 hours)

### Morning (4 hours): Import Implementation

#### Task 2.1: Create rsync client pod helper (1 hour)

**File:** `pkg/transfer/local/rsync_client.go`

```go
package local

import (
    "context"
    "fmt"
    
    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "sigs.k8s.io/controller-runtime/pkg/client"
)

type RsyncClientPod struct {
    client    client.Client
    namespace string
    pvcName   string
    pod       *corev1.Pod
}

func NewRsyncClientPod(client client.Client, namespace, pvcName string) *RsyncClientPod {
    return &RsyncClientPod{
        client:    client,
        namespace: namespace,
        pvcName:   pvcName,
    }
}

func (r *RsyncClientPod) Create(ctx context.Context) error {
    pod := &corev1.Pod{
        ObjectMeta: metav1.ObjectMeta{
            Name:      fmt.Sprintf("crane-import-%s", r.pvcName),
            Namespace: r.namespace,
            Labels: map[string]string{
                "app.kubernetes.io/name":      "crane",
                "app.kubernetes.io/component": "import-rsync-client",
                "crane.konveyor.io/pvc":       r.pvcName,
            },
        },
        Spec: corev1.PodSpec{
            RestartPolicy: corev1.RestartPolicyNever,
            Containers: []corev1.Container{
                {
                    Name:  "rsync-server",
                    Image: serverImage,
                    Command: []string{
                        "/usr/bin/rsync",
                        "--daemon",
                        "--no-detach",
                        "--port", fmt.Sprintf("%d", rsyncPort),
                        "--config", "/etc/rsyncd/rsyncd.conf",
                    },
                    Ports: []corev1.ContainerPort{
                        {
                            Name:          "rsync",
                            ContainerPort: rsyncPort,
                            Protocol:      corev1.ProtocolTCP,
                        },
                    },
                    VolumeMounts: []corev1.VolumeMount{
                        {
                            Name:      "data",
                            MountPath: "/data",
                            ReadOnly:  false, // ReadWrite for import
                        },
                        {
                            Name:      "config",
                            MountPath: "/etc/rsyncd",
                        },
                    },
                },
            },
            Volumes: []corev1.Volume{
                {
                    Name: "data",
                    VolumeSource: corev1.VolumeSource{
                        PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
                            ClaimName: r.pvcName,
                            ReadOnly:  false,
                        },
                    },
                },
                {
                    Name: "config",
                    VolumeSource: corev1.VolumeSource{
                        ConfigMap: &corev1.ConfigMapVolumeSource{
                            LocalObjectReference: corev1.LocalObjectReference{
                                Name: "crane-rsync-config",
                            },
                        },
                    },
                },
            },
        },
    }
    
    if err := r.client.Create(ctx, pod); err != nil {
        return fmt.Errorf("failed to create pod: %w", err)
    }
    
    r.pod = pod
    
    return r.waitForReady(ctx)
}

func (r *RsyncClientPod) waitForReady(ctx context.Context) error {
    return wait.PollImmediate(2*time.Second, 5*time.Minute, func() (bool, error) {
        pod := &corev1.Pod{}
        if err := r.client.Get(ctx, client.ObjectKey{
            Name:      r.pod.Name,
            Namespace: r.pod.Namespace,
        }, pod); err != nil {
            return false, err
        }
        
        return pod.Status.Phase == corev1.PodRunning, nil
    })
}

func (r *RsyncClientPod) Delete(ctx context.Context) error {
    if r.pod == nil {
        return nil
    }
    
    return r.client.Delete(ctx, r.pod)
}

func (r *RsyncClientPod) Name() string {
    if r.pod == nil {
        return ""
    }
    return r.pod.Name
}
```

**Checklist:**
- [ ] Implement RsyncClientPod (similar to server but ReadWrite)
- [ ] Test pod creation

---

#### Task 2.2: Implement import command (2 hours)

**File:** `pkg/transfer/local/import.go`

```go
package local

import (
    "context"
    "fmt"
    "os"
    "os/exec"
    
    "github.com/go-logr/logr"
    corev1 "k8s.io/api/core/v1"
    "k8s.io/apimachinery/pkg/api/resource"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/rest"
    "sigs.k8s.io/controller-runtime/pkg/client"
)

type ImportOptions struct {
    Client       client.Client
    Config       *rest.Config
    Source       string
    PVCName      string
    PVCNamespace string
    CreatePVC    bool
    StorageClass string
    PVCSize      string
    Logger       logr.Logger
}

type Importer struct {
    opts ImportOptions
}

func NewImporter(opts ImportOptions) *Importer {
    return &Importer{opts: opts}
}

func (i *Importer) Run(ctx context.Context) error {
    // 1. Parse and validate source
    sourcePath, err := ParseDestination(i.opts.Source)
    if err != nil {
        return err
    }
    
    i.opts.Logger.Info("Importing from local file to PVC",
        "source", sourcePath,
        "pvc", i.opts.PVCName,
        "namespace", i.opts.PVCNamespace,
    )
    
    // 2. Check if source exists
    sourceInfo, err := os.Stat(sourcePath)
    if err != nil {
        return fmt.Errorf("source not found: %w", err)
    }
    
    // 3. Ensure PVC exists
    if i.opts.CreatePVC {
        if err := i.ensurePVCExists(ctx); err != nil {
            return err
        }
    }
    
    // 4. Extract archive to temp directory if source is a file
    var dataDir string
    var cleanup func()
    
    if !sourceInfo.IsDir() {
        tempDir, err := os.MkdirTemp("", "crane-import-*")
        if err != nil {
            return err
        }
        cleanup = func() { os.RemoveAll(tempDir) }
        defer cleanup()
        
        i.opts.Logger.Info("Extracting archive", "source", sourcePath)
        
        archive, err := NewArchiveReader(sourcePath)
        if err != nil {
            return err
        }
        defer archive.Close()
        
        if err := archive.ExtractTo(tempDir); err != nil {
            return fmt.Errorf("extraction failed: %w", err)
        }
        
        dataDir = tempDir
    } else {
        dataDir = sourcePath
    }
    
    // 5. Create rsync client pod
    clientPod := NewRsyncClientPod(i.opts.Client, i.opts.PVCNamespace, i.opts.PVCName)
    if err := clientPod.Create(ctx); err != nil {
        return fmt.Errorf("failed to create rsync client: %w", err)
    }
    defer clientPod.Delete(ctx)
    
    i.opts.Logger.Info("Rsync client pod created", "pod", clientPod.Name())
    
    // 6. Setup port forwarding
    pf := NewPortForwarder(i.opts.Config, i.opts.PVCNamespace, clientPod.Name(), rsyncPort)
    if err := pf.Start(ctx); err != nil {
        return fmt.Errorf("failed to start port forwarding: %w", err)
    }
    defer pf.Stop()
    
    i.opts.Logger.Info("Port forwarding established", "localPort", pf.LocalPort())
    
    // 7. Push data via rsync
    if err := i.rsyncPush(ctx, pf.LocalPort(), dataDir); err != nil {
        return fmt.Errorf("rsync failed: %w", err)
    }
    
    i.opts.Logger.Info("Import completed successfully")
    
    return nil
}

func (i *Importer) rsyncPush(ctx context.Context, localPort int, sourceDir string) error {
    cmd := exec.CommandContext(ctx, "rsync",
        "-avz",
        "--progress",
        "--delete", // Remove files in destination not in source
        sourceDir+"/",
        fmt.Sprintf("rsync://crane@localhost:%d/data/", localPort),
    )
    
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    
    return cmd.Run()
}

func (i *Importer) ensurePVCExists(ctx context.Context) error {
    // Check if PVC already exists
    pvc := &corev1.PersistentVolumeClaim{}
    err := i.opts.Client.Get(ctx, client.ObjectKey{
        Name:      i.opts.PVCName,
        Namespace: i.opts.PVCNamespace,
    }, pvc)
    
    if err == nil {
        i.opts.Logger.Info("PVC already exists", "pvc", i.opts.PVCName)
        return nil
    }
    
    if !errors.IsNotFound(err) {
        return err
    }
    
    // Create PVC
    i.opts.Logger.Info("Creating PVC",
        "pvc", i.opts.PVCName,
        "size", i.opts.PVCSize,
        "storageClass", i.opts.StorageClass,
    )
    
    newPVC := &corev1.PersistentVolumeClaim{
        ObjectMeta: metav1.ObjectMeta{
            Name:      i.opts.PVCName,
            Namespace: i.opts.PVCNamespace,
        },
        Spec: corev1.PersistentVolumeClaimSpec{
            AccessModes: []corev1.PersistentVolumeAccessMode{
                corev1.ReadWriteOnce,
            },
            Resources: corev1.VolumeResourceRequirements{
                Requests: corev1.ResourceList{
                    corev1.ResourceStorage: resource.MustParse(i.opts.PVCSize),
                },
            },
        },
    }
    
    if i.opts.StorageClass != "" {
        newPVC.Spec.StorageClassName = &i.opts.StorageClass
    }
    
    return i.opts.Client.Create(ctx, newPVC)
}
```

**Checklist:**
- [ ] Implement Importer struct
- [ ] Implement Run() method
- [ ] Implement ensurePVCExists()
- [ ] Handle both file and directory sources
- [ ] Test end-to-end import

---

#### Task 2.3: Integrate with CLI (1 hour)

**File:** `cmd/transfer-pvc/export_cmd.go`

```go
package transfer_pvc

import (
    "github.com/spf13/cobra"
    "github.com/konveyor/crane/pkg/transfer/local"
)

func NewExportCommand() *cobra.Command {
    var (
        pvcName      string
        pvcNamespace string
        destination  string
        compress     bool
    )
    
    cmd := &cobra.Command{
        Use:   "export",
        Short: "Export PVC data to local filesystem",
        Long: `Export PVC data to local filesystem as tar.gz archive.

Examples:
  # Export to local file
  crane transfer-pvc export --pvc-name=mydata --destination=/tmp/backup.tar.gz

  # Export to home directory
  crane transfer-pvc export --pvc-name=mydata --destination=~/backups/mydata.tar.gz
`,
        RunE: func(cmd *cobra.Command, args []string) error {
            // Get clients and config
            // ...
            
            exporter := local.NewExporter(local.ExportOptions{
                Client:       client,
                Config:       config,
                PVCName:      pvcName,
                PVCNamespace: pvcNamespace,
                Destination:  destination,
                Compress:     compress,
                Logger:       logger,
            })
            
            return exporter.Run(cmd.Context())
        },
    }
    
    cmd.Flags().StringVar(&pvcName, "pvc-name", "", "Name of PVC to export (required)")
    cmd.Flags().StringVar(&pvcNamespace, "pvc-namespace", "", "Namespace of PVC")
    cmd.Flags().StringVar(&destination, "destination", "", "Local destination path (required)")
    cmd.Flags().BoolVar(&compress, "compress", true, "Compress archive with gzip")
    
    cmd.MarkFlagRequired("pvc-name")
    cmd.MarkFlagRequired("destination")
    
    return cmd
}
```

**File:** `cmd/transfer-pvc/import_cmd.go`

```go
func NewImportCommand() *cobra.Command {
    var (
        source       string
        pvcName      string
        pvcNamespace string
        createPVC    bool
        storageClass string
        pvcSize      string
    )
    
    cmd := &cobra.Command{
        Use:   "import",
        Short: "Import PVC data from local filesystem",
        Long: `Import PVC data from local filesystem archive.

Examples:
  # Import from local file
  crane transfer-pvc import --source=/tmp/backup.tar.gz --pvc-name=mydata

  # Import and create PVC
  crane transfer-pvc import --source=~/backup.tar.gz --pvc-name=mydata --create-pvc --pvc-size=100Gi
`,
        RunE: func(cmd *cobra.Command, args []string) error {
            // Get clients and config
            // ...
            
            importer := local.NewImporter(local.ImportOptions{
                Client:       client,
                Config:       config,
                Source:       source,
                PVCName:      pvcName,
                PVCNamespace: pvcNamespace,
                CreatePVC:    createPVC,
                StorageClass: storageClass,
                PVCSize:      pvcSize,
                Logger:       logger,
            })
            
            return importer.Run(cmd.Context())
        },
    }
    
    cmd.Flags().StringVar(&source, "source", "", "Local source path (required)")
    cmd.Flags().StringVar(&pvcName, "pvc-name", "", "Name of target PVC (required)")
    cmd.Flags().StringVar(&pvcNamespace, "pvc-namespace", "", "Namespace of PVC")
    cmd.Flags().BoolVar(&createPVC, "create-pvc", false, "Create PVC if it doesn't exist")
    cmd.Flags().StringVar(&storageClass, "storage-class", "", "StorageClass for new PVC")
    cmd.Flags().StringVar(&pvcSize, "pvc-size", "10Gi", "Size for new PVC")
    
    cmd.MarkFlagRequired("source")
    cmd.MarkFlagRequired("pvc-name")
    
    return cmd
}
```

**Update:** `cmd/transfer-pvc/transfer-pvc.go`

```go
func NewTransferPVCCommand() *cobra.Command {
    cmd := &cobra.Command{
        Use:   "transfer-pvc",
        Short: "Transfer PVC data",
    }
    
    // Add subcommands
    cmd.AddCommand(NewExportCommand())
    cmd.AddCommand(NewImportCommand())
    // ... existing sync command
    
    return cmd
}
```

**Checklist:**
- [ ] Create export subcommand
- [ ] Create import subcommand
- [ ] Add to main transfer-pvc command
- [ ] Test CLI flags
- [ ] Test help text

---

### Afternoon (4 hours): Testing

#### Task 2.4: Create integration tests (2 hours)

**File:** `pkg/transfer/local/export_test.go`

```go
package local_test

import (
    "context"
    "os"
    "path/filepath"
    "testing"
    
    "github.com/konveyor/crane/pkg/transfer/local"
    // ... imports
)

func TestExporter_Run(t *testing.T) {
    if testing.Short() {
        t.Skip("skipping integration test")
    }
    
    // Setup test environment (requires kind cluster)
    ctx := context.Background()
    client, config := setupTestCluster(t)
    
    // Create test PVC with data
    pvcName := "test-export-pvc"
    namespace := "default"
    createTestPVC(t, client, namespace, pvcName)
    writeTestData(t, client, namespace, pvcName, map[string]string{
        "file1.txt": "content1",
        "file2.txt": "content2",
        "dir/file3.txt": "content3",
    })
    
    // Export to temp file
    tempFile := filepath.Join(t.TempDir(), "export.tar.gz")
    
    exporter := local.NewExporter(local.ExportOptions{
        Client:       client,
        Config:       config,
        PVCName:      pvcName,
        PVCNamespace: namespace,
        Destination:  tempFile,
        Compress:     true,
        Logger:       testLogger(t),
    })
    
    err := exporter.Run(ctx)
    if err != nil {
        t.Fatalf("Export failed: %v", err)
    }
    
    // Verify archive was created
    if _, err := os.Stat(tempFile); os.IsNotExist(err) {
        t.Fatal("Archive file was not created")
    }
    
    // Verify archive contents
    verifyArchiveContents(t, tempFile, map[string]string{
        "file1.txt": "content1",
        "file2.txt": "content2",
        "dir/file3.txt": "content3",
    })
}
```

**Checklist:**
- [ ] Write export integration test
- [ ] Write import integration test
- [ ] Write round-trip test (export then import)
- [ ] Test with compressed and uncompressed archives
- [ ] Test with directory source/destination

---

#### Task 2.5: Manual testing (1 hour)

**Test scenarios:**

1. **Export small PVC**
   ```bash
   kubectl create configmap test-data --from-literal=file1.txt=hello
   kubectl apply -f test-pvc.yaml
   
   crane transfer-pvc export \
     --pvc-name=test-pvc \
     --destination=/tmp/test-export.tar.gz \
     --context=kind-kind
   
   # Verify
   tar -tzf /tmp/test-export.tar.gz
   ```

2. **Import to new PVC**
   ```bash
   crane transfer-pvc import \
     --source=/tmp/test-export.tar.gz \
     --pvc-name=test-import \
     --create-pvc \
     --pvc-size=1Gi \
     --context=kind-kind
   
   # Verify data
   kubectl exec test-pod -- cat /data/file1.txt
   ```

3. **Export to home directory**
   ```bash
   crane transfer-pvc export \
     --pvc-name=test-pvc \
     --destination=~/backups/test-$(date +%Y%m%d).tar.gz
   ```

4. **Test error cases**
   - Non-existent PVC
   - Invalid destination path
   - Insufficient disk space
   - PVC in use (should still work)

**Checklist:**
- [ ] Test successful export
- [ ] Test successful import
- [ ] Test round-trip (export + import)
- [ ] Test error handling
- [ ] Test with different PVC sizes

---

#### Task 2.6: Create ConfigMap for rsyncd.conf (30 min)

**File:** `deploy/rsync-config.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: crane-rsync-config
  namespace: default
data:
  rsyncd.conf: |
    uid = 0
    gid = 0
    use chroot = no
    log file = /dev/stdout
    read only = no
    
    [data]
    path = /data
    comment = PVC data
    read only = no
    auth users = crane
    secrets file = /etc/rsyncd/rsyncd.secrets
```

**Checklist:**
- [ ] Create ConfigMap manifest
- [ ] Document how to deploy
- [ ] Consider embedding in code vs external manifest

---

#### Task 2.7: Update documentation (30 min)

**File:** `docs/transfer-pvc-local.md`

```markdown
# Local Export/Import

Export PVC data to your local laptop and import it back.

## Export

```bash
crane transfer-pvc export \
  --pvc-name=mydata \
  --pvc-namespace=production \
  --destination=~/backups/mydata-$(date +%Y%m%d).tar.gz \
  --context=prod-cluster
```

## Import

```bash
crane transfer-pvc import \
  --source=~/backups/mydata-20260703.tar.gz \
  --pvc-name=mydata-restored \
  --pvc-namespace=recovery \
  --create-pvc \
  --storage-class=fast-ssd \
  --pvc-size=100Gi \
  --context=dr-cluster
```
```

**Checklist:**
- [ ] Write user documentation
- [ ] Add examples to README
- [ ] Update main CLI help text

---

**Day 2 Summary:**
- ✅ Import command implementation
- ✅ CLI integration (export/import subcommands)
- ✅ Integration tests
- ✅ Manual testing
- ✅ Documentation

---

<a name="day-3"></a>
## Day 3: Polish & Documentation (8 hours)

### Morning (4 hours): Error Handling & Edge Cases

#### Task 3.1: Improve error messages (1 hour)

**Areas to improve:**
- Clear error when rsync is not installed
- Clear error when PVC doesn't exist
- Clear error when destination path is not writable
- Progress indication for large transfers
- Timeout handling

**Example:**

```go
func (e *Exporter) validatePrerequisites() error {
    // Check rsync is installed
    if _, err := exec.LookPath("rsync"); err != nil {
        return fmt.Errorf("rsync not found in PATH. Please install rsync: %w", err)
    }
    
    // Check PVC exists
    pvc := &corev1.PersistentVolumeClaim{}
    if err := e.opts.Client.Get(ctx, client.ObjectKey{
        Name:      e.opts.PVCName,
        Namespace: e.opts.PVCNamespace,
    }, pvc); err != nil {
        if errors.IsNotFound(err) {
            return fmt.Errorf("PVC %s/%s not found", e.opts.PVCNamespace, e.opts.PVCName)
        }
        return err
    }
    
    // Check destination is writable
    destDir := filepath.Dir(e.opts.Destination)
    if err := os.MkdirAll(destDir, 0755); err != nil {
        return fmt.Errorf("destination directory %s is not writable: %w", destDir, err)
    }
    
    return nil
}
```

**Checklist:**
- [ ] Add validatePrerequisites() for export
- [ ] Add validatePrerequisites() for import
- [ ] Improve all error messages
- [ ] Add context to errors (which step failed)

---

#### Task 3.2: Add progress reporting (1.5 hours)

**Goal:** Show progress during long transfers

```go
func (e *Exporter) rsyncPull(ctx context.Context, localPort int, destDir string) error {
    cmd := exec.CommandContext(ctx, "rsync",
        "-avz",
        "--progress",
        "--stats",  // Show transfer stats at end
        fmt.Sprintf("rsync://crane@localhost:%d/data/", localPort),
        destDir+"/",
    )
    
    // Create progress parser
    progressReader := &rsyncProgressReader{
        logger: e.opts.Logger,
    }
    
    cmd.Stdout = progressReader
    cmd.Stderr = os.Stderr
    
    return cmd.Run()
}

type rsyncProgressReader struct {
    logger logr.Logger
}

func (r *rsyncProgressReader) Write(p []byte) (n int, err error) {
    line := string(p)
    
    // Parse rsync progress output
    // Example: "1.23M  45%  2.5MB/s  0:01:23"
    if strings.Contains(line, "%") {
        r.logger.Info("Transfer progress", "status", strings.TrimSpace(line))
    }
    
    return len(p), nil
}
```

**Checklist:**
- [ ] Add progress parsing
- [ ] Show estimated time remaining
- [ ] Show transfer speed
- [ ] Test with large PVCs

---

#### Task 3.3: Handle edge cases (1.5 hours)

**Edge cases to handle:**

1. **PVC is in use by running pod** (should still work - ReadOnly mount)
   ```go
   // Export uses ReadOnly mount, so it's safe
   ```

2. **Insufficient disk space on laptop**
   ```go
   func checkDiskSpace(path string, requiredBytes int64) error {
       var stat syscall.Statfs_t
       if err := syscall.Statfs(path, &stat); err != nil {
           return err
       }
       
       availableBytes := stat.Bavail * uint64(stat.Bsize)
       if uint64(requiredBytes) > availableBytes {
           return fmt.Errorf("insufficient disk space: need %s, have %s",
               humanize.Bytes(uint64(requiredBytes)),
               humanize.Bytes(availableBytes))
       }
       
       return nil
   }
   ```

3. **Network interruption during transfer**
   ```go
   // rsync handles this naturally - will error and can be retried
   // Add retry logic?
   ```

4. **Archive already exists**
   ```go
   func (e *Exporter) Run(ctx context.Context) error {
       if _, err := os.Stat(destPath); err == nil {
           return fmt.Errorf("destination %s already exists (remove it or use different path)", destPath)
       }
       // ... continue
   }
   ```

5. **Empty PVC**
   ```go
   // Should create valid empty archive
   ```

**Checklist:**
- [ ] Handle PVC in use
- [ ] Check disk space before export
- [ ] Handle existing destination file
- [ ] Handle empty PVC
- [ ] Add retry on network errors

---

### Afternoon (4 hours): Final Polish

#### Task 3.4: Add compression options (1 hour)

**Support different compression levels:**

```go
type CompressionLevel int

const (
    CompressionNone CompressionLevel = 0
    CompressionFast CompressionLevel = 1
    CompressionBest CompressionLevel = 9
)

func NewArchiveWriter(path string, level CompressionLevel) (*ArchiveWriter, error) {
    // ...
    
    if level > CompressionNone {
        gzipWriter, err := gzip.NewWriterLevel(file, int(level))
        if err != nil {
            return nil, err
        }
        aw.gzipWriter = gzipWriter
        writer = gzipWriter
    }
    
    // ...
}
```

**CLI flag:**
```go
cmd.Flags().IntVar(&compressionLevel, "compression-level", 6, "Compression level (0-9, 0=none, 9=best)")
```

**Checklist:**
- [ ] Add compression level option
- [ ] Update CLI flags
- [ ] Test different levels
- [ ] Document in help text

---

#### Task 3.5: Add dry-run mode (30 min)

```go
type ExportOptions struct {
    // ... existing fields
    DryRun bool
}

func (e *Exporter) Run(ctx context.Context) error {
    // ... setup
    
    if e.opts.DryRun {
        e.opts.Logger.Info("DRY RUN: Would export PVC",
            "pvc", e.opts.PVCName,
            "destination", destPath,
        )
        return nil
    }
    
    // ... actual export
}
```

**CLI flag:**
```bash
crane transfer-pvc export --dry-run --pvc-name=test
```

**Checklist:**
- [ ] Add dry-run mode
- [ ] Test dry-run
- [ ] Document in help

---

#### Task 3.6: Complete documentation (1.5 hours)

**Files to create/update:**

1. **User guide:** `docs/pvc-local-export-import.md`
2. **CLI help:** Update `--help` text
3. **README:** Add examples to main README
4. **Troubleshooting guide:** Common issues

**Example documentation:**

```markdown
# PVC Local Export/Import

## Prerequisites

- `rsync` must be installed on your laptop
- `kubectl` access to the cluster
- Sufficient disk space for export

## Quick Start

### Export

```bash
crane transfer-pvc export \
  --pvc-name=mydata \
  --destination=~/backups/mydata.tar.gz
```

### Import

```bash
crane transfer-pvc import \
  --source=~/backups/mydata.tar.gz \
  --pvc-name=mydata-restored \
  --create-pvc
```

## Use Cases

### 1. Quick Backup Before Upgrade

```bash
# Before upgrade
crane transfer-pvc export \
  --pvc-name=production-db \
  --destination=~/backup-$(date +%Y%m%d).tar.gz

# If upgrade fails, restore
crane transfer-pvc import \
  --source=~/backup-20260703.tar.gz \
  --pvc-name=production-db
```

### 2. Offline Transfer via USB

```bash
# On source cluster
crane transfer-pvc export \
  --pvc-name=data \
  --destination=/mnt/usb/data.tar.gz

# Move USB drive physically

# On target cluster
crane transfer-pvc import \
  --source=/mnt/usb/data.tar.gz \
  --pvc-name=data \
  --create-pvc
```

## Troubleshooting

### "rsync not found"

Install rsync:
- macOS: `brew install rsync`
- Ubuntu: `apt-get install rsync`
- RHEL: `dnf install rsync`

### "Insufficient disk space"

Check available space: `df -h /tmp`
Free up space or use different destination.

### "PVC not found"

Verify PVC exists: `kubectl get pvc -n <namespace>`
```

**Checklist:**
- [ ] Write complete user guide
- [ ] Add troubleshooting section
- [ ] Add examples for common use cases
- [ ] Update main README
- [ ] Review all help text

---

#### Task 3.7: Code review & cleanup (1 hour)

**Review checklist:**
- [ ] Remove debug logging
- [ ] Add package documentation
- [ ] Check error handling is complete
- [ ] Verify all resources are cleaned up (defer)
- [ ] Run `go fmt`
- [ ] Run `go vet`
- [ ] Run `golangci-lint`
- [ ] Check for TODOs
- [ ] Ensure consistent naming
- [ ] Add missing comments

---

**Day 3 Summary:**
- ✅ Improved error handling
- ✅ Progress reporting
- ✅ Edge case handling
- ✅ Compression options
- ✅ Dry-run mode
- ✅ Complete documentation
- ✅ Code cleanup

---

<a name="file-structure"></a>
## File Structure

```
crane/
├── pkg/transfer/local/
│   ├── path.go              # Path parsing and validation
│   ├── path_test.go
│   ├── portforward.go       # Port-forwarding helper
│   ├── portforward_test.go
│   ├── rsync_server.go      # Rsync server pod management
│   ├── rsync_client.go      # Rsync client pod management
│   ├── archive.go           # Tar/gzip archive creation/extraction
│   ├── archive_test.go
│   ├── export.go            # Export implementation
│   ├── export_test.go
│   ├── import.go            # Import implementation
│   ├── import_test.go
│   └── doc.go               # Package documentation
│
├── cmd/transfer-pvc/
│   ├── export_cmd.go        # Export subcommand
│   ├── import_cmd.go        # Import subcommand
│   └── transfer-pvc.go      # Main command (updated)
│
├── deploy/
│   └── rsync-config.yaml    # ConfigMap for rsyncd.conf
│
└── docs/
    └── pvc-local-export-import.md  # User documentation
```

---

<a name="testing"></a>
## Testing Strategy

### Unit Tests

```bash
# Run unit tests
go test ./pkg/transfer/local/... -v

# With coverage
go test ./pkg/transfer/local/... -v -cover -coverprofile=coverage.out
go tool cover -html=coverage.out
```

**Target coverage:** >80%

### Integration Tests

```bash
# Requires kind cluster
kind create cluster

# Run integration tests
go test ./pkg/transfer/local/... -v -tags=integration

# Or skip integration tests
go test ./pkg/transfer/local/... -v -short
```

### E2E Tests

```bash
# Manual E2E test script
./test/e2e/test-local-export-import.sh
```

**Script content:**
```bash
#!/bin/bash
set -e

# Create test PVC with data
kubectl create configmap test-data --from-literal=file.txt="test content"
kubectl apply -f test/fixtures/test-pvc.yaml

# Export
crane transfer-pvc export \
  --pvc-name=test-pvc \
  --destination=/tmp/test-export.tar.gz

# Verify archive
tar -tzf /tmp/test-export.tar.gz | grep file.txt

# Import to new PVC
crane transfer-pvc import \
  --source=/tmp/test-export.tar.gz \
  --pvc-name=test-import \
  --create-pvc \
  --pvc-size=1Gi

# Verify data
kubectl exec test-pod -- cat /data/file.txt | grep "test content"

echo "E2E test passed!"
```

---

<a name="success-criteria"></a>
## Success Criteria

### Functional Requirements

- [x] Export PVC to local tar.gz file
- [x] Import tar.gz file to PVC
- [x] Support compressed and uncompressed archives
- [x] Auto-create PVC on import
- [x] Support home directory paths (~/...)
- [x] Support relative and absolute paths
- [x] Clean up temporary resources on error

### Non-Functional Requirements

- [x] No new dependencies (uses stdlib only)
- [x] Works with any rsync-compatible cluster
- [x] Progress reporting for long transfers
- [x] Comprehensive error messages
- [x] Unit test coverage >80%
- [x] Integration tests pass
- [x] Documentation complete

### User Experience

- [x] Simple CLI interface
- [x] Clear error messages
- [x] Progress indication
- [x] Works in air-gapped environments
- [x] No cloud dependencies

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| rsync not installed on laptop | Check and provide clear error with install instructions |
| Port-forwarding fails | Retry logic, clear error messages |
| Insufficient disk space | Check before starting, estimate size |
| Network interruption | rsync handles gracefully, can be retried |
| PVC in use | Use ReadOnly mount for export (safe) |

---

## Bonus: Upload Local Export to S3-Compatible Storage

After exporting PVC data locally, you can upload it to S3-compatible storage (S3, MinIO, Ceph, etc.) using standard tools.

### Option 1: Using AWS CLI (for S3)

```bash
# 1. Export PVC to local file
crane transfer-pvc export \
  --pvc-name=postgres-data \
  --destination=~/backups/postgres-2026-07-03.tar.gz

# 2. Upload to S3 using AWS CLI
aws s3 cp ~/backups/postgres-2026-07-03.tar.gz \
  s3://my-backup-bucket/postgres/2026-07-03.tar.gz \
  --storage-class GLACIER  # Optional: use cheaper storage class

# 3. Verify upload
aws s3 ls s3://my-backup-bucket/postgres/

# Later: Download from S3 and import
aws s3 cp s3://my-backup-bucket/postgres/2026-07-03.tar.gz \
  ~/restore/postgres.tar.gz

crane transfer-pvc import \
  --source=~/restore/postgres.tar.gz \
  --pvc-name=postgres-restored \
  --create-pvc
```

### Option 2: Using MinIO Client (mc) - S3-compatible

```bash
# 1. Configure MinIO client
mc alias set myminio https://minio.example.com ACCESS_KEY SECRET_KEY

# 2. Export PVC
crane transfer-pvc export \
  --pvc-name=app-data \
  --destination=./app-data-backup.tar.gz

# 3. Upload to MinIO/S3-compatible storage
mc cp ./app-data-backup.tar.gz myminio/backups/app-data/

# 4. List backups
mc ls myminio/backups/app-data/

# Later: Download and import
mc cp myminio/backups/app-data/app-data-backup.tar.gz ./
crane transfer-pvc import --source=./app-data-backup.tar.gz --pvc-name=app-data
```

### Option 3: Using rclone (works with 40+ providers)

```bash
# 1. Configure rclone (one-time setup)
cat > ~/.config/rclone/rclone.conf <<EOF
[mybackup]
type = s3
provider = AWS
access_key_id = AKIAIOSFODNN7EXAMPLE
secret_access_key = wJalrXUtnFEMI/K7MDENG...
region = us-east-1
EOF

# 2. Export PVC
crane transfer-pvc export \
  --pvc-name=mydata \
  --destination=~/exports/mydata.tar.gz

# 3. Upload with rclone
rclone copy ~/exports/mydata.tar.gz mybackup:my-bucket/backups/

# Or sync entire export directory
rclone sync ~/exports/ mybackup:my-bucket/backups/ \
  --progress \
  --transfers=16

# 4. List remote backups
rclone ls mybackup:my-bucket/backups/

# Later: Download and import
rclone copy mybackup:my-bucket/backups/mydata.tar.gz ~/restore/
crane transfer-pvc import --source=~/restore/mydata.tar.gz --pvc-name=mydata
```

### Option 4: Scripted Backup with S3 Upload

```bash
#!/bin/bash
# backup-to-s3.sh - Export PVC and upload to S3 in one script

set -e

PVC_NAME="$1"
BUCKET="$2"

if [ -z "$PVC_NAME" ] || [ -z "$BUCKET" ]; then
    echo "Usage: $0 <pvc-name> <s3-bucket>"
    exit 1
fi

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${PVC_NAME}-${DATE}.tar.gz"
LOCAL_PATH="/tmp/${BACKUP_FILE}"

echo "==> Exporting PVC ${PVC_NAME} to ${LOCAL_PATH}"
crane transfer-pvc export \
  --pvc-name="${PVC_NAME}" \
  --destination="${LOCAL_PATH}" \
  --compress

echo "==> Uploading to S3: s3://${BUCKET}/${PVC_NAME}/${BACKUP_FILE}"
aws s3 cp "${LOCAL_PATH}" \
  "s3://${BUCKET}/${PVC_NAME}/${BACKUP_FILE}" \
  --storage-class STANDARD_IA

echo "==> Calculating checksum"
md5sum "${LOCAL_PATH}" > "${LOCAL_PATH}.md5"
aws s3 cp "${LOCAL_PATH}.md5" \
  "s3://${BUCKET}/${PVC_NAME}/${BACKUP_FILE}.md5"

echo "==> Cleaning up local file"
rm -f "${LOCAL_PATH}" "${LOCAL_PATH}.md5"

echo "==> Backup complete!"
echo "    S3 URI: s3://${BUCKET}/${PVC_NAME}/${BACKUP_FILE}"
```

**Usage:**
```bash
chmod +x backup-to-s3.sh
./backup-to-s3.sh postgres-data my-backup-bucket
```

### Option 5: Automated Backup with Retention Policy

```bash
#!/bin/bash
# backup-rotate.sh - Export PVC, upload to S3, and rotate old backups

PVC_NAME="$1"
BUCKET="$2"
KEEP_DAYS=30

DATE=$(date +%Y%m%d)
BACKUP_FILE="${PVC_NAME}-${DATE}.tar.gz"

# Export
crane transfer-pvc export \
  --pvc-name="${PVC_NAME}" \
  --destination="/tmp/${BACKUP_FILE}"

# Upload
aws s3 cp "/tmp/${BACKUP_FILE}" \
  "s3://${BUCKET}/${PVC_NAME}/${BACKUP_FILE}"

# Cleanup local
rm -f "/tmp/${BACKUP_FILE}"

# Delete backups older than KEEP_DAYS
aws s3 ls "s3://${BUCKET}/${PVC_NAME}/" | while read -r line; do
    BACKUP_DATE=$(echo "$line" | awk '{print $4}' | sed "s/${PVC_NAME}-//" | sed 's/.tar.gz//')
    BACKUP_AGE=$(( ($(date +%s) - $(date -d "$BACKUP_DATE" +%s)) / 86400 ))
    
    if [ "$BACKUP_AGE" -gt "$KEEP_DAYS" ]; then
        BACKUP_NAME=$(echo "$line" | awk '{print $4}')
        echo "Deleting old backup: $BACKUP_NAME (${BACKUP_AGE} days old)"
        aws s3 rm "s3://${BUCKET}/${PVC_NAME}/${BACKUP_NAME}"
    fi
done
```

### Comparison of Upload Methods

| Method | Pros | Cons | Best For |
|--------|------|------|----------|
| **AWS CLI** | Native S3 support, widely used | AWS only | AWS S3 users |
| **MinIO Client (mc)** | S3-compatible, fast, simple | Extra tool to install | MinIO, Ceph, S3-compatible |
| **rclone** | 40+ providers, resume, encryption | Larger learning curve | Multi-cloud, advanced features |
| **Script** | Automated, customizable | Requires scripting | Production workflows |

### Storage Class Recommendations

**For S3:**
```bash
# Hot data (frequent access)
--storage-class STANDARD

# Warm data (monthly access)
--storage-class STANDARD_IA

# Cold data (yearly access)
--storage-class GLACIER_IR

# Archive (compliance, rarely accessed)
--storage-class DEEP_ARCHIVE
```

**Cost comparison:**
- STANDARD: $23/TB/month
- STANDARD_IA: $12.50/TB/month
- GLACIER_IR: $4/TB/month
- DEEP_ARCHIVE: $1/TB/month

### Security: Encrypt Before Upload

```bash
# Export and encrypt locally
crane transfer-pvc export \
  --pvc-name=sensitive-data \
  --destination=/tmp/data.tar.gz

# Encrypt with GPG
gpg --symmetric --cipher-algo AES256 /tmp/data.tar.gz
# Creates: /tmp/data.tar.gz.gpg

# Upload encrypted file
aws s3 cp /tmp/data.tar.gz.gpg s3://bucket/encrypted/

# Later: Download and decrypt
aws s3 cp s3://bucket/encrypted/data.tar.gz.gpg /tmp/
gpg --decrypt /tmp/data.tar.gz.gpg > /tmp/data.tar.gz

# Import
crane transfer-pvc import --source=/tmp/data.tar.gz --pvc-name=sensitive-data
```

---

## Deliverables Checklist

- [ ] All code implemented and tested
- [ ] Unit tests passing (>80% coverage)
- [ ] Integration tests passing
- [ ] E2E test script created
- [ ] User documentation written
- [ ] CLI help text updated
- [ ] Example use cases documented
- [ ] Troubleshooting guide created
- [ ] Code reviewed and cleaned up
- [ ] Ready for PR

---

## Timeline Summary

| Day | Tasks | Hours | Status |
|-----|-------|-------|--------|
| **Day 1** | Foundation & Export | 8 | ⬜ |
| **Day 2** | Import & Testing | 8 | ⬜ |
| **Day 3** | Polish & Documentation | 8 | ⬜ |
| **Total** | | 24 hours (3 days) | ⬜ |

---

**Ready to start implementation!** 🚀
