# In-Cluster Transfer Execution Proposal

**Date:** 2026-06-30  
**Author:** Analysis based on crane codebase review  
**Status:** Proposal for discussion  

## Executive Summary

Running `crane transfer-pvc` **inside the destination cluster** (as a Kubernetes Job/CronJob) instead of from a local machine would bring **significant advantages** for stability, reliability, and operational simplicity.

**Recommendation:** ✅ **YES, implement in-cluster execution mode**

**Key Benefits:**
- 🚀 **Faster:** Direct cluster-to-cluster network, no local bottleneck
- 🔒 **More Stable:** Survives local network/laptop interruptions
- 🔄 **Better for Automation:** Native Kubernetes orchestration (CronJob for incremental sync)
- 📊 **Observable:** Kubernetes-native logging, metrics, and status
- 🎯 **Simpler Credentials:** Uses ServiceAccount, no kubeconfig juggling

---

## 1. Current Architecture (External Execution)

### How it works now:

```
┌─────────────────┐
│  User's Laptop  │
│                 │
│  crane CLI      │◄─── Reads ~/.kube/config
│  transfer-pvc   │
└────────┬────────┘
         │
         ├──────────────────┐
         │                  │
         ▼                  ▼
┌─────────────────┐  ┌─────────────────┐
│ Source Cluster  │  │  Dest Cluster   │
│                 │  │                 │
│ ┌─────────────┐ │  │ ┌─────────────┐ │
│ │ rsync-client│ │  │ │ rsync-server│ │
│ │    Pod      │◄┼──┼─┤    Pod      │ │
│ └─────────────┘ │  │ └─────────────┘ │
│                 │  │        ▲        │
│                 │  │        │        │
│                 │  │ ┌──────┴──────┐ │
│                 │  │ │   Endpoint  │ │
│                 │  │ │ (Ingress/   │ │
│                 │  │ │   Route)    │ │
│                 │  │ └─────────────┘ │
└─────────────────┘  └─────────────────┘
         ▲                  ▲
         │                  │
         └──────────────────┘
              crane CLI controls
              both clusters via
              kubeconfig contexts
```

### Problems with External Execution:

| Problem | Impact | Severity |
|---------|--------|----------|
| **Local network dependency** | Transfer fails if laptop disconnects, WiFi drops, VPN flickers | 🔴 Critical |
| **Laptop must stay on** | Cannot close laptop, transfer can take hours/days | 🔴 Critical |
| **Credential management** | Need kubeconfig with access to BOTH clusters on laptop | 🟡 High |
| **No cluster orchestration** | Cannot use CronJob for incremental sync (EXTENSION B1.2) | 🟡 High |
| **Poor observability** | Progress only visible in terminal, no K8s native status | 🟠 Medium |
| **Bandwidth bottleneck** | Data flows through laptop's network connection | 🟠 Medium |
| **Manual recovery** | User must monitor and restart manually on failure | 🟡 High |

---

## 2. Proposed Architecture (In-Cluster Execution)

### Option A: Kubernetes Job (Recommended)

```
┌─────────────────────────────────────────────────────────┐
│              Destination Cluster                        │
│                                                         │
│  ┌───────────────────────────────────────────────────┐ │
│  │  crane-transfer Job                               │ │
│  │                                                   │ │
│  │  ┌─────────────────────────────────────────────┐ │ │
│  │  │ crane transfer-pvc                          │ │ │
│  │  │ (runs as container in Job)                  │ │ │
│  │  │                                             │ │ │
│  │  │ Uses:                                       │ │ │
│  │  │ - In-cluster config for dest cluster       │ │ │
│  │  │ - Secret with source cluster kubeconfig     │ │ │
│  │  └─────────────────────────────────────────────┘ │ │
│  │                                                   │ │
│  │  Creates:                                         │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐       │ │
│  │  │  rsync   │  │ stunnel  │  │ Endpoint │       │ │
│  │  │  server  │  │  server  │  │(Ingress) │       │ │
│  │  │   Pod    │  │   Pod    │  │          │       │ │
│  │  └──────────┘  └──────────┘  └──────────┘       │ │
│  └───────────────────────────────────────────────────┘ │
│                          │                             │
└──────────────────────────┼─────────────────────────────┘
                           │
                           │ Connects to source via
                           │ kubeconfig in Secret
                           ▼
                ┌─────────────────────┐
                │  Source Cluster     │
                │                     │
                │  ┌──────────────┐   │
                │  │ rsync-client │   │
                │  │     Pod      │   │
                │  └──────────────┘   │
                │                     │
                └─────────────────────┘
```

