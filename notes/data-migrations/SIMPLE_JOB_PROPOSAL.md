# Crane transfer-pvc as Kubernetes Job (No Operator)

**Date:** 2026-06-30  
**Requirement:** NO operator, NO CRD, just run crane as a simple Kubernetes Job

## Summary

✅ **YES, you can run `crane transfer-pvc` as a Kubernetes Job** without any operator or CRD complexity.

**Benefits:**
- 🚀 Faster & more stable (runs in cluster, not on laptop)
- 🔄 Survives network disconnects
- ⏰ Can use CronJob for incremental sync (EXTENSION B1.2)
- 📊 Standard Kubernetes observability (kubectl logs, kubectl get jobs)
- 🔒 RBAC-controlled

**No operator needed** - just a Job manifest and proper RBAC.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│         Destination Cluster                         │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  Kubernetes Job: crane-transfer-mydata       │  │
│  │                                              │  │
│  │  Container: quay.io/konveyor/crane:latest   │  │
│  │  Command: crane transfer-pvc \              │  │
│  │           --source-context=source \          │  │
│  │           --destination-context=dest \       │  │
│  │           --pvc-name=mydata \                │  │
│  │           --endpoint=route                   │  │
│  │                                              │  │
│  │  Uses:                                       │  │
│  │  - ServiceAccount: crane-transfer           │  │
│  │  - Secret: source-cluster-kubeconfig         │  │
│  │  - In-cluster config for destination         │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  Creates (via crane CLI):                          │
│  - rsync server Pod                                │
│  - stunnel server Pod                              │
│  - Route/Ingress endpoint                          │
│  - Secrets (TLS certs)                             │
└─────────────────────────────────────────────────────┘
                        │
                        │ Connects to source
                        ▼
              ┌───────────────────┐
              │  Source Cluster   │
              │                   │
              │  - rsync client   │
              │    Pod            │
              └───────────────────┘
```

---

## 1. Basic Job Example

### 1.1 Create Secret with Source Kubeconfig

```bash
# Get source cluster kubeconfig
kubectl --context=source-cluster config view --raw --minify > /tmp/source-kubeconfig.yaml

# Create Secret in destination cluster
kubectl --context=dest-cluster create secret generic source-cluster-kubeconfig \
  --from-file=kubeconfig=/tmp/source-kubeconfig.yaml \
  -n crane-transfers

# Clean up local file
rm /tmp/source-kubeconfig.yaml
```

### 1.2 Create ServiceAccount and RBAC

```yaml
# rbac.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: crane-transfers
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: crane-transfer
  namespace: crane-transfers
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
  
  # Manage Pods (rsync, stunnel)
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "create", "delete", "watch"]
  
  # Manage Services
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "create", "delete"]
  
  # Manage Secrets (TLS certs)
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "create", "delete"]
  
  # Manage ConfigMaps
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "create", "delete"]
  
  # Manage Routes (OpenShift)
  - apiGroups: ["route.openshift.io"]
    resources: ["routes"]
    verbs: ["get", "list", "create", "delete"]
  
  # Manage Ingresses
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "create", "delete"]
  
  # Read namespaces (for security context)
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get"]
  
  # Read cluster config (OpenShift ingress domain)
  - apiGroups: ["config.openshift.io"]
    resources: ["ingresses"]
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
    namespace: crane-transfers
```

Apply:
```bash
kubectl apply -f rbac.yaml
```

### 1.3 Create Job Manifest

```yaml
# transfer-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: crane-transfer-postgres-data
  namespace: crane-transfers
