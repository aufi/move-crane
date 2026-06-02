# Scenario 4: Customization for Target Environment

## Description

This scenario focuses on customizing applications for a new target environment. Common customizations include:

- **Resource limits/requests** - Different cluster sizes
- **Storage classes** - Different storage providers
- **Namespaces** - Reorganizing namespace structure
- **Replica counts** - Scaling for new environment
- **Image registries** - Private registries, air-gapped environments
- **Configuration values** - Environment-specific settings
- **Network policies** - Different security requirements

## Learning Objectives

- Master Kustomize overlays for environment customization
- Learn to use configMapGenerator and secretGenerator
- Practice advanced JSONPatch techniques
- Combine multiple customization concerns in one pipeline

## Test Application: Production-Ready Application

We'll use a realistic application with multiple configuration points.

## Test Environment Setup

### 1. Deploy on Source Cluster (Dev Environment)

```bash
# Connect to source cluster
kubectl cluster-info

# Create dev namespace
kubectl create namespace app-dev
```

```bash
# Deploy development configuration
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: app-dev
data:
  environment: "development"
  log-level: "debug"
  database-host: "dev-db.internal.svc.cluster.local"
  database-port: "5432"
  database-name: "devdb"
  cache-enabled: "false"
  feature-flags: '{"new-ui": true, "beta-api": true}'
---
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: app-dev
type: Opaque
stringData:
  database-password: "dev-password-123"
  api-key: "dev-api-key-xyz"
  jwt-secret: "dev-jwt-secret"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: app-dev
  labels:
    app: backend
    tier: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: app
        image: docker.io/library/nginx:1.25
        ports:
        - containerPort: 8080
        env:
        - name: ENVIRONMENT
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: environment
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: log-level
        - name: DATABASE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: database-password
        envFrom:
        - configMapRef:
            name: app-config
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        volumeMounts:
        - name: cache
          mountPath: /cache
      volumes:
      - name: cache
        emptyDir: {}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: app-dev
  labels:
    app: frontend
    tier: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: nginx
        image: docker.io/library/nginx:1.25-alpine
        ports:
        - containerPort: 80
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
  name: backend-service
  namespace: app-dev
spec:
  selector:
    app: backend
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: app-dev
spec:
  selector:
    app: frontend
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: LoadBalancer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: app-dev
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: standard
EOF
```

### 2. Validate Source Application

```bash
kubectl get all,configmap,secret,pvc -n app-dev
kubectl wait --for=condition=ready pod -l app=backend -n app-dev --timeout=120s
```

## Migration with Crane - Target: Production Environment

Our target production environment has different requirements:
- **Namespace**: `app-production` (not `app-dev`)
- **Image registry**: Private registry `registry.prod.example.com`
- **Replicas**: Higher for production (backend: 3, frontend: 5)
- **Resources**: More generous limits for production
- **Configuration**: Production database, disabled debug logging
- **Storage**: Different storage class (`premium-ssd`)
- **Security**: Production secrets (will set separately)
- **Labels**: Production-specific labels for monitoring/alerting
- **Network**: ClusterIP for frontend (behind ingress), not LoadBalancer

## Migration Steps

### Step 1: Export from Development

```bash
mkdir -p ~/crane-test-customization
cd ~/crane-test-customization

crane export -n app-dev

ls -la export/resources/app-dev/
```

### Step 2: Base Transform - KubernetesPlugin

```bash
crane transform KubernetesPlugin

tree transform/10_KubernetesPlugin/
```

### Step 3: Create Production Customization Stage

```bash
crane transform 20_ProductionCustomization
```

### Step 4: Configure Production Settings in Stage 2

This is the main customization work. Edit the kustomization.yaml:

```bash
cat > transform/20_ProductionCustomization/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Base resources from previous stage
resources:
- configmap.yaml
- deployment.yaml
- persistentvolumeclaim.yaml
- secret.yaml
- service.yaml

# Change namespace to production
namespace: app-production

# Add production labels to all resources
commonLabels:
  environment: production
  managed-by: crane
  monitoring: enabled
  team: platform

# Add production annotations
commonAnnotations:
  crane.konveyor.io/migrated-from: "app-dev"
  crane.konveyor.io/migration-date: "2026-06-01"

# Update ConfigMap with production values
configMapGenerator:
- name: app-config
  behavior: merge
  literals:
  - environment=production
  - log-level=info
  - database-host=prod-db.prod-infra.svc.cluster.local
  - database-port=5432
  - database-name=proddb
  - cache-enabled=true
  - feature-flags={"new-ui": false, "beta-api": false}

# Note: Secrets should be managed separately in production
# This is just for demonstration
secretGenerator:
- name: app-secrets
  behavior: merge
  literals:
  - database-password=REPLACE_WITH_PROD_PASSWORD
  - api-key=REPLACE_WITH_PROD_API_KEY
  - jwt-secret=REPLACE_WITH_PROD_JWT_SECRET

# Update image references to production registry
images:
- name: docker.io/library/nginx:1.25
  newName: registry.prod.example.com/nginx
  newTag: 1.25.0
- name: docker.io/library/nginx:1.25-alpine
  newName: registry.prod.example.com/nginx
  newTag: 1.25.0-alpine

# Scale replicas for production
replicas:
- name: backend
  count: 3
- name: frontend
  count: 5

# JSON patches for complex changes
patches:
- path: patches/production-resources.yaml
  target:
    kind: Deployment
- path: patches/storage-class.yaml
  target:
    kind: PersistentVolumeClaim
- path: patches/frontend-service-type.yaml
  target:
    kind: Service
    name: frontend-service
EOF
```

### Step 5: Create Production Resource Patches

Create directory for patches:

```bash
mkdir -p transform/20_ProductionCustomization/patches
```

#### Patch 1: Production Resource Limits

```bash
cat > transform/20_ProductionCustomization/patches/production-resources.yaml <<'EOF'
# Increase resource requests/limits for production
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
```

#### Patch 2: Storage Class Change

```bash
cat > transform/20_ProductionCustomization/patches/storage-class.yaml <<'EOF'
# Change storage class to premium SSD
- op: replace
  path: /spec/storageClassName
  value: premium-ssd
# Increase storage size for production
- op: replace
  path: /spec/resources/requests/storage
  value: 10Gi
EOF
```

#### Patch 3: Frontend Service Type

```bash
cat > transform/20_ProductionCustomization/patches/frontend-service-type.yaml <<'EOF'
# Change from LoadBalancer to ClusterIP (will use Ingress)
- op: replace
  path: /spec/type
  value: ClusterIP
EOF
```

### Step 6: Add Production-Specific Resources

Add an Ingress for production:

```bash
cat > transform/20_ProductionCustomization/resources/ingress.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
  namespace: app-production
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - app.production.example.com
    secretName: frontend-tls
  rules:
  - host: app.production.example.com
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

# Add to resources in kustomization.yaml
echo "- ingress.yaml" >> transform/20_ProductionCustomization/kustomization.yaml
```

### Step 7: Add Network Policy for Production Security

```bash
cat > transform/20_ProductionCustomization/resources/networkpolicy.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-network-policy
  namespace: app-production
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from frontend
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
  egress:
  # Allow to database
  - to:
    - namespaceSelector:
        matchLabels:
          name: prod-infra
    ports:
    - protocol: TCP
      port: 5432
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

echo "- networkpolicy.yaml" >> transform/20_ProductionCustomization/kustomization.yaml
```

### Step 8: Preview Production Configuration

```bash
# Preview what will be generated
kubectl kustomize transform/20_ProductionCustomization/

# Check specific aspects
echo "=== Namespace ==="
kubectl kustomize transform/20_ProductionCustomization/ | grep "namespace:"

echo "=== Replicas ==="
kubectl kustomize transform/20_ProductionCustomization/ | grep "replicas:"

echo "=== Images ==="
kubectl kustomize transform/20_ProductionCustomization/ | grep "image:"

echo "=== Storage ==="
kubectl kustomize transform/20_ProductionCustomization/ | grep -A 3 "storageClassName"

echo "=== Resources ==="
kubectl kustomize transform/20_ProductionCustomization/ | grep -A 10 "resources:"
```

