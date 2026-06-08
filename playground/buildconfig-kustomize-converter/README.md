# BuildConfig to Shipwright - Kustomize Conversion

**Working implementation** of Scenario 06 - BuildConfig → Shipwright conversion using **Kustomize + Helm** (no Go plugin).

## Overview

This implementation demonstrates how to convert OpenShift BuildConfigs to Shipwright Builds using:
- ✅ **Helm templates** for conversion logic
- ✅ **Bash script** to process BuildConfigs
- ✅ **Kustomize** for resource generation
- ✅ **Native crane apply** - no custom Go plugins
- ✅ **Claude Code friendly** - easy to generate and modify

**Key advantage:** No Go programming needed, everything is Bash + YAML.

## Directory Structure

```
buildconfig-kustomize-converter/
├── README.md                          # This file
├── helm-chart/                        # Helm chart for conversion
│   └── buildconfig-to-shipwright/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           └── build.yaml
├── scripts/
│   └── converter.sh                   # Bash script for conversion
├── samples/
│   ├── buildconfig-docker.yaml        # Sample Docker strategy
│   ├── buildconfig-source.yaml        # Sample Source strategy
│   └── test-stage/                    # Example crane transform stage
└── docs/
    └── USAGE.md                       # Detailed usage guide
```

## Quick Start

### 1. Test Helm Chart

```bash
# Test chart rendering
helm template test helm-chart/buildconfig-to-shipwright/

# Test with sample values
cat > /tmp/test-values.yaml <<EOF
name: test-build
namespace: test
labels:
  app: test
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
    name: quay.io/test/app:latest
EOF

helm template test helm-chart/buildconfig-to-shipwright/ -f /tmp/test-values.yaml
```

### 2. Test Converter Script

```bash
# Make script executable
chmod +x scripts/converter.sh

# Test with sample BuildConfig
scripts/converter.sh samples/buildconfig-docker.yaml

# Should output Shipwright Build YAML
```

### 3. Use in Crane Migration

```bash
# Export BuildConfigs from OpenShift
crane export -n myapp

# Standard cleanup
crane transform KubernetesPlugin

# Create custom stage manually
mkdir -p transform/20_BuildConfigConversion
cd transform/20_BuildConfigConversion

# Copy resources from previous stage
cp -r ../10_KubernetesPlugin/resources .

# Copy converter tools
cp -r /path/to/playground/buildconfig-kustomize-converter/helm-chart .
cp /path/to/playground/buildconfig-kustomize-converter/scripts/converter.sh .
chmod +x converter.sh

# Generate Builds
mkdir -p builds
./converter.sh resources/myapp/*BuildConfig*.yaml > builds/generated-builds.yaml

# Create kustomization.yaml
cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- builds/generated-builds.yaml
EOF

# Test
kustomize build .

# Go back and apply
cd ../..
crane apply
```

## How It Works

### Runtime Generation Flow

**IMPORTANT:** Conversion happens **at `crane apply` time**, NOT during stage setup.

```
crane apply
    ↓
kustomize build transform/20_BuildConfigConversion/
    ↓
Reads kustomization.yaml → sees generator
    ↓
EXECUTES converter.sh (RUNTIME - happens NOW!)
    ↓
converter.sh reads BuildConfig YAMLs
    ↓
converter.sh extracts fields with yq
    ↓
converter.sh generates Helm values
    ↓
converter.sh calls: helm template
    ↓
converter.sh outputs Shipwright Build YAML to stdout
    ↓
Kustomize captures stdout
    ↓
Kustomize applies patches (removes BuildConfigs)
    ↓
Kustomize outputs final YAML
    ↓
crane apply merges all stages → output/output.yaml
```

**Key Point:** Generator executes **during kustomize build**, ensuring fresh conversion every time.

### Field Mapping

| BuildConfig | Shipwright Build |
|-------------|------------------|
| `spec.strategy.type: Docker` | `spec.strategy.name: buildah` |
| `spec.strategy.type: Source` | `spec.strategy.name: source-to-image` |
| `spec.strategy.dockerStrategy.dockerfilePath` | `spec.paramValues[0].name: dockerfile` |
| `spec.strategy.sourceStrategy.from.name` | `spec.paramValues[0].name: builder-image` |
| `spec.source.git.uri` | `spec.source.git.url` |
| `spec.source.git.ref` | `spec.source.git.revision` |
| `spec.output.to.name` | `spec.output.image` |

## Components

### Helm Chart

**Purpose:** Template engine for generating Shipwright Builds

**Location:** `helm-chart/buildconfig-to-shipwright/`