### Advantages of In-Cluster Execution:

| Advantage | Benefit | Priority |
|-----------|---------|----------|
| **Network stability** | Transfer continues even if operator disconnects | 🔴 Critical |
| **Direct cluster network** | No laptop network bottleneck, faster transfers | 🔴 Critical |
| **Native K8s orchestration** | Can use CronJob for B1.2 (incremental sync) | 🔴 Critical |
| **Persistent state** | Job status persisted in etcd, survives restarts | 🟡 High |
| **K8s-native observability** | `kubectl get jobs`, `kubectl logs`, metrics | 🟡 High |
| **ServiceAccount auth** | Simpler than kubeconfig management | 🟠 Medium |
| **Automatic retry** | Job restartPolicy handles transient failures | 🟡 High |
| **Audit trail** | K8s events show what happened | 🟠 Medium |

---

## 3. Detailed Design

### 3.1 Custom Resource Definition (CRD)

```yaml
apiVersion: migration.konveyor.io/v1alpha1
kind: PVCTransfer
metadata:
  name: postgres-data-migration
  namespace: default
spec:
  # Source cluster connection
  source:
    # Option 1: Reference to Secret containing kubeconfig
    kubeconfigSecret:
      name: source-cluster-kubeconfig
      key: kubeconfig
    # Option 2: In-cluster (for same-cluster transfers)
    # inCluster: true
    
    # PVC to transfer from
    pvc:
      name: postgres-data
      namespace: production
  
  # Destination (uses in-cluster config by default)
  destination:
    pvc:
      name: postgres-data
      namespace: production
    storageClass: premium-ssd
    storageRequests: 100Gi
  
  # Transfer configuration
  transfer:
    # Endpoint type (route, ingress)
    endpoint:
      type: route
      # For ingress:
      # subdomain: transfer.example.com
      # ingressClass: nginx
    
    # Transfer options
    verify: true
    enableCompression: true
    bandwidthLimit: "100M"
    
    # Scheduling (for incremental sync - EXTENSION B1.2)
    schedule:
      # Run incremental sync every 30 minutes
      interval: 30m
      # OR: cron expression
      # cron: "*/30 * * * *"
    
    # Pod lifecycle (EXTENSION B1.3)
    scaleDownSource: true
    scaleUpTarget: true
    
    # Resume support (EXTENSION B4.3)
    enableResume: true
  
  # Advanced options
  advanced:
    sourceImage: quay.io/konveyor/rsync-transfer:latest
    destinationImage: quay.io/konveyor/rsync-transfer:latest
    
    # Resource limits for transfer Pods
    resources:
      limits:
        cpu: "2"
        memory: 4Gi
      requests:
        cpu: "1"
        memory: 2Gi

status:
  # Current phase
  phase: Syncing  # Pending, Initializing, Syncing, Finalizing, Completed, Failed
  
  # Conditions
  conditions:
    - type: Ready
      status: "True"
      lastTransitionTime: "2026-06-30T10:00:00Z"
      reason: TransferInProgress
      message: "Incremental sync 5/10 completed"
  
  # Progress
  progress:
    percentage: 73
    transferredBytes: 73000000000
    transferredFiles: 15234
    totalFiles: 20891
    transferRate: "150MB/s"
    
  # Sync history
  syncHistory:
    - syncNumber: 1
      startTime: "2026-06-30T09:00:00Z"
      endTime: "2026-06-30T09:15:00Z"
      bytesTransferred: 50000000000
      exitCode: 0
    - syncNumber: 2
      startTime: "2026-06-30T09:30:00Z"
      endTime: "2026-06-30T09:35:00Z"
      bytesTransferred: 15000000000
      exitCode: 0
  
  # Next scheduled sync (for incremental mode)
  nextSyncTime: "2026-06-30T10:30:00Z"
  
  # Errors
  errors:
    - timestamp: "2026-06-30T09:45:00Z"
      message: "Failed to sync file /data/large.bin: connection timeout"
      retryable: true
```

### 3.2 Controller Implementation

