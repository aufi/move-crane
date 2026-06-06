# BuildConfig Converter - Testing Guide

Complete testing guide for the BuildConfig to Shipwright converter.

## Test Levels

### 1. Helm Template Testing

Test Helm chart independently before plugin integration.

#### Test Basic Rendering

```bash
cd helm-chart/shipwright-build/

# Test with default values
helm template test .

# Test with Docker strategy
helm template test . -f ../../samples/helm-values-docker.yaml

# Test with Source strategy
helm template test . -f ../../samples/helm-values-source.yaml

# Validate output
helm template test . | kubectl apply --dry-run=client -f -
```

#### Create Test Values Files

**Docker strategy values:**
```bash
cat > samples/helm-values-docker.yaml <<'EOF'
buildconfig:
  name: test-docker-build
  namespace: test
  labels:
    app: test-app
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
      env:
      - name: ENV
        value: test
  source:
    type: Git
    git:
      uri: https://github.com/example/repo
      ref: main
  output:
    to:
      kind: DockerImage
      name: quay.io/test/image:latest
EOF
```

**Source strategy values:**
```bash
cat > samples/helm-values-source.yaml <<'EOF'
buildconfig:
  name: test-s2i-build
  namespace: test
  strategy:
    type: Source
    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: python:3.11
        namespace: openshift
      env:
      - name: PIP_INDEX
        value: https://pypi.org/simple
  source:
    type: Git
    git:
      uri: https://github.com/example/python-app
      ref: main
  output:
    to:
      kind: ImageStreamTag
      name: python-app:latest
EOF
```

### 2. Plugin Unit Testing

Test plugin in standalone mode.

```bash
cd plugin/

# Build plugin
./build.sh

# Test with Docker BuildConfig
./buildconfig-converter --test ../samples/buildconfig-docker.yaml

# Test with Source BuildConfig
./buildconfig-converter --test ../samples/buildconfig-source.yaml

# Test with complex BuildConfig
./buildconfig-converter --test ../samples/buildconfig-complex.yaml
```

**Expected output:**
- Plugin processes BuildConfig
- Generates Shipwright Build YAML
- Shows conversion mappings
- No errors

**Verify output contains:**
- `kind: Build`
- `apiVersion: shipwright.io/v1beta1`
- `spec.strategy.name: buildah` (for Docker) or `source-to-image` (for Source)
- Environment variables preserved
- Git source configured
- Output image set

### 3. Integration Testing with Crane

**Prerequisites:**
- crane v0.1.0+ (with NewResources support)
- kubectl access to source cluster
- Sample BuildConfigs deployed

#### Deploy Test BuildConfigs

```bash
# Create test namespace
kubectl create namespace buildconfig-test

# Deploy Docker strategy BuildConfig
kubectl apply -f samples/buildconfig-docker.yaml

# Deploy Source strategy BuildConfig
kubectl apply -f samples/buildconfig-source.yaml

# Verify
kubectl get buildconfigs -n buildconfig-test
```

#### Run Crane Transformation

```bash
# Create migration workspace
mkdir -p ~/test-migration
cd ~/test-migration

# Export BuildConfigs
crane export -n buildconfig-test

# Verify export
ls -la export/resources/buildconfig-test/
grep "kind: BuildConfig" export/resources/buildconfig-test/*.yaml

# Stage 1: KubernetesPlugin
crane transform KubernetesPlugin

# Stage 2: BuildConfigConverter (our custom plugin)
crane transform BuildConfigConverter

# Check Stage 2 output
tree transform/20_BuildConfigConverter/
ls -la transform/20_BuildConfigConverter/resources/buildconfig-test/

# Verify Build resources generated
grep "kind: Build" transform/20_BuildConfigConverter/resources/buildconfig-test/*.yaml

# Verify BuildConfigs whited out (should not exist in Stage 2)
ls transform/20_BuildConfigConverter/resources/buildconfig-test/ | grep BuildConfig
# Should return nothing

# Generate final output
crane apply

# Verify final output
cat output/output.yaml | grep "^kind:"
# Should show: Build (not BuildConfig)
```

### 4. End-to-End Testing

Full workflow from source OpenShift to target Kubernetes with Shipwright.

