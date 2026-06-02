# Scenario 4: Validation Testing

**Priority:** 4 - Validation Features  
**Duration:** ~45 minutes  
**Goal:** Test crane's validation capabilities and error reporting

## Objective

Validate that crane:
1. Detects incompatible resources before deployment
2. Validates against target cluster API
3. Reports missing dependencies clearly
4. Provides actionable error messages and recommendations
5. Catches common migration issues

## Test Cases

### Test Case 1: API Version Compatibility

Test validation of deprecated/removed API versions.

#### Setup

```bash
# Create namespace on source cluster
kubectl config use-context <source-context>
kubectl create namespace validation-test

# Deploy app using deprecated API (if applicable to your K8s version)
# Example: networking.k8s.io/v1beta1 Ingress (deprecated in 1.19, removed in 1.22)

# For testing, we'll simulate by creating resources with different versions
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-version-test
  namespace: validation-test
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
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
EOF
```

#### Migration and Validation

```bash
mkdir -p ~/crane-test-validation
cd ~/crane-test-validation

# Export
crane export -n validation-test

# Transform
crane transform

# Apply
crane apply

# Validate against target cluster
kubectl config use-context <target-context>

# Test crane validation (if command exists)
crane validate -f output/output.yaml

# Or use kubectl validation
kubectl apply --dry-run=server -f output/output.yaml

# Test with cluster that doesn't support the API version
# (e.g., if source is K8s 1.25 with v1beta1 resources, target is 1.30 without v1beta1)
```

**Expected:**
- Validation detects API version incompatibility
- Clear error message about which resource and API version
- Recommendation to upgrade API version

**Document:**
- Did crane detect API version issues?
- Was error message clear?
- Did it suggest a fix?

### Test Case 2: Missing Custom Resource Definitions

Test detection of missing CRDs.

#### Setup

```bash
# On source cluster with existing CRD from Scenario 3
kubectl config use-context <source-context>
kubectl create namespace validation-crd-test

# Create Custom Resource
cat <<EOF | kubectl apply -f -
apiVersion: example.com/v1
kind: AppConfig
metadata:
  name: test-config
  namespace: validation-crd-test
spec:
  databaseUrl: "postgresql://localhost:5432/testdb"
  cacheSize: 512
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: validation-crd-test
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
      containers:
      - name: app
        image: nginx:1.25
EOF
```

#### Migration and Validation

```bash
cd ~/crane-test-validation

# Export
crane export -n validation-crd-test -e export-crd

# Transform
crane transform -e export-crd -t transform-crd

# Apply
crane apply -t transform-crd -o output-crd

# Validate against target cluster WITHOUT the CRD
kubectl config use-context <target-context>

# Run validation
crane validate -f output-crd/output.yaml

# Or
kubectl apply --dry-run=server -f output-crd/output.yaml
```

**Expected:**
- Validation fails for AppConfig resource
- Error: "no matches for kind AppConfig in version example.com/v1"
- Recommendation: Install CRD first

**Document:**
- Did crane detect missing CRD?
- Was error clear about what's missing?
- Did it recommend installing CRD?

### Test Case 3: Resource Quota and Limit Violations

Test validation against cluster resource constraints.

#### Setup on Target Cluster

```bash
# On target cluster, create namespace with quotas
kubectl config use-context <target-context>
kubectl create namespace validation-quota-test

# Set resource quota
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: validation-quota-test
spec:
  hard:
    requests.cpu: "2"
    requests.memory: "4Gi"
    limits.cpu: "4"
    limits.memory: "8Gi"
    pods: "5"
EOF

# Set limit range
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: resource-limits
  namespace: validation-quota-test
spec:
  limits:
  - max:
      cpu: "1"
      memory: "2Gi"
    min:
      cpu: "100m"
      memory: "128Mi"
    type: Container
EOF
```

#### Create App That Violates Quota

