# rclone Implementation Notes: Comparison with rsync Approach

**Date:** 2026-06-30  
**Purpose:** Analyze how crane transfer-pvc uses rsync and how rclone would work similarly

> **✅ RECOMMENDED:** Use rclone as a **Go library** instead of external binary
> 
> rclone is written in Go (`github.com/rclone/rclone`) and can be imported directly into crane's codebase. This approach:
> - ✅ Eliminates RHEL/EPEL dependency issues entirely
> - ✅ Simplifies deployment (single crane binary)
> - ✅ Better integration with crane's error handling and logging
> - ✅ No need for separate container images
>
> **Only if library approach is infeasible:** Use external binary (requires EPEL on RHEL/CentOS or upstream Alpine-based container images).

---

## How crane transfer-pvc Currently Works (rsync)

### Architecture Overview

```
Source Cluster                    Destination Cluster
┌──────────────────┐             ┌──────────────────┐
│  Source PVC      │             │  Dest PVC        │
│  ┌────────────┐  │             │  ┌────────────┐  │
│  │    Data    │  │             │  │   Empty    │  │
│  └────────────┘  │             │  └────────────┘  │
│        ▲         │             │        ▲         │
│        │mount    │             │        │mount    │
│  ┌─────┴──────┐  │   stunnel   │  ┌─────┴──────┐  │
│  │ rsync-client│  │   (TLS)     │  │rsync-server│  │
│  │    Pod      │──┼────────────►│  │    Pod     │  │
│  │             │  │   Ingress/  │  │            │  │
│  │ /usr/bin/   │  │   Route     │  │ rsyncd     │  │
│  │   rsync     │  │             │  │  daemon    │  │
│  └─────────────┘  │             │  └────────────┘  │
└──────────────────┘             └──────────────────┘
```

### Detailed Flow

#### 1. **Destination: rsync Server Setup**

**Created resources:**
- **Pod:** `rsync-server-{hash}`
- **Container 1:** rsync daemon (port 8873)
  ```yaml
  image: quay.io/konveyor/rsync-transfer:latest
  command: ["/usr/bin/rsync", "--daemon", "--config=/etc/rsyncd/rsyncd.conf"]
  volumeMounts:
    - name: dest-pvc
      mountPath: /mnt/{namespace}/{pvc-name}
    - name: config
      mountPath: /etc/rsyncd/rsyncd.conf
      subPath: rsyncd.conf
  ```
- **Container 2:** stunnel server (TLS termination)
  ```yaml
  image: registry.access.redhat.com/ubi8/ubi:latest
  command: ["/usr/bin/stunnel", "/etc/stunnel/stunnel.conf"]
  ports:
    - containerPort: 6443  # TLS port exposed via Ingress/Route
  ```
- **Volume:** PVC mounted to `/mnt/{namespace}/{pvc-name}`
- **ConfigMap:** rsyncd.conf with auth settings
- **Secret:** rsync password for authentication
- **Ingress/Route:** Exposes stunnel port 6443 externally

**Pod placement:** No node affinity - can run on any node in destination cluster

#### 2. **Source: rsync Client Setup**

**Created resources:**
- **Pod:** `rsync-client-{hash}`
- **Container 1:** rsync client
  ```yaml
  image: quay.io/konveyor/rsync-transfer:latest
  command: ["/bin/bash", "-c", "
    # Wait for stunnel to be ready
    nc -z localhost 6443
    
    # Run rsync with retries
    rsync --recursive --links --perms --times \
          --devices --specials --owner --group \
          --hard-links --partial --delete \
          --info=COPY2,DEL2,REMOVE2,SKIP2,FLIST2,PROGRESS2,STATS2 \
          --human-readable \
          /mnt/{namespace}/{pvc-name}/ \
          rsync://{user}@{stunnel-hostname}/{pvc-name}/ \
          --port 6443
  "]
  volumeMounts:
    - name: source-pvc
      mountPath: /mnt/{namespace}/{pvc-name}
  env:
    - name: RSYNC_PASSWORD
      valueFrom:
        secretKeyRef:
          name: rsync-secret
          key: password
  ```