spec:
  # Retry on failure
  backoffLimit: 3
  
  # Keep completed Job for 1 hour for log inspection
  ttlSecondsAfterFinished: 3600
  
  template:
    metadata:
      labels:
        app: crane-transfer
        transfer: postgres-data
    spec:
      serviceAccountName: crane-transfer
      restartPolicy: OnFailure
      
      containers:
      - name: crane
        image: quay.io/konveyor/crane:latest
        
        command:
        - /bin/bash
        - -c
        - |
          set -e
          
          # Setup kubeconfig with both contexts
          mkdir -p /tmp/kubeconfig
          
          # Copy source kubeconfig
          cp /secrets/source-kubeconfig/kubeconfig /tmp/kubeconfig/source
          
          # Get in-cluster config for destination
          # (automatically available as /var/run/secrets/kubernetes.io/serviceaccount/...)
          
          # Merge configs
          export KUBECONFIG=/tmp/kubeconfig/source:/tmp/kubeconfig/dest
          
          # Create dest context using in-cluster credentials
          kubectl config set-cluster dest-cluster \
            --server=https://kubernetes.default.svc \
            --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          
          kubectl config set-credentials dest-sa \
            --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
          
          kubectl config set-context dest \
            --cluster=dest-cluster \
            --user=dest-sa
          
          # Run crane transfer
          crane transfer-pvc \
            --source-context=source \
            --destination-context=dest \
            --pvc-name=postgres-data \
            --pvc-namespace=database \
            --endpoint=route \
            --verify \
            --bandwidth-limit=100M
        
        volumeMounts:
        - name: source-kubeconfig
          mountPath: /secrets/source-kubeconfig
          readOnly: true
        
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
      
      volumes:
      - name: source-kubeconfig
        secret:
          secretName: source-cluster-kubeconfig
```

### 1.4 Run the Job

```bash
# Apply the Job
kubectl apply -f transfer-job.yaml

# Watch Job status
kubectl get job crane-transfer-postgres-data -w

# View logs
kubectl logs -f job/crane-transfer-postgres-data

# Check if successful
kubectl get job crane-transfer-postgres-data -o jsonpath='{.status.succeeded}'
```

---

## 2. Incremental Sync with CronJob (EXTENSION B1.2)

For incremental sync, use a **CronJob** that runs every N minutes:

```yaml
# transfer-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: crane-transfer-incremental-ml-data
  namespace: crane-transfers
spec:
  # Run every 30 minutes
  schedule: "*/30 * * * *"
  
  # Keep last 3 successful and 1 failed Job
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  
  jobTemplate:
    spec:
      backoffLimit: 2
      ttlSecondsAfterFinished: 1800  # 30 minutes
      
      template:
        metadata:
          labels:
            app: crane-transfer
            transfer: ml-training-data
            mode: incremental
        spec:
          serviceAccountName: crane-transfer
          restartPolicy: OnFailure
          
          containers:
          - name: crane
            image: quay.io/konveyor/crane:latest
            
            command:
            - /bin/bash
            - -c
            - |
              set -e
              
              # Setup kubeconfig
              mkdir -p /tmp/kubeconfig
              cp /secrets/source-kubeconfig/kubeconfig /tmp/kubeconfig/source
              
              kubectl config set-cluster dest-cluster \
                --server=https://kubernetes.default.svc \
                --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              
              kubectl config set-credentials dest-sa \
                --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
              
              kubectl config set-context dest \
                --cluster=dest-cluster \
                --user=dest-sa
              
              export KUBECONFIG=/tmp/kubeconfig/source:/tmp/kubeconfig/dest
              
              # Incremental sync (rsync will only transfer changes)
              crane transfer-pvc \
                --source-context=source \
                --destination-context=dest \
                --pvc-name=ml-training-data \
                --pvc-namespace=ml-workloads \
                --endpoint=route \
                --bandwidth-limit=500M \
                --enable-compression
              
              echo "Incremental sync completed at $(date)"
            
            volumeMounts:
            - name: source-kubeconfig
              mountPath: /secrets/source-kubeconfig
              readOnly: true
          
          volumes:
          - name: source-kubeconfig
            secret:
              secretName: source-cluster-kubeconfig
```

**Apply:**
```bash
kubectl apply -f transfer-cronjob.yaml