### Step 9: Create Final Stage for Manual Review

Sometimes you want a final stage where you can manually review and tweak:

```bash
crane transform 90_FinalReview

# This creates a pass-through stage with all previous transformations applied
# You can manually edit resources here if needed

tree transform/90_FinalReview/
```

### Step 10: Generate Final Output

```bash
crane apply

# Review output
cat output/output.yaml | head -100

# Count resources
echo "=== Resource counts ==="
grep "^kind:" output/output.yaml | sort | uniq -c
```

### Step 11: Validate Production Configuration

```bash
# Syntax validation
kubectl apply --dry-run=client -f output/output.yaml

# Validate against production cluster (if accessible)
kubectl apply --dry-run=server -f output/output.yaml --context=<prod-cluster-context>

# Check specific configurations
echo "=== Backend replicas ==="
grep -A 2 "name: backend" output/output.yaml | grep "replicas:"

echo "=== Frontend replicas ==="
grep -A 2 "name: frontend" output/output.yaml | grep "replicas:"

echo "=== Image registry ==="
grep "image:" output/output.yaml | head -5
```

### Step 12: Handle Production Secrets Separately

**Important**: Don't commit production secrets to Git!

```bash
# Create separate sealed secret or use external secret management
# Example with kubectl create secret (not recommended for real prod)

kubectl create secret generic app-secrets \
  --from-literal=database-password='ACTUAL_PROD_PASSWORD' \
  --from-literal=api-key='ACTUAL_PROD_API_KEY' \
  --from-literal=jwt-secret='ACTUAL_PROD_JWT_SECRET' \
  -n app-production \
  --dry-run=client -o yaml > production-secrets.yaml

# Then apply this separately, never commit to Git
echo "production-secrets.yaml" >> .gitignore
```

### Step 13: Deploy to Production

```bash
# Switch to production cluster
kubectl config use-context <prod-cluster-context>

# Create namespace
kubectl create namespace app-production

# Apply production secrets first (from secure vault/store)
kubectl apply -f production-secrets.yaml

# Apply migrated application
kubectl apply -f output/output.yaml

# Validate deployment
kubectl get all,ingress,pvc,networkpolicy -n app-production
kubectl wait --for=condition=ready pod -l app=backend -n app-production --timeout=300s
kubectl wait --for=condition=ready pod -l app=frontend -n app-production --timeout=300s
```

### Step 14: Production Validation

```bash
# Check pod distribution
kubectl get pods -n app-production -o wide

# Verify replicas
kubectl get deployment -n app-production

# Check PVC storage class
kubectl get pvc -n app-production -o custom-columns=NAME:.metadata.name,STORAGECLASS:.spec.storageClassName,SIZE:.spec.resources.requests.storage

# Test backend
kubectl run test-curl --rm -i --tty --image=curlimages/curl -n app-production -- \
  curl -s http://backend-service:8080

# Check Ingress
kubectl get ingress -n app-production

# Verify network policy
kubectl get networkpolicy -n app-production
kubectl describe networkpolicy backend-network-policy -n app-production
```

## Validation Checklist

### Environment Customization
- [ ] Namespace changed to app-production
- [ ] ConfigMap has production values (log-level=info, production DB host)
- [ ] Secrets marked for production replacement (not dev values)
- [ ] Feature flags disabled for production

### Scaling and Resources
- [ ] Backend scaled to 3 replicas
- [ ] Frontend scaled to 5 replicas
- [ ] Resource requests increased (512Mi memory, 500m CPU)
- [ ] Resource limits increased (1Gi memory, 1000m CPU)