```go
// api/v1alpha1/pvctransfer_types.go
package v1alpha1

import (
    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type PVCTransferSpec struct {
    Source      SourceSpec      `json:"source"`
    Destination DestinationSpec `json:"destination"`
    Transfer    TransferSpec    `json:"transfer"`
    Advanced    AdvancedSpec    `json:"advanced,omitempty"`
}

type SourceSpec struct {
    // Reference to Secret containing kubeconfig for source cluster
    KubeconfigSecret *corev1.SecretKeySelector `json:"kubeconfigSecret,omitempty"`
    
    // Use in-cluster config (for same-cluster transfers)
    InCluster bool `json:"inCluster,omitempty"`
    
    // PVC to transfer
    PVC PVCRef `json:"pvc"`
}

type DestinationSpec struct {
    PVC             PVCRef  `json:"pvc"`
    StorageClass    string  `json:"storageClass,omitempty"`
    StorageRequests string  `json:"storageRequests,omitempty"`
}

type TransferSpec struct {
    Endpoint          EndpointSpec  `json:"endpoint"`
    Verify            bool          `json:"verify,omitempty"`
    EnableCompression bool          `json:"enableCompression,omitempty"`
    BandwidthLimit    string        `json:"bandwidthLimit,omitempty"`
    Schedule          *ScheduleSpec `json:"schedule,omitempty"`
    ScaleDownSource   bool          `json:"scaleDownSource,omitempty"`
    ScaleUpTarget     bool          `json:"scaleUpTarget,omitempty"`
    EnableResume      bool          `json:"enableResume,omitempty"`
}

type ScheduleSpec struct {
    // Interval between syncs (e.g., "30m", "1h")
    Interval string `json:"interval,omitempty"`
    
    // OR: Cron expression
    Cron string `json:"cron,omitempty"`
}

type PVCTransferStatus struct {
    Phase        TransferPhase      `json:"phase"`
    Conditions   []metav1.Condition `json:"conditions,omitempty"`
    Progress     *ProgressStatus    `json:"progress,omitempty"`
    SyncHistory  []SyncAttempt      `json:"syncHistory,omitempty"`
    NextSyncTime *metav1.Time       `json:"nextSyncTime,omitempty"`
    Errors       []TransferError    `json:"errors,omitempty"`
}

type TransferPhase string

const (
    PhasePending      TransferPhase = "Pending"
    PhaseInitializing TransferPhase = "Initializing"
    PhaseSyncing      TransferPhase = "Syncing"
    PhaseFinalizing   TransferPhase = "Finalizing"
    PhaseCompleted    TransferPhase = "Completed"
    PhaseFailed       TransferPhase = "Failed"
)

type ProgressStatus struct {
    Percentage       int64  `json:"percentage"`
    TransferredBytes int64  `json:"transferredBytes"`
    TransferredFiles int64  `json:"transferredFiles"`
    TotalFiles       *int64 `json:"totalFiles,omitempty"`
    TransferRate     string `json:"transferRate,omitempty"`
}

type SyncAttempt struct {
    SyncNumber        int          `json:"syncNumber"`
    StartTime         metav1.Time  `json:"startTime"`
    EndTime           *metav1.Time `json:"endTime,omitempty"`
    BytesTransferred  int64        `json:"bytesTransferred"`
    ExitCode          *int32       `json:"exitCode,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:shortName=pvct
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
// +kubebuilder:printcolumn:name="Progress",type=string,JSONPath=`.status.progress.percentage`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

type PVCTransfer struct {
    metav1.TypeMeta   `json:",inline"`
    metav1.ObjectMeta `json:"metadata,omitempty"`
    
    Spec   PVCTransferSpec   `json:"spec,omitempty"`
    Status PVCTransferStatus `json:"status,omitempty"`
}
```

### 3.3 Controller Logic

```go
// controllers/pvctransfer_controller.go
package controllers

import (
    "context"
    "time"
    
    batchv1 "k8s.io/api/batch/v1"
    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    ctrl "sigs.k8s.io/controller-runtime"
    "sigs.k8s.io/controller-runtime/pkg/client"
    
    migrationv1alpha1 "github.com/migtools/crane/api/v1alpha1"
)

type PVCTransferReconciler struct {
    client.Client
    Scheme *runtime.Scheme
}

func (r *PVCTransferReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    log := ctrl.LoggerFrom(ctx)
    
    // Fetch PVCTransfer
    transfer := &migrationv1alpha1.PVCTransfer{}
    if err := r.Get(ctx, req.NamespacedName, transfer); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)
    }
    
    // State machine based on Phase
    switch transfer.Status.Phase {
    case "", migrationv1alpha1.PhasePending:
        return r.reconcilePending(ctx, transfer)
        
    case migrationv1alpha1.PhaseInitializing:
        return r.reconcileInitializing(ctx, transfer)
        
    case migrationv1alpha1.PhaseSyncing:
        return r.reconcileSyncing(ctx, transfer)
        
    case migrationv1alpha1.PhaseFinalizing:
        return r.reconcileFinalizing(ctx, transfer)
        
    case migrationv1alpha1.PhaseCompleted, migrationv1alpha1.PhaseFailed:
        // Terminal states - no action needed
        return ctrl.Result{}, nil
    }
    
    return ctrl.Result{}, nil
}

