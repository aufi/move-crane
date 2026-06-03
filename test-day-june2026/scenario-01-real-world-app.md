# Scenario 1: Real-World Application Migration

**Priority:** 1 - KubernetesPlugin Validation  
**Goal:** Verify KubernetesPlugin correctly cleans all resource types for migration

## Objective

Deploy real-world applications and validate that:
1. All resource types are exported correctly
2. KubernetesPlugin generates appropriate cleanup patches
3. No manual intervention needed for metadata cleanup
4. Application starts successfully on target cluster

## Test Applications

### Option A: WordPress + MySQL (Recommended start)

A realistic stateless-startable application with multiple resource types.

**Resources involved:**
- Deployments (WordPress, MySQL)
- Services (ClusterIP, LoadBalancer)
- ConfigMaps (MySQL config)
- Secrets (passwords)
- PersistentVolumeClaims (will be empty for stateless test)
- HorizontalPodAutoscaler (for WordPress)

### Option B: Existing Real-World App (Advanced, but Important)

Kindy asking to find an existing real-world app, deploy it and test its migration (stateless, skip PVC). This will help us ensure crane can handle application beyond our existing tests.

**Sample resources involved:**
- Multiple Deployments (frontend, cart, catalog, payment)
- Services (ClusterIP)
- ConfigMaps (per service)
- Secrets (API keys, service tokens)
- NetworkPolicy (service isolation)
- PodDisruptionBudget
- ServiceAccounts
- DeploymentConfig (OpenShift)
- BuildConfig (OpenShift)
- ImageStream (OpenShift)
- Route (OpenShift)
- ConfigMaps, Secrets
- PersistentVolumeClaims
- ServiceAccounts with specific permissions

## Setup - Option A: WordPress

### 1. Deploy on Source Cluster

```bash
# Switch to source cluster
kubectl config use-context <source-context>

# Create namespace
kubectl create namespace wordpress-test

# Deploy MySQL
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
  namespace: wordpress-test
type: Opaque
stringData:
  password: "mysql-root-password-123"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql-config
  namespace: wordpress-test
data:
  mysql.cnf: |
    [mysqld]
    max_connections=100
    default-storage-engine=INNODB
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
  namespace: wordpress-test
  labels:
    app: wordpress
    tier: database
spec:
  ports:
  - port: 3306
    targetPort: 3306
  selector:
    app: wordpress
    tier: mysql
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: wordpress-test
  labels:
    app: wordpress
    tier: mysql
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        - name: MYSQL_DATABASE
          value: wordpress
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: mysql-config-volume
          mountPath: /etc/mysql/conf.d
        - name: mysql-data
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-config-volume
        configMap:
          name: mysql-config
      - name: mysql-data
        emptyDir: {}  # Using emptyDir for stateless test
EOF

# Deploy WordPress
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: wordpress-secret
  namespace: wordpress-test
type: Opaque
stringData:
  password: "wordpress-admin-password-456"
---
apiVersion: v1
kind: Service
metadata:
  name: wordpress
  namespace: wordpress-test
  labels:
    app: wordpress
    tier: frontend
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: wordpress
    tier: frontend
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  namespace: wordpress-test
  labels:
    app: wordpress
    tier: frontend
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: frontend
  replicas: 2
  template:
    metadata:
      labels:
        app: wordpress
        tier: frontend
    spec:
      containers:
      - name: wordpress
        image: wordpress:6.4-apache
        env:
        - name: WORDPRESS_DB_HOST
          value: mysql:3306
        - name: WORDPRESS_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        - name: WORDPRESS_DB_NAME
          value: wordpress
        ports:
        - containerPort: 80
          name: wordpress
        volumeMounts:
        - name: wordpress-data
          mountPath: /var/www/html
      volumes:
      - name: wordpress-data
        emptyDir: {}  # Using emptyDir for stateless test
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: wordpress-hpa
  namespace: wordpress-test
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: wordpress
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: wordpress-pdb
  namespace: wordpress-test
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: wordpress
      tier: frontend
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: mysql-network-policy
  namespace: wordpress-test
spec:
  podSelector:
    matchLabels:
      app: wordpress
      tier: mysql
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: wordpress
          tier: frontend
    ports:
    - protocol: TCP
      port: 3306
EOF
```

### 2. Validate Application Running

```bash
# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=wordpress -n wordpress-test --timeout=300s

# Check all resources
kubectl get all,configmap,secret,hpa,pdb,networkpolicy -n wordpress-test

# Test WordPress (if LoadBalancer IP is available)
# Or use port-forward:
kubectl port-forward -n wordpress-test svc/wordpress 8080:80 &
curl http://localhost:8080
# You should see WordPress installation page
```

