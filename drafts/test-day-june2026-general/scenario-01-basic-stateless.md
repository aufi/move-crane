# Scenario 1: Basic Stateless Application

## Description

This scenario tests the most basic use case - migration of a simple stateless application without persistent data. The application contains:

- **Deployment** - running application (e.g., simple web server)
- **Service** - ClusterIP service for application access
- **ConfigMap** - application configuration
- **Secret** - sensitive data (e.g., API keys)

The goal is to verify that crane can:
1. Export all resources from namespace
2. Clean live/runtime metadata using KubernetesPlugin
3. Generate redeployable manifests

## Test Application: Nginx Static Web

We'll use a simple Nginx application with custom HTML content.

## Test Environment Setup

### 1. Connect to Source Cluster

```bash
# Verify connection
kubectl cluster-info

# Create test namespace
kubectl create namespace crane-test-basic
```

### 2. Deploy Test Application

```bash
# ConfigMap with HTML content
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-content
  namespace: crane-test-basic
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head><title>Crane Test App</title></head>
    <body>
      <h1>Hello from Crane Test!</h1>
      <p>This is a simple stateless application.</p>
      <p>Environment: SOURCE_CLUSTER</p>
    </body>
    </html>
EOF

# Secret with API key
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: crane-test-basic
type: Opaque
stringData:
  api-key: "test-api-key-12345"
  db-password: "not-used-but-here"
EOF

# Deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-app
  namespace: crane-test-basic
  labels:
    app: nginx-test
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
        env:
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: api-key
      volumes:
      - name: html
        configMap:
          name: nginx-content
EOF

# Service
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: crane-test-basic
spec:
  selector:
    app: nginx-test
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF
```

### 3. Validate Running Application

```bash
# Wait for ready pods
kubectl wait --for=condition=ready pod -l app=nginx-test -n crane-test-basic --timeout=120s

# Verify deployment
kubectl get deployment -n crane-test-basic
kubectl get pods -n crane-test-basic
kubectl get svc -n crane-test-basic

# Test application (from another pod or via port-forward)
kubectl run test-curl --rm -i --tty --image=curlimages/curl -n crane-test-basic -- \
  curl -s http://nginx-service.crane-test-basic.svc.cluster.local

# You should see HTML with "Hello from Crane Test!"
```

## Migration with Crane

### Step 1: Export Resources

```bash
# Create working directory for migration
mkdir -p ~/crane-test-basic
cd ~/crane-test-basic

# Export namespace
crane export -n crane-test-basic

# Explore exported files
tree export/

# Expected output:
# export/
# └── resources/
#     └── crane-test-basic/
#         ├── ConfigMap_crane-test-basic_nginx-content.yaml
#         ├── Deployment_apps_v1_crane-test-basic_nginx-app.yaml
#         ├── Secret_crane-test-basic_app-secrets.yaml
#         ├── Service_crane-test-basic_nginx-service.yaml
#         └── ... (possibly other auto-generated resources like ServiceAccount tokens)
```

### Step 2: Inspect Exported Resources

```bash
# Look at Deployment - contains runtime metadata
cat export/resources/crane-test-basic/Deployment_apps_v1_crane-test-basic_nginx-app.yaml

# Notice presence of:
# - metadata.uid
# - metadata.resourceVersion
# - metadata.creationTimestamp
# - metadata.managedFields
# - status section
```

**Expected issues:**
- These fields would cause conflicts when applying to new cluster
- Crane needs to clean them using transform

### Step 3: Transform with KubernetesPlugin

```bash
# Run transform (uses KubernetesPlugin automatically)
crane transform

# Explore output
tree transform/

# Expected output:
# transform/
# └── 10_KubernetesPlugin/
#     ├── kustomization.yaml
#     ├── patches/
#     │   ├── crane-test-basic--v1--ConfigMap--nginx-content.patch.yaml
#     │   ├── crane-test-basic--apps-v1--Deployment--nginx-app.patch.yaml
#     │   ├── crane-test-basic--v1--Secret--app-secrets.patch.yaml
#     │   └── crane-test-basic--v1--Service--nginx-service.patch.yaml
#     └── resources/
#         ├── configmap.yaml
#         ├── deployment.yaml
#         ├── secret.yaml
#         └── service.yaml
```

### Step 4: Inspect Patches

```bash
# Look at patch for Deployment
cat transform/10_KubernetesPlugin/patches/crane-test-basic--apps-v1--Deployment--nginx-app.patch.yaml

# You should see JSONPatch operations like:
# - op: remove
#   path: /metadata/uid
# - op: remove
#   path: /metadata/resourceVersion
# - op: remove
#   path: /status
# ... etc
```

**What to check:**
- ✅ Patches remove all runtime/live metadata
- ✅ Patches preserve user-defined fields (labels, annotations, spec)
- ✅ kustomization.yaml correctly references resources and patches

