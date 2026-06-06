#!/bin/bash
set -e

# Quick test script for Helm chart

echo "=== Testing Helm Chart ==="
echo ""

CHART_DIR="helm-chart/shipwright-build"
SAMPLES_DIR="samples"

# Test 1: Lint chart
echo "Test 1: Linting Helm chart..."
if helm lint "$CHART_DIR"; then
    echo "✓ Chart lint passed"
else
    echo "✗ Chart lint failed"
    exit 1
fi
echo ""

# Test 2: Render with default values
echo "Test 2: Rendering with default values..."
if helm template test "$CHART_DIR" > /dev/null; then
    echo "✓ Default values render succeeded"
else
    echo "✗ Default values render failed"
    exit 1
fi
echo ""

# Test 3: Test Docker strategy
echo "Test 3: Testing Docker strategy conversion..."
cat > /tmp/docker-values.yaml <<'EOF'
buildconfig:
  name: docker-test
  namespace: test
  labels:
    app: docker-app
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
      env:
      - name: ENV
        value: prod
  source:
    type: Git
    git:
      uri: https://github.com/example/app
      ref: main
  output:
    to:
      kind: DockerImage
      name: quay.io/test/app:latest
EOF

helm template test "$CHART_DIR" -f /tmp/docker-values.yaml > /tmp/docker-build.yaml

if grep -q "kind: Build" /tmp/docker-build.yaml && \
   grep -q "name: buildah" /tmp/docker-build.yaml && \
   grep -q "dockerfile" /tmp/docker-build.yaml; then
    echo "✓ Docker strategy conversion correct"
else
    echo "✗ Docker strategy conversion failed"
    cat /tmp/docker-build.yaml
    exit 1
fi
echo ""

# Test 4: Test Source strategy
echo "Test 4: Testing Source strategy conversion..."
cat > /tmp/source-values.yaml <<'EOF'
buildconfig:
  name: source-test
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

helm template test "$CHART_DIR" -f /tmp/source-values.yaml > /tmp/source-build.yaml

if grep -q "kind: Build" /tmp/source-build.yaml && \
   grep -q "name: source-to-image" /tmp/source-build.yaml && \
   grep -q "builder-image" /tmp/source-build.yaml; then
    echo "✓ Source strategy conversion correct"
else
    echo "✗ Source strategy conversion failed"
    cat /tmp/source-build.yaml
    exit 1
fi
echo ""

# Test 5: Validate against Kubernetes
echo "Test 5: Validating generated YAML..."
if kubectl apply --dry-run=client -f /tmp/docker-build.yaml > /dev/null 2>&1; then
    echo "✓ Generated YAML is valid Kubernetes resource"
else
    echo "⚠ Warning: kubectl validation failed (Shipwright CRD may not be installed)"
fi
echo ""

# Cleanup
rm -f /tmp/docker-values.yaml /tmp/source-values.yaml /tmp/docker-build.yaml /tmp/source-build.yaml

echo "=== All Helm tests passed! ==="
echo ""
echo "To view generated Build:"
echo "  helm template test $CHART_DIR -f samples/<values-file>"