# Watch CronJob
kubectl get cronjob crane-transfer-incremental-ml-data

# See last runs
kubectl get jobs -l transfer=ml-training-data

# View logs from latest run
kubectl logs -l transfer=ml-training-data --tail=100
```

**When ready to finalize:**
```bash
# 1. Suspend the CronJob (stop incremental syncs)
kubectl patch cronjob crane-transfer-incremental-ml-data \
  -p '{"spec":{"suspend":true}}'

# 2. Run final sync with source scaled down
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: crane-transfer-ml-data-final
  namespace: crane-transfers
spec:
  backoffLimit: 1
  template:
    spec:
      serviceAccountName: crane-transfer
      restartPolicy: Never
      containers:
      - name: crane
        image: quay.io/konveyor/crane:latest
        command:
        - /bin/bash
        - -c
        - |
          set -e
          
          # Setup kubeconfig (same as before)
          mkdir -p /tmp/kubeconfig
          cp /secrets/source-kubeconfig/kubeconfig /tmp/kubeconfig/source
          
          kubectl config set-cluster dest-cluster \
            --server=https://kubernetes.default.svc \
            --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          
          kubectl config set-credentials dest-sa \
            --token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
          
          kubectl config set-context dest \
            --cluster=dest-cluster \
            --user=dest-sa
          
          export KUBECONFIG=/tmp/kubeconfig/source:/tmp/kubeconfig/dest
          
          # Scale down source workload
          kubectl --context=source scale deployment ml-training \
            --namespace=ml-workloads --replicas=0
          
          # Wait for pods to terminate
          kubectl --context=source wait --for=delete pod \
            -l app=ml-training \
            --namespace=ml-workloads \
            --timeout=300s || true
          
          # Final sync
          crane transfer-pvc \
            --source-context=source \
            --destination-context=dest \
            --pvc-name=ml-training-data \
            --pvc-namespace=ml-workloads \
            --endpoint=route \
            --verify
          
          echo "Final sync completed!"
          
          # Optionally: scale up target
          # kubectl --context=dest scale deployment ml-training \
          #   --namespace=ml-workloads --replicas=3
        
        volumeMounts:
        - name: source-kubeconfig
          mountPath: /secrets/source-kubeconfig
          readOnly: true
      
      volumes:
      - name: source-kubeconfig
        secret:
          secretName: source-cluster-kubeconfig
EOF
```

---

## 3. Helper Script for Easy Job Creation

Create a helper script that generates Job YAML:

```bash
#!/bin/bash
# generate-transfer-job.sh

set -e

# Parse arguments
SOURCE_CONTEXT=""
DEST_CONTEXT="dest"  # Always use in-cluster for destination
PVC_NAME=""
PVC_NAMESPACE=""
STORAGE_CLASS=""
ENDPOINT_TYPE="route"
BANDWIDTH_LIMIT=""
VERIFY=false
MODE="one-shot"  # or "incremental"
CRON_SCHEDULE="*/30 * * * *"

while [[ $# -gt 0 ]]; do
  case $1 in
    --source-context)
      SOURCE_CONTEXT="$2"
      shift 2
      ;;
    --pvc-name)
      PVC_NAME="$2"
      shift 2
      ;;
    --pvc-namespace)
      PVC_NAMESPACE="$2"
      shift 2
      ;;
    --dest-storage-class)
      STORAGE_CLASS="$2"
      shift 2
      ;;
    --endpoint)
      ENDPOINT_TYPE="$2"
      shift 2
      ;;
    --bandwidth-limit)
      BANDWIDTH_LIMIT="$2"
      shift 2
      ;;
    --verify)
      VERIFY=true
      shift
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --cron-schedule)
      CRON_SCHEDULE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required args
