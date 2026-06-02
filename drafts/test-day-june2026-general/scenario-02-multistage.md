# Scenario 2: Multi-stage Transformation

## Description

This scenario tests multi-stage transformation pipelines where resources go through multiple sequential transformation stages. This is useful when:

- Multiple transformation concerns need to be separated
- You need to inspect intermediate results
- You want to separate automated and manual changes
- Complex transformations benefit from separation of concerns

The application contains:
- **Deployment** with multiple containers
- **Service** - both ClusterIP and NodePort
- **ConfigMap** with multiple data entries
- **Ingress** resource (requires platform-specific handling)

## Learning Objectives

- Understand multi-stage pipeline concept
- Learn difference between plugin-based and pass-through stages
- Practice creating custom transformation stages
- Debug intermediate transformation results

## Test Application: Multi-tier Web App

We'll use a simple multi-tier application with frontend and backend components.

## Test Environment Setup

### 1. Connect to Source Cluster

```bash
# Verify connection
kubectl cluster-info

# Create test namespace
kubectl create namespace crane-test-multistage
```

### 2. Deploy Test Application

```bash
# Backend ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: crane-test-multistage
  labels:
    tier: backend
data:
  database-url: "postgresql://db.example.com:5432/mydb"
  cache-url: "redis://cache.example.com:6379"
  log-level: "info"
EOF

# Frontend ConfigMap
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
  namespace: crane-test-multistage
  labels:
    tier: frontend
data:
  api-endpoint: "http://backend-service:8080"
  theme: "default"
EOF

# Backend Deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: crane-test-multistage
  labels:
    app: backend
    tier: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        tier: backend
    spec:
      containers:
      - name: app
        image: hashicorp/http-echo:0.2.3
        args:
        - "-text=Backend API v1.0"
        - "-listen=:8080"
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: backend-config
EOF

# Backend Service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: crane-test-multistage
  labels:
    app: backend
spec:
  selector:
    app: backend
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  type: ClusterIP
EOF

# Frontend Deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: crane-test-multistage
  labels:
    app: frontend
    tier: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        tier: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: frontend-config
EOF

# Frontend Service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: crane-test-multistage
  labels:
    app: frontend
spec:
  selector:
    app: frontend
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: NodePort
EOF

# Ingress (if your cluster supports it)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
  namespace: crane-test-multistage
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: frontend.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
EOF
```

### 3. Validate Running Application

```bash
# Wait for ready pods
kubectl wait --for=condition=ready pod -l tier=backend -n crane-test-multistage --timeout=120s
kubectl wait --for=condition=ready pod -l tier=frontend -n crane-test-multistage --timeout=120s

# Verify deployments
kubectl get all -n crane-test-multistage
kubectl get ingress -n crane-test-multistage

# Test backend
kubectl run test-curl --rm -i --tty --image=curlimages/curl -n crane-test-multistage -- \
  curl -s http://backend-service:8080
```

## Migration with Crane - Multi-stage Pipeline

### Step 1: Export Resources

```bash
# Create working directory
mkdir -p ~/crane-test-multistage
cd ~/crane-test-multistage

# Export namespace
crane export -n crane-test-multistage

# Verify export
ls -la export/resources/crane-test-multistage/
```

### Step 2: Run Initial Transform (Stage 1)

```bash
# Run default transform - creates KubernetesPlugin stage
crane transform

# Inspect created stage
tree transform/10_KubernetesPlugin/

# Check what patches were generated
ls transform/10_KubernetesPlugin/patches/
```

**What happened:**
- Stage `10_KubernetesPlugin/` was created
- Resources were copied to `resources/` directory
- Patches generated to clean Kubernetes metadata
- Kustomization.yaml created

### Step 3: Create Second Stage for Environment-Specific Changes

Now we'll create a custom stage for modifying resources for the target environment.

```bash
# Create custom stage using base name (automatic priority)
crane transform EnvironmentCustomization

# Inspect the new stage
tree transform/

# You should see:
# transform/
# ├── 10_KubernetesPlugin/
# └── 20_EnvironmentCustomization/
```

**What happened:**
- New stage `20_EnvironmentCustomization/` was created
- It has priority 20 (next after 10)
- Resources are **copied from Stage 1 output**, not from export
- This is a pass-through stage (no plugin)

### Step 4: Inspect Sequential Consistency

This is a critical concept - let's verify it:

```bash
# Compare resources in Stage 1 vs Stage 2
diff -r transform/10_KubernetesPlugin/resources/ \
        transform/20_EnvironmentCustomization/resources/

# Check .work/ directory to see intermediate outputs
ls -la transform/.work/

# Inspect Stage 1 output (what Stage 2 received as input)
ls transform/.work/10_KubernetesPlugin/output/
```

