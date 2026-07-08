# Proposal: In-Cluster Execution for crane transfer-pvc

**Date:** 2026-07-02  
**Status:** Proposal  
**Target Version:** v0.11+  
**Goal:** Enable running `crane transfer-pvc` as a Kubernetes Job/Pod instead of from a local workstation

---

## Executive Summary

This proposal addresses the need to run `crane transfer-pvc` **inside a Kubernetes cluster** (typically the destination cluster) rather than from a developer's laptop or CI/CD runner. This approach provides significant operational, reliability, and security benefits for production data migrations.

**Key Benefits:**
- ✅ **Reliability:** Immune to laptop/VPN disconnects, automatic cleanup on failure
- ✅ **Control Plane Efficiency:** Lower API call latency (in-cluster networking)
- ✅ **Security:** RBAC-controlled execution with ServiceAccounts
- ✅ **Observability:** Standard Kubernetes monitoring and logging
- ✅ **GitOps Integration:** Declarative Job manifests in version control
- ✅ **No Operator Required:** Uses native Kubernetes Jobs, not a custom operator

**Note:** Data transfer performance is identical - data flows directly cluster-to-cluster in both laptop and Job execution modes.

---

## Problem Statement

### Current State: Running from Workstation

Today, `crane transfer-pvc` is designed to run from a user's laptop or CI/CD runner:

```bash
# User runs from laptop
crane transfer-pvc \
  --source-context=prod-cluster \
  --destination-context=new-cluster \
  --pvc-name=postgres-data \
  --pvc-namespace=database
```

**This works, but has significant limitations:**

### 1. **Network Reliability Issues**

| Scenario | Impact |
|----------|--------|
| WiFi disconnect during 4-hour transfer | ❌ Transfer fails, must restart |
| VPN timeout after 30 minutes | ❌ Connection lost, no recovery |
| Laptop sleep/hibernate | ❌ Process killed |
| Network congestion on home internet | ⚠️ Slow, unreliable |

**Real-world example:**
```
User starts transfer of 500GB PVC at 9am
↓
11:30am - VPN disconnects during lunch
↓
Transfer fails after 2.5 hours
↓
Must restart from beginning, loses progress
```

---

### 2. **Reliability: No Automatic Cleanup on Failure**

**Problem:** When `crane transfer-pvc` runs from laptop and fails (crash, VPN disconnect, Ctrl+C), it leaves orphaned resources in both clusters.

**Current behavior:**
```bash
# User runs transfer from laptop
crane transfer-pvc --pvc-name=postgres-data ...

# VPN disconnects at 50% complete
# crane process dies

# LEFT BEHIND in destination cluster:
- rsync server Pod (still running)
- stunnel server Pod (still running)  
- Service for stunnel
- Secrets with TLS certificates
- Route/Ingress endpoint

# LEFT BEHIND in source cluster:
- rsync client Pod (may still be running)
- stunnel client Pod
- Secrets with copied TLS certificates

# User must MANUALLY cleanup:
kubectl --context=dest delete pods,services,secrets,routes -l app.kubernetes.io/name=crane
kubectl --context=source delete pods,secrets -l app.kubernetes.io/name=crane
```

**Why this is problematic:**
- ❌ Resource leaks (Pods consume CPU/memory indefinitely)
- ❌ Port conflicts (re-running transfer may fail if old resources still exist)
- ❌ Security risk (TLS certificates and Pods remain accessible)
- ❌ Manual intervention required (user must know what to cleanup)

**With Kubernetes Job:**
```yaml
apiVersion: batch/v1
kind: Job
spec:
  template:
    spec:
      containers:
      - name: crane
        command:
        - /bin/bash
        - -c
        - |
          # Cleanup function runs on ANY exit (success, failure, kill)
          cleanup() {
            echo "Cleaning up transfer resources..."
            kubectl --context=dest delete pods,services,secrets,routes \
              -l transfer-id=${TRANSFER_ID} || true
            kubectl --context=source delete pods,secrets \
              -l transfer-id=${TRANSFER_ID} || true
          }
          trap cleanup EXIT
          
          # Run transfer
          crane transfer-pvc ...
```

**Benefits:**
- ✅ Automatic cleanup even if Pod crashes
- ✅ Automatic cleanup even if Job is deleted mid-transfer
- ✅ No manual intervention required
- ✅ No resource leaks