if [[ -z "$SOURCE_CONTEXT" ]] || [[ -z "$PVC_NAME" ]]; then
  echo "Usage: $0 --source-context=<ctx> --pvc-name=<name> [options]"
  echo ""
  echo "Required:"
  echo "  --source-context        Source cluster context name"
  echo "  --pvc-name             PVC name to transfer"
  echo ""
  echo "Optional:"
  echo "  --pvc-namespace        PVC namespace (default: current namespace)"
  echo "  --dest-storage-class   Destination storage class"
  echo "  --endpoint            Endpoint type: route or nginx-ingress (default: route)"
  echo "  --bandwidth-limit     Bandwidth limit (e.g., 100M)"
  echo "  --verify              Enable checksum verification"
  echo "  --mode                Transfer mode: one-shot or incremental (default: one-shot)"
  echo "  --cron-schedule       Cron schedule for incremental mode (default: */30 * * * *)"
  exit 1
fi

# Build crane command
CRANE_CMD="crane transfer-pvc"
CRANE_CMD="$CRANE_CMD --source-context=source"
CRANE_CMD="$CRANE_CMD --destination-context=dest"
CRANE_CMD="$CRANE_CMD --pvc-name=$PVC_NAME"

if [[ -n "$PVC_NAMESPACE" ]]; then
  CRANE_CMD="$CRANE_CMD --pvc-namespace=$PVC_NAMESPACE"
fi

if [[ -n "$STORAGE_CLASS" ]]; then
  CRANE_CMD="$CRANE_CMD --dest-storage-class=$STORAGE_CLASS"
fi

CRANE_CMD="$CRANE_CMD --endpoint=$ENDPOINT_TYPE"

if [[ -n "$BANDWIDTH_LIMIT" ]]; then
  CRANE_CMD="$CRANE_CMD --bandwidth-limit=$BANDWIDTH_LIMIT"
fi

if [[ "$VERIFY" == "true" ]]; then
  CRANE_CMD="$CRANE_CMD --verify"
fi

# Generate Job or CronJob YAML
if [[ "$MODE" == "incremental" ]]; then
  # Generate CronJob
  cat <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: crane-transfer-${PVC_NAME}
  namespace: crane-transfers
spec:
  schedule: "$CRON_SCHEDULE"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 2
      ttlSecondsAfterFinished: 1800
      template:
        metadata:
          labels:
            app: crane-transfer
            transfer: ${PVC_NAME}
            mode: incremental
        spec:
          serviceAccountName: crane-transfer
          restartPolicy: OnFailure
          containers:
          - name: crane
            image: quay.io/konveyor/crane:latest
            command:
            - /bin/bash
            - -c
            - |
              set -e
              mkdir -p /tmp/kubeconfig
              cp /secrets/source-kubeconfig/kubeconfig /tmp/kubeconfig/source
              
              kubectl config set-cluster dest-cluster \\
                --server=https://kubernetes.default.svc \\
                --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              kubectl config set-credentials dest-sa \\
                --token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
              kubectl config set-context dest \\
                --cluster=dest-cluster --user=dest-sa
              
              export KUBECONFIG=/tmp/kubeconfig/source:/tmp/kubeconfig/dest
              
              $CRANE_CMD
              
              echo "Incremental sync completed at \$(date)"
            volumeMounts:
            - name: source-kubeconfig
              mountPath: /secrets/source-kubeconfig
              readOnly: true
            resources:
              requests:
                cpu: 100m
                memory: 256Mi
              limits:
                cpu: 500m
                memory: 1Gi
          volumes:
          - name: source-kubeconfig
            secret:
              secretName: source-cluster-kubeconfig