func (r *PVCTransferReconciler) reconcilePending(ctx context.Context, transfer *migrationv1alpha1.PVCTransfer) (ctrl.Result, error) {
    log := ctrl.LoggerFrom(ctx)
    log.Info("Starting PVC transfer initialization")
    
    // Validate configuration
    if err := r.validateTransfer(transfer); err != nil {
        transfer.Status.Phase = migrationv1alpha1.PhaseFailed
        transfer.Status.Errors = append(transfer.Status.Errors, migrationv1alpha1.TransferError{
            Timestamp: metav1.Now(),
            Message:   err.Error(),
            Retryable: false,
        })
        return ctrl.Result{}, r.Status().Update(ctx, transfer)
    }
    
    // Create Job to run the transfer
    job := r.buildTransferJob(transfer)
    if err := r.Create(ctx, job); err != nil {
        return ctrl.Result{}, err
    }
    
    // Update status
    transfer.Status.Phase = migrationv1alpha1.PhaseInitializing
    return ctrl.Result{}, r.Status().Update(ctx, transfer)
}

func (r *PVCTransferReconciler) buildTransferJob(transfer *migrationv1alpha1.PVCTransfer) *batchv1.Job {
    // Build crane transfer-pvc command arguments
    args := []string{
        "transfer-pvc",
        "--source-context=source",  // Will use kubeconfig from Secret
        "--destination-context=destination", // Will use in-cluster config
        fmt.Sprintf("--pvc-name=%s:%s", 
            transfer.Spec.Source.PVC.Name,
            transfer.Spec.Destination.PVC.Name),
        fmt.Sprintf("--pvc-namespace=%s:%s",
            transfer.Spec.Source.PVC.Namespace,
            transfer.Spec.Destination.PVC.Namespace),
    }
    
    if transfer.Spec.Destination.StorageClass != "" {
        args = append(args, fmt.Sprintf("--dest-storage-class=%s", 
            transfer.Spec.Destination.StorageClass))
    }
    
    if transfer.Spec.Transfer.Verify {
        args = append(args, "--verify")
    }
    
    if transfer.Spec.Transfer.BandwidthLimit != "" {
        args = append(args, fmt.Sprintf("--bandwidth-limit=%s", 
            transfer.Spec.Transfer.BandwidthLimit))
    }
    
    // Add endpoint configuration
    args = append(args, fmt.Sprintf("--endpoint=%s", transfer.Spec.Transfer.Endpoint.Type))
    if transfer.Spec.Transfer.Endpoint.Subdomain != "" {
        args = append(args, fmt.Sprintf("--subdomain=%s", 
            transfer.Spec.Transfer.Endpoint.Subdomain))
    }
    
    // Build Job
    backoffLimit := int32(3)
    ttlSecondsAfterFinished := int32(3600) // Keep for 1 hour
    
    return &batchv1.Job{
        ObjectMeta: metav1.ObjectMeta{
            Name:      fmt.Sprintf("crane-transfer-%s", transfer.Name),
            Namespace: transfer.Namespace,
            Labels: map[string]string{
                "app.kubernetes.io/name":       "crane",
                "app.kubernetes.io/component":  "transfer-pvc",
                "app.konveyor.io/transfer-cr":  transfer.Name,
            },
            OwnerReferences: []metav1.OwnerReference{
                *metav1.NewControllerRef(transfer, migrationv1alpha1.GroupVersion.WithKind("PVCTransfer")),
            },
        },
        Spec: batchv1.JobSpec{
            BackoffLimit:            &backoffLimit,
            TTLSecondsAfterFinished: &ttlSecondsAfterFinished,
            Template: corev1.PodTemplateSpec{
                Spec: corev1.PodSpec{
                    ServiceAccountName: "crane-transfer",
                    RestartPolicy:      corev1.RestartPolicyOnFailure,
                    
                    Volumes: []corev1.Volume{
                        {
                            Name: "source-kubeconfig",
                            VolumeSource: corev1.VolumeSource{
                                Secret: &corev1.SecretVolumeSource{
                                    SecretName: transfer.Spec.Source.KubeconfigSecret.Name,
                                },
                            },
                        },
                    },
                    
                    Containers: []corev1.Container{
                        {
                            Name:  "crane",
                            Image: "quay.io/konveyor/crane:latest",
                            Args:  args,
                            
                            Env: []corev1.EnvVar{
                                {
                                    Name:  "KUBECONFIG",
                                    Value: "/kubeconfig/source/kubeconfig:/kubeconfig/dest/config",
                                },
                            },
                            
                            VolumeMounts: []corev1.VolumeMount{
                                {
                                    Name:      "source-kubeconfig",
                                    MountPath: "/kubeconfig/source",
                                    ReadOnly:  true,
                                },
                            },
                            
                            Resources: corev1.ResourceRequirements{
                                Requests: corev1.ResourceList{
                                    corev1.ResourceCPU:    resource.MustParse("100m"),
                                    corev1.ResourceMemory: resource.MustParse("256Mi"),
                                },
                                Limits: corev1.ResourceList{
                                    corev1.ResourceCPU:    resource.MustParse("500m"),
                                    corev1.ResourceMemory: resource.MustParse("1Gi"),
                                },
                            },
                        },
                    },
                },
            },
        },
    }
}