**Templates:**
- `build.yaml` - Main Build resource template
- Handles both Docker and Source strategies
- Conditional logic for different fields

**Usage:**
```bash
helm template <release-name> helm-chart/buildconfig-to-shipwright/ -f values.yaml
```

### Converter Script

**Purpose:** Extract BuildConfig fields and generate Helm values

**Location:** `scripts/converter.sh`

**Dependencies:**
- `yq` - YAML processor
- `helm` - Template engine
- `bash` - Shell scripting

**Usage:**
```bash
./converter.sh <buildconfig-file> [<buildconfig-file> ...]
./converter.sh resources/*BuildConfig*.yaml
```

**Output:** Shipwright Build YAML to stdout

## Sample BuildConfigs

### Docker Strategy

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: nodejs-app
  namespace: demo
spec:
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  source:
    git:
      uri: https://github.com/sclorg/nodejs-ex
      ref: master
  output:
    to:
      kind: DockerImage
      name: quay.io/myorg/nodejs-app:latest
```

**Converts to:**
```yaml
apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: nodejs-app
  namespace: demo
spec:
  strategy:
    kind: ClusterBuildStrategy
    name: buildah
  paramValues:
  - name: dockerfile
    value: Dockerfile
  source:
    type: Git
    git:
      url: https://github.com/sclorg/nodejs-ex
      revision: master
  output:
    image: quay.io/myorg/nodejs-app:latest
```

### Source Strategy

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: python-app
  namespace: demo
spec:
  strategy:
    type: Source
    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: python:3.11
  source:
    git:
      uri: https://github.com/sclorg/django-ex
      ref: master
  output:
    to:
      kind: ImageStreamTag
      name: python-app:latest
```

**Converts to:**
```yaml
apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: python-app
  namespace: demo
spec:
  strategy:
    kind: ClusterBuildStrategy
    name: source-to-image
  paramValues:
  - name: builder-image
    value: python:3.11
  source:
    type: Git
    git:
      url: https://github.com/sclorg/django-ex
      revision: master
  output:
    image: python-app:latest
```

## Integration with Crane

### Manual Stage Creation (Runtime Generation)

**IMPORTANT:** Configure Kustomize to call converter.sh **at runtime**, NOT pre-generate!

```bash
# After crane transform KubernetesPlugin
cd transform/
mkdir 20_BuildConfigConversion
cd 20_BuildConfigConversion/

# Setup
cp -r ../10_KubernetesPlugin/resources .
cp -r /path/to/playground/buildconfig-kustomize-converter/helm-chart .
cp /path/to/playground/buildconfig-kustomize-converter/scripts/converter.sh .
chmod +x converter.sh

# Create generator configuration (NOT pre-generated builds!)
cat > generator-config.yaml <<'EOF'
apiVersion: someteam.example.com/v1
kind: ShipwrightGenerator
metadata:
  name: buildconfig-converter
  annotations:
    config.kubernetes.io/function: |
      exec:
        path: ./converter.sh
        args:
        - resources
EOF

# Create kustomization.yaml that uses generator
cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

generators:
- generator-config.yaml

patches:
- target:
    kind: BuildConfig
  patch: |-
    $patch: delete
    apiVersion: build.openshift.io/v1
    kind: BuildConfig
    metadata:
      name: not-used
EOF

# Test RUNTIME generation
kustomize build --enable-alpha-plugins --enable-exec .
# converter.sh executes NOW and outputs Builds

# crane apply will execute converter.sh again (runtime!)
cd ../..
crane apply
```

### Automated with Script (Runtime Generation)

Create helper script for stage creation with **runtime generator**:

```bash
#!/bin/bash
# create-buildconfig-stage.sh

STAGE_DIR="transform/20_BuildConfigConversion"
CONVERTER_DIR="/path/to/playground/buildconfig-kustomize-converter"

mkdir -p "$STAGE_DIR"
cd "$STAGE_DIR"

# Setup
cp -r ../10_KubernetesPlugin/resources .
cp -r "$CONVERTER_DIR/helm-chart" .
cp "$CONVERTER_DIR/scripts/converter.sh" .
chmod +x converter.sh

# Create generator config (NOT pre-generated builds!)
cat > generator-config.yaml <<'EOF'
apiVersion: someteam.example.com/v1
kind: ShipwrightGenerator
metadata:
  name: buildconfig-converter
  annotations:
    config.kubernetes.io/function: |
      exec:
        path: ./converter.sh
        args:
        - resources
EOF

# Kustomization with generator
cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

generators:
- generator-config.yaml

patches:
- target:
    kind: BuildConfig
  patch: |-
    $patch: delete
    apiVersion: build.openshift.io/v1
    kind: BuildConfig
    metadata:
      name: not-used
EOF

echo "Stage created: $STAGE_DIR (with runtime generator)"
echo "Run: crane apply (converter will execute at that time)"
```

