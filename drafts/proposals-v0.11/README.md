# Crane v0.11 Proposals

**Date:** 2026-07-02  
**Status:** Proposals for crane v0.11 release  
**Focus:** `crane transfer-pvc` improvements and new features

---

## Overview

This directory contains three proposals for improving `crane transfer-pvc` in the v0.11 release:

1. **Priority Fixes** - Critical bug fixes and quick wins
2. **In-Cluster Execution** - Run transfer-pvc as Kubernetes Job
3. **PVC Discovery** - Automatic PVC discovery from export artifacts

---

## Proposals

| Proposal | Type | Effort | Description |
|----------|------|--------|-------------|
| **[TRANSFER_PVC_FIXES_PLAN.md](TRANSFER_PVC_FIXES_PLAN.md)** | 🔧 Fixes | 2.5 weeks | 12 priority fixes and improvements<br>No major rewrites<br>100% backward compatible |
| **[IN_CLUSTER_EXECUTION_PROPOSAL.md](IN_CLUSTER_EXECUTION_PROPOSAL.md)** | 🚀 Feature | TBD | Run transfer-pvc as Kubernetes Job<br>Reliability + automatic cleanup<br>GitOps integration |
| **[PVC_EXPLORE_PROPOSAL.md](PVC_EXPLORE_PROPOSAL.md)** | 🔍 Feature | TBD | Auto-discover PVCs from export<br>`crane transfer-pvc explore`<br>Multiple output formats |

---

## Priority: TRANSFER_PVC_FIXES_PLAN.md

### Recommended Implementation Order

**P0 - Critical (2-3 days):**
1. ⚠️ Replace 17x `log.Fatal` with proper error handling + cleanup
2. 🚀 Add bandwidth limiting (30 min quick win)
3. ⚡ Add rsync optimization flags (compression, partial resume)

**P1 - High Priority (1 week):**
4. Retry logic with exponential backoff
5. Pre-transfer validation
6. Improved progress reporting
7. Permission preservation options
8. Dry-run mode

**P2 - Medium Priority (3-4 days):**
9. Incremental sync support
10. Transfer statistics report
11. Verification mode
12. Auto-detect permissions from source Pod

### Quick Wins

- **Bandwidth limiting:** 30 minutes implementation
- **Rsync optimization:** 1 day (significant performance impact)
- **Error handling:** 2 days (prevents resource leaks)

---

## Feature: IN_CLUSTER_EXECUTION_PROPOSAL.md

### Key Benefits

**Why run transfer-pvc as Kubernetes Job?**

| Benefit | Description |
|---------|-------------|
| **Reliability** | Survives laptop/VPN disconnects |
| **Automatic Cleanup** | No orphaned resources on failure (trap EXIT) |
| **Security** | ServiceAccount (RBAC) instead of user kubeconfig |
| **GitOps** | Declarative Job manifests in Git |
| **Observability** | kubectl logs, Prometheus integration |

**Note:** Data transfer performance is identical (data flows cluster-to-cluster in both modes). Control plane operations are slightly faster (~5 min savings on multi-hour transfers).

### Use Cases

1. **Large Production Migrations** - 2TB database during maintenance window (no human supervision needed)
2. **Multi-Tenant Platforms** - 500 customers, parallel Jobs
3. **GitOps Workflows** - Job manifest in Git, PR approval, Argo CD execution

### Implementation

Uses native Kubernetes Jobs - **no operator required**.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: crane-transfer-postgres
spec:
  template:
    spec:
      serviceAccountName: crane-transfer
      containers:
      - name: crane
        image: quay.io/konveyor/crane:latest
        command:
        - /bin/bash
        - -c
        - |
          # Cleanup on ANY exit
          cleanup() {
            kubectl delete pods,secrets -l transfer-id=${ID} || true
          }
          trap cleanup EXIT
          
          crane transfer-pvc --pvc-name=postgres-data ...
```

---

## Feature: PVC_EXPLORE_PROPOSAL.md

### Key Benefits

**Automatic PVC discovery from crane export artifacts:**

| Benefit | Description |
|---------|-------------|
| ⏱️ **Save Time** | No manual PVC discovery |
| ✅ **No Missed PVCs** | Finds StatefulSet volumeClaimTemplates |
| 🎯 **Correct Commands** | Generates valid crane transfer-pvc commands |
| 📊 **See Dependencies** | Shows which workloads use which PVCs |
| 🔄 **Reusable** | Instructions file for incremental syncs |
| 👥 **Team Collaboration** | Git commit, PR review |

### Workflow

```bash
# Step 1: Export workloads (existing)
crane export --namespace=myapp --export-dir=myapp/

# Step 2: NEW - Discover PVCs automatically
crane transfer-pvc explore --export-dir=myapp/

