# Stateful Workload Migration Flow

**Status:** Proposal  
**Audience:** crane CLI users migrating stateful workloads  
**Goal:** Define complete migration flow from discovery to cutover for workloads with PVCs

---

## Executive Summary

This document describes the **end-to-end flow** for migrating stateful Kubernetes workloads using `crane` CLI commands combined with `kubectl` operations. It addresses:

1. **Discovery** - How users identify PVCs that need migration
2. **PVC Creation** - Creating target PVCs before data transfer
3. **PVC Mapping** - Matching source PVCs to target PVCs (name changes, StorageClass mapping)
4. **Data Transfer** - Using `crane transfer-pvc` for actual data copy
5. **Complete Migration Flow** - Step-by-step guide with all `kubectl` commands
6. **Integration with crane export/transform/apply** - How transfer-pvc fits into the standard crane workflow

**Key Insight:** `crane transfer-pvc` is a **standalone utility** that operates OUTSIDE the export→transform→apply flow. Users must orchestrate PVC transfers separately, typically AFTER creating target PVCs but BEFORE starting target workloads.

---

## Table of Contents

1. [Current State: How crane Handles PVCs](#current-state)
2. [PVC Discovery: Finding What Needs Migration](#pvc-discovery)
3. [PVC Mapping Strategies](#pvc-mapping)
4. [Complete Migration Flow](#complete-flow)
5. [Integration Opportunities](#integration)
6. [Example Scenarios](#examples)
7. [Recommendations](#recommendations)

---

<a name="current-state"></a>
## 1. Current State: How crane Handles PVCs

### What crane export Does

```bash
crane export --context source-cluster --namespace myapp
```

**Output:** `myapp/` directory containing:
- `persistentvolumeclaim_*.yaml` - PVC definitions (WITHOUT data)
- `deployment_*.yaml` - Deployment manifests referencing PVCs
- `statefulset_*.yaml` - StatefulSet manifests with volumeClaimTemplates
- Other resources (Services, ConfigMaps, etc.)

**IMPORTANT:** `crane export` captures PVC **metadata** only - no data transfer happens!

### What crane transform Does

```bash
crane transform --export-dir myapp/ --transform strip-ns
```

**Output:** Modified YAML files with transformations applied (e.g., remove namespaces, change storage classes)

**Relevant transforms for PVCs:**
- `strip-ns` - Remove namespace references
- `storage-class-mapping` - NOT YET IMPLEMENTED (see Extension feature B2.3)

### What crane apply Does

```bash
crane apply --export-dir myapp/ --context target-cluster
```

**Output:** Creates resources in target cluster, including empty PVCs

**CRITICAL GAP:** PVCs are created empty - data is NOT transferred!

### Where transfer-pvc Fits

```bash
crane transfer-pvc --source-context source-cluster \
  --destination-context target-cluster \
  --pvc-name myapp-data \
  --pvc-namespace myapp
```

**Purpose:** Transfer data from source PVC → target PVC **after both exist**

**Current Limitation:** Completely manual - user must:
1. Know which PVCs need transfer
2. Ensure target PVCs exist first
3. Run `transfer-pvc` for each PVC individually
4. Ensure workloads don't start until transfer completes

---

<a name="pvc-discovery"></a>
## 2. PVC Discovery: Finding What Needs Migration

### Strategy 1: Analyze Exported YAML

After `crane export`, inspect `persistentvolumeclaim_*.yaml` files:

```bash
# List all exported PVCs
ls myapp/persistentvolumeclaim_*.yaml

# Example output:
# myapp/persistentvolumeclaim_postgres-data.yaml
# myapp/persistentvolumeclaim_redis-cache.yaml
```

**Manual check:**
```bash
# See PVC details
cat myapp/persistentvolumeclaim_postgres-data.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: myapp
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: gp2
```

**What to note:**
- `metadata.name` - PVC name for transfer-pvc
- `spec.resources.requests.storage` - Size (estimate transfer time)
- `spec.storageClassName` - May need mapping in target cluster

### Strategy 2: Use kubectl to Find Active PVCs

```bash
# List PVCs in source namespace
kubectl get pvc -n myapp --context source-cluster

# Output:
# NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
# postgres-data   Bound    pvc-abc123-...                             50Gi       RWO            gp2            30d
# redis-cache     Bound    pvc-def456-...                             10Gi       RWO            gp2            30d
```

**Filter for bound PVCs only:**
```bash
kubectl get pvc -n myapp --context source-cluster \
  --field-selector=status.phase=Bound \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.resources.requests.storage}{"\n"}{end}'

# Output:
# postgres-data   50Gi
# redis-cache     10Gi
```

### Strategy 3: Find PVCs Referenced by Workloads

**For Deployments/StatefulSets:**
```bash
# Find which Deployments use PVCs
kubectl get deployment -n myapp --context source-cluster -o json | \
  jq -r '.items[] | select(.spec.template.spec.volumes[]?.persistentVolumeClaim) | 
    .metadata.name + " uses PVC: " + 
    (.spec.template.spec.volumes[] | select(.persistentVolumeClaim) | .persistentVolumeClaim.claimName)'

# Example output:
# postgres-deployment uses PVC: postgres-data
```

**For StatefulSets (volumeClaimTemplates):**
```bash
kubectl get statefulset -n myapp --context source-cluster -o json | \
  jq -r '.items[] | select(.spec.volumeClaimTemplates) | 
    .metadata.name + " creates PVC pattern: " + 
    (.spec.volumeClaimTemplates[].metadata.name)'

# Example output:
# kafka-cluster creates PVC pattern: data-kafka-cluster-{0..2}
```

**IMPORTANT for StatefulSets:** PVCs follow pattern `{volumeClaimTemplate}-{podName}`:
- Template name: `data`
- StatefulSet name: `kafka-cluster`
- Replicas: 3
- Actual PVCs: `data-kafka-cluster-0`, `data-kafka-cluster-1`, `data-kafka-cluster-2`

### Strategy 4: Estimate Data Size

```bash
# Check actual PVC usage (requires metrics-server or kubelet access)
kubectl exec -n myapp postgres-deployment-xyz -- df -h /var/lib/postgresql/data

# Output:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/xvdf       50G   35G   15G  70%  /var/lib/postgresql/data
```

**Use this to:**
- Estimate transfer time (35GB actual vs 50GB capacity)
- Decide if full copy or incremental sync is needed
- Plan maintenance window

---

<a name="pvc-mapping"></a>
## 3. PVC Mapping Strategies

### Scenario 1: Same Names (Simplest)

**Source PVC:** `postgres-data` in namespace `myapp`  
**Target PVC:** `postgres-data` in namespace `myapp`

**No mapping needed** - names match 1:1

```bash
crane transfer-pvc \
  --source-context source-cluster \
  --destination-context target-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp
```

### Scenario 2: Different Namespace

**Source PVC:** `postgres-data` in namespace `myapp-prod`  
**Target PVC:** `postgres-data` in namespace `myapp`

**Current limitation:** `crane transfer-pvc` uses SAME namespace for both clusters!

**Workaround 1: Temporary namespace**
```bash
# Create temp namespace in source cluster
kubectl create namespace myapp --context source-cluster

# Clone PVC to temp namespace (requires snapshot support)
kubectl get pvc postgres-data -n myapp-prod --context source-cluster -o yaml | \
  sed 's/namespace: myapp-prod/namespace: myapp/' | \
  kubectl apply --context source-cluster -f -

# Transfer from temp namespace
crane transfer-pvc --source-context source-cluster \
  --destination-context target-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp

# Cleanup temp namespace
kubectl delete namespace myapp --context source-cluster
```

**Workaround 2: Use different contexts with namespace override**
```bash
# Create contexts with namespace embedded
kubectl config set-context source-myapp-prod \
  --cluster source-cluster \
  --namespace myapp-prod \
  --user source-user

kubectl config set-context target-myapp \
  --cluster target-cluster \
  --namespace myapp \
  --user target-user
```

**RECOMMENDATION:** Add `--source-namespace` and `--destination-namespace` flags (Extension feature B2.3)

### Scenario 3: StorageClass Mapping

**Source PVC:** Uses `storageClassName: gp2` (AWS EBS)  
**Target PVC:** Needs `storageClassName: standard-rwo` (GCP PD)

**Current limitation:** transfer-pvc doesn't modify StorageClass - target PVC must already exist with correct class

**Manual workflow:**
```bash
# 1. Export source PVC
kubectl get pvc postgres-data -n myapp --context source-cluster -o yaml > pvc-source.yaml

# 2. Edit for target cluster
cat pvc-source.yaml | \
  sed 's/storageClassName: gp2/storageClassName: standard-rwo/' | \
  sed '/uid:/d' | sed '/resourceVersion:/d' | \
  kubectl apply --context target-cluster -f -

# 3. Transfer data
crane transfer-pvc --source-context source-cluster \
  --destination-context target-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp
```

**Alternative: crane transform with storage class mapping** (Extension feature B2.3):
```bash
crane transform --export-dir myapp/ \
  --storage-class-mapping gp2=standard-rwo
```

### Scenario 4: StatefulSet PVC Renaming

**Source StatefulSet:** `kafka-cluster` with 3 replicas  
**Source PVCs:** `data-kafka-cluster-0`, `data-kafka-cluster-1`, `data-kafka-cluster-2`

**Target StatefulSet:** Renamed to `kafka` with 3 replicas  
**Target PVCs:** `data-kafka-0`, `data-kafka-1`, `data-kafka-2`

**Manual mapping required:**
```bash
# Transfer each PVC individually with explicit mapping
for i in 0 1 2; do
  # Create target PVC first (from modified template)
  kubectl get pvc data-kafka-cluster-$i -n myapp --context source-cluster -o yaml | \
    sed "s/data-kafka-cluster-$i/data-kafka-$i/" | \
    sed '/uid:/d' | sed '/resourceVersion:/d' | \
    kubectl apply --context target-cluster -f -
  
  # Transfer data (PROBLEM: transfer-pvc expects same names!)
  # This won't work without --source-pvc-name and --destination-pvc-name flags
done
```

**CRITICAL LIMITATION:** `crane transfer-pvc` assumes source and target PVC names are IDENTICAL

**RECOMMENDATION:** Add flags for explicit mapping (Extension feature B2.3):
```bash
crane transfer-pvc \
  --source-context source-cluster \
  --source-pvc-name data-kafka-cluster-0 \
  --source-namespace myapp \
  --destination-context target-cluster \
  --destination-pvc-name data-kafka-0 \
  --destination-namespace myapp
```

---

<a name="complete-flow"></a>
## 4. Complete Migration Flow

### Flow 1: Stateless-First Migration (Recommended)

**Use case:** Migrate stateless components first, then stateful workloads during maintenance window

#### Phase 1: Export Everything

```bash
# Export all resources from source cluster
crane export \
  --context source-cluster \
  --namespace myapp \
  --export-dir myapp-export/

# Verify PVCs were captured
ls myapp-export/persistentvolumeclaim_*.yaml
```

#### Phase 2: Identify Stateful vs Stateless

```bash
# List PVCs
kubectl get pvc -n myapp --context source-cluster

# Identify which workloads use PVCs
kubectl get deploy,sts -n myapp --context source-cluster -o json | \
  jq -r '.items[] | select(
    (.spec.template.spec.volumes[]?.persistentVolumeClaim) or 
    (.spec.volumeClaimTemplates)
  ) | .kind + "/" + .metadata.name'

# Example output:
# Deployment/postgres
# StatefulSet/kafka-cluster
```

#### Phase 3: Split Exports

```bash
# Create separate directories
mkdir myapp-stateless/ myapp-stateful/

# Move stateless workloads (no PVCs)
mv myapp-export/deployment_frontend.yaml myapp-stateless/
mv myapp-export/deployment_api.yaml myapp-stateless/

# Move stateful workloads + their PVCs
mv myapp-export/deployment_postgres.yaml myapp-stateful/
mv myapp-export/persistentvolumeclaim_postgres-data.yaml myapp-stateful/
mv myapp-export/statefulset_kafka-cluster.yaml myapp-stateful/
mv myapp-export/persistentvolumeclaim_data-kafka-*.yaml myapp-stateful/

# Move shared resources (Services, ConfigMaps) to stateless
mv myapp-export/*.yaml myapp-stateless/
```

#### Phase 4: Migrate Stateless Workloads (Zero Downtime)

```bash
# Transform stateless exports
crane transform --export-dir myapp-stateless/ --transform strip-ns

# Apply to target cluster
crane apply --export-dir myapp-stateless/ --context target-cluster

# Verify workloads started
kubectl get pods -n myapp --context target-cluster

# Update DNS/Load Balancer to point to target cluster
# (application-specific - not crane's responsibility)
```

#### Phase 5: Prepare Stateful Migration (During Maintenance)

```bash
# Scale down stateful workloads in SOURCE cluster
kubectl scale deployment postgres --replicas=0 -n myapp --context source-cluster
kubectl scale statefulset kafka-cluster --replicas=0 -n myapp --context source-cluster

# Verify pods are terminated
kubectl get pods -n myapp --context source-cluster
```

#### Phase 6: Create Target PVCs

```bash
# Transform stateful exports (apply storage class mapping if needed)
crane transform --export-dir myapp-stateful/ --transform strip-ns

# Apply ONLY PVCs first (not workloads yet!)
kubectl apply -f myapp-stateful/persistentvolumeclaim_*.yaml --context target-cluster

# Verify PVCs are Bound (or Pending if dynamic provisioning)
kubectl get pvc -n myapp --context target-cluster
```

#### Phase 7: Transfer PVC Data

```bash
# Transfer each PVC (example: postgres-data)
crane transfer-pvc \
  --source-context source-cluster \
  --destination-context target-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp

# For StatefulSet PVCs, loop through replicas
for i in 0 1 2; do
  crane transfer-pvc \
    --source-context source-cluster \
    --destination-context target-cluster \
    --pvc-name data-kafka-cluster-$i \
    --pvc-namespace myapp
done
```

**Monitor progress:**
```bash
# Watch crane output for progress percentage
# Look for lines like: "25% (5.2GB/20GB) transferred"
```

#### Phase 8: Start Target Workloads

```bash
# Apply stateful workloads (Deployments, StatefulSets)
kubectl apply -f myapp-stateful/deployment_*.yaml --context target-cluster
kubectl apply -f myapp-stateful/statefulset_*.yaml --context target-cluster

# Verify pods start and mount PVCs
kubectl get pods -n myapp --context target-cluster -w

# Verify data integrity
kubectl exec -n myapp postgres-xyz --context target-cluster -- psql -c '\dt'
```

#### Phase 9: Cutover and Cleanup

```bash
# Update DNS/LB to point to target cluster
# (application-specific)

# Verify target cluster is serving traffic
# (application-specific)

# Delete source cluster resources (ONLY after confirming target works!)
kubectl delete namespace myapp --context source-cluster
```

**Total downtime:** Time for Phase 5 + Phase 7 + Phase 8 (typically 30 min - 4 hours depending on data size)

---

### Flow 2: Incremental Sync Migration (Minimal Downtime)

**Use case:** Large PVCs (100GB+) where downtime must be minimized

**Requires:** Extension feature B1.2 (incremental sync) - NOT YET IMPLEMENTED

#### Phase 1-6: Same as Flow 1

#### Phase 7a: Initial Sync (While Source is Running)

```bash
# Perform initial sync while source workload is still running
crane transfer-pvc \
  --source-context source-cluster \
  --destination-context target-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp \
  --incremental  # NOT YET IMPLEMENTED

# This copies bulk of data (e.g., 90GB out of 100GB)
# Time: 3-4 hours (but source is still serving traffic!)
```

#### Phase 7b: Scale Down and Final Sync

```bash
# Scale down source workload
kubectl scale deployment postgres --replicas=0 -n myapp --context source-cluster

# Perform final incremental sync (only changed data)
crane transfer-pvc \
  --source-context source-cluster \
  --destination-context target-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp \
  --incremental  # NOT YET IMPLEMENTED

# This copies only delta (e.g., 10GB)
# Time: 20-30 minutes
```

#### Phase 8-9: Same as Flow 1

**Total downtime:** Phase 7b + Phase 8 only (20-40 minutes instead of 4+ hours)

---

### Flow 3: Live Migration with Quiescence (Future)

**Use case:** Database migrations with application-level quiescence

**Requires:** Extension feature B3.3 (quiescence gate) - NOT YET IMPLEMENTED

```bash
# Start transfer with quiescence gate
crane transfer-pvc \
  --source-context source-cluster \
  --destination-context target-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp \
  --quiesce-endpoint http://postgres-svc:5432/quiesce \  # NOT YET IMPLEMENTED
  --quiesce-timeout 60s

# crane will:
# 1. Perform initial sync while DB is live
# 2. Call quiesce endpoint (DB stops writes, flushes buffers)
# 3. Perform final sync of deltas
# 4. Resume DB (or user starts target workload)
```

**Benefit:** Application controls quiescence, ensuring data consistency

---

<a name="integration"></a>
## 5. Integration Opportunities

### Current Gap: transfer-pvc is Separate

**Today's reality:**
```
crane export → crane transform → crane apply
                                     ↓
                        (PVCs created empty)
                                     ↓
                       (USER MUST MANUALLY RUN)
                                     ↓
                            crane transfer-pvc
                                     ↓
                       (USER MUST MANUALLY START WORKLOADS)
```

**Problems:**
1. No automated orchestration
2. User must track which PVCs need transfer
3. Easy to forget PVCs or start workloads too early
4. No atomic migration

### Integration Option 1: Kubernetes Job Orchestration

**Concept:** Run crane as a Kubernetes Job in target cluster to orchestrate migration

```bash
# Create a migration script that orchestrates the flow
cat > migration-script.sh <<'EOF'
#!/bin/bash
set -euo pipefail

# Phase 1: Apply stateless workloads first
echo "==> Applying stateless workloads..."
crane apply --export-dir /workspace/stateless/ --context in-cluster

# Phase 2: Create PVCs in target cluster
echo "==> Creating target PVCs..."
kubectl apply -f /workspace/stateful/persistentvolumeclaim_*.yaml

# Phase 3: Wait for PVCs to be Bound
echo "==> Waiting for PVCs to be Bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound \
  pvc/postgres-data pvc/data-kafka-cluster-0 \
  -n myapp --timeout=5m

# Phase 4: Transfer PVC data
echo "==> Transferring PVCs..."
crane transfer-pvc \
  --source-context /workspace/source-kubeconfig \
  --destination-context in-cluster \
  --pvc-name postgres-data \
  --pvc-namespace myapp

crane transfer-pvc \
  --source-context /workspace/source-kubeconfig \
  --destination-context in-cluster \
  --pvc-name data-kafka-cluster-0 \
  --pvc-namespace myapp

# Phase 5: Apply stateful workloads
echo "==> Applying stateful workloads..."
crane apply --export-dir /workspace/stateful/ --context in-cluster

echo "==> Migration complete!"
EOF

# Create ConfigMap with migration assets
kubectl create configmap migration-assets \
  --from-file=stateless=/path/to/myapp-stateless/ \
  --from-file=stateful=/path/to/myapp-stateful/ \
  --from-file=migration-script.sh=migration-script.sh \
  -n crane-migrations

# Create Secret with source kubeconfig
kubectl create secret generic source-kubeconfig \
  --from-file=kubeconfig=/path/to/source-kubeconfig.yaml \
  -n crane-migrations

# Create Job to run migration
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: myapp-migration
  namespace: crane-migrations
spec:
  backoffLimit: 2
  template:
    spec:
      serviceAccountName: crane-migration-sa
      restartPolicy: OnFailure
      containers:
      - name: crane
        image: quay.io/konveyor/crane:latest
        command: ["/bin/bash", "/workspace/migration-script.sh"]
        volumeMounts:
        - name: migration-assets
          mountPath: /workspace
        - name: source-kubeconfig
          mountPath: /workspace/source-kubeconfig
          subPath: kubeconfig
      volumes:
      - name: migration-assets
        configMap:
          name: migration-assets
      - name: source-kubeconfig
        secret:
          secretName: source-kubeconfig
EOF

# Monitor migration progress
kubectl logs -f job/myapp-migration -n crane-migrations
```

**Benefits:**
- No new CRDs or APIs needed
- Uses standard Kubernetes Job
- Runs in-cluster (reliable, no network issues)
- Automated orchestration via shell script
- Easy to customize per migration

**Challenges:**
- Requires RBAC setup (ServiceAccount, Role)
- Script must handle errors manually
- Not resumable (if Job fails, must restart from beginning)

#### Variant: Tekton Pipeline

**For teams already using Tekton:**

```yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: crane-stateful-migration
  namespace: crane-migrations
spec:
  params:
    - name: namespace
      description: Target namespace for migration
    - name: source-kubeconfig-secret
      description: Secret containing source cluster kubeconfig
  workspaces:
    - name: migration-assets
      description: Workspace containing crane export files
  tasks:
    - name: apply-stateless
      taskRef:
        name: crane-apply
      params:
        - name: export-dir
          value: "$(workspaces.migration-assets.path)/stateless"
        - name: context
          value: "in-cluster"
      workspaces:
        - name: source
          workspace: migration-assets
    
    - name: create-pvcs
      runAfter: [apply-stateless]
      taskRef:
        name: kubectl-apply
      params:
        - name: files
          value: "$(workspaces.migration-assets.path)/stateful/persistentvolumeclaim_*.yaml"
      workspaces:
        - name: source
          workspace: migration-assets
    
    - name: wait-pvcs-bound
      runAfter: [create-pvcs]
      taskRef:
        name: kubectl-wait
      params:
        - name: resource
          value: "pvc/postgres-data"
        - name: condition
          value: "jsonpath='{.status.phase}'=Bound"
        - name: timeout
          value: "5m"
    
    - name: transfer-postgres-pvc
      runAfter: [wait-pvcs-bound]
      taskRef:
        name: crane-transfer-pvc
      params:
        - name: pvc-name
          value: "postgres-data"
        - name: pvc-namespace
          value: "$(params.namespace)"
        - name: source-kubeconfig-secret
          value: "$(params.source-kubeconfig-secret)"
      workspaces:
        - name: source
          workspace: migration-assets
    
    - name: apply-stateful-workloads
      runAfter: [transfer-postgres-pvc]
      taskRef:
        name: crane-apply
      params:
        - name: export-dir
          value: "$(workspaces.migration-assets.path)/stateful"
        - name: context
          value: "in-cluster"
      workspaces:
        - name: source
          workspace: migration-assets

---
# Reusable Tekton Task for crane transfer-pvc
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: crane-transfer-pvc
  namespace: crane-migrations
spec:
  params:
    - name: pvc-name
    - name: pvc-namespace
    - name: source-kubeconfig-secret
  workspaces:
    - name: source
  steps:
    - name: transfer
      image: quay.io/konveyor/crane:latest
      script: |
        #!/bin/bash
        set -euo pipefail
        
        # Mount source kubeconfig
        export KUBECONFIG_SOURCE=/workspace/source-kubeconfig/kubeconfig
        
        echo "Transferring PVC $(params.pvc-name) in namespace $(params.pvc-namespace)..."
        
        crane transfer-pvc \
          --source-context source \
          --destination-context in-cluster \
          --pvc-name "$(params.pvc-name)" \
          --pvc-namespace "$(params.pvc-namespace)"
        
        echo "Transfer complete!"
      volumeMounts:
        - name: source-kubeconfig
          mountPath: /workspace/source-kubeconfig
  volumes:
    - name: source-kubeconfig
      secret:
        secretName: $(params.source-kubeconfig-secret)

---
# Run the pipeline
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: myapp-migration-run
  namespace: crane-migrations
spec:
  pipelineRef:
    name: crane-stateful-migration
  params:
    - name: namespace
      value: myapp
    - name: source-kubeconfig-secret
      value: source-kubeconfig
  workspaces:
    - name: migration-assets
      configMap:
        name: migration-assets
```

**Run and monitor:**
```bash
# Watch pipeline progress
tkn pipelinerun logs myapp-migration-run -f -n crane-migrations

# Check task status
tkn pipelinerun describe myapp-migration-run -n crane-migrations
```

**Benefits over plain Job:**
- Task-level retries (individual tasks can fail and retry)
- Better visibility (Tekton Dashboard shows per-task status)
- Reusable tasks (crane-transfer-pvc task can be used in multiple pipelines)
- Conditional execution (when expressions for skipping tasks)
- Parallel execution (multiple PVCs can transfer in parallel)

**Challenges:**
- Requires Tekton installed in cluster
- More complex YAML than plain Job

### Integration Option 2: crane transfer-pvc --batch

**Concept:** Transfer multiple PVCs in one command

```bash
# Auto-discover PVCs from export directory
crane transfer-pvc batch \
  --source-context source-cluster \
  --destination-context target-cluster \
  --export-dir myapp-export/ \
  --namespace myapp

# crane reads persistentvolumeclaim_*.yaml files and transfers all PVCs
```

**Implementation:**
```go
func (t *TransferPVCCommand) RunBatch() error {
    // Read all PVC YAML files from export-dir
    pvcs := parseExportedPVCs(t.ExportDir)
    
    // Transfer each PVC
    for _, pvc := range pvcs {
        log.Infof("Transferring PVC %s/%s...", pvc.Namespace, pvc.Name)
        err := t.transferSinglePVC(pvc.Name, pvc.Namespace)
        if err != nil {
            return fmt.Errorf("failed to transfer %s: %w", pvc.Name, err)
        }
    }
    
    return nil
}
```

**Benefits:**
- Simpler than migration plan
- Reuses existing transfer-pvc logic
- Easy to add to crane CLI

**Challenges:**
- No dependency management (user must ensure PVCs exist in target)
- No StatefulSet handling (PVC names don't appear in export YAMLs)

### Integration Option 3: Post-Apply Hook

**Concept:** crane apply triggers transfer-pvc automatically

```bash
# crane apply with auto-transfer flag
crane apply \
  --export-dir myapp-export/ \
  --context target-cluster \
  --auto-transfer-pvcs \
  --source-context source-cluster

# crane:
# 1. Applies all resources (including PVCs)
# 2. Waits for PVCs to be Bound
# 3. Automatically runs transfer-pvc for each PVC
# 4. Waits for transfers to complete
# 5. Exits (user manually starts workloads if scaled down)
```

**Benefits:**
- No new APIs
- Works with existing export/transform/apply flow
- Optional (--auto-transfer-pvcs flag)

**Challenges:**
- Assumes target PVCs should have same names
- No way to skip specific PVCs
- Hard to resume if partial failure

---

<a name="examples"></a>
## 6. Example Scenarios

### Example 1: Simple PostgreSQL Migration

**Source:**
- Namespace: `prod`
- Deployment: `postgres`
- PVC: `postgres-data` (50GB, storageClass `gp2`)

**Target:**
- Namespace: `prod`
- StorageClass: `standard-rwo` (GCP)

**Steps:**

```bash
# 1. Export
crane export --context source --namespace prod --export-dir prod-export/

# 2. Transform (change storage class)
cd prod-export/
sed -i 's/storageClassName: gp2/storageClassName: standard-rwo/' persistentvolumeclaim_postgres-data.yaml

# 3. Scale down source
kubectl scale deployment postgres --replicas=0 -n prod --context source

# 4. Create target PVC only
kubectl apply -f prod-export/persistentvolumeclaim_postgres-data.yaml --context target

# 5. Wait for PVC to be Bound
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/postgres-data -n prod --context target --timeout=5m

# 6. Transfer data
crane transfer-pvc \
  --source-context source \
  --destination-context target \
  --pvc-name postgres-data \
  --pvc-namespace prod

# 7. Start target deployment
kubectl apply -f prod-export/deployment_postgres.yaml --context target

# 8. Verify
kubectl exec -n prod $(kubectl get pod -n prod -l app=postgres -o name --context target) --context target -- \
  psql -U postgres -c 'SELECT count(*) FROM users;'
```

**Downtime:** Step 3 through step 7 (data transfer time + pod startup ~30min for 50GB)

---

### Example 2: StatefulSet with 3 Replicas

**Source:**
- Namespace: `kafka`
- StatefulSet: `kafka-cluster` (3 replicas)
- PVCs: `data-kafka-cluster-0`, `data-kafka-cluster-1`, `data-kafka-cluster-2` (100GB each)

**Target:**
- Namespace: `kafka`
- Same StorageClass

**Steps:**

```bash
# 1. Export
crane export --context source --namespace kafka --export-dir kafka-export/

# 2. Scale down source StatefulSet
kubectl scale statefulset kafka-cluster --replicas=0 -n kafka --context source

# 3. Create target PVCs
kubectl apply -f kafka-export/persistentvolumeclaim_data-kafka-cluster-*.yaml --context target

# 4. Transfer all PVCs in parallel (using background jobs)
for i in 0 1 2; do
  crane transfer-pvc \
    --source-context source \
    --destination-context target \
    --pvc-name data-kafka-cluster-$i \
    --pvc-namespace kafka &
done

# Wait for all transfers to complete
wait

# 5. Start target StatefulSet
kubectl apply -f kafka-export/statefulset_kafka-cluster.yaml --context target

# 6. Verify all pods started and data is intact
kubectl get pods -n kafka --context target
kubectl exec -n kafka kafka-cluster-0 --context target -- ls -lh /var/lib/kafka/data
```

**Optimization:** Transfers run in parallel (3x faster than sequential)

---

### Example 3: Cross-Cloud Migration (AWS → GCP)

**Source:**
- AWS EKS cluster
- StorageClass: `gp2` (EBS)
- PVC: `app-data` (200GB)

**Target:**
- GCP GKE cluster
- StorageClass: `standard-rwo` (Persistent Disk)

**Challenges:**
- Different storage classes
- Large PVC (4+ hours transfer)
- Need minimal downtime

**Steps (using incremental sync - future feature):**

```bash
# 1. Export
crane export --context aws-eks --namespace myapp --export-dir myapp-export/

# 2. Transform storage class
sed -i 's/storageClassName: gp2/storageClassName: standard-rwo/' \
  myapp-export/persistentvolumeclaim_app-data.yaml

# 3. Create target PVC
kubectl apply -f myapp-export/persistentvolumeclaim_app-data.yaml --context gcp-gke

# 4. Initial sync (while source is still running)
crane transfer-pvc \
  --source-context aws-eks \
  --destination-context gcp-gke \
  --pvc-name app-data \
  --pvc-namespace myapp \
  --incremental  # NOT YET IMPLEMENTED
# Transfer 180GB (90%) in 3 hours - source still serving traffic!

# 5. Scale down source
kubectl scale deployment myapp --replicas=0 -n myapp --context aws-eks

# 6. Final incremental sync
crane transfer-pvc \
  --source-context aws-eks \
  --destination-context gcp-gke \
  --pvc-name app-data \
  --pvc-namespace myapp \
  --incremental  # NOT YET IMPLEMENTED
# Transfer remaining 20GB in 30 minutes

# 7. Start target deployment
kubectl apply -f myapp-export/deployment_myapp.yaml --context gcp-gke

# 8. Update DNS to point to GCP load balancer
# (application-specific)
```

**Downtime:** 30 minutes (step 5-7) instead of 4+ hours

---

<a name="recommendations"></a>
## 7. Recommendations

### Immediate Improvements (No New Features)

**1. Document the Complete Flow**
- Add this guide to official crane docs
- Include kubectl commands for each step
- Provide example scripts for common scenarios

**2. Add Validation Commands**
```bash
# crane validate-migration - check if migration is ready
crane validate-migration --export-dir myapp-export/ --context target-cluster

# Checks:
# - Do all target PVCs exist?
# - Are target PVCs Bound?
# - Do source PVCs match target PVCs (size, access mode)?
# - Are source workloads scaled down?
```

**3. Add Discovery Helper**
```bash
# crane pvc list - show all PVCs needing transfer
crane pvc list --export-dir myapp-export/

# Output:
# PVC NAME              SIZE    STORAGECLASS    USED BY
# postgres-data         50Gi    gp2             deployment/postgres
# data-kafka-cluster-0  100Gi   gp2             statefulset/kafka-cluster
# data-kafka-cluster-1  100Gi   gp2             statefulset/kafka-cluster
# data-kafka-cluster-2  100Gi   gp2             statefulset/kafka-cluster
```

### Medium-Term Enhancements

**1. Implement Extension Features**
- B1.2: Incremental sync (minimize downtime)
- B2.3: StorageClass mapping + namespace mapping
- B3.3: Quiescence gate (database-safe migrations)

**2. Add Batch Transfer**
```bash
crane transfer-pvc batch --export-dir myapp-export/ \
  --source-context source \
  --destination-context target
```

**3. Provide Migration Script Templates**
```bash
# crane export generates migration script template
crane export --context source --namespace myapp \
  --with-migration-script

# Creates: migration-script.sh with all necessary steps
# Users can customize and run as Job or Tekton Task
```

### Long-Term Vision

**1. Kubernetes-Native Orchestration**

Run complete migration as Kubernetes Job or Tekton Pipeline (see Integration Option 1):

```bash
# Generate Job manifest with migration orchestration
crane generate migration-job \
  --export-dir myapp-export/ \
  --source-context source \
  --target-context target \
  --output migration-job.yaml

# Apply and run
kubectl apply -f migration-job.yaml
kubectl logs -f job/myapp-migration -n crane-migrations
```

**Benefits:**
- No new CRDs or operators
- Leverage existing Kubernetes primitives
- Works with any CI/CD system
- Easy to customize per migration

**2. GitOps Integration**

Use crane in ArgoCD PreSync hooks or Tekton Tasks:

```yaml
# ArgoCD Application with PreSync hook
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
spec:
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
    hooks:
      - name: transfer-pvcs
        type: PreSync
        hook:
          exec:
            command:
              - /bin/bash
              - -c
              - |
                # Source kubeconfig from secret
                crane transfer-pvc batch \
                  --export-dir /manifests/pvcs/ \
                  --source-context source \
                  --destination-context in-cluster
```

**3. CI/CD Pipeline Integration**

Example with Tekton (reusing tasks from Integration Option 1):

```yaml
# Reuse crane-transfer-pvc Task in any Tekton Pipeline
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: app-deployment-with-data
spec:
  tasks:
    - name: transfer-data
      taskRef:
        name: crane-transfer-pvc  # Reusable task
      params:
        - name: pvc-name
          value: postgres-data
    - name: deploy-app
      runAfter: [transfer-data]
      taskRef:
        name: kubectl-apply
```

**4. Incremental Migration Workflows**

Once Extension features are implemented:

```bash
# Initial sync (source still running)
crane transfer-pvc \
  --source-context source \
  --destination-context target \
  --pvc-name postgres-data \
  --pvc-namespace myapp \
  --incremental \
  --initial-sync

# Schedule periodic sync via CronJob
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-incremental-sync
spec:
  schedule: "*/30 * * * *"  # Every 30 minutes
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: crane-sa
          containers:
          - name: crane
            image: quay.io/konveyor/crane:latest
            command:
              - crane
              - transfer-pvc
              - --source-context=source
              - --destination-context=in-cluster
              - --pvc-name=postgres-data
              - --pvc-namespace=myapp
              - --incremental
          restartPolicy: OnFailure
EOF

# Final cutover sync (source scaled down)
kubectl scale deployment postgres --replicas=0 -n myapp --context source
crane transfer-pvc --incremental --final-sync
kubectl apply -f postgres-deployment.yaml --context target
```

---

## Summary

**Current State:**
- `crane transfer-pvc` is a **manual, standalone utility**
- Users must orchestrate PVC discovery, creation, transfer, and workload startup
- No integration with `crane export/transform/apply`

**Complete Flow Requires:**
1. Export resources with `crane export`
2. Identify PVCs manually (via exported YAML or kubectl)
3. Scale down source workloads (kubectl)
4. Create target PVCs (kubectl or crane apply)
5. Transfer data (crane transfer-pvc, one per PVC)
6. Start target workloads (kubectl)
7. Verify and cutover

**Key Gaps:**
- No automated PVC discovery
- No batch transfer
- No incremental sync (full copy only)
- No orchestration (user must track state)
- No validation (easy to start workloads before transfer completes)

**Recommended Next Steps:**
1. Document complete flow (this document)
2. Add `crane pvc list` discovery helper
3. Add `crane validate-migration` checker
4. Add `crane generate migration-job` for Kubernetes Job generation
5. Implement Extension features (B1.2, B2.3, B3.3)
6. Add `crane transfer-pvc batch`
7. Provide Tekton Task examples for pipeline integration

**For users TODAY:**
- Follow Flow 1 (Stateless-First Migration) for simplest path
- Use provided kubectl commands to orchestrate manually
- Estimate downtime based on PVC sizes
- Test migration in staging first!

---

**Document Version:** 1.0  
**Last Updated:** 2026-06-30  
**Related Documents:**
- [VERIFICATION_REPORT.md](VERIFICATION_REPORT.md) - Feature verification
- [TRANSFER_PVC_RECOMMENDATIONS.md](TRANSFER_PVC_RECOMMENDATIONS.md) - Code improvements
- [SIMPLE_JOB_PROPOSAL.md](SIMPLE_JOB_PROPOSAL.md) - In-cluster execution
- [README.md](README.md) - Implementation roadmap