```bash
# On source cluster
kubectl config use-context <source-context>
kubectl create namespace validation-quota-test

# Deploy app that would exceed quota
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-heavy
  namespace: validation-quota-test
spec:
  replicas: 10  # Would exceed pod quota of 5
  selector:
    matchLabels:
      app: heavy
  template:
    metadata:
      labels:
        app: heavy
    spec:
      containers:
      - name: app
        image: nginx:1.25
        resources:
          requests:
            cpu: "500m"
            memory: "1Gi"
          limits:
            cpu: "2"  # Exceeds max per container (1)
            memory: "3Gi"  # Exceeds max per container (2Gi)
EOF
```

#### Migration and Validation

```bash
cd ~/crane-test-validation

# Export
crane export -n validation-quota-test -e export-quota

# Transform
crane transform -e export-quota -t transform-quota

# Apply
crane apply -t transform-quota -o output-quota

# Validate against target with quotas
kubectl config use-context <target-context>

crane validate -f output-quota/output.yaml --namespace validation-quota-test

# Or
kubectl apply --dry-run=server -f output-quota/output.yaml
```

**Expected:**
- Validation detects quota violations
- Error about exceeding ResourceQuota
- Error about exceeding LimitRange
- Clear messages about what to fix

**Document:**
- Did validation catch quota violations?
- Were error messages helpful?
- Did it suggest specific fixes (reduce replicas, reduce limits)?

### Test Case 4: Storage Class Availability

Test validation of storage resources.

#### Setup

```bash
# On source cluster
kubectl config use-context <source-context>
kubectl create namespace validation-storage-test

# Create PVC with specific storage class
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: validation-storage-test
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: premium-ssd  # May not exist on target
  resources:
    requests:
      storage: 10Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-storage
  namespace: validation-storage-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: storage-app
  template:
    metadata:
      labels:
        app: storage-app
    spec:
      containers:
      - name: app
        image: nginx:1.25
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: app-data
EOF
```

#### Migration and Validation

```bash
cd ~/crane-test-validation

# Export
crane export -n validation-storage-test -e export-storage

# Transform
crane transform -e export-storage -t transform-storage

# Apply
crane apply -t transform-storage -o output-storage

# Check storage classes on target
kubectl config use-context <target-context>
kubectl get storageclass

# Validate
crane validate -f output-storage/output.yaml

# Or
kubectl apply --dry-run=server -f output-storage/output.yaml
```

**Expected:**
- Validation checks if StorageClass "premium-ssd" exists
- If missing, clear error message
- Recommendation: change to available StorageClass or create it

**Document:**
- Did validation check StorageClass availability?
- Was error message clear?
- Did it list available StorageClasses?

### Test Case 5: Security Policy Violations

Test validation against Pod Security Standards / Pod Security Policies.

#### Setup on Target Cluster

```bash
# On target cluster, enable Pod Security Standards
kubectl config use-context <target-context>
kubectl create namespace validation-security-test

# Label namespace with restricted policy
kubectl label namespace validation-security-test \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

#### Create Non-Compliant App

```bash
# On source cluster
kubectl config use-context <source-context>
kubectl create namespace validation-security-test

# Deploy app that violates restricted policy
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: insecure-app
  namespace: validation-security-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: insecure
  template:
    metadata:
      labels:
        app: insecure
    spec:
      containers:
      - name: app
        image: nginx:1.25  # Runs as root by default
        ports:
        - containerPort: 80
        securityContext:
          privileged: true  # Violates restricted policy
EOF
```

#### Migration and Validation

```bash
cd ~/crane-test-validation

# Export
crane export -n validation-security-test -e export-security

# Transform  
crane transform -e export-security -t transform-security

# Apply
crane apply -t transform-security -o output-security

# Validate against restricted namespace
kubectl config use-context <target-context>

crane validate -f output-security/output.yaml --namespace validation-security-test