**Key insight:**
- Stage 2's `resources/` contains the **materialized output** from Stage 1
- NOT the raw export
- Metadata already cleaned by Stage 1's patches

### Step 5: Add Custom Transformations to Stage 2

Edit the kustomization.yaml in Stage 2 to add environment-specific changes:

```bash
cat >> transform/20_EnvironmentCustomization/kustomization.yaml <<'EOF'

# Change namespace for target environment
namespace: production-app

# Add common labels
commonLabels:
  environment: production
  managed-by: crane
  migration-date: "2026-06-01"

# Add common annotations
commonAnnotations:
  crane.konveyor.io/migrated: "true"
  crane.konveyor.io/source-cluster: "dev-cluster"

# Update ConfigMap data
configMapGenerator:
- name: backend-config
  behavior: merge
  literals:
  - log-level=warning
  - database-url=postgresql://prod-db.example.com:5432/proddb

# Update images for production registry
images:
- name: nginx:1.25
  newName: registry.prod.example.com/nginx
  newTag: "1.25-prod"
- name: hashicorp/http-echo:0.2.3
  newName: registry.prod.example.com/http-echo
  newTag: "0.2.3"

# Increase replicas for production
replicas:
- name: frontend
  count: 5
- name: backend
  count: 3
EOF
```

### Step 6: Create Third Stage for Manual Patches

```bash
# Create another custom stage for manual fine-tuning
crane transform ManualPatches

# This creates 30_ManualPatches/
tree transform/
```

### Step 7: Add Manual JSONPatch to Stage 3

Create a custom patch to modify the Ingress resource:

```bash
cat > transform/30_ManualPatches/patches/custom-ingress-patch.yaml <<'EOF'
- op: replace
  path: /spec/rules/0/host
  value: "app.production.example.com"
- op: add
  path: /metadata/annotations/cert-manager.io~1cluster-issuer
  value: "letsencrypt-prod"
EOF

# Add patch to kustomization.yaml
cat >> transform/30_ManualPatches/kustomization.yaml <<'EOF'

patches:
- path: patches/custom-ingress-patch.yaml
  target:
    kind: Ingress
    name: frontend-ingress
EOF
```

**Note:** The `~1` is JSONPatch escape for `/` character in annotation keys.

### Step 8: Preview All Stages

```bash
# Preview each stage individually
echo "=== Stage 1: KubernetesPlugin ==="
kubectl kustomize transform/10_KubernetesPlugin/ | head -50

echo "=== Stage 2: EnvironmentCustomization ==="
kubectl kustomize transform/20_EnvironmentCustomization/ | head -50

echo "=== Stage 3: ManualPatches ==="
kubectl kustomize transform/30_ManualPatches/ | head -50
```

### Step 9: Inspect .work/ Directory for Debugging

```bash
# See the flow of transformations
tree transform/.work/

# Compare input vs output for Stage 2
echo "=== Stage 2 Input (from Stage 1 output) ==="
ls transform/.work/20_EnvironmentCustomization/input/

echo "=== Stage 2 Output (to Stage 3 input) ==="
ls transform/.work/20_EnvironmentCustomization/output/

# Diff to see what Stage 2 changed
diff -u transform/.work/20_EnvironmentCustomization/input/deployment.yaml \
        transform/.work/20_EnvironmentCustomization/output/deployment.yaml
```

### Step 10: Generate Final Output

```bash
# Run crane apply to generate final manifests
crane apply

# Inspect output
cat output/output.yaml | grep -A 5 "kind: Deployment"
cat output/output.yaml | grep -A 5 "namespace:"
cat output/output.yaml | grep -A 5 "managed-by:"
```

### Step 11: Validate Transformations

```bash
# Verify namespace was changed
grep "namespace: production-app" output/output.yaml

# Verify labels were added
grep "managed-by: crane" output/output.yaml

# Verify replicas were increased
grep -A 10 "kind: Deployment" output/output.yaml | grep "replicas:"

# Verify images were updated
grep "image:" output/output.yaml

# Verify Ingress was patched
grep -A 10 "kind: Ingress" output/output.yaml | grep "host:"
```

### Step 12: Re-run Specific Stages

Test the flexibility of stage selection:

```bash
# Re-run only Stage 2 (requires Stage 1 output to exist)
crane transform EnvironmentCustomization

# Re-run Stages 2 and 3
crane transform EnvironmentCustomization ManualPatches

# Re-run all stages
crane transform

# Force re-run all (WARNING: overwrites custom stages!)
crane transform --force
```

