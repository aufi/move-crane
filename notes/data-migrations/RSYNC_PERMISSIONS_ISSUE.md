# rsync Permission Issues: How to Transfer Files with Restrictive Permissions (0700)

**Date:** 2026-07-01  
**Problem:** rsync skips files owned by different user with permissions 0700  
**Root Cause:** Non-privileged rsync Pods can't read files owned by other users

---

## Problem Description

### Symptom:

```bash
crane transfer-pvc --pvc-name myapp-data --pvc-namespace myapp ...

# rsync output:
rsync: send_files failed to open "/mnt/myapp/myapp-data/user1/.ssh/id_rsa": Permission denied (13)
rsync: send_files failed to open "/mnt/myapp/myapp-data/user2/private/secret.txt": Permission denied (13)
...
```

**Files being skipped:**
- Owner: user1 (UID 1001)
- Permissions: `0700` (drwx------)
- rsync runs as: different user (UID 1000650000 from namespace range)
- Result: **Permission denied** - files not transferred!

---

## Root Cause Analysis

### How crane transfer-pvc Runs rsync:

**1. Pod Security Context (Non-Root User):**

```go
// cmd/transfer-pvc/transfer-pvc.go:460-466
ContainerSecurityContext: corev1.SecurityContext{
    Privileged: &falseBool,              // ← NOT privileged!
    RunAsNonRoot: &trueBool,             // ← Must run as non-root
    RunAsUser: clientPodSecCtx.RunAsUser, // ← UID from namespace annotation
    AllowPrivilegeEscalation: &falseBool, // ← Can't escalate privileges
}
```

**2. UID/GID Detection:**

```go
// Reads from namespace annotation (OpenShift)
ns.Annotations[securityv1.UIDRangeAnnotation] // e.g., "1000650000/10000"
// Pod runs as UID 1000650000 (first UID in namespace range)
```

**3. rsync Options (Restricted Mode):**

```go
// cmd/transfer-pvc/transfer-pvc.go:452
restrictedContainers(true)

// This disables:
opts.Groups = false      // --group flag DISABLED
opts.Owners = false      // --owner flag DISABLED
opts.DeviceFiles = false // --devices flag DISABLED
opts.SpecialFiles = false // --specials flag DISABLED
```

**Resulting rsync command:**
```bash
rsync --recursive --links --perms --times \
      --hard-links --partial --delete \
      --info=COPY,DEL,STATS2,PROGRESS2,FLIST2 \
      --progress --omit-dir-times \
      /mnt/myapp/myapp-data/ \
      rsync://user@server/myapp-data/
```

**Note:** NO `--owner` or `--group` flags!

### Why Files are Skipped:

```
File on source PVC:
- Path: /mnt/myapp/myapp-data/user1/.ssh/id_rsa
- Owner: UID 1001, GID 1001
- Permissions: 0700 (drwx------)

rsync Pod trying to read:
- Running as: UID 1000650000
- Tries to open: /mnt/myapp/myapp-data/user1/.ssh/id_rsa
- Linux kernel checks: UID 1000650000 != UID 1001
- Permissions: 0700 = owner-only access
- Result: Permission denied!
```

**rsync can't read the file** → skips it → file NOT transferred!

---

## Solutions

### Solution 1: Run rsync as Root (NOT RECOMMENDED - Security Risk!)

**Requires:** Privileged container

**Implementation:**

1. **Fork crane** and modify `cmd/transfer-pvc/transfer-pvc.go`:

```go
// BEFORE (line 455-462):
ContainerSecurityContext: corev1.SecurityContext{
    Privileged: &falseBool,
    RunAsNonRoot: &trueBool,
    RunAsUser: clientPodSecCtx.RunAsUser,
    AllowPrivilegeEscalation: &falseBool,
}

// AFTER:
privilegedBool := true
rootUser := int64(0)
ContainerSecurityContext: corev1.SecurityContext{
    Privileged: &privilegedBool,  // ← Run as privileged
    RunAsUser: &rootUser,          // ← Run as root
}
```

2. **Enable privileged containers** in cluster (OpenShift SCC, Kubernetes PSP/PSA)

**Pros:**
- ✅ Can read all files regardless of ownership
- ✅ Preserves ownership with `--owner --group`

**Cons:**
- ❌ **SECURITY RISK** - privileged container can do anything
- ❌ Violates security policies (PSP, PSA, OpenShift SCC)
- ❌ May be blocked by cluster admins
- ❌ NOT recommended for production