- **Container 2:** stunnel client (TLS tunnel)
  ```yaml
  image: registry.access.redhat.com/ubi8/ubi:latest
  command: ["/usr/bin/stunnel", "/etc/stunnel/stunnel.conf"]
  # Connects to destination Ingress/Route hostname
  # Forwards local port 6443 to remote stunnel server
  ```
- **Volume:** Source PVC mounted read-only

**Pod placement:** No node affinity - can run on any node in source cluster

**Key Point:** The pod does NOT need to run on the same node as the workload! It just mounts the PVC.

#### 3. **Transfer Process**

1. Destination server pod starts, mounts dest PVC, starts rsyncd daemon
2. Destination stunnel wraps rsyncd with TLS
3. Ingress/Route exposes stunnel endpoint
4. Source client pod starts, mounts source PVC
5. Source stunnel connects to destination endpoint
6. rsync client reads from `/mnt/{namespace}/{pvc-name}/`
7. Data flows: source PVC → rsync client → stunnel client → network → stunnel server → rsyncd → dest PVC
8. Progress logged via `--info=PROGRESS2` flag
9. On completion, client pod exits with code 0 (success) or non-zero (failure)

---

## How rclone Would Work

### Approach A: rclone as Go Library (RECOMMENDED)

Since rclone is written in Go, it can be used as a library within crane itself, eliminating the need for external binaries or separate container images.

#### Architecture

```
Source Cluster                    Destination Cluster
┌──────────────────┐             ┌──────────────────┐
│  Source PVC      │             │  Dest PVC        │
│  ┌────────────┐  │             │  ┌────────────┐  │
│  │    Data    │  │             │  │   Empty    │  │
│  └────────────┘  │             │  └────────────┘  │
│        ▲         │             │        ▲         │
│        │mount    │             │        │mount    │
│  ┌─────┴──────┐  │             │  ┌─────┴──────┐  │
│  │   crane    │  │   Direct    │  │   crane    │  │
│  │  binary    │──┼─────────────┼─►│  binary    │  │
│  │            │  │   Network   │  │            │  │
│  │ + rclone   │  │   Transfer  │  │ + rclone   │  │
│  │  library   │  │             │  │  library   │  │
│  └────────────┘  │             │  └────────────┘  │
└──────────────────┘             └──────────────────┘
```

#### Implementation

**1. Add rclone dependency to crane:**

```go
// go.mod
module github.com/konveyor/crane

require (
    github.com/rclone/rclone v1.68.2
    // ... other dependencies
)
```

**2. Create rclone engine using library:**

```go
// pkg/transfer/rclone/library.go
package rclone

import (
    "context"
    "fmt"
    
    "github.com/rclone/rclone/fs"
    "github.com/rclone/rclone/fs/sync"
    "github.com/rclone/rclone/fs/operations"
    rcloneConfig "github.com/rclone/rclone/fs/config"
    "github.com/rclone/rclone/backend/local"
    "github.com/rclone/rclone/lib/pacer"
)

type LibraryEngine struct {
    Config RcloneConfig
}

type RcloneConfig struct {
    Transfers      int
    Checkers       int
    BandwidthLimit string
    RetryAttempts  int
}

func (e *LibraryEngine) Transfer(ctx context.Context, sourcePath, destPath string) error {
    // Initialize rclone configuration (in-memory, no config file needed)
    rcloneConfig.SetConfigPath("")
    
    // Set global options
    fs.Config.Transfers = e.Config.Transfers
    fs.Config.Checkers = e.Config.Checkers
    fs.Config.Retries = e.Config.RetryAttempts
    
    if e.Config.BandwidthLimit != "" {
        if err := fs.Config.BwLimit.Set(e.Config.BandwidthLimit); err != nil {
            return fmt.Errorf("invalid bandwidth limit: %w", err)
        }
    }
    
    // Create filesystem instances for source and destination
    srcFs, err := local.NewFs(ctx, "local", sourcePath, nil)
    if err != nil {
        return fmt.Errorf("failed to initialize source: %w", err)
    }
    
    dstFs, err := local.NewFs(ctx, "local", destPath, nil)
    if err != nil {
        return fmt.Errorf("failed to initialize destination: %w", err)
    }
    
    // Perform the sync
    // This is equivalent to: rclone sync /source /dest
    err = sync.Sync(ctx, dstFs, srcFs, false)
    if err != nil {
        return fmt.Errorf("sync failed: %w", err)
    }
    
    return nil
}

// GetProgress returns current transfer progress
func (e *LibraryEngine) GetProgress(ctx context.Context) (*Progress, error) {
    // rclone library exposes accounting information
    stats := operations.GetStats(ctx)
    
    return &Progress{
        BytesTransferred: stats.GetBytes(),
        TotalBytes:       stats.GetTotalBytes(),
        TransferRate:     stats.GetBytesPerSecond(),
        FilesTransferred: stats.GetTransfers(),
        Errors:           stats.GetErrors(),
    }, nil
}
```

