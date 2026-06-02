# Scenario 3: Cross-platform Migration

## Description

This scenario tests migration between different Kubernetes distributions, specifically:
- Vanilla Kubernetes → OpenShift (or vice versa)
- Platform-specific resource handling
- Using platform-specific plugins (e.g., OpenshiftPlugin)

Platform differences might include:
- **Security Context Constraints (SCC)** - OpenShift-specific
- **Routes** - OpenShift alternative to Ingress
- **ImageStreams** - OpenShift image management
- **Different default namespaces** - (default vs project names)
- **Different security defaults** - (restricted SCC, runAsNonRoot requirements)

## Learning Objectives

- Understand platform-specific resources and their transformations
- Learn how to use OpenshiftPlugin (if available)
- Handle resources that don't exist on target platform
- Deal with security context differences

## Test Application: Platform-Aware Web Application

We'll use an application that has platform-specific resources.

## Test Environment Setup

### Option A: Kubernetes → OpenShift Migration

#### 1. Deploy on Vanilla Kubernetes (Source)

```bash
# Verify connection to Kubernetes cluster
kubectl cluster-info

# Create namespace
kubectl create namespace crane-test-platform
```

```bash
# Application with Ingress (Kubernetes-style)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: crane-test-platform
data:
  message: "Hello from Kubernetes"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: crane-test-platform
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginxinc/nginx-unprivileged:1.25
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d
        securityContext:
          runAsNonRoot: true
          runAsUser: 101
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
      volumes:
      - name: config
        configMap:
          name: app-config
---
apiVersion: v1
kind: Service
metadata:
  name: web-service
  namespace: crane-test-platform
spec:
  selector:
    app: web
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: crane-test-platform
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
EOF
```

### Option B: OpenShift → Kubernetes Migration

#### 1. Deploy on OpenShift (Source)

```bash
# Verify connection to OpenShift cluster
oc whoami
oc cluster-info

# Create project (OpenShift namespace)
oc new-project crane-test-platform
```

```bash
# Application with Route (OpenShift-style)
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: crane-test-platform
data:
  message: "Hello from OpenShift"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: crane-test-platform
  labels:
    app: web
    app.kubernetes.io/component: web
    app.kubernetes.io/instance: web-app
    app.kubernetes.io/name: web-app
    app.openshift.io/runtime: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginxinc/nginx-unprivileged:1.25
        ports:
        - containerPort: 8080
          protocol: TCP
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d
---
apiVersion: v1
kind: Service
metadata:
  name: web-service
  namespace: crane-test-platform
  labels:
    app: web
spec:
  selector:
    app: web
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: web-route
  namespace: crane-test-platform
  labels:
    app: web
spec:
  to:
    kind: Service
    name: web-service
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF
```

### 2. Validate Source Application

```bash
# For Kubernetes
kubectl get all,ingress -n crane-test-platform
kubectl wait --for=condition=ready pod -l app=web -n crane-test-platform --timeout=120s

# For OpenShift
oc get all,route -n crane-test-platform
oc wait --for=condition=ready pod -l app=web -n crane-test-platform --timeout=120s
```

## Migration with Crane

### Step 1: Export Resources

```bash
# Create working directory
mkdir -p ~/crane-test-platform
cd ~/crane-test-platform

# Export namespace
crane export -n crane-test-platform

# Inspect exported resources
ls -la export/resources/crane-test-platform/

# Check for platform-specific resources
# Kubernetes source: should have Ingress
# OpenShift source: should have Route
```

### Step 2: First Transform - KubernetesPlugin

```bash
# Run basic Kubernetes cleanup transform
crane transform KubernetesPlugin

# Inspect output
tree transform/10_KubernetesPlugin/

# Check patches
ls transform/10_KubernetesPlugin/patches/
```

**What happened:**
- KubernetesPlugin cleaned standard Kubernetes metadata
- Platform-specific resources (Route/Ingress) remain unchanged
- Need additional transformation for cross-platform compatibility

### Step 3: Platform-Specific Transform

#### If Migrating to OpenShift (and OpenshiftPlugin is available)

```bash
# Check if OpenshiftPlugin is installed
crane transform list-plugins

# If OpenshiftPlugin is available:
crane transform OpenshiftPlugin

# This creates 15_OpenshiftPlugin/ stage (or similar priority)
```

**What OpenshiftPlugin might do:**
- Convert Ingress → Route
- Add OpenShift-specific labels
- Adjust security contexts for OpenShift SCCs
- Handle ImageStreams

