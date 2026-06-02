# Scenario 2: Multi-stage Transformation with Kustomize

**Priority:** 2 - Multi-stage Workflow Validation  
**Duration:** ~60 minutes  
**Goal:** Validate multi-stage transformation workflow clarity and usability

## Objective

Test that users can successfully:
1. Create multiple transformation stages
2. Apply common Kustomize transformations (namespace, labels, images)
3. Understand the iteration workflow
4. Work with transform/ directory stage-by-stage vs regenerating

This scenario directly addresses the question: **"Does it make sense to work on transform/ dir iteratively stage-by-stage or just generate whole dir again if some change is needed?"**

## Test Application

We'll use a simple multi-tier application to demonstrate transformation capabilities.

## Setup

### 1. Deploy Test Application on Source

```bash
# Switch to source cluster
kubectl config use-context <source-context>

# Create dev namespace
kubectl create namespace app-dev

# Deploy application
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: app-dev
  labels:
    app: demo-app
    component: backend
data:
  environment: "development"
  log-level: "debug"
  database-host: "dev-postgres.dev-infra.svc.cluster.local"
  feature-flags: |
    experimental_api: true
    debug_mode: true
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: frontend-config
  namespace: app-dev
  labels:
    app: demo-app
    component: frontend
data:
  api-url: "http://backend:8080"
  theme: "development"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: app-dev
  labels:
    app: demo-app
    component: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
      component: backend
  template:
    metadata:
      labels:
        app: demo-app
        component: backend
    spec:
      containers:
      - name: app
        image: docker.io/nginxinc/nginx-unprivileged:1.25
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: backend-config
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: app-dev
  labels:
    app: demo-app
    component: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
      component: frontend
  template:
    metadata:
      labels:
        app: demo-app
        component: frontend
    spec:
      containers:
      - name: web
        image: docker.io/library/nginx:1.25-alpine
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: frontend-config
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: app-dev
  labels:
    app: demo-app
    component: backend
spec:
  selector:
    app: demo-app
    component: backend
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: app-dev
  labels:
    app: demo-app
    component: frontend
spec:
  selector:
    app: demo-app
    component: frontend
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

# Verify
kubectl wait --for=condition=ready pod -l app=demo-app -n app-dev --timeout=120s
kubectl get all,cm -n app-dev
```

## Multi-Stage Transformation

### Stage 1: Export and Base Cleanup

```bash
# Create working directory
mkdir -p ~/crane-test-multistage
cd ~/crane-test-multistage

# Export
crane export -n app-dev

# Initial transform with KubernetesPlugin
crane transform

# Verify Stage 1
tree transform/10_KubernetesPlugin/
cat transform/10_KubernetesPlugin/kustomization.yaml
```

**Checkpoint 1:**
- [ ] Export successful
- [ ] Stage 1 created
- [ ] Patches generated

### Stage 2: Namespace Change (Production)

Goal: Change namespace from `app-dev` to `app-production`

```bash
# Create custom stage for namespace change
crane transform 20_NamespaceChange

# Verify stage was created
ls -la transform/20_NamespaceChange/

# Check that resources were copied from Stage 1 output
diff -r transform/10_KubernetesPlugin/resources/ transform/20_NamespaceChange/resources/ || echo "Resources copied (expected diff due to cleanup)"
```

**Edit kustomization.yaml:**

```bash
cat > transform/20_NamespaceChange/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- configmap.yaml
- deployment.yaml
- service.yaml

# Change namespace
namespace: app-production
EOF
```

**Test the stage:**

```bash
# Preview namespace change
kubectl kustomize transform/20_NamespaceChange/ | grep "namespace:" | head -10

# All should show: namespace: app-production
```

**Checkpoint 2:**
- [ ] Stage 2 created successfully
- [ ] Resources copied from Stage 1 output
- [ ] Namespace change preview shows correct namespace

**Question to answer:** Was it clear how to create this stage? Was the workflow intuitive?

### Stage 3: Add Production Labels and Annotations

Goal: Add common production labels and monitoring annotations