---

### 3. **Control Plane Latency (Minor Performance Impact)**

**Important:** Data transfer performance is **identical** - data flows directly cluster-to-cluster in both modes:

```
Laptop execution:
  crane CLI (laptop) → creates Pods → Source rsync Pod ──┐
                                                          │ Data flows
                                                          │ cluster-to-cluster
  crane CLI (laptop) ← monitors logs ← Dest rsync Pod ←──┘ (NOT through laptop!)

In-cluster execution:  
  crane CLI (Job Pod) → creates Pods → Source rsync Pod ──┐
                                                           │ Same data flow!
  crane CLI (Job Pod) ← monitors logs ← Dest rsync Pod ←──┘
```

**However, control plane operations are faster:**

| Operation | Laptop | In-Cluster Job |
|-----------|--------|----------------|
| API calls (create Pod, get logs, etc.) | 50-200ms | 1-5ms |
| Total API calls during 4-hour transfer | ~2,880 (every 5s) | ~2,880 (same) |
| Time spent on API calls | ~5 minutes | ~10 seconds |

**Impact:** Saves a few minutes on multi-hour transfers, not significant for data transfer itself.

---

### 4. **Operational Challenges**

#### 4.1 Long-Running Transfers Require Human Presence

**Problem:** Large PVC transfers (500GB+) take hours, requiring someone to:
- Keep laptop awake and connected
- Monitor progress
- Be available to retry on failure

**This doesn't scale for:**
- Migrations during maintenance windows (2am - 6am)
- Multiple simultaneous PVC transfers
- Transfers across timezones (EU → US clusters)

#### 4.2 Difficult to Integrate with Existing Workflows

**Common enterprise migration workflow:**
1. Gitops repo defines migration plan
2. CI/CD pipeline orchestrates migration steps
3. Automated testing validates migration
4. Automated rollback on failure