#### Prerequisites

- Source cluster: OpenShift with BuildConfigs
- Target cluster: Kubernetes with Shipwright installed

#### E2E Test Steps

```bash
# 1. Deploy test app to source OpenShift
kubectl config use-context <source-openshift>
kubectl create namespace e2e-test
kubectl apply -f samples/buildconfig-docker.yaml -n e2e-test

# 2. Export
mkdir -p ~/e2e-test-migration
cd ~/e2e-test-migration
crane export -n e2e-test

# 3. Transform
crane transform KubernetesPlugin
crane transform BuildConfigConverter

# 4. Apply
crane apply

# 5. Deploy to target Kubernetes
kubectl config use-context <target-k8s>
kubectl create namespace e2e-test
kubectl apply -f output/output.yaml

# 6. Verify Build resource
kubectl get builds -n e2e-test
kubectl describe build nodejs-docker-build -n e2e-test

# 7. Trigger BuildRun
cat <<EOF | kubectl apply -f -
apiVersion: shipwright.io/v1beta1
kind: BuildRun
metadata:
  name: test-build-run
  namespace: e2e-test
spec:
  build:
    name: nodejs-docker-build
EOF

# 8. Watch BuildRun
kubectl get buildrun -n e2e-test -w

# 9. Check logs
kubectl logs -f buildrun/test-build-run -n e2e-test

# 10. Verify image built and pushed
kubectl get buildrun test-build-run -n e2e-test -o yaml | grep "succeeded:"
```

## Test Cases

### Test Case 1: Docker Strategy - Basic

**Input:** `samples/buildconfig-docker.yaml`

**Expected:**
- Strategy: `buildah`
- Parameter: `dockerfile: Dockerfile`
- Env vars: NODE_ENV=production, BUILD_LOGLEVEL=verbose
- Build args: NPM_MIRROR, NODE_VERSION
- Git source: sclorg/nodejs-ex
- Output image: quay.io/example/nodejs-app:latest

**Validation:**
```bash
./buildconfig-converter --test samples/buildconfig-docker.yaml | grep "strategy:"
# Should show: name: buildah

./buildconfig-converter --test samples/buildconfig-docker.yaml | grep "dockerfile"
# Should show: value: Dockerfile
```

### Test Case 2: Source Strategy - S2I

**Input:** `samples/buildconfig-source.yaml`

**Expected:**
- Strategy: `source-to-image`
- Parameter: `builder-image: image-registry.openshift-image-registry.svc:5000/openshift/python:3.11`
- Env vars: PIP_INDEX_URL, UPGRADE_PIP_TO_LATEST
- Git source: sclorg/django-ex
- Clone secret: git-credentials
- Output: image-registry.openshift-image-registry.svc:5000/buildconfig-test/python-app:latest

**Validation:**
```bash
./buildconfig-converter --test samples/buildconfig-source.yaml | grep "strategy:"
# Should show: name: source-to-image

./buildconfig-converter --test samples/buildconfig-source.yaml | grep "builder-image"
# Should show converted ImageStreamTag
```

### Test Case 3: Complex BuildConfig

**Input:** `samples/buildconfig-complex.yaml`

**Expected:**
- All labels preserved
- All annotations preserved
- Multiple env vars
- Multiple build args
- Custom Dockerfile path: docker/Dockerfile.prod
- Context dir: services/api
- Git ref: release/v2.0

**Validation:**
```bash
./buildconfig-converter --test samples/buildconfig-complex.yaml > /tmp/complex-output.yaml

# Check labels preserved
grep "environment: production" /tmp/complex-output.yaml
grep "team: platform" /tmp/complex-output.yaml

# Check dockerfile path
grep "docker/Dockerfile.prod" /tmp/complex-output.yaml

# Check git ref
grep "release/v2.0" /tmp/complex-output.yaml
```

## Automated Test Suite

Create automated test script:

```bash
cat > test-all.sh <<'EOF'
#!/bin/bash
set -e

echo "=== BuildConfig Converter Test Suite ==="
echo ""

FAILED=0
PASSED=0

# Test 1: Helm chart renders
echo "Test 1: Helm chart rendering..."
if helm template test helm-chart/shipwright-build/ > /dev/null 2>&1; then
    echo "  ✓ PASS"
    ((PASSED++))
else
    echo "  ✗ FAIL"
    ((FAILED++))
fi

# Test 2: Plugin builds
echo "Test 2: Plugin build..."
if cd plugin && ./build.sh > /dev/null 2>&1 && cd ..; then
    echo "  ✓ PASS"
    ((PASSED++))
else
    echo "  ✗ FAIL"
    ((FAILED++))
fi

# Test 3: Docker BuildConfig conversion
echo "Test 3: Docker strategy conversion..."
if plugin/buildconfig-converter --test samples/buildconfig-docker.yaml 2>&1 | grep -q "kind: Build"; then
    echo "  ✓ PASS"
    ((PASSED++))
else
    echo "  ✗ FAIL"
    ((FAILED++))
fi

# Test 4: Source BuildConfig conversion
echo "Test 4: Source strategy conversion..."
if plugin/buildconfig-converter --test samples/buildconfig-source.yaml 2>&1 | grep -q "source-to-image"; then
    echo "  ✓ PASS"
    ((PASSED++))
else
    echo "  ✗ FAIL"
    ((FAILED++))
fi

# Test 5: Complex BuildConfig conversion
echo "Test 5: Complex BuildConfig conversion..."
if plugin/buildconfig-converter --test samples/buildconfig-complex.yaml 2>&1 | grep -q "docker/Dockerfile.prod"; then
    echo "  ✓ PASS"
    ((PASSED++))
else
    echo "  ✗ FAIL"
    ((FAILED++))
fi

echo ""
echo "=== Test Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
EOF

chmod +x test-all.sh
```

Run automated tests:
```bash
./test-all.sh
```

## Performance Testing

### Test Conversion Speed

```bash
# Time single conversion
time plugin/buildconfig-converter --test samples/buildconfig-docker.yaml > /dev/null

# Typical: < 500ms (includes helm template execution)
```

### Test with Many BuildConfigs

```bash
# Generate 100 BuildConfigs
for i in {1..100}; do
  sed "s/nodejs-docker-build/build-$i/" samples/buildconfig-docker.yaml > /tmp/bc-$i.yaml
done

# Time batch conversion
time for f in /tmp/bc-*.yaml; do
  plugin/buildconfig-converter --test $f > /dev/null
done

# Cleanup
rm /tmp/bc-*.yaml
```

## Troubleshooting Tests

### helm template fails

```bash
# Debug Helm chart
helm template test helm-chart/shipwright-build/ --debug

# Check for syntax errors
helm lint helm-chart/shipwright-build/
```

### Plugin crashes

```bash
# Run with verbose output (edit main.go to add debug prints)
./buildconfig-converter --test samples/buildconfig-docker.yaml 2>&1 | less

# Check helm is in PATH
which helm
helm version
```

### Conversion produces invalid Build

```bash
# Validate generated YAML
./buildconfig-converter --test samples/buildconfig-docker.yaml > /tmp/build.yaml
kubectl apply --dry-run=client -f /tmp/build.yaml

# Check against Shipwright CRD
kubectl explain build.spec
```

## Test Checklist

Before considering the implementation complete:

- [ ] Helm chart renders without errors
- [ ] Plugin builds successfully
- [ ] Docker strategy converts correctly
- [ ] Source strategy converts correctly
- [ ] Environment variables preserved
- [ ] Build args converted (Docker)
- [ ] Builder image resolved (Source)
- [ ] Git source configured
- [ ] Git secrets preserved
- [ ] Output image correct
- [ ] Push secrets preserved
- [ ] Labels preserved
- [ ] Annotations added
- [ ] BuildConfig whited out (IsWhiteOut=true)
- [ ] Generated Build validates with kubectl
- [ ] Integration with crane works
- [ ] End-to-end test passes

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Test BuildConfig Converter
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - uses: actions/setup-go@v4
      with:
        go-version: '1.21'
    
    - name: Install Helm
      run: |
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    
    - name: Run tests
      run: |
        cd playground/buildconfig-converter
        ./test-all.sh
```

---

**Next:** See [ARCHITECTURE.md](ARCHITECTURE.md) for implementation details