```bash
# Create another stage
crane transform 30_ProductionLabels

# Edit kustomization
cat > transform/30_ProductionLabels/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- configmap.yaml
- deployment.yaml
- service.yaml

namespace: app-production

# Add production labels
commonLabels:
  environment: production
  managed-by: crane
  team: platform-team

# Add monitoring annotations  
commonAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  crane.konveyor.io/migrated: "true"
  crane.konveyor.io/source-namespace: "app-dev"
EOF

# Preview
kubectl kustomize transform/30_ProductionLabels/ | grep -A 5 "labels:"
kubectl kustomize transform/30_ProductionLabels/ | grep -A 5 "annotations:"
```

**Checkpoint 3:**
- [ ] Stage 3 created from Stage 2 output
- [ ] Labels added to all resources
- [ ] Annotations added to all resources

### Stage 4: Update Images to Production Registry

Goal: Change images to use private production registry

```bash
# Create stage
crane transform 40_ProductionImages

# Edit kustomization
cat > transform/40_ProductionImages/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- configmap.yaml
- deployment.yaml
- service.yaml

namespace: app-production

commonLabels:
  environment: production
  managed-by: crane
  team: platform-team

commonAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  crane.konveyor.io/migrated: "true"
  crane.konveyor.io/source-namespace: "app-dev"

# Update images to production registry
images:
- name: docker.io/nginxinc/nginx-unprivileged:1.25
  newName: registry.production.example.com/nginx-unprivileged
  newTag: 1.25.0
- name: docker.io/library/nginx:1.25-alpine
  newName: registry.production.example.com/nginx
  newTag: 1.25.0-alpine
EOF

# Preview images
kubectl kustomize transform/40_ProductionImages/ | grep "image:"
```

**Checkpoint 4:**
- [ ] Stage 4 created
- [ ] Images updated to production registry
- [ ] Image tags updated

### Stage 5: Update Configuration for Production

Goal: Change ConfigMap values for production environment

```bash
# Create stage
crane transform 50_ProductionConfig

# Edit kustomization to use configMapGenerator
cat > transform/50_ProductionConfig/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml

namespace: app-production

commonLabels:
  environment: production
  managed-by: crane
  team: platform-team

commonAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  crane.konveyor.io/migrated: "true"
  crane.konveyor.io/source-namespace: "app-dev"

images:
- name: docker.io/nginxinc/nginx-unprivileged:1.25
  newName: registry.production.example.com/nginx-unprivileged
  newTag: 1.25.0
- name: docker.io/library/nginx:1.25-alpine
  newName: registry.production.example.com/nginx
  newTag: 1.25.0-alpine

# Replace ConfigMaps with production values
configMapGenerator:
- name: backend-config
  literals:
  - environment=production
  - log-level=info
  - database-host=prod-postgres.prod-infra.svc.cluster.local
  - feature-flags={"experimental_api": false, "debug_mode": false}
- name: frontend-config
  literals:
  - api-url=http://backend:8080
  - theme=production

# Disable name suffix hash to keep original names
generatorOptions:
  disableNameSuffixHash: true
EOF

# Preview config changes
kubectl kustomize transform/50_ProductionConfig/ | grep -A 10 "kind: ConfigMap"
```

**Checkpoint 5:**
- [ ] Stage 5 created
- [ ] ConfigMap values updated for production
- [ ] No name hash issues (generatorOptions worked)

### Stage 6: Scale for Production Load

Goal: Increase replicas and resource limits