## Validation Checklist

### Multi-Stage Pipeline
- [ ] Three stages were created (10_KubernetesPlugin, 20_EnvironmentCustomization, 30_ManualPatches)
- [ ] Each stage has its own directory with resources/, patches/, kustomization.yaml
- [ ] `.work/` directory shows intermediate inputs/outputs for each stage

### Sequential Consistency
- [ ] Stage 2's resources/ contain output from Stage 1, not raw export
- [ ] Stage 3's resources/ contain output from Stage 2
- [ ] Each stage sees fully materialized output from previous stage

### Stage Transformations
- [ ] Stage 1 (KubernetesPlugin) cleaned Kubernetes metadata
- [ ] Stage 2 (EnvironmentCustomization) changed namespace to production-app
- [ ] Stage 2 added common labels and annotations
- [ ] Stage 2 updated images to production registry
- [ ] Stage 2 increased replica counts
- [ ] Stage 3 (ManualPatches) modified Ingress host

### Final Output
- [ ] `output/output.yaml` contains all transformations applied
- [ ] Namespace is production-app throughout
- [ ] Labels include environment=production, managed-by=crane
- [ ] Replicas: frontend=5, backend=3
- [ ] Images point to production registry
- [ ] Ingress host is app.production.example.com

### Stage Re-run Behavior
- [ ] Plugin stages (10_KubernetesPlugin) auto-regenerate without --force
- [ ] Custom stages (20, 30) require --force to regenerate
- [ ] Can run specific stages by name
- [ ] Stages execute in priority order regardless of argument order

## Expected Results

### What Should Work
- ✅ Create multiple transformation stages
- ✅ Each stage processes output from previous stage
- ✅ Plugin stages auto-regenerate
- ✅ Custom stages protected from accidental overwrite
- ✅ Flexible stage selection (by name, priority, or plugin name)
- ✅ Debug intermediate results via .work/ directory
- ✅ Combine automated (plugin) and manual (custom) transformations

### Known Issues and Edge Cases

1. **Stale Custom Stage Resources**
   - If you re-run Stage 1 but not Stage 2, Stage 2 has stale data
   - **Solution**: Run all stages or use `--force`

2. **Stage Name Collisions**
   - If same plugin used in multiple stages, must use exact stage directory name
   - **Example**: Can't use "KubernetesPlugin" if both 10_KubernetesPlugin and 20_KubernetesPlugin exist

3. **Manual Edits Lost with --force**
   - `--force` overwrites everything, including custom stages
   - **Solution**: Only use --force when you want to regenerate from scratch

4. **ConfigMapGenerator Name Hashing**
   - Kustomize adds hash suffix to ConfigMap names by default
   - This might break references in Deployments
   - **Solution**: Use `generatorOptions: {disableNameSuffixHash: true}`

## Advanced Topics

### Testing Stage Order

Create stages in non-sequential order and verify execution order:

```bash
# Create stages with priorities: 50, 10, 30
crane transform 50_Final 10_First 30_Middle

# Verify they execute in order: 10 → 30 → 50
crane transform --debug
```

### Using Base Names

```bash
# Create stage with automatic priority
crane transform MyCustomStage

# This finds existing or creates new with next available priority
```

### Stage Discovery

```bash
# List all discovered stages
ls -d transform/*/

# Crane discovers stages by scanning transform/ directory
# Runs them in priority order when you run `crane transform`
```

## Time Requirements

- **Setup**: 15 minutes
- **Export**: 2 minutes
- **Multi-stage transform**: 15 minutes
- **Custom stages**: 15 minutes
- **Apply and validation**: 10 minutes
- **Debugging and experimentation**: 15 minutes

**Total**: ~70 minutes

## Reporting

### Successful Test

```markdown
## Scenario 2: Multi-stage Transformation - PASSED ✅

**Environment:**
- Source cluster: Kubernetes 1.28
- Target cluster: Kubernetes 1.29
- Crane version: main@20260601

**Result:**
Multi-stage pipeline worked as expected. Created 3 stages with different transformations. Sequential consistency verified - each stage correctly processed output from previous stage.

**Positive:**
- Easy to create multiple stages
- .work/ directory excellent for debugging
- Clear separation between plugin and custom stages
- Stage re-run flexibility is very useful

**Issues:**
- None

**Suggestions:**
- Document configMapGenerator name hashing behavior
- Add warning when custom stage might have stale data
```

## Next Steps

After completing this scenario:
- [Scenario 3: Cross-platform Migration](./scenario-03-cross-platform.md)
- Experiment with more complex stage pipelines
- Try combining different plugins