**crane transfer-pvc from laptop doesn't fit:**
- Can't be automated in CI/CD (requires interactive kubectl access)
- No declarative definition (can't store in Git)
- No integration with CD tools (Argo CD, Flux, Tekton)

---

### 5. **Security and Compliance Concerns**

#### 5.1 Broad Kubeconfig Access

Running from laptop requires user to have:
- Full kubeconfig for source cluster (often production)
- Full kubeconfig for destination cluster
- Stored on laptop (security risk if stolen/compromised)

**Compliance issues:**
- SOC2: Requires audit trail of who accessed production
- PCI-DSS: Production access must be logged and time-limited
- GDPR: Access to customer data must be traceable

**Current state:**
- ❌ No audit trail (transfer runs with user's credentials)
- ❌ No automatic credential expiration
- ❌ Difficult to trace who initiated transfer

#### 5.2 No RBAC Granularity

**Laptop execution:**
- User needs admin-level access to both clusters
- Can't restrict to specific namespaces
- Can't enforce approval workflows

**Desired state:**
- ✅ ServiceAccount with minimal permissions (only what transfer needs)
- ✅ Namespace-scoped access (can only transfer PVCs in `database` namespace)
- ✅ Approval required before Job runs (via GitOps PR approval)

---

### 6. **Observability Gaps**

#### 6.1 Logs Scattered

**Current state:**
- Transfer logs: On user's laptop terminal
- rsync server logs: In dest cluster
- rsync client logs: In source cluster
- No centralized view

**Problems:**
- Debugging requires accessing 3 different locations
- Historical transfers: Logs lost when laptop reboots
- Team collaboration: Can't share logs easily

#### 6.2 No Integration with Cluster Monitoring

**Existing cluster monitoring (Prometheus, Grafana):**
- Can monitor CPU/memory of Pods
- Can track PVC usage
- Can alert on failures

**crane transfer-pvc from laptop:**
- ❌ Not visible in cluster metrics
- ❌ Can't set alerts on transfer failures
- ❌ Can't track transfer history in dashboards

---

## Why In-Cluster Execution Solves These Problems

### 1. **Reliability: Survives Network Issues + Automatic Cleanup**

**Kubernetes Job guarantees:**
- Runs until completion (or failure limit)
- Survives node failures (rescheduled automatically)
- Network disconnects don't affect execution (Pod runs in cluster)
- **Automatic cleanup on failure** (trap EXIT in Job script)

**Example:**
```
9:00am  - Job starts transfer
9:30am  - User's laptop crashes (doesn't matter!)
10:00am - User VPN expires (doesn't matter!)
11:00am - Job Pod crashes due to node failure
          ↓
          Kubernetes restarts Job on different node
          ↓
          cleanup() runs automatically before exit
          ↓
          All rsync/stunnel Pods and Secrets deleted
1:00pm  - Transfer completes successfully
         - User checks: kubectl get job → Completed
         - No leftover resources
```

**Automatic cleanup example:**
```bash
#!/bin/bash
cleanup() {
  kubectl delete pods,services,secrets,routes -l transfer-id=${ID} || true
}
trap cleanup EXIT  # Runs on success, failure, or kill

crane transfer-pvc ...
```

---

### 2. **Control Plane Efficiency**

**Note:** Data transfer speed is **identical** (data flows cluster-to-cluster in both modes).

**However, API operations are faster:**
- Laptop → cluster API: 50-200ms per call
- In-cluster → cluster API: 1-5ms per call
- Savings: ~5 minutes on multi-hour transfers

---

### 3. **Security: RBAC and Audit Trail**

**ServiceAccount-based execution:**

| Aspect | Laptop Execution | In-Cluster Job |
|--------|------------------|----------------|
| **Credentials** | User's kubeconfig (broad) | ServiceAccount (minimal) |
| **Scope** | Cluster-admin typical | Namespace-scoped possible |
| **Audit trail** | User identity (varies) | ServiceAccount (consistent) |
| **Expiration** | Manual rotation | Auto-expiring tokens |
| **Compliance** | Hard to audit | Native k8s audit logs |

**Example: Minimal permissions**
```yaml
# ServiceAccount only for database namespace transfers
rules:
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "create"]
    # Only in specific namespace
```

**Audit trail:**
```bash
# Who ran the transfer?
kubectl get job crane-transfer-postgres -o yaml
# spec.serviceAccountName: crane-transfer-db
# Fully auditable via k8s audit logs
```

---

### 4. **Observability: Native Kubernetes Monitoring**

**Centralized logging:**
```bash
# All logs in one place
kubectl logs job/crane-transfer-postgres

# Historical logs (if log aggregation enabled)
kubectl logs job/crane-transfer-postgres-20260701
kubectl logs job/crane-transfer-postgres-20260702
```

**Metrics integration:**
```
Prometheus:
  - job_duration_seconds{job="crane-transfer-postgres"}
  - job_failures_total{job="crane-transfer-postgres"}
  - pvc_transfer_bytes{pvc="postgres-data"}

Grafana dashboard:
  - Transfer duration over time
  - Success/failure rate
  - Data volume transferred
```

**Alerting:**
```yaml
# Prometheus alert
- alert: CraneTransferFailed
  expr: kube_job_failed{job_name=~"crane-transfer-.*"} > 0
  annotations:
    summary: "PVC transfer {{ $labels.job_name }} failed"
```

---

## Use Cases

### Use Case 1: Large Production Database Migration

**Scenario:**
- Migrate 2TB PostgreSQL database from old cluster to new cluster
- Must happen during maintenance window (Saturday 2am - 6am)
- Database can stay online (read-only) during transfer

**Why in-cluster execution is critical:**
- ✅ **Reliability:** No one needs to be awake at 2am watching their laptop
- ✅ **Automatic cleanup:** If transfer fails, no orphaned Pods/Secrets left behind
- ✅ **Monitoring:** Prometheus alerts if Job fails

**Workflow:**
```
Friday 10pm:
  - Submit Job to destination cluster
  - Job runs unattended through the night
  
Saturday 6am:
  - kubectl get job → Completed
  - Transfer successful, all resources cleaned up
  - OR: Job failed → automatic cleanup ran, safe to retry
```

---

### Use Case 2: Multi-Tenant Platform Migration

**Scenario:**
- SaaS platform with 500 customers
- Each customer has 1-5 PVCs (file storage)
- Migrating to new infrastructure (different cloud provider)

**Why in-cluster execution is critical:**
- ✅ **Scale:** Can run 50 parallel Jobs (one per customer)
- ✅ **Automation:** Generate Jobs from customer list (GitOps)
- ✅ **Tracking:** kubectl get jobs shows progress for all customers
- ✅ **Cleanup:** Failed transfers don't leave orphaned resources

**Workflow:**
```bash
# Generate Job per customer
for customer in $(list-customers); do
  cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-customer-${customer}
spec:
  backoffLimit: 3
  template:
    spec:
      containers:
      - name: crane
        command:
        - /bin/bash
        - -c
        - |
          cleanup() {
            kubectl delete pods,secrets -l customer=${customer},transfer=pvc || true
          }
          trap cleanup EXIT
          
          crane transfer-pvc --pvc-name=${customer}-data
EOF
done

# Monitor progress
kubectl get jobs -l migration=prod-to-new
# NAME                      COMPLETIONS   DURATION
# migrate-customer-acme     1/1           12m
# migrate-customer-globex   1/1           8m
# migrate-customer-initech  0/1           Running (5m)
# migrate-customer-oscorp   0/3 (failed)  Failed (cleanup ran!)
```

---

---

### Use Case 3: GitOps-Driven Migrations

**Scenario:**
- Enterprise using GitOps for all cluster operations
- Migration plan must be:
  - Reviewed via Pull Request
  - Approved by team lead
  - Applied via Argo CD / Flux
  - Auditable (who approved, when)

**Why in-cluster execution is critical:**
- ✅ **Declarative:** Job manifests in Git
- ✅ **Approval workflow:** PR review before execution
- ✅ **Audit trail:** Git history + k8s audit logs
- ✅ **Rollback:** Revert PR if something goes wrong

**Workflow:**
```
Developer creates PR:
  - migrations/prod-to-new/postgres-transfer-job.yaml
  
Team lead reviews:
  - Checks PVC names, namespaces, flags
  - Approves PR
  
Argo CD applies:
  - Job runs automatically
  - Slack notification on completion
  
Audit:
  - Git: Who approved PR
  - K8s: Which ServiceAccount ran Job
  - Logs: Full transfer history
```

---

## Comparison: Laptop vs In-Cluster Execution

| Aspect | Laptop Execution | In-Cluster Job | Winner |
|--------|------------------|----------------|--------|
| **Reliability** | ❌ Fails on disconnect | ✅ Immune to network issues | Job |
| **Cleanup on failure** | ❌ Manual cleanup required | ✅ Automatic (trap EXIT) | Job |
| **Data transfer speed** | ✅ Same (cluster-to-cluster) | ✅ Same (cluster-to-cluster) | Tie |
| **Control plane latency** | ⚠️ 50-200ms API calls | ✅ 1-5ms API calls | Job (minor) |
| **Security** | ⚠️ User credentials | ✅ ServiceAccount (RBAC) | Job |
| **Audit** | ⚠️ Hard to track | ✅ K8s audit logs | Job |
| **Observability** | ❌ Logs on laptop | ✅ Centralized (kubectl logs) | Job |
| **Monitoring** | ❌ No metrics | ✅ Prometheus integration | Job |
| **GitOps** | ❌ Can't declaratively define | ✅ Job YAML in Git | Job |
| **Scale** | ❌ Limited by laptop | ✅ Parallel Jobs | Job |
| **Ease of use** | ✅ Simple (just run CLI) | ⚠️ Requires setup (RBAC, Secret) | Laptop |
| **Quick testing** | ✅ Fast iteration | ⚠️ Slower (apply YAML) | Laptop |

**Recommendation:**
- **Development / Testing:** Laptop execution (simpler, faster iteration)
- **Production / Automation:** In-cluster Job (reliable, auditable, performant)

---

## What This Proposal Does NOT Include

This proposal focuses on **why** in-cluster execution is needed, not **how** to implement it.

**Out of scope:**
- ❌ Implementation details (code changes to crane CLI)
- ❌ Specific RBAC manifests
- ❌ Job YAML templates
- ❌ Migration guides for existing users
- ❌ Performance benchmarks
- ❌ Security hardening details

**These will be addressed in:**
- Implementation plan (separate document)
- User documentation (crane docs)
- E2E test suite

---

## Success Criteria

This proposal is successful if it enables:

1. **Production-grade migrations:**
   - ✅ Run multi-hour transfers without human supervision
   - ✅ Survive network disconnects / laptop failures
   - ✅ Automatic cleanup of orphaned resources on failure

2. **Enterprise compliance:**
   - ✅ RBAC-controlled execution (ServiceAccounts)
   - ✅ Full audit trail (k8s audit logs)
   - ✅ Integration with existing monitoring (Prometheus, Grafana)

3. **GitOps workflows:**
   - ✅ Declarative Job definitions (stored in Git)
   - ✅ PR approval before execution
   - ✅ Argo CD / Flux integration

4. **Ease of use:**
   - ✅ Simple setup (apply RBAC, create Secret, apply Job)
   - ✅ Standard k8s tooling (kubectl get jobs, kubectl logs)
   - ✅ No operator installation required

---

## Alternatives Considered

### Alternative 1: Continue Laptop-Only Execution

**Pros:**
- No changes needed
- Simple for users

**Cons:**
- ❌ Doesn't solve any of the problems above
- ❌ Not viable for production migrations
- ❌ Blocks enterprise adoption

**Verdict:** Not acceptable for production use cases.

---

### Alternative 2: Build a Custom Operator (Like VolSync)

**Pros:**
- ✅ Rich CRD-based API
- ✅ Advanced features (automatic failover, etc.)

**Cons:**
- ❌ Violates hard requirement: "NO operator"
- ❌ Adds operational complexity (operator must be installed)
- ❌ Overkill for simple PVC transfers
- ❌ Longer implementation time (months vs weeks)

**Verdict:** Too complex, violates requirements. See `IN_CLUSTER_TRANSFER_PROPOSAL.md` (rejected proposal).

---

### Alternative 3: Hybrid Approach

**Idea:** Support both laptop and in-cluster execution.

**Pros:**
- ✅ Flexible (users choose based on use case)
- ✅ Laptop for dev/testing (simple)
- ✅ Job for prod (reliable, performant)

**Cons:**
- ⚠️ Two code paths to maintain
- ⚠️ More documentation needed

**Verdict:** ✅ **Recommended approach**
- Keep existing laptop execution (don't break users)
- Add new in-cluster execution mode
- Let users choose based on needs

---

## Open Questions

1. **Should crane CLI generate Job manifests?**
   - Option A: User writes Job YAML manually (more flexible)
   - Option B: `crane transfer-pvc --generate-job > job.yaml` (easier)
   - Recommendation: Both (B for convenience, A for advanced users)

2. **How to handle source cluster credentials?**
   - Option A: Kubeconfig in Secret (current proposal)
   - Option B: ServiceAccount token exchange (more secure, complex)
   - Recommendation: Start with A, add B later

3. **Should Jobs auto-cleanup rsync/stunnel Pods?**
   - Option A: Leave Pods running (for debugging)
   - Option B: Always cleanup (cleaner)
   - Option C: Flag-controlled: `--cleanup=true|false`
   - Recommendation: **C (default true for prod, false for debug)**
   - Implementation: `trap cleanup EXIT` in Job script

---

## Next Steps

1. **Review & Approval:**
   - Team review this proposal
   - Stakeholder sign-off (product, engineering, security)

2. **Implementation Planning:**
   - Create detailed implementation plan
   - Define API changes (if any)
   - Design Job manifest templates

3. **Documentation:**
   - User guide: "Running transfer-pvc as a Job"
   - Examples: One-time Job, CronJob, GitOps workflow
   - Troubleshooting guide

4. **Implementation:**
   - Phase 1: Basic Job support (manual YAML)
   - Phase 2: CLI flag to generate Job YAML
   - Phase 3: CronJob templates for incremental sync

5. **Testing:**
   - E2E tests: Job-based transfers
   - Performance benchmarks: Laptop vs Job
   - Security review: ServiceAccount permissions

---

## Conclusion

In-cluster execution of `crane transfer-pvc` addresses critical gaps for production migrations:

✅ **Reliability:** Survives network disconnects + automatic cleanup on failure  
✅ **Security:** RBAC, audit trails, compliance  
✅ **Observability:** Native k8s monitoring  
✅ **GitOps:** Declarative, reviewable, auditable  
✅ **No Operator:** Simple Kubernetes Jobs, not complex CRDs

**Note:** Data transfer performance is identical (cluster-to-cluster in both modes). Control plane operations are slightly faster (~5 minutes savings on multi-hour transfers).

**This proposal enables crane to be a production-grade migration tool** suitable for enterprise use cases, while maintaining simplicity (no operator required).

**Recommended approach:** Hybrid model
- Keep laptop execution for dev/testing
- Add in-cluster Job execution for production
- Let users choose based on their needs