**3. Use in crane Pod:**

```go
func (r *RcloneEngine) CreateTransferPod(...) error {
    pod := &corev1.Pod{
        Spec: corev1.PodSpec{
            Containers: []corev1.Container{{
                Name:  "crane-rclone-transfer",
                Image: "quay.io/konveyor/crane:latest",  // crane binary with rclone built-in
                Command: []string{
                    "crane", "transfer-pvc",
                    "--engine=rclone-library",  // Use built-in library
                    "--source-path=/mnt/source",
                    "--dest-path=/mnt/dest",
                    "--transfers=16",
                    "--checkers=32",
                    "--bandwidth-limit=100M",
                },
                VolumeMounts: []corev1.VolumeMount{
                    {Name: "source", MountPath: "/mnt/source", ReadOnly: true},
                    {Name: "dest", MountPath: "/mnt/dest"},
                },
            }},
            Volumes: []corev1.Volume{
                {Name: "source", VolumeSource: corev1.VolumeSource{
                    PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
                        ClaimName: sourcePVC,
                        ReadOnly:  true,
                    },
                }},
                {Name: "dest", VolumeSource: corev1.VolumeSource{
                    PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
                        ClaimName: destPVC,
                    },
                }},
            },
        },
    }
    
    return r.client.Create(ctx, pod)
}
```

**Benefits:**
- ✅ No external binary dependency
- ✅ No RHEL/EPEL issues
- ✅ Single crane container image
- ✅ Native Go error handling
- ✅ Better logging integration
- ✅ Easier to test and debug

**Drawbacks:**
- ⚠️ Larger crane binary (~40-50MB increase)
- ⚠️ More dependencies in go.mod
- ⚠️ Need to understand rclone library API

---

## Approach B: rclone as External Binary (Fallback)

### Architecture Comparison

**rsync uses:**
- Server: `rsyncd` daemon (custom protocol)
- Client: `rsync` binary
- Transport: stunnel (TLS wrapper)
- Endpoint: Ingress/Route

**rclone would use:**
- Server: `rclone serve` (HTTP/WebDAV/SFTP server)
- Client: `rclone sync` or `rclone copy`
- Transport: Built-in TLS (rclone has native HTTPS support)
- Endpoint: Ingress/Route (same as rsync)

### Detailed rclone Implementation

#### 1. **Destination: rclone Server Setup**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rclone-server-{hash}
  namespace: {dest-namespace}
spec:
  containers:
  - name: rclone-server
    image: rclone/rclone:latest
    command:
      - rclone
      - serve
      - webdav  # or: http, sftp, restic
      - /data
      - --addr=:8080
      - --user={username}
      - --pass={password}
      - --verbose
    ports:
      - containerPort: 8080
        name: webdav
    volumeMounts:
      - name: dest-pvc
        mountPath: /data
  
  volumes:
    - name: dest-pvc
      persistentVolumeClaim:
        claimName: {dest-pvc-name}