#### If OpenshiftPlugin is Not Available - Manual Conversion

Create custom stage for manual platform conversion:

```bash
# Create custom conversion stage
crane transform 20_PlatformConversion
```

##### For Kubernetes → OpenShift: Convert Ingress to Route

```bash
# Create manual patch to convert Ingress to Route
# First, create a Route resource manually

cat > transform/20_PlatformConversion/resources/route.yaml <<'EOF'
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: web-route
  namespace: crane-test-platform
spec:
  to:
    kind: Service
    name: web-service
  port:
    targetPort: 8080
  tls:
    termination: edge
EOF

# Add to kustomization.yaml
cat >> transform/20_PlatformConversion/kustomization.yaml <<'EOF'

resources:
- route.yaml
EOF

# Create whiteout for Ingress (mark it for deletion)
# Remove Ingress from kustomization.yaml resources list
# or use patches to mark it
```

##### For OpenShift → Kubernetes: Convert Route to Ingress

```bash
# Create Ingress resource
cat > transform/20_PlatformConversion/resources/ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: crane-test-platform
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
EOF

# Add to kustomization.yaml
cat >> transform/20_PlatformConversion/kustomization.yaml <<'EOF'

resources:
- ingress.yaml
EOF

# Remove Route (whiteout) by not including it in resources list
```

### Step 4: Handle Security Context Differences

Different platforms have different security defaults:

```bash
# Create stage for security adjustments
crane transform 30_SecurityAdjustments

# Add patch for security context
cat > transform/30_SecurityAdjustments/patches/deployment-security.yaml <<'EOF'
- op: add
  path: /spec/template/spec/securityContext
  value:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
- op: add
  path: /spec/template/spec/containers/0/securityContext/runAsUser
  value: 1000
EOF

cat >> transform/30_SecurityAdjustments/kustomization.yaml <<'EOF'

patches:
- path: patches/deployment-security.yaml
  target:
    kind: Deployment
    name: web-app
EOF
```

### Step 5: Remove Platform-Specific Labels

OpenShift adds many auto-generated labels that might not be needed:

```bash
# Create stage to clean platform-specific metadata
crane transform 40_CleanPlatformMetadata

# Create patch to remove OpenShift-specific annotations/labels
cat > transform/40_CleanPlatformMetadata/patches/clean-labels.yaml <<'EOF'
- op: remove
  path: /metadata/labels/app.openshift.io~1runtime
- op: remove
  path: /metadata/annotations/openshift.io~1generated-by
EOF

cat >> transform/40_CleanPlatformMetadata/kustomization.yaml <<'EOF'

patches:
- path: patches/clean-labels.yaml
  target:
    kind: Deployment
    name: web-app
EOF
```

### Step 6: Preview All Transformations

```bash
# Preview pipeline
for stage in transform/*/; do
  echo "=== $(basename $stage) ==="
  kubectl kustomize "$stage" | grep -A 5 "kind: " | head -20
done

# Check .work/ directory for debugging
tree transform/.work/
```

### Step 7: Generate Final Output

```bash
# Run crane apply
crane apply

# Inspect output
cat output/output.yaml

# Verify platform-specific resource conversion
# Kubernetes→OpenShift: should have Route, no Ingress
# OpenShift→Kubernetes: should have Ingress, no Route
grep -E "kind: (Route|Ingress)" output/output.yaml
```

### Step 8: Validate Against Target Platform

```bash
# Switch to target cluster context
kubectl config use-context <target-cluster-context>

# For OpenShift target:
# oc config use-context <openshift-context>

# Validate syntax
kubectl apply --dry-run=client -f output/output.yaml

# Check for platform-specific issues
kubectl apply --dry-run=server -f output/output.yaml
```

### Step 9: Deploy to Target Cluster

```bash
# Create namespace
kubectl create namespace crane-test-platform
# Or for OpenShift: oc new-project crane-test-platform

# Apply manifests
kubectl apply -f output/output.yaml

# Validate deployment
kubectl get all -n crane-test-platform

# For OpenShift, check Route
# oc get route -n crane-test-platform

# For Kubernetes, check Ingress
# kubectl get ingress -n crane-test-platform
```

### Step 10: Functional Testing

```bash
# Test application accessibility
# For OpenShift Route:
# curl https://$(oc get route web-route -n crane-test-platform -o jsonpath='{.spec.host}')

# For Kubernetes Ingress:
# curl http://app.example.com (requires DNS/hosts file setup)

# Or test via Service
kubectl run test-curl --rm -i --tty --image=curlimages/curl -n crane-test-platform -- \
  curl -s http://web-service:80
```