# Or
kubectl apply --dry-run=server -f output-security/output.yaml
```

**Expected:**
- Validation fails due to privileged container
- Clear error about Pod Security Standards violation
- Recommendation: set runAsNonRoot, drop privileged

**Document:**
- Did validation catch security policy violations?
- Were error messages actionable?
- Did it suggest specific security context fixes?

### Test Case 6: Service Type Compatibility

Test validation of service types (LoadBalancer on cluster without support).

#### Setup

```bash
# On source cluster
kubectl config use-context <source-context>
kubectl create namespace validation-service-test

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: external-service
  namespace: validation-service-test
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: web
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: validation-service-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
EOF
```

#### Migration and Validation

```bash
cd ~/crane-test-validation

# Export
crane export -n validation-service-test -e export-service

# Transform
crane transform -e export-service -t transform-service

# Apply
crane apply -t transform-service -o output-service

# Validate against cluster without LoadBalancer support
kubectl config use-context <target-context>

crane validate -f output-service/output.yaml
```

**Expected:**
- Validation warns if LoadBalancer not supported
- Recommendation: use NodePort or ClusterIP + Ingress

**Document:**
- Did validation detect LoadBalancer incompatibility?
- Was warning helpful?

## Validation Checklist

### Crane Validate Command
- [ ] Command exists: `crane validate`
- [ ] Can validate against target cluster
- [ ] Can validate without applying
- [ ] Provides exit code (0=success, non-zero=issues)

### Error Detection
- [ ] API version compatibility issues
- [ ] Missing CRDs
- [ ] Resource quota violations
- [ ] LimitRange violations
- [ ] Missing StorageClasses
- [ ] Security policy violations
- [ ] Service type compatibility

### Error Messages
- [ ] Clear and specific
- [ ] Identify which resource has issue
- [ ] Explain what's wrong
- [ ] Suggest how to fix
- [ ] Provide relevant documentation links

### Recommendations
- [ ] Actionable suggestions
- [ ] Alternative approaches offered
- [ ] Commands to fix issues (when applicable)

## Expected Crane Validate Features

### Must Have
1. Validate syntax (YAML parsing)
2. Validate against Kubernetes API schema
3. Check API version compatibility
4. Detect missing CRDs

### Should Have
5. Check resource quotas
6. Check limit ranges
7. Check storage class availability
8. Check security policies
9. Service type compatibility

### Nice to Have
10. Suggest automatic fixes
11. Export validation report
12. Integration with CI/CD
13. Pre-migration validation checklist

## Common Validation Scenarios

### Pre-Migration Validation

```bash
# Before starting migration
crane validate source -n <namespace> --source-cluster <source-context>

# Should report:
# - Resources that will be exported
# - Potential issues
# - Cluster resources needed
# - Warnings about stateful components
```

### Post-Transform Validation

```bash
# After transformation
crane validate -f output/output.yaml --target-cluster <target-context>

# Should report:
# - Compatibility issues
# - Missing dependencies
# - Policy violations
# - Recommendations
```

### Continuous Validation

```bash
# During multi-stage transformation
crane transform && crane validate

# Validate after each stage
crane validate -t transform/20_CustomStage/
```

## Expected Results

✅ **Success:**
- Crane validate command exists and works
- Detects major compatibility issues
- Error messages are clear and actionable
- Provides recommendations

⚠️ **Acceptable:**
- Some validations require manual checking
- Limited to API-level validation
- Doesn't catch all runtime issues

❌ **Blocking:**
- No validation capability
- Silent failures on incompatible resources
- Unclear error messages
- No recommendations provided

## Time Estimate

- Test Case 1 (API version): 5 min
- Test Case 2 (CRD): 5 min
- Test Case 3 (Quotas): 10 min
- Test Case 4 (Storage): 5 min
- Test Case 5 (Security): 10 min
- Test Case 6 (Service): 5 min
- Documentation: 5 min
- **Total: ~45 minutes**

## Key Questions

1. Does `crane validate` command exist?
2. What validations does it perform?
3. Can it validate without applying resources?
4. Are error messages helpful?
5. Does it provide fix recommendations?
6. Can it integrate with CI/CD pipelines?

## Next Steps

- Document all validation capabilities (or gaps)
- List validation features that should be added
- Provide examples of helpful error messages
- Continue to [Scenario 5: Custom Plugin Creation](./scenario-05-custom-plugin.md)