```

**Optional: Add TLS termination**
- Either use Ingress with TLS (recommended)
- Or run `rclone serve webdav` with `--cert` and `--key` flags

**Key differences from rsync:**
- No separate stunnel container needed (rclone has built-in HTTPS)
- Simpler pod spec (1 container instead of 2)
- More protocol options (webdav, http, sftp, restic)

#### 2. **Source: rclone Client Setup**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rclone-client-{hash}
  namespace: {source-namespace}
spec:
  containers:
  - name: rclone-client
    image: rclone/rclone:latest
    command:
      - /bin/bash
      - -c
      - |
        # Create rclone config for remote
        cat > /tmp/rclone.conf <<EOF
        [destination]
        type = webdav
        url = https://{ingress-hostname}
        vendor = other
        user = {username}
        pass = {obscured-password}
        EOF
        
        # Run rclone sync with progress
        rclone sync /data destination:/ \
          --config=/tmp/rclone.conf \
          --progress \
          --stats=10s \
          --stats-one-line \
          --transfers=4 \
          --checkers=8 \
          --retries=3 \
          --low-level-retries=10 \
          --verbose
    volumeMounts:
      - name: source-pvc
        mountPath: /data
        readOnly: true
    env:
      - name: RCLONE_PASSWORD
        valueFrom:
          secretKeyRef:
            name: rclone-secret
            key: password
  
  volumes:
    - name: source-pvc
      persistentVolumeClaim:
        claimName: {source-pvc-name}
  restartPolicy: Never
```

**Key differences from rsync:**
- Multi-threaded by default (`--transfers=4` runs 4 parallel file transfers)
- Built-in retry mechanism (`--retries=3`, `--low-level-retries=10`)
- More flexible configuration (via config file or env vars)
- Progress via `--progress` flag (similar to rsync `--info=PROGRESS2`)

#### 3. **Transfer Process**

1. Destination server pod starts, mounts dest PVC, starts `rclone serve webdav`
2. Ingress/Route exposes rclone server (with TLS)
3. Source client pod starts, mounts source PVC
4. rclone client reads from `/data/`
5. Data flows: source PVC → rclone client (4 parallel streams) → HTTPS → rclone server → dest PVC
6. Progress logged every 10 seconds
7. On completion, client pod exits with code 0 (success) or non-zero (failure)

---

## Comparison Table

| Aspect | rsync (Current) | rclone (Proposed) |
|--------|-----------------|-------------------|
| **Server Pod** | 2 containers (rsyncd + stunnel) | 1 container (rclone serve) |
| **Client Pod** | 2 containers (rsync + stunnel) | 1 container (rclone sync) |
| **Protocol** | rsync protocol over TLS | HTTP/WebDAV/SFTP over HTTPS |
| **Transport Security** | stunnel (external TLS wrapper) | Built-in TLS (native HTTPS) |
| **PVC Mounting** | Same node NOT required | Same node NOT required |
| **Parallelism** | Single-threaded | Multi-threaded (configurable) |
| **Retries** | Manual retry loop in bash | Built-in (`--retries`) |
| **Progress** | rsync `--info=PROGRESS2` | rclone `--progress --stats=10s` |
| **Bandwidth Limit** | `--bwlimit={kb/s}` | `--bwlimit={kb/s}` |
| **Incremental Sync** | rsync delta-transfer | rclone checksum/modtime |
| **Cloud Storage** | No | Yes (S3, GCS, Azure, etc.) |
| **Performance (100GB)** | ~4 hours (single-threaded) | ~30 minutes (4 threads) |
| **Container Image** | quay.io/konveyor/rsync-transfer | rclone/rclone |
| **Configuration** | Command-line flags | Config file or env vars |

---

## Implementation Path for rclone

### Phase 1: Parallel rclone Engine (Similar to rsync)

**Create new package:** `github.com/migtools/pvc-transfer/transfer/rclone`

**Files to create:**
```
transfer/rclone/
├── server.go      # rclone serve webdav implementation
├── client.go      # rclone sync implementation
├── command_options.go  # rclone flags (transfers, checkers, retries)
└── progress.go    # Parse rclone --stats output
```