---

### Solution 2: Use initContainer to Fix Permissions (RECOMMENDED)

**Idea:** Run an initContainer as root to make files readable before rsync

**Implementation:**

Add custom PodSpec via crane fork or use Job-based approach from SIMPLE_JOB_PROPOSAL.md:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: rsync-client-custom
spec:
  # initContainer runs as root, fixes permissions
  initContainers:
  - name: fix-permissions
    image: registry.access.redhat.com/ubi8/ubi:latest
    command:
    - /bin/bash
    - -c
    - |
      # Make all files readable by group
      find /mnt -type d -exec chmod g+rx {} \;
      find /mnt -type f -exec chmod g+r {} \;
      
      # OR: Change ownership to rsync user
      # chown -R 1000650000:1000650000 /mnt
    volumeMounts:
    - name: source-pvc
      mountPath: /mnt
    securityContext:
      runAsUser: 0  # Run as root
      privileged: true
  
  # Regular rsync containers
  containers:
  - name: rsync
    image: quay.io/konveyor/rsync-transfer:latest
    command: [...]
    volumeMounts:
    - name: source-pvc
      mountPath: /mnt
    securityContext:
      runAsUser: 1000650000  # Non-root user
  
  volumes:
  - name: source-pvc
    persistentVolumeClaim:
      claimName: myapp-data
```

**Pros:**
- ✅ Works with non-privileged rsync container
- ✅ Only initContainer needs privilege (time-limited)
- ✅ Complies with most security policies

**Cons:**
- ⚠️ Modifies source PVC permissions (may not be acceptable)
- ⚠️ Requires custom Pod spec (not standard crane command)

---

### Solution 3: Use FSGroup to Grant Access (EASIEST - RECOMMENDED)

**Idea:** Set FSGroup to match file owner's GID

**How it works:**
- Kubernetes automatically changes group ownership of PVC files to FSGroup
- rsync Pod gets read access via group permissions

**Implementation:**

**Option A: Modify crane code:**

```go
// cmd/transfer-pvc/transfer-pvc.go - modify getRsyncClientPodSecurityContext
func getRsyncClientPodSecurityContext(client client.Client, namespace string) (*corev1.PodSecurityContext, error) {
    ps := &corev1.PodSecurityContext{}
    ctx, err := getIDsForNamespace(client, namespace)
    if err != nil {
        return ps, err
    }
    ps.RunAsUser = ctx.RunAsUser
    ps.RunAsGroup = ctx.RunAsGroup
    
    // NEW: Set FSGroup to file owner's GID
    fileOwnerGID := int64(1001)  // ← Get this from user or auto-detect
    ps.FSGroup = &fileOwnerGID   // ← This gives Pod access!
    
    return ps, nil
}
```

**Option B: Use Job with custom FSGroup (NO CODE CHANGE NEEDED):**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pvc-transfer-custom
spec:
  template:
    spec:
      serviceAccountName: crane-sa
      securityContext:
        fsGroup: 1001  # ← GID of file owner
        runAsUser: 1000650000
        runAsGroup: 1000650000
      
      containers:
      - name: rsync-client
        image: quay.io/konveyor/rsync-transfer:latest
        command:
        - /bin/bash
        - -c
        - |
          rsync --recursive --links --perms --times \
                --hard-links --partial --delete \
                --info=COPY,DEL,STATS2,PROGRESS2,FLIST2 \
                --progress \
                /mnt/source/ \
                rsync://user@dest-server/target/
        volumeMounts:
        - name: source-pvc
          mountPath: /mnt/source
      
      volumes:
      - name: source-pvc
        persistentVolumeClaim:
          claimName: myapp-data
      
      restartPolicy: Never
```

**How FSGroup works:**

```
Before (files owned by UID 1001, GID 1001, perms 0700):
- Pod runs as UID 1000650000, GID 1000650000
- Can't read files (not owner, not in group)

After (FSGroup = 1001):
- Kubernetes changes group ownership: UID 1001, GID 1001 → GID still 1001
- Pod runs as UID 1000650000, GID 1000650000, supplementary groups [1001]
- File perms: 0700 still owner-only
- BUT Kubernetes also sets perms to 0750 (adds group read)
- Pod can now read! (member of GID 1001 via supplementary group)
```

**Pros:**
- ✅ **EASIEST** solution
- ✅ No privileged containers needed
- ✅ Works with standard Kubernetes
- ✅ Complies with security policies