### Step 5: Preview Transformed Resources

```bash
# Preview final output (without applying to cluster)
kubectl kustomize transform/10_KubernetesPlugin/

# Or use crane apply with --dry-run (if supported)
# crane apply --dry-run

# Check that Deployment no longer has:
# - metadata.uid
# - metadata.resourceVersion
# - metadata.creationTimestamp
# - status section
```

### Step 6: Apply (Generate Final Manifests)

```bash
# Run crane apply
crane apply

# Explore output
cat output/output.yaml

# You should see:
# - Multi-document YAML (--- separated)
# - All resources (Deployment, Service, ConfigMap, Secret)
# - Cleaned metadata
```

### Step 7: Validate Final Manifests

```bash
# Syntax validation
kubectl apply --dry-run=client -f output/output.yaml

# If you want to validate against target cluster:
kubectl apply --dry-run=server -f output/output.yaml --context=<target-cluster-context>
```

### Step 8: Deploy to Target Cluster

```bash
# Switch context to target cluster
kubectl config use-context <target-cluster-context>

# Create namespace (if it doesn't exist)
kubectl create namespace crane-test-basic

# Apply manifests
kubectl apply -f output/output.yaml

# Validate deployment
kubectl get all -n crane-test-basic
kubectl wait --for=condition=ready pod -l app=nginx-test -n crane-test-basic --timeout=120s
```

### Step 9: Functional Test on Target Cluster

```bash
# Test application
kubectl run test-curl --rm -i --tty --image=curlimages/curl -n crane-test-basic -- \
  curl -s http://nginx-service.crane-test-basic.svc.cluster.local

# You should see the same HTML as on source cluster

# Verify Secret
kubectl get secret app-secrets -n crane-test-basic -o jsonpath='{.data.api-key}' | base64 -d
# Should output: test-api-key-12345
```

## Validation Checklist

After completing migration verify:

### Export Phase
- [ ] All resources were exported (Deployment, Service, ConfigMap, Secret)
- [ ] Exported files contain complete YAML
- [ ] Export contains live/runtime metadata (this is OK, transform will clean it)

### Transform Phase
- [ ] Transform created stage `10_KubernetesPlugin/`
- [ ] Patches were generated for each resource
- [ ] Patches remove `metadata.uid`, `metadata.resourceVersion`, `metadata.creationTimestamp`
- [ ] Patches remove `status` section
- [ ] Patches remove `metadata.managedFields`
- [ ] User-defined metadata (labels, annotations) remain preserved

### Apply Phase
- [ ] `output/output.yaml` was successfully generated
- [ ] Contains all resources
- [ ] Resources are valid YAML
- [ ] Syntax validation passes (`kubectl apply --dry-run=client`)

### Target Cluster Deployment
- [ ] Application deployed successfully
- [ ] All pods are Running and Ready
- [ ] Service is accessible
- [ ] Application responds to HTTP requests
- [ ] Secret data is correctly mapped to env variables

## Expected Results

### What Should Work
- ✅ Export all resources from namespace
- ✅ Automatic generation of patches for metadata cleanup
- ✅ Creation of redeployable manifests
- ✅ Successful deployment to target cluster
- ✅ Functional application on target cluster identical to source

### Known Issues and Edge Cases

1. **Auto-generated ServiceAccount Tokens**
   - Crane may export auto-generated Secret tokens for ServiceAccount
   - These are not needed and should be removed or ignored
   - **Workaround**: Manually remove them from output.yaml or use whiteout

2. **Default Namespace**
   - If namespace is not explicit in metadata, kubectl uses `default`
   - Ensure all resources have `metadata.namespace`

3. **Resource Discovery**
   - Crane should discover all resources in namespace
   - If some are missing, check `crane export --debug`

## Time Requirements

- **Setup**: 10 minutes
- **Export**: 2 minutes
- **Transform**: 2 minutes
- **Apply and deploy**: 5 minutes
- **Validation**: 5 minutes

**Total**: ~25 minutes

## Reporting

### Successful Test

If everything worked:
```markdown
## Scenario 1: Basic Stateless - PASSED ✅

**Environment:**
- Source cluster: Kubernetes 1.28
- Target cluster: Kubernetes 1.29
- Crane version: main@20260601

**Result:**
Migration completed successfully. All resources were exported, transformed, and deployed to target cluster. Application functions identically as on source.

**Positive:**
- Export was fast and complete
- Patches correctly cleaned metadata
- Deploy to target cluster completed without issues

**Suggestions:**
- (if any)
```

### Test with Issues

If something didn't work, record:
- What was the problem?
- In which phase did it occur?
- Error message
- How did you solve it (or not)?

## Next Steps

After completing this scenario you can continue with:
- [Scenario 2: Multi-stage Transformation](./scenario-02-multistage.md)
- Experiment with other plugins
- Test larger applications