```bash
# Create stage
crane transform 60_ProductionScaling

# Edit kustomization
cat > transform/60_ProductionScaling/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml

namespace: app-production

commonLabels:
  environment: production
  managed-by: crane
  team: platform-team

commonAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  crane.konveyor.io/migrated: "true"
  crane.konveyor.io/source-namespace: "app-dev"

images:
- name: docker.io/nginxinc/nginx-unprivileged:1.25
  newName: registry.production.example.com/nginx-unprivileged
  newTag: 1.25.0
- name: docker.io/library/nginx:1.25-alpine
  newName: registry.production.example.com/nginx
  newTag: 1.25.0-alpine

configMapGenerator:
- name: backend-config
  literals:
  - environment=production
  - log-level=info
  - database-host=prod-postgres.prod-infra.svc.cluster.local
  - feature-flags={"experimental_api": false, "debug_mode": false}
- name: frontend-config
  literals:
  - api-url=http://backend:8080
  - theme=production

generatorOptions:
  disableNameSuffixHash: true

# Scale replicas
replicas:
- name: backend
  count: 3
- name: frontend
  count: 5

# Increase resource limits via patches
patches:
- path: patches/backend-resources.yaml
  target:
    kind: Deployment
    name: backend
- path: patches/frontend-resources.yaml
  target:
    kind: Deployment
    name: frontend
EOF

# Create patches directory
mkdir -p transform/60_ProductionScaling/patches

# Backend resources patch
cat > transform/60_ProductionScaling/patches/backend-resources.yaml <<'EOF'
- op: replace
  path: /spec/template/spec/containers/0/resources
  value:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"
EOF

# Frontend resources patch
cat > transform/60_ProductionScaling/patches/frontend-resources.yaml <<'EOF'
- op: replace
  path: /spec/template/spec/containers/0/resources
  value:
    requests:
      memory: "256Mi"
      cpu: "250m"
    limits:
      memory: "512Mi"
      cpu: "500m"
EOF

# Preview scaling
kubectl kustomize transform/60_ProductionScaling/ | grep "replicas:"
kubectl kustomize transform/60_ProductionScaling/ | grep -A 8 "resources:"
```

**Checkpoint 6:**
- [ ] Stage 6 created
- [ ] Replicas scaled up
- [ ] Resources increased via JSONPatch

## Testing the Iteration Workflow

### Test 1: Modify Existing Stage

Simulate needing to change something in an earlier stage.

```bash
# Suppose we need to change the production namespace
# Edit Stage 2
vi transform/20_NamespaceChange/kustomization.yaml
# Change namespace to: app-prod (instead of app-production)

# Now we need to propagate this change to later stages
# Question: Do we re-run all stages? Or manually update each?

# Option A: Re-run all stages (regenerate)
crane transform --force
# This would regenerate everything, losing manual edits

# Option B: Re-run specific stages
crane transform 20_NamespaceChange 30_ProductionLabels 40_ProductionImages 50_ProductionConfig 60_ProductionScaling
# Does this update all stages correctly?

# Option C: Manually edit each stage's kustomization.yaml
# Edit each stage file to change namespace
# This is tedious but preserves other changes

# Test which option works best
```

**Document:**
- Which approach did you use?
- What problems did you encounter?
- Which approach felt most natural?
- Should crane provide better support for this?

### Test 2: Add New Stage in Middle

Simulate needing to add a new stage between existing ones.

```bash
# Suppose we need to add security labels between Stage 3 and 4
# We want priority 35 (between 30 and 40)

# Create new stage
crane transform 35_SecurityLabels

# Does it correctly use output from Stage 30?
ls -la transform/35_SecurityLabels/resources/

# Edit the new stage
cat > transform/35_SecurityLabels/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- configmap.yaml
- deployment.yaml
- service.yaml

namespace: app-production

commonLabels:
  environment: production
  managed-by: crane
  team: platform-team
  security-scan: required
  compliance: pci-dss

commonAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  crane.konveyor.io/migrated: "true"
  crane.konveyor.io/source-namespace: "app-dev"
EOF

# Now do we need to regenerate stages 40, 50, 60?
# Or do they automatically pick up the new stage 35's output?
```

**Document:**
- Did the new stage integrate smoothly?
- Did later stages need regeneration?
- What was confusing about this process?

### Test 3: Remove a Stage

Simulate removing a stage from the pipeline.

```bash
# Suppose Stage 4 (image changes) isn't needed anymore
# We want to skip it

# Option A: Delete the directory
rm -rf transform/40_ProductionImages/

# Now re-run remaining stages - do they still work?
crane transform 50_ProductionConfig 60_ProductionScaling

# Option B: Skip it during apply
# Is there a way to selectively apply stages?
```