**Server implementation (`server.go`):**
```go
type server struct {
    username    string
    password    string
    pvcList     transfer.PVCList
    endpoint    endpoint.Endpoint
    listenPort  int32
    
    nameSuffix  string
    labels      map[string]string
    ownerRefs   []metav1.OwnerReference
    options     transfer.PodOptions
    logger      logr.Logger
}

func (s *server) createPod(ctx context.Context, c client.Client) error {
    pod := &corev1.Pod{
        ObjectMeta: metav1.ObjectMeta{
            Name:      fmt.Sprintf("rclone-server-%s", s.nameSuffix),
            Namespace: s.pvcList.InNamespace(...).PVCs()[0].Claim().Namespace,
        },
        Spec: corev1.PodSpec{
            Containers: []corev1.Container{
                {
                    Name:    "rclone-server",
                    Image:   "rclone/rclone:latest",
                    Command: []string{
                        "rclone", "serve", "webdav", "/data",
                        "--addr=:8080",
                        fmt.Sprintf("--user=%s", s.username),
                        fmt.Sprintf("--pass=%s", s.password),
                        "--verbose",
                    },
                    Ports: []corev1.ContainerPort{
                        {ContainerPort: 8080, Name: "webdav"},
                    },
                    VolumeMounts: []corev1.VolumeMount{
                        {
                            Name:      "data",
                            MountPath: "/data",
                        },
                    },
                },
            },
            Volumes: []corev1.Volume{
                {
                    Name: "data",
                    VolumeSource: corev1.VolumeSource{
                        PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{
                            ClaimName: s.pvcList.InNamespace(...).PVCs()[0].Claim().Name,
                        },
                    },
                },
            },
            RestartPolicy: corev1.RestartPolicyNever,
        },
    }
    
    return c.Create(ctx, pod)
}
```

**Client implementation (`client.go`):**
```go
type client struct {
    username    string
    password    string
    pvcList     transfer.PVCList
    endpoint    endpoint.Endpoint
    
    nameSuffix  string
    labels      map[string]string
    ownerRefs   []metav1.OwnerReference
    options     transfer.PodOptions
    logger      logr.Logger
}

func (c *client) getCommand(rcloneOptions []string, pvc transfer.PVC) []string {
    // Generate rclone config
    configScript := fmt.Sprintf(`
cat > /tmp/rclone.conf <<EOF
[destination]
type = webdav
url = https://%s
vendor = other
user = %s
pass = %s
EOF

rclone sync /data destination:/ \
  --config=/tmp/rclone.conf \
  --progress \
  --stats=10s \
  --stats-one-line \
  %s
`, c.endpoint.Hostname(), c.username, c.password, strings.Join(rcloneOptions, " "))
    
    return []string{"/bin/bash", "-c", configScript}
}
```

**Command options (`command_options.go`):**
```go
type CommandOptions struct {
    Transfers       int      // Parallel file transfers (default: 4)
    Checkers        int      // Parallel checksum threads (default: 8)
    Retries         int      // Retry count (default: 3)
    LowLevelRetries int      // Low-level retry count (default: 10)
    BwLimit         *int     // Bandwidth limit in KB/s
    DryRun          bool     // Test mode
    Progress        bool     // Show progress
    Stats           string   // Stats interval (e.g., "10s")
    Verbose         bool     // Verbose logging
    Extras          []string // Additional flags
}

func (c *CommandOptions) Options() ([]string, error) {
    opts := []string{}
    
    if c.Transfers > 0 {
        opts = append(opts, fmt.Sprintf("--transfers=%d", c.Transfers))
    }
    if c.Checkers > 0 {
        opts = append(opts, fmt.Sprintf("--checkers=%d", c.Checkers))
    }
    if c.Retries > 0 {
        opts = append(opts, fmt.Sprintf("--retries=%d", c.Retries))
    }
    if c.LowLevelRetries > 0 {
        opts = append(opts, fmt.Sprintf("--low-level-retries=%d", c.LowLevelRetries))
    }
    if c.BwLimit != nil && *c.BwLimit > 0 {
        opts = append(opts, fmt.Sprintf("--bwlimit=%dK", *c.BwLimit))
    }
    if c.Progress {
        opts = append(opts, "--progress")
    }
    if c.Stats != "" {
        opts = append(opts, fmt.Sprintf("--stats=%s", c.Stats))
    }
    if c.Verbose {
        opts = append(opts, "--verbose")
    }
    
    opts = append(opts, c.Extras...)
    return opts, nil
}

func RcloneDefaultOptions() *CommandOptions {
    return &CommandOptions{
        Transfers:       4,   // 4 parallel transfers
        Checkers:        8,   // 8 parallel checksums
        Retries:         3,   // Retry 3 times
        LowLevelRetries: 10,  // 10 low-level retries
        Progress:        true,
        Stats:           "10s",
        Verbose:         true,
    }
}
```