EOF
else
  # Generate one-shot Job
  cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: crane-transfer-${PVC_NAME}
  namespace: crane-transfers
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app: crane-transfer
        transfer: ${PVC_NAME}
        mode: one-shot
    spec:
      serviceAccountName: crane-transfer
      restartPolicy: OnFailure
      containers:
      - name: crane
        image: quay.io/konveyor/crane:latest
        command:
        - /bin/bash
        - -c
        - |
          set -e
          mkdir -p /tmp/kubeconfig
          cp /secrets/source-kubeconfig/kubeconfig /tmp/kubeconfig/source
          
          kubectl config set-cluster dest-cluster \\
            --server=https://kubernetes.default.svc \\
            --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          kubectl config set-credentials dest-sa \\
            --token=\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
          kubectl config set-context dest \\
            --cluster=dest-cluster --user=dest-sa
          
          export KUBECONFIG=/tmp/kubeconfig/source:/tmp/kubeconfig/dest
          
          $CRANE_CMD
          
          echo "Transfer completed successfully!"
        volumeMounts:
        - name: source-kubeconfig
          mountPath: /secrets/source-kubeconfig
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 1Gi
      volumes:
      - name: source-kubeconfig
        secret:
          secretName: source-cluster-kubeconfig
EOF
fi
```

**Usage:**
```bash
chmod +x generate-transfer-job.sh

# Generate one-shot Job
./generate-transfer-job.sh \
  --source-context=prod \
  --pvc-name=postgres-data \
  --pvc-namespace=database \
  --endpoint=route \
  --verify \
  --bandwidth-limit=100M > job.yaml

kubectl apply -f job.yaml

# Generate incremental CronJob (every 30 min)
./generate-transfer-job.sh \
  --source-context=prod \
  --pvc-name=ml-data \
  --mode=incremental \
  --cron-schedule="*/30 * * * *" \
  --bandwidth-limit=500M > cronjob.yaml

kubectl apply -f cronjob.yaml
```

---

## 4. Monitoring & Observability

### 4.1 Check Job Status

```bash
# List all transfer Jobs
kubectl get jobs -n crane-transfers -l app=crane-transfer

# Get specific Job status
kubectl get job crane-transfer-postgres-data -n crane-transfers -o yaml

# Check if Job succeeded
kubectl get job crane-transfer-postgres-data -n crane-transfers \
  -o jsonpath='{.status.succeeded}'

# Check for failures
kubectl get job crane-transfer-postgres-data -n crane-transfers \
  -o jsonpath='{.status.failed}'
```

### 4.2 View Logs

```bash
# Follow logs in real-time
kubectl logs -f job/crane-transfer-postgres-data -n crane-transfers

# Get last 100 lines
kubectl logs job/crane-transfer-postgres-data -n crane-transfers --tail=100

# For CronJob, get logs from latest run
kubectl logs -n crane-transfers \
  -l transfer=ml-training-data \
  --tail=100
```

### 4.3 Check Created Resources

The crane Job will create several resources in the destination cluster:

```bash
# Check rsync/stunnel Pods
kubectl get pods -n <target-namespace> \
  -l app.kubernetes.io/name=crane,app.kubernetes.io/component=transfer-pvc

# Check endpoint (Route or Ingress)
kubectl get routes -n <target-namespace> -l app.kubernetes.io/name=crane
# OR
kubectl get ingress -n <target-namespace> -l app.kubernetes.io/name=crane

# Check Secrets (TLS certs)
kubectl get secrets -n <target-namespace> -l app.kubernetes.io/name=crane

# Check destination PVC
kubectl get pvc -n <target-namespace>
```

### 4.4 Cleanup

```bash
# Delete the Job (and its Pods)
kubectl delete job crane-transfer-postgres-data -n crane-transfers

# Delete CronJob (stops future runs)
kubectl delete cronjob crane-transfer-incremental-ml-data -n crane-transfers

# Cleanup created resources (if transfer failed and cleanup didn't run)
# These are normally cleaned up by crane automatically
kubectl delete pods,services,secrets,routes,ingresses -n <target-namespace> \
  -l app.kubernetes.io/name=crane,app.kubernetes.io/component=transfer-pvc
