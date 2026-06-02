# Scenario 3: Cluster-Level Resources Migration

**Priority:** 3 - Cluster-Scoped Resource Handling  
**Goal:** Test migration of applications with cluster-level dependencies

## Objective

Validate that crane can:
1. Detect and export cluster-level resources referenced by namespace-scoped applications
2. Handle ClusterRoles, ClusterRoleBindings, CRDs, and other cluster-scoped resources
3. Provide clear guidance when cluster resources cannot be migrated
4. Successfully migrate applications with cluster-level dependencies (with cluster-admin)

## Test Application

An application that requires cluster-level resources:
- Custom Resource Definition (CRD)
- Custom Resources (CRs) using the CRD
- ClusterRole for cross-namespace access
- ClusterRoleBinding linking ServiceAccount to ClusterRole
- PriorityClass for pod scheduling
- StorageClass (if testing storage)

## Setup

### 1. Deploy Application with Cluster Dependencies

```bash
# Switch to source cluster with cluster-admin
kubectl config use-context <source-context>

# First, create cluster-level resources
# CRD for application configuration
cat <<EOF | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: appconfigs.example.com
spec:
  group: example.com
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              databaseUrl:
                type: string
              cacheSize:
                type: integer
              features:
                type: object
                x-kubernetes-preserve-unknown-fields: true
  scope: Namespaced
  names:
    plural: appconfigs
    singular: appconfig
    kind: AppConfig
    shortNames:
    - ac
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: app-cluster-viewer
spec:
  rules:
  - apiGroups: [""]
    resources: ["nodes", "namespaces"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["example.com"]
    resources: ["appconfigs"]
    verbs: ["get", "list", "watch", "create", "update"]
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: app-high-priority
value: 1000
globalDefault: false
description: "High priority for critical application pods"
EOF

# Wait for CRD to be established
kubectl wait --for condition=established --timeout=60s crd/appconfigs.example.com

# Now create namespace and namespace-scoped resources
kubectl create namespace app-with-cluster-deps

# Create ServiceAccount
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: app-with-cluster-deps
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: app-cluster-viewer-binding
subjects:
- kind: ServiceAccount
  name: app-service-account
  namespace: app-with-cluster-deps
roleRef:
  kind: ClusterRole
  name: app-cluster-viewer
  apiGroup: rbac.authorization.k8s.io
EOF

# Create Custom Resource using the CRD
cat <<EOF | kubectl apply -f -
apiVersion: example.com/v1
kind: AppConfig
metadata:
  name: production-config
  namespace: app-with-cluster-deps
spec:
  databaseUrl: "postgresql://db.example.com:5432/proddb"
  cacheSize: 1024
  features:
    enable_analytics: true
    enable_caching: true
    debug_mode: false
EOF

# Create application using cluster resources
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: app-with-cluster-deps
data:
  config.yaml: |
    app:
      name: cluster-aware-app
      version: "1.0"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: app-with-cluster-deps
  labels:
    app: cluster-aware
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cluster-aware
  template:
    metadata:
      labels:
        app: cluster-aware
    spec:
      serviceAccountName: app-service-account
      priorityClassName: app-high-priority
      containers:
      - name: app
        image: nginxinc/nginx-unprivileged:1.25
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: config
          mountPath: /etc/app
        env:
        - name: APP_CONFIG_NAME
          value: production-config
      volumes:
      - name: config
        configMap:
          name: app-config
---
apiVersion: v1
kind: Service
metadata:
  name: app-service
  namespace: app-with-cluster-deps
spec:
  selector:
    app: cluster-aware
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF

# Verify everything is running
kubectl wait --for=condition=ready pod -l app=cluster-aware -n app-with-cluster-deps --timeout=120s
kubectl get all,appconfig,sa -n app-with-cluster-deps
```

### 2. Document Cluster Dependencies

```bash
# List cluster-level resources
echo "=== Cluster-level resources referenced by app ==="

# ClusterRole
kubectl get clusterrole app-cluster-viewer

# ClusterRoleBinding
kubectl get clusterrolebinding app-cluster-viewer-binding

# CRD
kubectl get crd appconfigs.example.com

# PriorityClass
kubectl get priorityclass app-high-priority

# Verify application is using them
kubectl get pod -n app-with-cluster-deps -o yaml | grep -E "(serviceAccountName|priorityClassName)"
```

## Migration Test 1: Namespace-Only Export (Expected to Fail)

### Export Only Namespace

```bash
mkdir -p ~/crane-test-cluster-resources
cd ~/crane-test-cluster-resources

# Export only the namespace (default crane behavior)
crane export -n app-with-cluster-deps

# Inspect what was exported
ls -la export/resources/app-with-cluster-deps/

# Check if cluster resources were included
echo "=== Checking for cluster resources in export ==="
ls export/resources/app-with-cluster-deps/ | grep -i cluster
ls export/resources/app-with-cluster-deps/ | grep -i CustomResourceDefinition
ls export/resources/app-with-cluster-deps/ | grep -i PriorityClass
```