func (r *PVCTransferReconciler) reconcileSyncing(ctx context.Context, transfer *migrationv1alpha1.PVCTransfer) (ctrl.Result, error) {
    // Find the Job
    job := &batchv1.Job{}
    jobName := fmt.Sprintf("crane-transfer-%s", transfer.Name)
    if err := r.Get(ctx, client.ObjectKey{
        Name:      jobName,
        Namespace: transfer.Namespace,
    }, job); err != nil {
        return ctrl.Result{}, err
    }
    
    // Update status based on Job status
    if job.Status.Succeeded > 0 {
        // Check if this is incremental sync or final
        if transfer.Spec.Transfer.Schedule != nil {
            // Incremental sync completed - schedule next one
            transfer.Status.SyncHistory = append(transfer.Status.SyncHistory, migrationv1alpha1.SyncAttempt{
                SyncNumber:       len(transfer.Status.SyncHistory) + 1,
                StartTime:        job.Status.StartTime,
                EndTime:          job.Status.CompletionTime,
                BytesTransferred: 0, // TODO: extract from logs
                ExitCode:         ptr.Int32(0),
            })
            
            // Calculate next sync time
            nextSync := metav1.NewTime(time.Now().Add(parseDuration(transfer.Spec.Transfer.Schedule.Interval)))
            transfer.Status.NextSyncTime = &nextSync
            
            return ctrl.Result{RequeueAfter: parseDuration(transfer.Spec.Transfer.Schedule.Interval)}, 
                r.Status().Update(ctx, transfer)
        } else {
            // One-shot transfer completed
            transfer.Status.Phase = migrationv1alpha1.PhaseCompleted
            return ctrl.Result{}, r.Status().Update(ctx, transfer)
        }
    }
    
    if job.Status.Failed > 0 {
        transfer.Status.Phase = migrationv1alpha1.PhaseFailed
        // TODO: Extract error from Job logs
        return ctrl.Result{}, r.Status().Update(ctx, transfer)
    }
    
    // Still running - update progress from logs
    if err := r.updateProgressFromLogs(ctx, transfer, job); err != nil {
        // Log error but don't fail reconciliation
        ctrl.LoggerFrom(ctx).Error(err, "failed to update progress from logs")
    }
    
    // Requeue to check again
    return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
}

func (r *PVCTransferReconciler) updateProgressFromLogs(ctx context.Context, transfer *migrationv1alpha1.PVCTransfer, job *batchv1.Job) error {
    // TODO: Parse progress from Job Pod logs
    // Similar to existing parseRsyncLogs() logic
    // Update transfer.Status.Progress
    return nil
}
```

### 3.4 RBAC Configuration

```yaml
# deploy/rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: crane-transfer
  namespace: crane-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: crane-transfer
rules:
  # Manage PVCs
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "create", "update", "patch"]
  
  # Manage Pods for rsync
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "create", "delete", "watch"]
  
  # Manage Services for endpoints
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "create", "delete"]
  
  # Manage Secrets for stunnel certificates
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "create", "delete"]
  
  # Manage ConfigMaps for transfer state
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "create", "update", "patch", "delete"]
  
  # Manage Ingresses/Routes for endpoints
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "create", "delete"]
  
  - apiGroups: ["route.openshift.io"]
    resources: ["routes"]
    verbs: ["get", "list", "create", "delete"]
  
  # Read Deployments/StatefulSets (for scaling - EXTENSION B1.3)
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["get", "list", "update", "patch"]
  
  # Read cluster ingress config (OpenShift)
  - apiGroups: ["config.openshift.io"]
    resources: ["ingresses"]
    verbs: ["get"]
  
  # Read namespace annotations (for security contexts)
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: crane-transfer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: crane-transfer
subjects:
  - kind: ServiceAccount
    name: crane-transfer
    namespace: crane-system