```

---

## 5. Advantages vs CLI on Laptop

| Feature | Laptop CLI | Kubernetes Job | Winner |
|---------|-----------|----------------|--------|
| **Stability** | ❌ Dies on disconnect | ✅ Survives network issues | 🏆 Job |
| **Speed** | ⚠️ Limited by laptop network | ✅ Direct cluster network | 🏆 Job |
| **Requires laptop on** | ❌ Must stay on for hours | ✅ Can close laptop | 🏆 Job |
| **Incremental sync** | ⚠️ Manual cron on laptop | ✅ Native CronJob | 🏆 Job |
| **Observability** | ⚠️ Only terminal | ✅ kubectl logs, events | 🏆 Job |
| **Multi-user** | ⚠️ One at a time | ✅ Parallel Jobs | 🏆 Job |
| **RBAC control** | ❌ Hard to audit | ✅ K8s RBAC | 🏆 Job |
| **Retry on failure** | ⚠️ Manual | ✅ Automatic (backoffLimit) | 🏆 Job |
| **Setup complexity** | ✅ Just install CLI | ⚠️ Need RBAC + Secret | 🏆 CLI |
| **Quick testing** | ✅ Very fast | ⚠️ Need to create YAML | 🏆 CLI |

**Recommendation:**
- **Use laptop CLI** for: quick tests, development, demos
- **Use Kubernetes Job** for: production migrations, long transfers, automated syncs

---

## 6. Code Changes Needed in crane

### 6.1 Support In-Cluster Config for Destination

Currently crane uses `--source-context` and `--destination-context` which read from kubeconfig.

**Add support for in-cluster config:**

```go
// cmd/transfer-pvc/transfer-pvc.go

func (t *TransferPVCCommand) getRestConfigFromContext(ctx string) (*rest.Config, error) {
    // NEW: Check if context name is special "in-cluster" value
    if ctx == "in-cluster" || ctx == "" {
        // Use in-cluster config
        return rest.InClusterConfig()
    }
    
    // Existing code for kubeconfig contexts
    c := ctx
    t.configFlags.Context = &c
    return t.configFlags.ToRESTConfig()
}
```

**Usage in Job:**
```bash
# Can now use:
crane transfer-pvc \
  --source-context=source \
  --destination-context=in-cluster \  # Uses ServiceAccount
  --pvc-name=mydata
```

### 6.2 Add Environment Variable Support

```go
// cmd/transfer-pvc/transfer-pvc.go

func addFlagsToTransferPVCCommand(c *Flags, cmd *cobra.Command) {
    // Existing flags...
    
    // NEW: Allow env var overrides for Job-friendly usage
    cmd.Flags().StringVar(&c.SourceContext, "source-context", 
        os.Getenv("CRANE_SOURCE_CONTEXT"), 
        "Name of the source context")
    
    cmd.Flags().StringVar(&c.DestinationContext, "destination-context", 
        getEnvOrDefault("CRANE_DEST_CONTEXT", "in-cluster"),
        "Name of the destination context (default: in-cluster)")
    
    // ... rest of flags
}
```

**Usage in Job:**
```yaml
env:
  - name: CRANE_SOURCE_CONTEXT
    value: source
  - name: CRANE_DEST_CONTEXT
    value: in-cluster
  - name: CRANE_PVC_NAME
    value: postgres-data
```

### 6.3 Add Job Template Generator Command

```go
// cmd/generate-job/generate-job.go

func NewGenerateJobCommand() *cobra.Command {
    cmd := &cobra.Command{
        Use:   "generate-job",
        Short: "Generate Kubernetes Job YAML for transfer-pvc",
        RunE: func(cmd *cobra.Command, args []string) error {
            // Parse flags (same as transfer-pvc)
            // Generate Job YAML to stdout
            return generateJobYAML(...)
        },
    }
    
    // Add same flags as transfer-pvc
    addFlagsToTransferPVCCommand(&flags, cmd)
    
    // Additional Job-specific flags
    cmd.Flags().StringVar(&jobName, "job-name", "", "Kubernetes Job name")
    cmd.Flags().StringVar(&namespace, "namespace", "crane-transfers", "Namespace for Job")
    cmd.Flags().BoolVar(&cronJob, "cron-job", false, "Generate CronJob instead of Job")
    cmd.Flags().StringVar(&schedule, "schedule", "*/30 * * * *", "Cron schedule (if --cron-job)")
    
    return cmd
}
```

**Usage:**
```bash
# Generate Job YAML
crane generate-job \
  --source-context=prod \
  --pvc-name=postgres-data \
  --endpoint=route \
  --verify > job.yaml