**Expected result:**
- Namespace-scoped resources exported (Deployment, Service, ConfigMap, AppConfig CR, ServiceAccount)
- Cluster-scoped resources NOT exported (ClusterRole, ClusterRoleBinding, CRD, PriorityClass)

**Document:**
- Which cluster resources were missing?
- Did crane warn about missing dependencies?

### Attempt Migration Without Cluster Resources

```bash
# Transform
crane transform

# Apply
crane apply

# Try to deploy to target cluster
kubectl config use-context <target-context>

# Create namespace
kubectl create namespace app-with-cluster-deps

# Try to apply
kubectl apply -f output/output.yaml
```

**Expected failures:**
- AppConfig CR fails (CRD not present)
- Deployment may fail or degrade:
  - ServiceAccount exists but ClusterRoleBinding missing (reduced permissions)
  - PriorityClass missing (defaults to priority 0)

**Document:**
- What errors occurred?
- Were error messages clear?
- Could you identify missing dependencies?

## Migration Test 2: Export with Cluster Resources

### Strategy A: Manual Cluster Resource Migration

```bash
# Back on source cluster
kubectl config use-context <source-context>

# Export cluster resources manually
mkdir -p cluster-resources

kubectl get crd appconfigs.example.com -o yaml > cluster-resources/crd-appconfigs.yaml
kubectl get clusterrole app-cluster-viewer -o yaml > cluster-resources/clusterrole.yaml
kubectl get clusterrolebinding app-cluster-viewer-binding -o yaml > cluster-resources/clusterrolebinding.yaml
kubectl get priorityclass app-high-priority -o yaml > cluster-resources/priorityclass.yaml

# Clean them manually or with crane transform
mkdir -p cluster-transform
cp cluster-resources/* cluster-transform/

# Review what needs cleaning
cat cluster-transform/crd-appconfigs.yaml | grep -E "(uid|resourceVersion|generation|creationTimestamp)"
```

**Question:** Should crane provide a flag to export cluster resources referenced by namespace?

### Strategy B: Crane Enhancement (if supported)

```bash
# If crane supports cluster resource export (test this)
crane export -n app-with-cluster-deps --include-cluster-resources

# Or
crane export -n app-with-cluster-deps --export-dependencies

# Check if it worked
ls -la export/resources/
```

**Document:**
- Does crane have this capability?
- If yes, does it work correctly?
- If no, should it be added?

### Clean Cluster Resources

```bash
# If exported manually, need to clean metadata
# Option 1: Use crane transform on cluster resources

# Create a transform directory for cluster resources
mkdir -p cluster-level-migration
mv cluster-resources cluster-level-migration/export-cluster

# Try running crane transform on cluster resources
cd cluster-level-migration
crane export # This won't work, just for directory structure

# Manual cleanup needed
for file in cluster-resources/*.yaml; do
  # Remove metadata fields
  yq eval 'del(.metadata.uid, .metadata.resourceVersion, .metadata.generation, .metadata.creationTimestamp, .metadata.managedFields)' "$file" > "cleaned-$(basename $file)"
done
```

**Document:**
- Was manual cleanup tedious?
- Should crane support cluster resource transformation?
- What's the expected workflow?

### Deploy Cluster Resources First

```bash
# Switch to target cluster
kubectl config use-context <target-context>

# Apply cluster resources first
kubectl apply -f cluster-resources/cleaned-crd-appconfigs.yaml
kubectl apply -f cluster-resources/cleaned-priorityclass.yaml
kubectl apply -f cluster-resources/cleaned-clusterrole.yaml

# Wait for CRD to be established
kubectl wait --for condition=established --timeout=60s crd/appconfigs.example.com

# Update ClusterRoleBinding for new cluster (namespace reference)
# Edit the cleaned file to ensure namespace exists
kubectl create namespace app-with-cluster-deps

# Apply ClusterRoleBinding
kubectl apply -f cluster-resources/cleaned-clusterrolebinding.yaml

# Now apply namespace resources
cd ~/crane-test-cluster-resources
kubectl apply -f output/output.yaml

# Verify
kubectl get all,appconfig -n app-with-cluster-deps
kubectl wait --for=condition=ready pod -l app=cluster-aware -n app-with-cluster-deps --timeout=120s
```

**Validation:**
- [ ] CRD created successfully
- [ ] Custom Resource (AppConfig) created
- [ ] PriorityClass applied to pods
- [ ] ClusterRole permissions working
- [ ] Application functional

## Migration Test 3: Detect Missing Cluster Dependencies

Test if crane validation can detect missing cluster-level dependencies.