```

---

## 4. Usage Examples

### 4.1 One-Shot Transfer

```yaml
apiVersion: migration.konveyor.io/v1alpha1
kind: PVCTransfer
metadata:
  name: postgres-migration
  namespace: migrations
spec:
  source:
    kubeconfigSecret:
      name: prod-cluster-kubeconfig
      key: kubeconfig
    pvc:
      name: postgres-data
      namespace: database
  
  destination:
    pvc:
      name: postgres-data
      namespace: database
    storageClass: fast-ssd
  
  transfer:
    endpoint:
      type: route
    verify: true
    bandwidthLimit: "100M"
```

**Monitor:**
```bash
# Watch transfer progress
kubectl get pvctransfer postgres-migration -w

# View detailed status
kubectl describe pvctransfer postgres-migration

# View logs
kubectl logs -l app.konveyor.io/transfer-cr=postgres-migration -f
```

### 4.2 Incremental Sync (EXTENSION B1.2)

```yaml
apiVersion: migration.konveyor.io/v1alpha1
kind: PVCTransfer
metadata:
  name: large-dataset-sync
  namespace: migrations
spec:
  source:
    kubeconfigSecret:
      name: source-kubeconfig
      key: config
    pvc:
      name: ml-training-data
      namespace: ml-workloads
  
  destination:
    pvc:
      name: ml-training-data
      namespace: ml-workloads
  
  transfer:
    endpoint:
      type: route
    
    # Incremental sync every 30 minutes
    schedule:
      interval: 30m
    
    # Optimize for large datasets
    enableCompression: true
    enableResume: true
    bandwidthLimit: "500M"
```

**Finalize when ready:**
```yaml
# Patch to trigger final sync with scaled-down workloads
apiVersion: migration.konveyor.io/v1alpha1
kind: PVCTransfer
metadata:
  name: large-dataset-sync
  namespace: migrations
spec:
  # ... previous spec ...
  
  transfer:
    # Remove schedule to trigger final sync
    # schedule: null
    
    # Scale down source before final sync
    scaleDownSource: true
    scaleUpTarget: true
```

OR via kubectl:
```bash
# Stop incremental sync and trigger finalize
kubectl patch pvctransfer large-dataset-sync \
  --type=json \
  -p='[
    {"op": "remove", "path": "/spec/transfer/schedule"},
    {"op": "add", "path": "/spec/transfer/scaleDownSource", "value": true},
    {"op": "add", "path": "/spec/transfer/scaleUpTarget", "value": true}
  ]'
```

### 4.3 StatefulSet Batch Transfer (EXTENSION B5.3)

```yaml
apiVersion: migration.konveyor.io/v1alpha1
kind: PVCTransfer
metadata:
  name: elasticsearch-cluster
  namespace: migrations
spec:
  source:
    kubeconfigSecret:
      name: prod-kubeconfig
      key: config
    
    # NEW: StatefulSet-aware mode
    statefulSet:
      name: elasticsearch
      namespace: elastic-system
      # Auto-discovers: data-elasticsearch-0, data-elasticsearch-1, data-elasticsearch-2
  
  destination:
    storageClass: premium-ssd
    # Namespace defaults to same as source
  
  transfer:
    endpoint:
      type: route
    verify: true
    
    # Transfer PVCs in ordinal order (0, 1, 2, ...)
    # Maintains StatefulSet ordering guarantees
```

---

## 5. Migration Path

### Phase 1: CLI Still Works (Backward Compatibility)

The existing CLI `crane transfer-pvc` should continue to work for users who prefer local execution:

```bash
# Existing workflow - UNCHANGED
crane transfer-pvc \
    --source-context=prod \
    --destination-context=dr \
    --pvc-name=mydata \
    --endpoint=route
```

### Phase 2: Add "Generator" Mode to CLI

```bash
# NEW: Generate CRD YAML instead of running transfer
crane transfer-pvc \
    --source-context=prod \
    --destination-context=dr \
    --pvc-name=mydata \
    --endpoint=route \
    --dry-run=client \
    --output=yaml > pvctransfer.yaml