kubectl apply -f job.yaml

# Generate CronJob YAML
crane generate-job \
  --cron-job \
  --schedule="*/30 * * * *" \
  --source-context=prod \
  --pvc-name=ml-data > cronjob.yaml

kubectl apply -f cronjob.yaml
```

---

## 7. Complete Example: Production Migration

### Step 1: Setup (one-time)

```bash
# 1. Create namespace
kubectl create namespace crane-transfers

# 2. Apply RBAC
kubectl apply -f rbac.yaml

# 3. Create Secret with source kubeconfig
kubectl config view --raw --minify --context=prod-cluster > /tmp/source.yaml
kubectl create secret generic source-cluster-kubeconfig \
  --from-file=kubeconfig=/tmp/source.yaml \
  -n crane-transfers
rm /tmp/source.yaml
```

### Step 2: Start Incremental Sync

```bash
# Generate CronJob for incremental sync every 30 min
cat > cronjob.yaml <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: crane-sync-ecommerce-db
  namespace: crane-transfers
spec:
  schedule: "*/30 * * * *"
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 2
      ttlSecondsAfterFinished: 1800
      template:
        spec:
          serviceAccountName: crane-transfer
          restartPolicy: OnFailure
          containers:
          - name: crane
            image: quay.io/konveyor/crane:latest
            command:
            - /bin/bash
            - -c
            - |
              set -e
              
              # Setup kubeconfig
              mkdir -p /tmp/kubeconfig
              cp /secrets/source-kubeconfig/kubeconfig /tmp/kubeconfig/source
              
              kubectl config set-cluster dest \
                --server=https://kubernetes.default.svc \
                --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
              kubectl config set-credentials dest-sa \
                --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
              kubectl config set-context dest \
                --cluster=dest --user=dest-sa
              
              export KUBECONFIG=/tmp/kubeconfig/source:/tmp/kubeconfig/dest
              
              # Incremental sync
              crane transfer-pvc \
                --source-context=source \
                --destination-context=dest \
                --pvc-name=postgres-data \
                --pvc-namespace=ecommerce \
                --dest-storage-class=fast-ssd \
                --endpoint=route \
                --bandwidth-limit=200M \
                --enable-compression
              
              echo "Sync #$(date +%s) completed at $(date)"
            
            volumeMounts:
            - name: source-kubeconfig
              mountPath: /secrets/source-kubeconfig
              readOnly: true
            resources:
              requests:
                cpu: 200m
                memory: 512Mi
              limits:
                cpu: 1000m
                memory: 2Gi
          
          volumes:
          - name: source-kubeconfig
            secret:
              secretName: source-cluster-kubeconfig
EOF

kubectl apply -f cronjob.yaml
```

### Step 3: Monitor Incremental Syncs

```bash
# Watch CronJob
kubectl get cronjob crane-sync-ecommerce-db -n crane-transfers -w

# Check recent sync Jobs
kubectl get jobs -n crane-transfers -l transfer=ecommerce-db --sort-by=.metadata.creationTimestamp

# View logs from last sync
LAST_JOB=$(kubectl get jobs -n crane-transfers -l transfer=ecommerce-db \
  --sort-by=.metadata.creationTimestamp -o name | tail -1)
kubectl logs -n crane-transfers $LAST_JOB
```

### Step 4: Final Cutover

When ready for final migration:

```bash
# 1. Stop incremental sync
kubectl patch cronjob crane-sync-ecommerce-db -n crane-transfers \
  -p '{"spec":{"suspend":true}}'