```bash
# On source cluster, create app with cluster dependency
kubectl create namespace test-missing-deps

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-needs-priority
  namespace: test-missing-deps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      priorityClassName: app-high-priority  # References cluster resource
      containers:
      - name: app
        image: nginx:1.25
EOF

# Export
crane export -n test-missing-deps

# Transform
crane transform

# Apply
crane apply

# Now test validation against target cluster WITHOUT the PriorityClass
kubectl config use-context <target-context>

# Validate (if crane has validation)
crane validate -f output/output.yaml --context <target-context>

# Or manually
kubectl apply --dry-run=server -f output/output.yaml
```

**Expected:**
- Validation should detect missing PriorityClass
- Should provide clear error or warning
- Should suggest creating the PriorityClass

**Document:**
- Did crane detect missing cluster resources?
- Was the error message helpful?
- Did it suggest a fix?

## Test Cases Summary

### Test Case 1: Application with CRD
- [ ] CRD exported (manually or via crane)
- [ ] CRD cleaned and migrated
- [ ] Custom Resources migrate correctly
- [ ] Application works with CRs on target

### Test Case 2: Application with ClusterRole
- [ ] ClusterRole and ClusterRoleBinding exported
- [ ] Binding updated for target cluster namespace
- [ ] ServiceAccount has correct permissions
- [ ] Application functions with cluster permissions

### Test Case 3: Application with PriorityClass
- [ ] PriorityClass exported and cleaned
- [ ] Applied to target cluster
- [ ] Pods scheduled with correct priority
- [ ] Priority reflected in pod spec

### Test Case 4: Missing Dependency Detection
- [ ] Crane detects missing cluster resources
- [ ] Error messages are clear
- [ ] Provides actionable guidance

## Validation Checklist

### Export Phase
- [ ] Namespace resources exported correctly
- [ ] Custom Resources (using CRDs) exported
- [ ] ServiceAccounts exported
- [ ] Cluster resources identified (even if not exported)

### Transform Phase
- [ ] Namespace resources cleaned correctly
- [ ] Cluster resources cleaned (if exported)
- [ ] References to cluster resources preserved

### Validation Phase
- [ ] Missing cluster resources detected
- [ ] Clear error messages provided
- [ ] Recommendations actionable

### Deploy Phase
- [ ] Cluster resources can be migrated separately
- [ ] Namespace resources depend correctly on cluster resources
- [ ] Application functional after migration

## Expected Behavior

### What Crane Should Do

1. **Detection:**
   - Identify cluster resources referenced by namespace resources
   - List them in export summary or warning

2. **Guidance:**
   - Provide clear message: "This app requires cluster resources"
   - List required cluster resources
   - Document how to migrate them

3. **Export Options (ideal):**
   - `--include-cluster-resources`: Export referenced cluster resources
   - Separate directory for cluster vs namespace resources

4. **Transform:**
   - Clean cluster resources same as namespace resources
   - Preserve references between resources

5. **Validation:**
   - Check target cluster for required cluster resources
   - Warn if missing
   - Suggest creation steps

### What Should Be Documented

- How to identify cluster resource dependencies
- How to export cluster resources
- How to clean cluster resource metadata
- Order of operations (cluster resources first, then namespace)
- Permissions required (cluster-admin)
- When cluster resources cannot be migrated (platform-specific CRDs)

## Common Issues

1. **CRD Not Available on Target**
   - Custom platform CRDs (OpenShift BuildConfig, Route, etc.)
   - Should be documented as non-migratable
   - Alternative solutions suggested

2. **ClusterRoleBinding Namespace Reference**
   - Subject namespace might not exist yet
   - Need to create namespace first

3. **Conflicting Cluster Resources**
   - PriorityClass names collide
   - ClusterRole names collide
   - Need merge or rename strategy

4. **Insufficient Permissions**
   - User lacks cluster-admin
   - Should provide clear error
   - Suggest using cluster-admin or requesting IT

## Expected Results

✅ **Success:**
- Cluster resource dependencies identified
- Clear workflow for migrating cluster resources
- Validation detects missing dependencies
- Documentation covers cluster resource migration

⚠️ **Acceptable:**
- Cluster resources require manual export/clean/apply
- Separate workflow from namespace resources
- Requires cluster-admin privileges

❌ **Blocking:**
- Cluster resources not identified
- No guidance on migration
- Silent failures when dependencies missing
- No way to migrate cluster resources

## Key Questions to Answer

1. Does crane identify cluster resource dependencies?
2. Can crane export cluster resources (with flag)?
3. Does validation detect missing cluster resources?
4. Are error messages helpful and actionable?
5. Is the workflow documented?
6. What should happen for platform-specific cluster resources?

## Next Steps

- Document all cluster resource issues
- List resources that cannot be migrated (platform-specific)
- Suggest API improvements for cluster resource handling
- Continue to [Scenario 4: Validation Testing](./scenario-04-validation.md)