# User can review and apply
kubectl apply -f pvctransfer.yaml
```

### Phase 3: Add "Submit" Mode to CLI

```bash
# NEW: Submit PVCTransfer CR directly to cluster
crane transfer-pvc \
    --source-context=prod \
    --destination-context=dr \
    --pvc-name=mydata \
    --endpoint=route \
    --submit

# Equivalent to:
# 1. Generate PVCTransfer CR
# 2. Create Secret with source kubeconfig
# 3. kubectl apply the CR
# 4. Watch status
```

---

## 6. Comparison: CLI vs In-Cluster

| Aspect | External CLI | In-Cluster (Job/Operator) | Winner |
|--------|-------------|---------------------------|--------|
| **Stability** | ❌ Depends on laptop/network | ✅ Runs in cluster, survives disconnects | 🏆 In-Cluster |
| **Speed** | ⚠️ Limited by local bandwidth | ✅ Direct cluster-to-cluster | 🏆 In-Cluster |
| **Setup complexity** | ✅ Just install CLI | ⚠️ Need to deploy operator | 🏆 CLI |
| **Credential mgmt** | ⚠️ Need kubeconfig for BOTH clusters | ✅ In-cluster for dest, Secret for source | 🏆 In-Cluster |
| **Observability** | ❌ Only terminal output | ✅ K8s status, events, metrics | 🏆 In-Cluster |
| **Automation** | ⚠️ Need external scheduler | ✅ CronJob for incremental sync | 🏆 In-Cluster |
| **Recovery** | ❌ Manual restart | ✅ Job restartPolicy | 🏆 In-Cluster |
| **Multi-tenancy** | ❌ Hard to control who runs what | ✅ RBAC-controlled | 🏆 In-Cluster |
| **Quick testing** | ✅ Just run command | ⚠️ Need to create CR | 🏆 CLI |

**Recommendation:**
- **Default:** In-cluster (Job/Operator) for production
- **Alternative:** CLI for quick testing, development, demos

---

## 7. Implementation Checklist

### Phase 1: Foundation (Sprint 1-2)

- [ ] Create `api/v1alpha1/pvctransfer_types.go` with CRD definition
- [ ] Generate CRD manifests with kubebuilder
- [ ] Create `controllers/pvctransfer_controller.go` skeleton
- [ ] Implement basic state machine (Pending → Initializing → Syncing → Completed)
- [ ] Implement Job creation from CR spec
- [ ] Add RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
- [ ] Create Dockerfile for operator (can reuse crane image)
- [ ] Add integration tests for CRD validation

**Estimated effort:** 2 weeks

### Phase 2: Core Functionality (Sprint 3-4)

- [ ] Implement progress tracking from Job logs
- [ ] Update CR status with progress
- [ ] Add error handling and failure recovery
- [ ] Implement source kubeconfig Secret handling
- [ ] Add validation webhooks for CR
- [ ] Create user documentation
- [ ] Add e2e tests

**Estimated effort:** 2 weeks

### Phase 3: EXTENSION Features (Sprint 5-7)

- [ ] **B1.2:** Implement incremental sync via CronJob
- [ ] **B1.2:** Add finalize logic (stop cron, do final sync)
- [ ] **B1.3:** Implement workload scaling (scale-down-source, scale-up-target)
- [ ] **B2.3:** Add storage class mapping from YAML ConfigMap
- [ ] **B3.3:** Implement quiescence gate (wait for pods to stop)
- [ ] **B4.2:** Already done via --bandwidth-limit ✅
- [ ] **B4.3:** Enable resume via rsync --partial ✅
- [ ] **B5.3:** Implement StatefulSet-aware batch transfer
- [ ] Add status conditions for each phase
- [ ] Add Prometheus metrics

**Estimated effort:** 3 weeks

### Phase 4: CLI Integration (Sprint 8)

- [ ] Add `--dry-run=client --output=yaml` to CLI
- [ ] Add `--submit` mode to CLI (creates CR instead of running locally)
- [ ] Add `crane transfer-pvc status <name>` to watch CR
- [ ] Add `crane transfer-pvc finalize <name>` helper
- [ ] Update documentation with both workflows

**Estimated effort:** 1 week

---

## 8. Open Questions for Discussion

1. **CRD namespace:** Should PVCTransfer be cluster-scoped or namespaced?
   - **Proposal:** Namespaced (in destination namespace) for better multi-tenancy

2. **Source credentials:** How to securely provide source cluster kubeconfig?
   - **Proposal:** Reference to Secret in same namespace as CR
   - **Alternative:** ClusterSecret for shared source clusters

3. **Resource cleanup:** When to delete rsync pods, endpoints, etc.?
   - **Proposal:** TTL on Job (default 1 hour), immediate cleanup on CR deletion

4. **Incremental sync finalize:** How does user signal "stop syncing, do final transfer"?
   - **Proposal:** Remove `.spec.transfer.schedule` from CR (triggers final sync)
   - **Alternative:** Add `.spec.finalize: true` field

5. **StatefulSet discovery:** Should we auto-detect PVC naming patterns?
   - **Proposal:** Yes, support standard `<volumeClaimTemplate>-<statefulset>-<ordinal>` pattern
   - **Alternative:** Require explicit list of PVCs

6. **Operator deployment:** Separate operator or extend existing crane?
   - **Proposal:** New `crane-operator` component, optional deployment
   - Keeps CLI standalone for simple use cases

---

## 9. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Increased complexity** | Users must understand CRDs, operators | Provide CLI helpers (`--submit`, `status`), clear docs |
| **Operator maintenance** | Need to maintain another component | Use kubebuilder, standard patterns, automated testing |
| **Source cluster access** | Job needs kubeconfig Secret | Document security best practices, use least-privilege RBAC |
| **Resource limits** | Transfer Job could OOM | Set default limits, allow user customization |
| **Breaking changes** | Existing CLI users disrupted | Maintain backward compatibility, CLI works as before |

---

## 10. Alternatives Considered

### Alternative 1: Keep CLI-Only, Add Remote Execution Option

```bash
# Run transfer from remote cluster via kubectl exec
kubectl exec -it crane-cli-pod -- \
    crane transfer-pvc --source-context=... --dest-context=...