# 2. Run final sync with source scaled down
cat > final-sync.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: crane-final-ecommerce-db
  namespace: crane-transfers
spec:
  backoffLimit: 1
  template:
    spec:
      serviceAccountName: crane-transfer
      restartPolicy: Never
      containers:
      - name: crane
        image: quay.io/konveyor/crane:latest
        command:
        - /bin/bash
        - -c
        - |
          set -e
          
          # Setup kubeconfig
          mkdir -p /tmp/kubeconfig
          cp /secrets/source-kubeconfig/kubeconfig /tmp/kubeconfig/source
          
          kubectl config set-cluster dest \
            --server=https://kubernetes.default.svc \
            --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          kubectl config set-credentials dest-sa \
            --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
          kubectl config set-context dest \
            --cluster=dest --user=dest-sa
          
          export KUBECONFIG=/tmp/kubeconfig/source:/tmp/kubeconfig/dest
          
          echo "==> Scaling down source application..."
          kubectl --context=source scale deployment ecommerce-api \
            -n ecommerce --replicas=0
          
          echo "==> Waiting for pods to terminate..."
          kubectl --context=source wait --for=delete pod \
            -l app=ecommerce-api -n ecommerce --timeout=300s || true
          
          echo "==> Running final sync with verification..."
          crane transfer-pvc \
            --source-context=source \
            --destination-context=dest \
            --pvc-name=postgres-data \
            --pvc-namespace=ecommerce \
            --dest-storage-class=fast-ssd \
            --endpoint=route \
            --verify
          
          echo "==> Final sync completed!"
          echo "==> You can now start the application on destination cluster"
        
        volumeMounts:
        - name: source-kubeconfig
          mountPath: /secrets/source-kubeconfig
          readOnly: true
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 2Gi
      
      volumes:
      - name: source-kubeconfig
        secret:
          secretName: source-cluster-kubeconfig
EOF

kubectl apply -f final-sync.yaml

# 3. Watch final sync
kubectl logs -f job/crane-final-ecommerce-db -n crane-transfers

# 4. When complete, start app on destination
kubectl --context=dest-cluster scale deployment ecommerce-api \
  -n ecommerce --replicas=3
```

---

## 8. Summary

### ✅ What You Get (No Operator Required)

1. **Stable in-cluster execution**
   - Transfer runs in destination cluster
   - Survives laptop disconnect
   - Uses cluster's faster network

2. **Native Kubernetes features**
   - `Job` for one-shot transfers
   - `CronJob` for incremental sync (EXTENSION B1.2)
   - `backoffLimit` for automatic retry
   - `ttlSecondsAfterFinished` for cleanup

3. **Standard observability**
   - `kubectl get jobs`
   - `kubectl logs`
   - Kubernetes events
   - No custom operators needed

4. **RBAC control**
   - ServiceAccount-based auth
   - ClusterRole defines permissions
   - Auditable via K8s audit logs

### 📋 Changes Needed in crane

**Minimal changes:**
1. Support `--destination-context=in-cluster` (uses ServiceAccount)
2. Optional: Add `crane generate-job` command for convenience
3. Optional: Environment variable support for flags

**Estimated effort:** 1-2 days

### 🎯 Recommendation

**YES, absolutely run crane as a Kubernetes Job!**

**Benefits:**
- ✅ Much more stable than laptop
- ✅ Faster (direct cluster network)
- ✅ Enables incremental sync (CronJob)
- ✅ No operator complexity
- ✅ Standard Kubernetes primitives
- ✅ Easy to implement (minimal crane changes)

**Use Cases:**
- **Job:** One-shot production migrations
- **CronJob:** Incremental sync for large datasets
- **CLI (laptop):** Quick testing, development

This gives you all the benefits of in-cluster execution **without the complexity of an operator**.