## Validation Checklist

### Platform Resource Conversion
- [ ] Source platform-specific resources identified (Route or Ingress)
- [ ] Target platform-specific resources created
- [ ] Source platform resources removed (whiteout)
- [ ] Conversion maintains functionality (routing still works)

### Security Context
- [ ] Security contexts appropriate for target platform
- [ ] Pods start successfully on target
- [ ] No SCC violations (OpenShift) or security policy violations (Kubernetes)

### Labels and Annotations
- [ ] Platform-specific labels removed if not needed
- [ ] Required labels for target platform added
- [ ] Annotations don't conflict with target platform

### Multi-Stage Pipeline
- [ ] KubernetesPlugin cleaned base metadata
- [ ] Platform conversion stage transformed resources
- [ ] Security adjustment stage set appropriate contexts
- [ ] Metadata cleanup stage removed platform-specific fields

### Deployment
- [ ] Application deploys successfully on target platform
- [ ] Pods are Running and Ready
- [ ] Service is accessible
- [ ] External routing works (Route or Ingress)

## Expected Results

### What Should Work
- ✅ Export resources from source platform
- ✅ Transform Kubernetes base resources
- ✅ Convert platform-specific resources (Route ↔ Ingress)
- ✅ Adjust security contexts for target platform
- ✅ Deploy successfully to target platform
- ✅ Application functions on target platform

### Known Issues and Edge Cases

1. **Route → Ingress Conversion Complexity**
   - Routes have TLS termination built-in
   - Ingress might need cert-manager or external TLS
   - **Solution**: Document TLS requirements separately

2. **Ingress → Route Conversion**
   - Ingress can have multiple hosts
   - Need multiple Routes in OpenShift
   - **Solution**: Create Route per Ingress rule

3. **Security Context Constraints (OpenShift)**
   - OpenShift has stricter defaults (restricted SCC)
   - Might need to grant specific SCC
   - **Solution**: Document SCC requirements or create ServiceAccount with appropriate SCC

4. **ImageStreams**
   - OpenShift might use ImageStreams
   - Vanilla Kubernetes doesn't support them
   - **Solution**: Convert to direct image references

5. **Build Configs and DeploymentConfigs**
   - OpenShift-specific build mechanisms
   - No equivalent in vanilla Kubernetes
   - **Solution**: Convert to Deployments, document build separately

## Advanced Topics

### Using OpenshiftPlugin (if available)

```bash
# Check plugin capabilities
crane transform optionals

# Run with OpenshiftPlugin
crane transform KubernetesPlugin OpenshiftPlugin

# Inspect OpenshiftPlugin transformations
cat transform/15_OpenshiftPlugin/patches/*
```

### Handling ImageStreams

```bash
# If source has ImageStream references
# Create patch to convert to direct image reference

cat > transform/20_PlatformConversion/patches/image-refs.yaml <<'EOF'
- op: replace
  path: /spec/template/spec/containers/0/image
  value: registry.example.com/nginx:1.25
EOF
```

### Multiple Platform-Specific Resources

```bash
# Create batch conversion for multiple resources
# Use Kustomize transformers or multiple patches
```

## Time Requirements

- **Setup**: 15 minutes
- **Export**: 3 minutes  
- **Platform conversion planning**: 15 minutes
- **Multi-stage transform**: 20 minutes
- **Testing and validation**: 15 minutes
- **Deploy to target**: 10 minutes

**Total**: ~80 minutes

## Reporting

### Successful Test

```markdown
## Scenario 3: Cross-platform Migration - PASSED ✅

**Environment:**
- Source: OpenShift 4.14
- Target: Kubernetes 1.29
- Crane version: main@20260601
- OpenshiftPlugin: not available (manual conversion)

**Result:**
Successfully migrated from OpenShift to Kubernetes. Route was manually converted to Ingress. Security contexts adjusted for vanilla Kubernetes. Application deployed and functional on target.

**Positive:**
- Multi-stage pipeline made conversion logical
- .work/ directory helped debug conversion
- Manual conversion documented for future use

**Issues:**
- TLS configuration needed manual setup (cert-manager)
- OpenShift-specific labels required manual cleanup

**Suggestions:**
- Provide OpenshiftPlugin in default installation
- Add Route→Ingress conversion helper/wizard
- Document common conversion patterns
```

## Next Steps

- [Scenario 4: Customization for Target Environment](./scenario-04-customization.md)
- Test other platform combinations
- Experiment with OpenshiftPlugin if available