**Document:**
- How did you remove the stage?
- Did it break the pipeline?
- Was there a clean way to skip stages?

## Generate Final Output

```bash
# Run crane apply (applies all discovered stages)
crane apply

# Inspect output
cat output/output.yaml | head -100

# Verify all transformations applied
grep "namespace: app-production" output/output.yaml
grep "environment: production" output/output.yaml
grep "registry.production.example.com" output/output.yaml
grep "replicas: 3" output/output.yaml
grep "replicas: 5" output/output.yaml
```

**Checkpoint 7:**
- [ ] All stages applied successfully
- [ ] Final output contains all transformations
- [ ] Transformations cascaded correctly through stages

## Deploy and Validate

```bash
# Switch to target cluster
kubectl config use-context <target-context>

# Create namespace
kubectl create namespace app-production

# Apply
kubectl apply -f output/output.yaml

# Verify
kubectl get all,cm -n app-production
kubectl get deployment backend -n app-production -o yaml | grep -A 5 "replicas:"
kubectl get deployment frontend -n app-production -o yaml | grep -A 5 "replicas:"

# Check labels
kubectl get deployment backend -n app-production -o yaml | grep -A 10 "labels:"

# Check images
kubectl get deployment backend -n app-production -o yaml | grep "image:"
```

## Validation Checklist

### Multi-Stage Creation
- [ ] Created 6 transformation stages successfully
- [ ] Each stage built on previous stage's output
- [ ] Stage naming and priorities worked as expected

### Kustomize Transformations
- [ ] Namespace change worked
- [ ] commonLabels added correctly
- [ ] commonAnnotations added correctly
- [ ] Image updates applied
- [ ] ConfigMap generator worked (with disableNameSuffixHash)
- [ ] Replica scaling worked
- [ ] JSONPatch for resources worked

### Iteration Workflow
- [ ] Tested modifying existing stage
- [ ] Tested adding stage in middle of pipeline
- [ ] Tested removing a stage
- [ ] Understood impact of changes on downstream stages

### Documentation and UX
- [ ] Workflow was clear from documentation
- [ ] Error messages (if any) were helpful
- [ ] Commands behaved as expected
- [ ] Iteration process was intuitive

## Key Questions to Answer

1. **Stage-by-stage vs full regeneration:**
   - Which approach did you use most often?
   - Which felt more natural?
   - What problems did you hit with each approach?
   - Should crane provide better support for iterative changes?

2. **Documentation clarity:**
   - Was multi-stage transformation well documented?
   - What was confusing?
   - What examples would have helped?

3. **User-friendliness:**
   - Was the workflow intuitive?
   - Were there unnecessary steps?
   - What could be automated better?

4. **Stage management:**
   - Was it easy to add/remove/modify stages?
   - Should there be commands for stage management?
   - Should stages be independent or cascading?

## Common Issues

- ConfigMap name hashing breaks Deployment references
  - Solution: `disableNameSuffixHash: true`
- Forgetting to propagate changes to later stages
- Confusion about which stage output is used as input
- Not clear when to use `--force` vs re-running specific stages

## Expected Results

✅ **Success:**
- All 6 stages created and worked correctly
- Kustomize transformations applied as expected
- Clear understanding of multi-stage workflow
- Iteration process was manageable

⚠️ **Acceptable issues:**
- Some manual coordination needed between stages
- Documentation gaps in advanced scenarios

❌ **Blocking issues:**
- Stages don't cascade correctly
- Cannot iterate on stages without full regeneration
- Kustomize transformations fail
- Confusing workflow with no clear guidance

## Time Estimate

- Setup: 5 min
- Export and Stage 1: 5 min
- Stages 2-6 creation: 30 min
- Iteration testing: 10 min
- Deploy and validate: 10 min
- **Total: ~60 minutes**

## Next Steps

- Document workflow preferences (stage-by-stage vs regeneration)
- Note all UX issues encountered
- Continue to [Scenario 3: Cluster-Level Resources](./scenario-03-cluster-resources.md)