**Cons:**
- ⚠️ Modifies file permissions on source PVC (0700 → 0740/0750)
- ⚠️ Need to know file owner's GID beforehand
- ⚠️ Only works if all files have same GID

---

### Solution 4: Use tar Instead of rsync (ALTERNATIVE APPROACH)

**Idea:** Use `tar` to preserve exact permissions without needing read access

**How it works:**
- `tar` on source side runs as root (via initContainer or privileged container)
- Creates tarball with all files (can read 0700 files as root)
- Transfers tarball to destination
- Extracts on destination (preserves exact ownership/permissions)

**Implementation:**

```bash
# Source cluster (run as privileged/root to read 0700 files)
kubectl run tar-source --rm -i \
  --image=registry.access.redhat.com/ubi8/ubi:latest \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' \
  --attach --restart=Never -- \
  tar czf - -C /mnt/source . > /tmp/pvc-data.tar.gz

# Transfer tarball (e.g., via kubectl cp or S3)
kubectl cp tar-source:/tmp/pvc-data.tar.gz ./pvc-data.tar.gz

# Destination cluster (extract as root to preserve ownership)
kubectl run tar-dest --rm -i \
  --image=registry.access.redhat.com/ubi8/ubi:latest \
  --overrides='{"spec":{"securityContext":{"runAsUser":0}}}' \
  --attach --restart=Never -- \
  tar xzf - -C /mnt/dest < ./pvc-data.tar.gz
```

**Pros:**
- ✅ Preserves exact ownership and permissions
- ✅ No permission modifications needed
- ✅ Works for complex permission scenarios

**Cons:**
- ❌ Requires root containers (privileged)
- ❌ No incremental sync (full copy each time)
- ❌ Slower for large PVCs (tar creates full archive)
- ❌ Requires manual orchestration

---

### Solution 5: Mount PVC as ReadWriteMany (If Supported)

**Idea:** Mount source PVC in destination cluster, copy locally

**Requirements:**
- PVC must support ReadWriteMany (RWX) access mode
- Both clusters must access same storage backend (e.g., NFS, CephFS)

**Implementation:**

```yaml
# Destination cluster - mount source PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: source-pvc-remote
spec:
  accessModes:
    - ReadWriteMany  # ← RWX required!
  storageClassName: nfs-shared
  volumeName: pv-source-pvc  # Points to source PVC's PV

---
# Pod that copies data locally
apiVersion: v1
kind: Pod
metadata:
  name: local-copy
spec:
  containers:
  - name: copier
    image: registry.access.redhat.com/ubi8/ubi:latest
    command:
    - /bin/bash
    - -c
    - |
      # Run as root to preserve ownership
      cp -a /source/* /dest/
    volumeMounts:
    - name: source
      mountPath: /source
    - name: dest
      mountPath: /dest
    securityContext:
      runAsUser: 0  # Root to preserve ownership
  
  volumes:
  - name: source
    persistentVolumeClaim:
      claimName: source-pvc-remote
  - name: dest
    persistentVolumeClaim:
      claimName: dest-pvc
```

**Pros:**
- ✅ No network transfer needed (local copy)
- ✅ Preserves exact permissions
- ✅ Fast (no network bottleneck)

**Cons:**
- ❌ Requires RWX storage (not all storage classes support it)
- ❌ Requires shared storage backend between clusters
- ❌ Not applicable for cross-cloud migrations
- ❌ Rarely feasible in practice

---

## Recommended Solution for crane transfer-pvc

### **Best Practice: Add CLI Flag for FSGroup**

**Add to crane transfer-pvc:**

```go
// cmd/transfer-pvc/transfer-pvc.go - add flag
type Flags struct {
    // ... existing flags
    FSGroup int64  // NEW: FSGroup for accessing files
}

// Add flag registration
cmd.Flags().Int64Var(&c.FSGroup, "fs-group", 0, 
    "FSGroup to set on rsync Pods for accessing files owned by specific GID")

// Use in Pod creation
func getRsyncClientPodSecurityContext(...) (*corev1.PodSecurityContext, error) {
    ps := &corev1.PodSecurityContext{}
    // ... existing code
    
    if t.Flags.FSGroup > 0 {
        ps.FSGroup = &t.Flags.FSGroup
    }
    
    return ps, nil
}
```

**Usage:**