### 3. Document Running State

```bash
# Get resource counts
echo "=== Resource Inventory ==="
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n wordpress-test 2>/dev/null | \
  grep -v "^NAME" | wc -l

# List all resource types
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n wordpress-test 2>/dev/null | \
  awk '{print $1}' | cut -d'/' -f1 | sort -u
```

## Migration with Crane

### Step 1: Export

```bash
# Create working directory
mkdir -p ~/crane-test-wordpress
cd ~/crane-test-wordpress

# Export namespace
crane export -n wordpress-test

# Inspect exported resources
ls -la export/resources/wordpress-test/

# Count exported files
echo "=== Exported files ==="
ls export/resources/wordpress-test/ | wc -l
ls export/resources/wordpress-test/
```

**Validation checklist:**
- [ ] All Deployments exported
- [ ] All Services exported
- [ ] All ConfigMaps exported
- [ ] All Secrets exported (except auto-generated tokens)
- [ ] HorizontalPodAutoscaler exported
- [ ] PodDisruptionBudget exported
- [ ] NetworkPolicy exported
- [ ] ServiceAccounts exported (if any custom ones)

**Common issues to watch:**
- Missing resource types
- Partial exports
- Export errors in debug output

### Step 2: Inspect Exported Resources

Pick a few different resource types and examine them:

```bash
# Deployment
cat export/resources/wordpress-test/Deployment_apps_v1_wordpress-test_wordpress.yaml

# Check for fields that need cleanup:
grep -E "(uid|resourceVersion|creationTimestamp|generation|managedFields|status)" \
  export/resources/wordpress-test/Deployment_apps_v1_wordpress-test_wordpress.yaml

# HPA
cat export/resources/wordpress-test/HorizontalPodAutoscaler*.yaml | head -50

# NetworkPolicy
cat export/resources/wordpress-test/NetworkPolicy*.yaml
```

**Document:**
- What server-managed fields are present?
- Are there any unexpected fields?
- Any resource-specific metadata?

### Step 3: Transform with KubernetesPlugin

```bash
# Run transform
crane transform

# Inspect output
tree transform/10_KubernetesPlugin/

# Check patches directory
ls -la transform/10_KubernetesPlugin/patches/

# Count patches
echo "=== Patch count ==="
ls transform/10_KubernetesPlugin/patches/ | wc -l
```

**Validation checklist:**
- [ ] One patch file per exported resource
- [ ] Patches directory matches resources count
- [ ] kustomization.yaml references all resources and patches

### Step 4: Inspect Patches for Different Resource Types

```bash
# Deployment patch
echo "=== Deployment patch ==="
cat transform/10_KubernetesPlugin/patches/wordpress-test--apps-v1--Deployment--wordpress.patch.yaml

# HPA patch
echo "=== HPA patch ==="
cat transform/10_KubernetesPlugin/patches/wordpress-test--autoscaling-v2--HorizontalPodAutoscaler--*.patch.yaml

# NetworkPolicy patch
echo "=== NetworkPolicy patch ==="
cat transform/10_KubernetesPlugin/patches/wordpress-test--networking.k8s.io-v1--NetworkPolicy--*.patch.yaml

# Secret patch
echo "=== Secret patch ==="
cat transform/10_KubernetesPlugin/patches/wordpress-test--v1--Secret--*.patch.yaml | head -20
```

**Validation for each resource type:**
- [ ] Removes `metadata.uid`
- [ ] Removes `metadata.resourceVersion`
- [ ] Removes `metadata.creationTimestamp`
- [ ] Removes `metadata.generation`
- [ ] Removes `metadata.managedFields`
- [ ] Removes `status` section
- [ ] Preserves user-defined fields (labels, annotations, spec)

**Document any missing or incorrect patches.**

### Step 5: Preview Cleaned Resources

```bash
# Preview all cleaned resources
kubectl kustomize transform/10_KubernetesPlugin/ > cleaned-preview.yaml

# Check that server-managed fields are removed
grep -E "(uid:|resourceVersion:|creationTimestamp:|managedFields:|^status:)" cleaned-preview.yaml

# Should return nothing or minimal matches

# Verify user fields preserved
grep -E "app: wordpress" cleaned-preview.yaml
# Should show app labels preserved
```

### Step 6: Generate Final Output