## Testing

### Test Helm Chart

```bash
cd helm-chart/buildconfig-to-shipwright/

# Lint
helm lint .

# Template with defaults
helm template test .

# Validate
helm template test . | kubectl apply --dry-run=client -f -
```

### Test Converter Script

```bash
# Test with sample
scripts/converter.sh samples/buildconfig-docker.yaml > /tmp/build.yaml

# Validate output
kubectl apply --dry-run=client -f /tmp/build.yaml

# Check fields
yq eval '.spec.strategy.name' /tmp/build.yaml
# Should be: buildah
```

### End-to-End Test

```bash
# Full workflow
crane export -n test-namespace
crane transform KubernetesPlugin
# Create stage (manual or script)
crane apply

# Verify
grep "kind: Build" output/output.yaml
grep "kind: BuildConfig" output/output.yaml  # Should be empty
```

## Troubleshooting

### Helm template fails

```bash
# Check Chart.yaml
cat helm-chart/buildconfig-to-shipwright/Chart.yaml

# Debug template
helm template test helm-chart/buildconfig-to-shipwright/ --debug

# Validate values
helm template test helm-chart/buildconfig-to-shipwright/ -f values.yaml --validate
```

### Converter script errors

```bash
# Check yq version
yq --version
# Should be v4+

# Test yq syntax
yq eval '.metadata.name' samples/buildconfig-docker.yaml

# Debug converter
bash -x scripts/converter.sh samples/buildconfig-docker.yaml
```

### No Builds generated

```bash
# Check BuildConfig files exist
ls -la resources/*BuildConfig*.yaml

# Run converter manually
scripts/converter.sh resources/*BuildConfig*.yaml

# Check output
cat builds/generated-builds.yaml
```

## Extending the Converter

### Add New Field Mapping

1. **Update Helm values.yaml** - Add new field
2. **Update Helm template** - Use new value
3. **Update converter.sh** - Extract field from BuildConfig
4. **Test** - Verify field appears in output

Example: Add build timeout

```yaml
# values.yaml
timeout: "10m"

# build.yaml template
spec:
  timeout: {{ .Values.timeout }}

# converter.sh
timeout: $(yq eval '.spec.completionDeadlineSeconds // "10m"' "$bc_file")
```

### Handle New Strategy Type

Add conditional logic in Helm template:

```yaml
{{- $strategy := "" -}}
{{- if eq .Values.strategy.type "Docker" -}}
  {{- $strategy = "buildah" -}}
{{- else if eq .Values.strategy.type "Source" -}}
  {{- $strategy = "source-to-image" -}}
{{- else if eq .Values.strategy.type "Custom" -}}
  {{- $strategy = "custom-builder" -}}
{{- end -}}
```

## Comparison with Plugin Approach

| Feature | Kustomize (This) | Go Plugin |
|---------|------------------|-----------|
| **Language** | Bash + Helm | Go |
| **Complexity** | Low-Medium | High |
| **Setup Time** | Minutes | Hours |
| **AI Friendly** | ✅ Excellent | Good |
| **Debugging** | Easy (shell) | Complex (Go debugger) |
| **Dependencies** | yq, helm | Go toolchain |
| **Performance** | Slower (shell) | Fast (compiled) |
| **Flexibility** | High (template) | High (code) |

## Known Limitations

1. **Manual stage creation** - Not automated by crane
2. **Shell dependencies** - Requires yq and helm
3. **No validation** - Converter doesn't validate BuildConfig
4. **Limited error handling** - Basic error checking only
5. **Performance** - Shell script slower than Go

## Best Practices

1. **Test Helm chart first** - Independent of converter
2. **Validate BuildConfigs** - Before running converter
3. **Pre-generate builds** - During stage creation, not at apply time
4. **Version control** - Track Helm chart and scripts in git
5. **Document mappings** - Clear field conversion reference

## Resources

- **Scenario 06:** ../test-day-june2026/scenario-06-buildconfig-kustomize-conversion.md
- **Shipwright:** https://shipwright.io/
- **Helm:** https://helm.sh/
- **yq:** https://github.com/mikefarah/yq
- **Kustomize:** https://kustomize.io/

---

**Status:** Working prototype for Kustomize-based conversion 🚀