### Infrastructure
- [ ] Image registry changed to registry.prod.example.com
- [ ] Storage class changed to premium-ssd
- [ ] PVC size increased to 10Gi
- [ ] Frontend Service changed from LoadBalancer to ClusterIP

### Security
- [ ] Production Ingress created with TLS
- [ ] Network policy created for backend
- [ ] Production-specific labels and annotations added

### Production Readiness
- [ ] All pods Running and Ready
- [ ] Correct replica counts achieved
- [ ] Ingress configured and accessible
- [ ] Network policy enforced
- [ ] Monitoring labels present

## Expected Results

### What Should Work
- ✅ Comprehensive environment customization using Kustomize
- ✅ ConfigMap values updated for production
- ✅ Scaling adjustments for production load
- ✅ Resource limits appropriate for production
- ✅ Storage class and size adjusted
- ✅ Image registry redirected to private registry
- ✅ Security hardening with Network Policy
- ✅ Production-ready deployment with Ingress

### Known Issues and Edge Cases

1. **ConfigMapGenerator Name Hashing**
   - Kustomize adds hash suffix by default
   - May break Deployment references
   - **Solution**: Add `generatorOptions: {disableNameSuffixHash: true}`

2. **Secret Management**
   - Secrets in YAML are base64, not encrypted
   - Should use external secret management
   - **Solution**: Use SealedSecrets, External Secrets Operator, or Vault

3. **Storage Class Availability**
   - premium-ssd might not exist on target cluster
   - **Solution**: Verify storage classes first: `kubectl get storageclass`

4. **Network Policy Conflicts**
   - Overly restrictive policies can break application
   - **Solution**: Test in staging first

5. **Image Pull Secrets**
   - Private registry requires authentication
   - **Solution**: Create imagePullSecrets and reference in Deployments

## Advanced Customization Techniques

### Using Kustomize Components

```bash
# Create reusable component for monitoring
cat > transform/20_ProductionCustomization/components/monitoring.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1alpha1
kind: Component

commonLabels:
  prometheus.io/scrape: "true"

commonAnnotations:
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
EOF

# Reference in kustomization.yaml
# components:
# - components/monitoring.yaml
```

### Strategic Merge Patches

```bash
# Alternative to JSONPatch - strategic merge
cat > transform/20_ProductionCustomization/patches/backend-strategic.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  template:
    spec:
      containers:
      - name: app
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
EOF
```

### Using Replacements for Cross-Resource References

```bash
# Kustomize replacements for dynamic values
# See Kustomize documentation for advanced replacement patterns
```

## Time Requirements

- **Setup**: 15 minutes
- **Export**: 2 minutes
- **Production customization planning**: 20 minutes
- **Creating patches and resources**: 25 minutes
- **Validation and testing**: 15 minutes
- **Deploy to production**: 10 minutes

**Total**: ~90 minutes

## Reporting

### Successful Test

```markdown
## Scenario 4: Production Customization - PASSED ✅

**Environment:**
- Source: Kubernetes 1.28 (dev)
- Target: Kubernetes 1.29 (prod)
- Crane version: main@20260601

**Result:**
Successfully customized application for production environment. All customizations applied correctly: namespace, replicas, resources, storage, registry, security. Application deployed and functional in production.

**Positive:**
- Kustomize integration very powerful
- Multi-stage approach kept customizations organized
- Easy to preview changes before applying
- ConfigMapGenerator and replica transformers worked perfectly

**Issues:**
- ConfigMap name hashing initially broke references (solved with disableNameSuffixHash)
- Network Policy testing needed iteration

**Suggestions:**
- Add examples for common customization patterns
- Document secret management best practices
- Provide templates for production hardening
```

## Next Steps

- Integrate with GitOps workflows (ArgoCD, Flux)
- Add CI/CD pipeline for automated migrations
- Create reusable customization templates
- Test rollback procedures

## Related Documentation

- [Kustomize Documentation](https://kubectl.docs.kubernetes.io/references/kustomize/)
- [Multi-Stage Transform Guide](../../notes/transform-multistage.md)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