```bash
# Run crane apply
crane apply

# Inspect output
cat output/output.yaml | head -100

# Verify resource count
grep "^kind:" output/output.yaml | sort | uniq -c

# Expected counts:
# 2 Deployment (mysql, wordpress)
# 2 Service (mysql, wordpress)
# 2 Secret (mysql-secret, wordpress-secret)
# 1 ConfigMap (mysql-config)
# 1 HorizontalPodAutoscaler
# 1 PodDisruptionBudget
# 1 NetworkPolicy
```

### Step 7: Validate Output

```bash
# Syntax validation
kubectl apply --dry-run=client -f output/output.yaml

# Check for any errors or warnings
```

**Document any validation failures.**

### Step 8: Deploy to Target Cluster

```bash
# Switch to target cluster
kubectl config use-context <target-context>

# Create namespace
kubectl create namespace wordpress-test

# Apply migrated resources
kubectl apply -f output/output.yaml

# Watch deployment
kubectl get pods -n wordpress-test -w
```

**Validation:**
- [ ] All resources created successfully
- [ ] No errors during apply
- [ ] Pods start successfully
- [ ] Services are created
- [ ] HPA is active
- [ ] NetworkPolicy is applied

### Step 9: Functional Testing

```bash
# Wait for ready state
kubectl wait --for=condition=ready pod -l app=wordpress,tier=frontend -n wordpress-test --timeout=300s
kubectl wait --for=condition=ready pod -l app=wordpress,tier=mysql -n wordpress-test --timeout=300s

# Test WordPress access
kubectl port-forward -n wordpress-test svc/wordpress 8080:80 &
curl -I http://localhost:8080
# Should return HTTP 200 or 302

# Verify MySQL connectivity from WordPress
kubectl exec -n wordpress-test deployment/wordpress -- \
  sh -c 'mysql -h mysql -u root -p$WORDPRESS_DB_PASSWORD -e "SHOW DATABASES;"'

# Check HPA
kubectl get hpa -n wordpress-test
kubectl describe hpa wordpress-hpa -n wordpress-test

# Verify NetworkPolicy
kubectl get networkpolicy -n wordpress-test
kubectl describe networkpolicy mysql-network-policy -n wordpress-test
```

## Validation Checklist

### Export Phase
- [ ] All resource types exported
- [ ] No missing resources compared to source
- [ ] Export completed without errors
- [ ] Exported files contain valid YAML

### Transform Phase
- [ ] KubernetesPlugin executed successfully
- [ ] Patches generated for all resources
- [ ] Patches remove all server-managed fields
- [ ] Patches preserve all user-defined fields
- [ ] Special resource types handled correctly:
  - [ ] HorizontalPodAutoscaler
  - [ ] PodDisruptionBudget
  - [ ] NetworkPolicy
  - [ ] ServiceAccount (if any)
  - [ ] Custom resources (if any)

### Apply Phase
- [ ] output.yaml generated successfully
- [ ] Contains all expected resources
- [ ] Validation passes (dry-run)
- [ ] No syntax errors

### Deployment Phase
- [ ] All resources created on target
- [ ] No apply errors
- [ ] Pods start successfully
- [ ] Application is functional
- [ ] All resource types work as expected

## Common Issues to Document

1. **Resource Types Not Exported**
   - Which types?
   - Why not exported?
   - Should they be?

2. **Incorrect or Missing Patches**
   - Which resource type?
   - What fields not cleaned?
   - What fields incorrectly removed?

3. **Apply Failures**
   - Error messages
   - Which resources failed?
   - Why (API version, field validation, etc.)?

4. **Resource-Specific Issues**
   - HPA not working on target
   - NetworkPolicy not enforced
   - ServiceAccount permissions missing
   - Other resource-type-specific problems

## Expected Results

✅ **Success criteria:**
- All resources export cleanly
- KubernetesPlugin generates correct patches for all resource types
- Application deploys and runs on target cluster without manual intervention
- No resource types require special handling

⚠️ **Acceptable issues:**
- Auto-generated ServiceAccount tokens not migrated (expected)
- LoadBalancer IPs change (expected, environment-specific)
- PersistentVolume bindings reset (expected for PVs)

❌ **Blocking issues:**
- Resource types not exported
- Patches missing for resource types
- Incorrect patches breaking resources
- Application fails to start due to metadata issues

## Next Steps

After completing this scenario:
- Document any resource types that had issues
- Note any patches that were incorrect
- Identify any manual cleanup needed
- Continue to [Scenario 2: Multi-stage Transformation](./scenario-02-multistage-kustomize.md)