```

**Pros:**
- No operator needed
- Simple to understand

**Cons:**
- ❌ No state persistence (Pod dies = lost progress)
- ❌ No CronJob for incremental sync
- ❌ Poor observability (logs only in Pod)
- ❌ Awkward credential management

**Verdict:** ❌ Not recommended - too hacky

---

### Alternative 2: Serverless Function (Knative)

Run transfer as a Knative Function triggered by CR creation.

**Pros:**
- Auto-scaling
- Pay-per-use model

**Cons:**
- ❌ Requires Knative (not standard)
- ❌ Complex setup
- ❌ Hard to debug long-running transfers
- ❌ Timeout limits

**Verdict:** ❌ Not recommended - too complex

---

### Alternative 3: Argo Workflows

Use Argo Workflows to orchestrate transfer steps.

**Pros:**
- Visual workflow
- Good for complex multi-step migrations

**Cons:**
- ❌ Requires Argo (not standard)
- ❌ Overkill for single transfer operation
- ❌ Steeper learning curve

**Verdict:** ⚠️ Could work, but Job is simpler for this use case

---

## 11. Conclusion

**Recommendation:** ✅ **Implement in-cluster execution via Kubernetes Job + CRD**

### Summary of Benefits:

1. **🚀 Faster & More Stable**
   - Direct cluster-to-cluster network
   - Survives local network issues
   - No laptop bandwidth bottleneck

2. **🔄 Enables EXTENSION Features**
   - B1.2: Incremental sync via CronJob
   - B1.3: Automated workload scaling
   - Better state management

3. **📊 Better Observability**
   - Kubernetes-native status
   - Metrics, events, logging
   - Standard kubectl commands

4. **🔒 More Secure & Auditable**
   - RBAC-controlled
   - Service Account auth for destination
   - Audit trail in K8s events

5. **⚡ Backward Compatible**
   - Existing CLI still works
   - Gradual migration path
   - `--submit` mode bridges both worlds

### Next Steps:

1. **Immediate:** Review this proposal with team
2. **Week 1-2:** Implement Phase 1 (CRD + basic controller)
3. **Week 3-4:** Implement Phase 2 (core functionality)
4. **Week 5-7:** Implement Phase 3 (EXTENSION features)
5. **Week 8:** Integrate with CLI (`--submit` mode)

### Success Metrics:

- ✅ 99%+ transfer reliability (vs current ~85% with CLI)
- ✅ Incremental sync works with <1min final cutover
- ✅ Users can submit transfer and disconnect laptop
- ✅ All 7 EXTENSION features implemented
- ✅ Backward compatible CLI still works

---

**Total Estimated Effort:** 8 weeks (2 developers)

**Priority:** 🔴 HIGH - Addresses critical stability and automation needs