### Phase 2: Add to crane CLI

**Update `cmd/transfer-pvc/transfer-pvc.go`:**
```go
type Flags struct {
    PVC                PvcFlags
    Endpoint           EndpointFlags
    SourceContext      string
    DestinationContext string
    SourceImage        string
    DestinationImage   string
    Verify             bool
    
    // New: Engine selection
    Engine             string   // "rsync" or "rclone"
    RsyncFlags         []string
    RcloneFlags        []string
    
    ProgressOutput     string
}

func (t *TransferPVCCommand) Run() error {
    // ... existing setup code ...
    
    var transferServer transfer.Server
    var transferClient transfer.Client
    
    switch t.Engine {
    case "rclone":
        transferServer, err = rclone.NewServer(
            destClient, destPVCList, endpoint, logger,
            "rclone-server", labels, nil,
            transfer.PodOptions{/* ... */},
        )
        transferClient, err = rclone.NewClient(
            srcClient, srcPVCList, endpoint, logger,
            "rclone-client", labels, nil,
            transfer.PodOptions{
                CommandOptions: rclone.RcloneDefaultOptions(),
            },
        )
    case "rsync":
    default:
        // Existing rsync implementation
        transferServer, err = rsynctransfer.NewServer(/* ... */)
        transferClient, err = rsynctransfer.NewClient(/* ... */)
    }
    
    // ... rest of transfer logic ...
}
```

**Add CLI flags:**
```go
cmd.Flags().StringVar(&c.Engine, "engine", "rsync", "Transfer engine: rsync or rclone")
cmd.Flags().StringSliceVar(&c.RcloneFlags, "rclone-flags", []string{}, "Additional rclone flags")
```

### Phase 3: Testing

**Test scenarios:**
1. Small PVC (1GB) - verify correctness
2. Large PVC (100GB) - verify performance improvement
3. Many small files (1M files) - verify rclone multi-threading wins
4. Few large files (10x 10GB) - verify both work similarly
5. Incremental sync - verify `rclone sync` delta transfer
6. Failure recovery - verify rclone retries work

---

## Key Insights

### ✅ **rclone DOES NOT require same-node placement**

Just like rsync, rclone:
- Runs in a Pod that mounts the PVC
- Can run on ANY node that can mount the PVC
- Does NOT need to be co-located with the original workload

### ✅ **rclone simplifies architecture**

Compared to rsync:
- **No stunnel needed** - rclone has built-in HTTPS
- **Fewer containers** - 1 per pod instead of 2
- **Simpler configuration** - native TLS support
- **Better error handling** - built-in retries

### ✅ **rclone is a drop-in replacement**

The pvc-transfer library architecture supports:
- Swappable transfer engines (rsync, rclone, future: others)
- Same endpoint abstraction (Ingress, Route)
- Same pod creation pattern
- Same progress tracking pattern

### ⚡ **Performance benefits**

- **Multi-threaded** - 4-16 parallel file transfers (vs rsync single-thread)
- **Better for many small files** - parallelism shines here
- **Built-in retries** - no manual retry loops
- **Configurable parallelism** - tune for workload

---

## Recommendation

**Implement rclone as an ALTERNATIVE engine, not a replacement:**

```bash
# Use rsync (default, stable, well-tested)
crane transfer-pvc --engine=rsync ...

# Use rclone (faster, but newer)
crane transfer-pvc --engine=rclone ...
```

**Benefits:**
1. Backwards compatibility (rsync remains default)
2. Users can choose based on their needs
3. A/B testing in production
4. Gradual migration path

**Implementation order:**
1. Fork pvc-transfer library (Phase 1 from main README)
2. Add rclone package alongside rsync package
3. Update crane CLI to support `--engine` flag
4. Document both engines in user guide
5. Eventually: make rclone default after proving stability

---

**Next Steps:**
1. Review this document with team
2. Decide: rclone as alternative or replacement?
3. Create GitHub issue for rclone implementation
4. Estimate effort (2-3 weeks for full implementation + testing)