# Output: Ready-to-use commands
# ┌─────────────────────────────────────────────────┐
# │ Found 4 PVCs to transfer:                       │
# │                                                 │
# │ 1. postgres-data (50Gi)                        │
# │    crane transfer-pvc \                        │
# │      --pvc-name=postgres-data \                │
# │      --pvc-namespace=myapp ...                 │
# └─────────────────────────────────────────────────┘

# Step 3: Copy-paste and run!
```

### Output Formats

| Format | Use Case | Example |
|--------|----------|---------|
| `text` (default) | Copy-paste to terminal | `crane transfer-pvc ...` |
| `script` | Executable bash script | `./transfer-plan.sh` |
| `instructions` | Editable YAML file (GitOps) | `--instructions-file=pvc.yaml` |
| `json` | Automation/tooling | `jq '.pvcs[] | .name'` |

### Advanced: Target Cluster Validation

```bash
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --target-context=gcp-cluster
```

**Validates:**
- ✅ Target namespace exists
- ✅ Storage classes available in target
- ⚠️ Warns about missing storage classes
- 💡 Suggests compatible mappings (AWS gp2 → GCP standard-rwo)

---

## Implementation Timeline (Tentative)

### Phase 1: Critical Fixes (Weeks 1-2)
- **TRANSFER_PVC_FIXES_PLAN.md** P0 items
- Goal: Production-ready reliability

### Phase 2: PVC Discovery (Weeks 3-4)
- **PVC_EXPLORE_PROPOSAL.md** basic implementation
- Output formats: text, script, instructions

### Phase 3: In-Cluster Execution (Weeks 5-6)
- **IN_CLUSTER_EXECUTION_PROPOSAL.md**
- Job-based execution, no operator

### Phase 4: Polish & Documentation (Week 7)
- E2E tests
- User documentation
- Migration guides

**Total estimated effort:** 7 weeks (2 developers)

---

## Quick Reference

### TRANSFER_PVC_FIXES_PLAN.md

**P0 Critical Fixes:**
```bash
# Example: Remove log.Fatal, add cleanup
func (t *TransferPVCCommand) RunE() error {
    cleanup := &Cleanup{...}
    defer cleanup.Execute()  // Always runs
    
    if err := ...; err != nil {
        return err  // Instead of log.Fatal
    }
}
```

**Quick Win: Bandwidth Limiting**
```bash
crane transfer-pvc \
  --bandwidth-limit=10M \
  --pvc-name=data
```

---

### IN_CLUSTER_EXECUTION_PROPOSAL.md

**Example: Run as Job**
```bash
# Create RBAC + Secret
kubectl apply -f rbac.yaml
kubectl create secret generic source-kubeconfig --from-file=...

# Run Job
kubectl apply -f transfer-job.yaml

# Monitor
kubectl logs -f job/crane-transfer-postgres
```

---

### PVC_EXPLORE_PROPOSAL.md

**Example: Basic Discovery**
```bash
crane transfer-pvc explore --export-dir=myapp/
```

**Example: Generate Script**
```bash
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --format=script \
  --output=transfer.sh

chmod +x transfer.sh
./transfer.sh
```

**Example: With Validation**
```bash
crane transfer-pvc explore \
  --export-dir=myapp/ \
  --target-context=gcp-cluster

# Output includes:
# ✅ Namespace exists
# ⚠️ Storage class gp2 not found
# 💡 Suggest: --dest-storage-class=standard-rwo
```

---

## Decision Matrix

### Which proposal addresses which problem?

| Problem | Solution |
|---------|----------|
| **Resource leaks on failure** | TRANSFER_PVC_FIXES_PLAN (P0.1) |
| **Slow transfers** | TRANSFER_PVC_FIXES_PLAN (P0.3) |
| **No bandwidth control** | TRANSFER_PVC_FIXES_PLAN (P0.2) |
| **Laptop disconnect = fail** | IN_CLUSTER_EXECUTION_PROPOSAL |
| **Manual PVC discovery** | PVC_EXPLORE_PROPOSAL |
| **StatefulSet PVC names** | PVC_EXPLORE_PROPOSAL |
| **Storage class mapping** | PVC_EXPLORE_PROPOSAL (--target-context) |
| **GitOps workflows** | IN_CLUSTER_EXECUTION + PVC_EXPLORE |

---

## Next Steps

1. **Review proposals** with team
2. **Prioritize** based on user feedback
3. **Spike** on PVC_EXPLORE_PROPOSAL (1 week proof-of-concept)
4. **Implement** TRANSFER_PVC_FIXES_PLAN P0 items (quick wins)
5. **Iterate** based on feedback

---

## Questions?

See individual proposal files for detailed design, implementation notes, and examples.

**For discussion:** Create GitHub issues referencing specific proposal sections.