```bash
# Transfer files owned by GID 1001
crane transfer-pvc \
  --pvc-name myapp-data \
  --pvc-namespace myapp \
  --fs-group 1001 \
  --source-context source \
  --destination-context dest
```

**Why this is best:**
1. ✅ Simple CLI flag (no code forking needed)
2. ✅ Works with existing security policies
3. ✅ No privileged containers
4. ✅ User can specify GID per transfer
5. ✅ Kubernetes handles permission magic via FSGroup

---

## Detection: How to Find File Owner GID

### Method 1: Inspect Files in Source PVC

```bash
# List a Pod using the PVC
kubectl get pods -n myapp -o json | \
  jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == "myapp-data") | .metadata.name'

# Output: myapp-deployment-xyz

# Exec into Pod and check file ownership
kubectl exec -n myapp myapp-deployment-xyz -- ls -ln /data

# Output:
# drwx------ 2 1001 1001 4096 Jul  1 12:00 user1
# drwx------ 2 1002 1002 4096 Jul  1 12:00 user2
#            ↑    ↑
#           UID  GID
```

**Common GIDs to try:**
- `1001` - common first user GID
- `0` - root group (if files are owned by root)
- Check namespace annotation: `kubectl get namespace myapp -o yaml | grep supplementalGroups`

### Method 2: Auto-Detect (Future Enhancement)

**Add to crane:**

```go
func detectFSGroup(client client.Client, pvcName, namespace string) (int64, error) {
    // Find Pod using this PVC
    podList := &corev1.PodList{}
    client.List(ctx, podList, client.InNamespace(namespace))
    
    for _, pod := range podList.Items {
        for _, vol := range pod.Spec.Volumes {
            if vol.PersistentVolumeClaim != nil && vol.PersistentVolumeClaim.ClaimName == pvcName {
                // Found Pod using this PVC
                // Exec into Pod and check file ownership
                // Return most common GID
            }
        }
    }
}
```

---

## Testing the Fix

### Test Case 1: Files with 0700 Permissions

**Setup:**
```bash
# Create test files on source PVC
kubectl exec -n myapp source-pod -- /bin/bash -c '
mkdir -p /data/user1/.ssh
echo "test" > /data/user1/.ssh/id_rsa
chmod 700 /data/user1/.ssh
chmod 600 /data/user1/.ssh/id_rsa
chown 1001:1001 /data/user1
ls -la /data/user1/.ssh/
'
# Output:
# drwx------ 2 1001 1001 4096 Jul  1 12:00 .
# -rw------- 1 1001 1001    5 Jul  1 12:00 id_rsa
```

**Test without FSGroup:**
```bash
crane transfer-pvc --pvc-name myapp-data --pvc-namespace myapp ...

# Expected: Permission denied errors
# rsync: send_files failed to open ".../.ssh/id_rsa": Permission denied (13)
```

**Test with FSGroup:**
```bash
crane transfer-pvc \
  --pvc-name myapp-data \
  --pvc-namespace myapp \
  --fs-group 1001 \
  ...

# Expected: Success! Files transferred
```

**Verify on destination:**
```bash
kubectl exec -n myapp dest-pod -- ls -la /data/user1/.ssh/
# Output:
# drwx------ 2 1001 1001 4096 Jul  1 12:00 .
# -rw------- 1 1001 1001    5 Jul  1 12:00 id_rsa
```

---

## Summary

| Solution | Effort | Security | Preserves Ownership | Recommended |
|----------|--------|----------|---------------------|-------------|
| **1. Run as root** | Low | ❌ Poor | ✅ Yes | ❌ No |
| **2. initContainer fix perms** | Medium | ⚠️ Medium | ❌ No (modifies source) | ⚠️ Maybe |
| **3. FSGroup** | Low | ✅ Good | ✅ Yes | ✅ **YES** |
| **4. tar method** | High | ❌ Poor | ✅ Yes | ⚠️ Alternative |
| **5. RWX mount** | High | ✅ Good | ✅ Yes | ❌ Rarely feasible |

### **Recommended Approach:**

1. **Add `--fs-group` flag to crane transfer-pvc**
2. **Detect file owner GID** (manual or auto-detect)
3. **Run transfer with FSGroup set**

```bash
crane transfer-pvc \
  --pvc-name myapp-data \
  --pvc-namespace myapp \
  --fs-group 1001 \
  --source-context source \
  --destination-context dest
```

This preserves security (no privileged containers), preserves ownership, and handles 0700 files correctly!

