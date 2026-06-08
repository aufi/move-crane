# Scenario 6: BuildConfig to Shipwright Conversion with Kustomize (optional, experimental)

**Priority:** 6 - Advanced Transformation with Custom Stage  
**Goal:** Convert OpenShift BuildConfig to Shipwright Build using custom crane stage with Kustomize generators

**Working Implementation:** [playground/buildconfig-kustomize-converter/](../playground/buildconfig-kustomize-converter/)

## Objective

Demonstrate how to implement complex resource transformation **without custom Go plugins** by using:
1. **Custom crane transform stage** with Kustomize configuration
2. **Helm templates** for BuildConfig → Shipwright conversion
3. **Kustomize generators** to create new resources
4. **Bash scripts** executed via Kustomize exec plugin pattern
5. **Native crane apply** - all conversion happens during `crane apply` using standard Kustomize

**Key difference from plugin approach:** No Go code needed, everything runs natively through Kustomize.

**Reference Implementation:** A complete working example with Helm chart, converter script, and samples is available in [playground/buildconfig-kustomize-converter/](../playground/buildconfig-kustomize-converter/). You can use this as a starting point or reference.

## Background: BuildConfig vs Shipwright Build

OpenShift BuildConfig and Shipwright Build serve the same purpose (building container images) but use different APIs:

**OpenShift BuildConfig:**
- API: `build.openshift.io/v1`
- Strategies: Docker, Source (S2I), Custom, Pipeline
- Integrated with OpenShift image registry
- Triggers (webhook, config change, image change)

**Shipwright Build:**
- API: `shipwright.io/v1beta1`
- Strategies: ClusterBuildStrategy (buildah, s2i, etc.)
- Registry-agnostic
- BuildRun for execution (one-time or automated via Tekton)

## Conversion Approach

Instead of a Go plugin, we use **Kustomize generators** that execute **at runtime** during `crane apply`:

```
┌─────────────────────────────────────────────────────────────────┐
│  crane apply                                                    │
└───────────────────────────┬─────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  kustomize build transform/20_BuildConfigConversion/            │
│                                                                 │
│  1. Read kustomization.yaml                                     │
│  2. See generator: converter.sh                                 │
│  3. EXECUTE converter.sh (RUNTIME - happens NOW)                │
│     ├─→ converter reads BuildConfig YAMLs                       │
│     ├─→ converter extracts fields with yq                       │
│     ├─→ converter generates Helm values                         │
│     ├─→ converter calls: helm template                          │
│     └─→ converter outputs Shipwright Build YAML to stdout      │
│  4. Kustomize captures stdout                                   │
│  5. Apply patches (remove BuildConfigs)                         │
│  6. Output final YAML                                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│  output/output.yaml (contains Shipwright Builds)                │
└─────────────────────────────────────────────────────────────────┘
```

**Key Point:** Conversion happens **at `crane apply` time**, NOT during stage creation.

**Benefits:**
- ✅ No pre-generation needed
- ✅ Always uses latest BuildConfig data
- ✅ crane apply controls entire workflow
- ✅ Repeatable and deterministic
- ✅ Easy to test (just run kustomize build)

## Prerequisites

### Software
- **crane** (latest)
- **kubectl/oc** - Access to OpenShift cluster
- **helm** (v3+)
- **kustomize** (v5+)
- **yq** - YAML processor
- **Claude Code** or similar AI assistant

### Cluster Requirements
- **Source:** OpenShift cluster with BuildConfigs
- **Target:** Kubernetes cluster with Shipwright installed

### Install Shipwright

```bash
# Switch to target cluster
kubectl config use-context <target-k8s>

# Install Shipwright Operator
kubectl apply -f https://github.com/shipwright-io/operator/releases/latest/download/release.yaml

# Install sample BuildStrategies
kubectl apply -f https://github.com/shipwright-io/build/releases/latest/download/sample-strategies.yaml

# Verify
kubectl get clusterbuildstrategies
# Should see: buildah, buildpacks-v3, kaniko, ko, source-to-image
```

## Implementation with Claude Code

### Step 1: Deploy Sample BuildConfig

```bash
# Switch to source OpenShift cluster
kubectl config use-context <source-openshift>

# Create test namespace
kubectl create namespace buildconfig-demo

# Deploy sample BuildConfig
cat <<'EOF' | kubectl apply -f -
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: nodejs-app
  namespace: buildconfig-demo
  labels:
    app: nodejs-app
    build-type: docker
spec:
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
      env:
      - name: NODE_ENV
        value: production
      buildArgs:
      - name: NODE_VERSION
        value: "18"
  source:
    type: Git
    git:
      uri: https://github.com/sclorg/nodejs-ex
      ref: master
  output:
    to:
      kind: DockerImage
      name: quay.io/myorg/nodejs-app:latest
    pushSecret:
      name: quay-push-secret
---
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: python-app
  namespace: buildconfig-demo
  labels:
    app: python-app
    build-type: source
spec:
  strategy:
    type: Source
    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: python:3.11
        namespace: openshift
      env:
      - name: PIP_INDEX_URL
        value: https://pypi.org/simple
  source:
    type: Git
    git:
      uri: https://github.com/sclorg/django-ex
      ref: master
  output:
    to:
      kind: ImageStreamTag
      name: python-app:latest
EOF

# Verify
kubectl get buildconfigs -n buildconfig-demo
```

### Step 2: Export with Crane

```bash
# Create migration workspace
mkdir -p ~/buildconfig-migration
cd ~/buildconfig-migration

# Export BuildConfigs
crane export -n buildconfig-demo

# Verify exported BuildConfigs
ls -la export/resources/buildconfig-demo/
grep "kind: BuildConfig" export/resources/buildconfig-demo/*.yaml
```

### Step 3: Create Helm Chart for Conversion

Use Claude Code to create Helm chart that converts BuildConfig to Shipwright Build.

**Quick Start:** A working Helm chart is available at [playground/buildconfig-kustomize-converter/helm-chart/buildconfig-to-shipwright/](../playground/buildconfig-kustomize-converter/helm-chart/buildconfig-to-shipwright/). You can copy it or use as reference.

**Prompt to Claude Code:**

```
Create a Helm chart in helm-chart/buildconfig-to-shipwright/ that converts OpenShift BuildConfig to Shipwright Build.

The chart should:
1. Accept BuildConfig spec as values
2. Output Shipwright Build resource
3. Handle both Docker and Source strategies
4. Map:
   - Docker strategy → buildah ClusterBuildStrategy
   - Source strategy → source-to-image ClusterBuildStrategy
   - dockerfilePath → paramValues[dockerfile]
   - sourceStrategy.from → paramValues[builder-image]
   - git source → source.git
   - output → output.image

Chart structure:
helm-chart/buildconfig-to-shipwright/
├── Chart.yaml
├── values.yaml (with BuildConfig fields)
└── templates/
    └── build.yaml (Shipwright Build template)

The values.yaml should have structure matching BuildConfig spec.
The template should generate Shipwright Build with proper field mapping.
```

**Expected Output from Claude Code:**

<details>
<summary>helm-chart/buildconfig-to-shipwright/Chart.yaml</summary>

```yaml
apiVersion: v2
name: buildconfig-to-shipwright
description: Converts OpenShift BuildConfig to Shipwright Build
version: 1.0.0
```
</details>

<details>
<summary>helm-chart/buildconfig-to-shipwright/values.yaml</summary>

```yaml
# BuildConfig fields (populated by converter script)
name: ""
namespace: ""
labels: {}

strategy:
  type: ""  # Docker or Source
  dockerStrategy:
    dockerfilePath: "Dockerfile"
    env: []
    buildArgs: []
  sourceStrategy:
    from:
      kind: ""
      name: ""
      namespace: ""
    env: []

source:
  type: ""
  git:
    uri: ""
    ref: ""
  sourceSecret: ""

output:
  to:
    kind: ""
    name: ""
  pushSecret: ""
```
</details>

<details>
<summary>helm-chart/buildconfig-to-shipwright/templates/build.yaml</summary>

```yaml
{{- $strategy := "" -}}
{{- if eq .Values.strategy.type "Docker" -}}
  {{- $strategy = "buildah" -}}
{{- else if eq .Values.strategy.type "Source" -}}
  {{- $strategy = "source-to-image" -}}
{{- end -}}

apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: {{ .Values.name }}
  namespace: {{ .Values.namespace }}
  labels:
    {{- toYaml .Values.labels | nindent 4 }}
    converted-from: buildconfig
  annotations:
    crane.konveyor.io/original-kind: "BuildConfig"
    crane.konveyor.io/conversion-method: "kustomize-helm"
spec:
  strategy:
    kind: ClusterBuildStrategy
    name: {{ $strategy }}

  {{- if eq .Values.strategy.type "Docker" }}
  paramValues:
  {{- if .Values.strategy.dockerStrategy.dockerfilePath }}
  - name: dockerfile
    value: {{ .Values.strategy.dockerStrategy.dockerfilePath | quote }}
  {{- end }}
  {{- range .Values.strategy.dockerStrategy.buildArgs }}
  - name: build-args
    value: {{ printf "%s=%s" .name .value | quote }}
  {{- end }}

  {{- if .Values.strategy.dockerStrategy.env }}
  env:
  {{- toYaml .Values.strategy.dockerStrategy.env | nindent 2 }}
  {{- end }}
  {{- end }}

  {{- if eq .Values.strategy.type "Source" }}
  {{- if .Values.strategy.sourceStrategy.from.name }}
  paramValues:
  - name: builder-image
    value: {{ .Values.strategy.sourceStrategy.from.name | quote }}
  {{- end }}

  {{- if .Values.strategy.sourceStrategy.env }}
  env:
  {{- toYaml .Values.strategy.sourceStrategy.env | nindent 2 }}
  {{- end }}
  {{- end }}

  {{- if eq .Values.source.type "Git" }}
  source:
    type: Git
    git:
      url: {{ .Values.source.git.uri | quote }}
      {{- if .Values.source.git.ref }}
      revision: {{ .Values.source.git.ref | quote }}
      {{- end }}
      {{- if .Values.source.sourceSecret }}
      cloneSecret: {{ .Values.source.sourceSecret | quote }}
      {{- end }}
  {{- end }}

  output:
    image: {{ .Values.output.to.name | quote }}
    {{- if .Values.output.pushSecret }}
    pushSecret: {{ .Values.output.pushSecret | quote }}
    {{- end }}
```
</details>

### Step 4: Create Converter Script

Use Claude Code to create Bash script that processes BuildConfigs.

**Quick Start:** A working converter script is available at [playground/buildconfig-kustomize-converter/scripts/converter.sh](../playground/buildconfig-kustomize-converter/scripts/converter.sh). Test it with the provided samples or use as reference.

**Prompt to Claude Code:**

```
Create a Bash script converter.sh that:
1. Reads all BuildConfig YAML files from stdin or current directory
2. For each BuildConfig:
   - Extract name, namespace, labels
   - Extract strategy (type, dockerStrategy or sourceStrategy)
   - Extract source (git uri, ref)
   - Extract output (image name, push secret)
3. Generate Helm values file for each BuildConfig
4. Run: helm template <name> helm-chart/buildconfig-to-shipwright/ -f values-<name>.yaml
5. Output Shipwright Build YAML to stdout

The script should handle:
- Multiple BuildConfigs in one run
- Both Docker and Source strategies
- Missing optional fields (graceful defaults)
- YAML document separators (---)

Dependencies: yq, helm
```

**Expected Output from Claude Code:**

<details>
<summary>converter.sh</summary>

```bash
#!/bin/bash
set -e

# converter.sh - Convert BuildConfig to Shipwright Build using Helm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_CHART="${SCRIPT_DIR}/helm-chart/buildconfig-to-shipwright"

# Check dependencies
command -v yq >/dev/null 2>&1 || { echo "Error: yq not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "Error: helm not found"; exit 1; }

# Process BuildConfig files
process_buildconfig() {
    local bc_file="$1"
    
    # Check if it's a BuildConfig
    local kind=$(yq eval '.kind' "$bc_file")
    if [ "$kind" != "BuildConfig" ]; then
        echo "Skipping non-BuildConfig: $bc_file" >&2
        return
    fi
    
    local name=$(yq eval '.metadata.name' "$bc_file")
    local namespace=$(yq eval '.metadata.namespace' "$bc_file")
    
    echo "Processing BuildConfig: $name" >&2
    
    # Generate Helm values
    local values_file="/tmp/bc-values-${name}.yaml"
    
    cat > "$values_file" <<EOF
name: $name
namespace: $namespace
labels: $(yq eval '.metadata.labels' "$bc_file")
strategy:
  type: $(yq eval '.spec.strategy.type' "$bc_file")
  dockerStrategy:
    dockerfilePath: $(yq eval '.spec.strategy.dockerStrategy.dockerfilePath // "Dockerfile"' "$bc_file")
    env: $(yq eval '.spec.strategy.dockerStrategy.env // []' "$bc_file")
    buildArgs: $(yq eval '.spec.strategy.dockerStrategy.buildArgs // []' "$bc_file")
  sourceStrategy:
    from:
      kind: $(yq eval '.spec.strategy.sourceStrategy.from.kind // ""' "$bc_file")
      name: $(yq eval '.spec.strategy.sourceStrategy.from.name // ""' "$bc_file")
      namespace: $(yq eval '.spec.strategy.sourceStrategy.from.namespace // ""' "$bc_file")
    env: $(yq eval '.spec.strategy.sourceStrategy.env // []' "$bc_file")
source:
  type: $(yq eval '.spec.source.type' "$bc_file")
  git:
    uri: $(yq eval '.spec.source.git.uri // ""' "$bc_file")
    ref: $(yq eval '.spec.source.git.ref // ""' "$bc_file")
  sourceSecret: $(yq eval '.spec.source.sourceSecret.name // ""' "$bc_file")
output:
  to:
    kind: $(yq eval '.spec.output.to.kind' "$bc_file")
    name: $(yq eval '.spec.output.to.name' "$bc_file")
  pushSecret: $(yq eval '.spec.output.pushSecret.name // ""' "$bc_file")
EOF
    
    # Run Helm template
    helm template "$name" "$HELM_CHART" -f "$values_file"
    
    # Cleanup
    rm -f "$values_file"
}

# Main logic
if [ $# -eq 0 ]; then
    # Process all BuildConfig files in resources/ directory
    find resources/ -name "*BuildConfig*.yaml" 2>/dev/null | while read bc_file; do
        process_buildconfig "$bc_file"
        echo "---"
    done
else
    # Process specified files
    for bc_file in "$@"; do
        process_buildconfig "$bc_file"
        echo "---"
    done
fi
```
</details>

Make converter script executable:
```bash
chmod +x converter.sh
```

### Step 5: Create Custom Crane Transform Stage

Create custom stage directory structure:

```bash
# Standard crane transform
crane transform KubernetesPlugin

# Create custom stage manually
mkdir -p transform/20_BuildConfigConversion
cd transform/20_BuildConfigConversion

# Copy BuildConfig resources from previous stage
cp -r ../10_KubernetesPlugin/resources .

# Copy Helm chart and converter script (created by Claude Code)
cp -r ~/buildconfig-migration/helm-chart .
cp ~/buildconfig-migration/converter.sh .
chmod +x converter.sh
```

Create kustomization.yaml that calls converter.sh **at runtime** (during `kustomize build`):

**Prompt to Claude Code:**

```
Create kustomization.yaml for crane transform stage that:
1. Runs converter.sh as a Kustomize generator (at kustomize build time)
2. Converter script reads BuildConfig YAMLs and outputs Shipwright Builds
3. Removes original BuildConfig resources from final output

The generator MUST execute during kustomize build (crane apply), NOT pre-generated.

Use Kustomize generators with exec plugin or helm chart plugin.
```

**Option A: Exec Generator (Recommended)**

Create `kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Generate Shipwright Builds at kustomize build time
generators:
- generator-config.yaml

# Remove BuildConfigs from output (optional - generator can skip them)
patches:
- target:
    kind: BuildConfig
  patch: |-
    $patch: delete
    apiVersion: build.openshift.io/v1
    kind: BuildConfig
    metadata:
      name: not-used
```

Create `generator-config.yaml`:
```yaml
apiVersion: someteam.example.com/v1
kind: ShipwrightGenerator
metadata:
  name: buildconfig-to-shipwright
  annotations:
    config.kubernetes.io/function: |
      exec:
        path: ./converter.sh
# Kustomize will execute converter.sh and use its stdout
```

**Option B: Inline Exec Generator**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

generators:
- |-
  apiVersion: builtin
  kind: ExecGenerator
  metadata:
    name: buildconfig-converter
    annotations:
      config.kubernetes.io/function: |
        exec:
          path: ./converter.sh
          args:
          - resources/buildconfig-demo

# Remove BuildConfigs
patches:
- target:
    kind: BuildConfig
  patch: |-
    $patch: delete
    apiVersion: build.openshift.io/v1
    kind: BuildConfig
    metadata:
      name: not-used
```

**Option C: Helm Chart Plugin (Direct Helm Integration)**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Use Kustomize Helm chart generator
helmCharts:
- name: buildconfig-to-shipwright
  repo: file://./helm-chart/buildconfig-to-shipwright
  version: 1.0.0
  releaseName: converted
  valuesInline:
    # Values would need to be populated from BuildConfig
    # This approach requires pre-processing to extract values
  
# Note: Helm chart plugin is less flexible for dynamic per-resource conversion
```

**Recommended: Option A with External Generator Config**

This provides clean separation and Kustomize will execute the script **only during build**.

### Step 6: Test Conversion Locally

**Important:** Test that converter runs **at kustomize build time**, not before.

```bash
cd transform/20_BuildConfigConversion

# Optional: Test converter script standalone (for debugging only)
./converter.sh resources/buildconfig-demo/*BuildConfig*.yaml
# This validates converter logic, but we won't save this output

# Test RUNTIME generation with Kustomize
# This is what crane apply will do - generator runs NOW
kustomize build --enable-alpha-plugins --enable-exec .

# Verify output contains Builds, not BuildConfigs
kustomize build --enable-alpha-plugins --enable-exec . | grep "^kind:"
# Should show: Build (not BuildConfig)

# Verify converter is called during build (not reading pre-generated file)
# Run multiple times - should generate fresh each time
kustomize build --enable-alpha-plugins --enable-exec . | grep "metadata:" | head -5
```

**What happens:**
1. `kustomize build` reads kustomization.yaml
2. Sees generator configuration
3. **Executes converter.sh** at that moment
4. Captures stdout (Shipwright Build YAML)
5. Includes generated resources in output
6. Applies patches (removes BuildConfigs)

**Debugging:**
```bash
# Enable debug to see generator execution
KUSTOMIZE_PLUGIN_DEBUG=true kustomize build --enable-alpha-plugins --enable-exec .

# Should show: "Running generator: converter.sh"
```

### Step 7: Run Crane Apply (Runtime Generation)

```bash
# Go back to migration root
cd ~/buildconfig-migration

# crane apply runs kustomize build on ALL stages
# Including our BuildConfigConversion stage which calls converter.sh
crane apply

# What happens internally:
# 1. crane apply processes each stage with kustomize build
# 2. For transform/20_BuildConfigConversion/:
#    - kustomize reads kustomization.yaml
#    - sees generator configuration
#    - EXECUTES converter.sh (runtime!)
#    - converter reads BuildConfigs
#    - converter calls helm template
#    - converter outputs Shipwright Builds to stdout
#    - kustomize captures output
# 3. crane merges all stages → output/output.yaml

# Check output
grep "kind: Build" output/output.yaml
# Should show Shipwright Builds

grep "kind: BuildConfig" output/output.yaml
# Should be empty (BuildConfigs removed by patch)

# Verify conversion metadata
grep "crane.konveyor.io/conversion-method" output/output.yaml
# Should show: kustomize-helm
```

**Verify Runtime Behavior:**

Run `crane apply` multiple times - each time converter.sh executes fresh:

```bash
# First run
crane apply
grep "crane.konveyor.io/conversion-date" output/output.yaml

# Modify a BuildConfig (change image tag)
yq eval '.spec.output.to.name = "quay.io/example/nodejs-app:v2"' \
  -i transform/10_KubernetesPlugin/resources/buildconfig-demo/BuildConfig*nodejs*.yaml

# Second run - should see updated image in Build
crane apply
grep "output:" -A 2 output/output.yaml | grep "image:"
# Should show: v2 tag (proves fresh generation)
```

### Step 8: Deploy to Target Cluster

```bash
# Switch to target Kubernetes with Shipwright
kubectl config use-context <target-k8s>

# Create namespace
kubectl create namespace buildconfig-demo

# Apply converted resources
kubectl apply -f output/output.yaml

# Verify Builds created
kubectl get builds -n buildconfig-demo

# Trigger BuildRun
kubectl create -f - <<EOF
apiVersion: shipwright.io/v1beta1
kind: BuildRun
metadata:
  name: nodejs-app-run-1
  namespace: buildconfig-demo
spec:
  build:
    name: nodejs-app
EOF

# Watch BuildRun
kubectl get buildrun -n buildconfig-demo -w
```

## Important: Runtime Generation Only

**Do NOT pre-generate builds!** The conversion must happen at **`crane apply` time** when Kustomize evaluates the generators.

**Why?**
- Ensures fresh conversion every time
- crane apply controls the entire workflow
- Kustomize generators are evaluated at build time
- No manual steps between transform creation and apply

**Correct Flow:**
```
crane apply
  → kustomize build transform/20_BuildConfigConversion/
    → evaluates generators in kustomization.yaml
      → executes converter.sh (reads BuildConfigs)
        → calls helm template
          → generates Shipwright Builds
    → merges with other resources
  → outputs final YAML
```

**Incorrect Flow (Don't do this):**
```
# WRONG - Don't pre-generate!
./converter.sh ... > builds/generated-builds.yaml  # ❌
crane apply  # Just uses stale pre-generated file
```

## Conversion Validation

### Verify Docker Strategy Conversion

```bash
# Original BuildConfig
yq eval '.spec.strategy.type' export/resources/buildconfig-demo/BuildConfig*nodejs*.yaml
# Output: Docker

# Converted Build
yq eval '.spec.strategy.name' output/output.yaml | grep -A 1 "nodejs-app"
# Output: buildah

# Check dockerfile parameter
yq eval 'select(.metadata.name == "nodejs-app") | .spec.paramValues[] | select(.name == "dockerfile")' output/output.yaml
```

### Verify Source Strategy Conversion

```bash
# Original BuildConfig
yq eval '.spec.strategy.type' export/resources/buildconfig-demo/BuildConfig*python*.yaml
# Output: Source

# Converted Build
yq eval '.spec.strategy.name' output/output.yaml | grep -A 1 "python-app"
# Output: source-to-image

# Check builder image parameter
yq eval 'select(.metadata.name == "python-app") | .spec.paramValues[] | select(.name == "builder-image")' output/output.yaml
```

## Troubleshooting

### Converter Script Fails

```bash
# Test converter with single BuildConfig
./converter.sh resources/buildconfig-demo/BuildConfig_build.openshift.io_v1_buildconfig-demo_nodejs-app.yaml

# Check yq syntax
yq eval '.metadata.name' resources/buildconfig-demo/*.yaml

# Check Helm chart
helm template test helm-chart/buildconfig-to-shipwright/ --debug
```

### Kustomize Build Fails

```bash
# Validate kustomization.yaml
kustomize build --enable-alpha-plugins .

# Check resources exist
ls -la resources/buildconfig-demo/

# Test without generators
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- builds/generated-builds.yaml
EOF

kustomize build .
```

### Builds Not Generated

```bash
# Run converter manually first
mkdir -p builds
./converter.sh resources/buildconfig-demo/*BuildConfig*.yaml > builds/generated-builds.yaml

# Check output
cat builds/generated-builds.yaml

# Then use simple kustomization
```

## Comparison: Plugin vs Kustomize Approach

| Aspect | Custom Plugin (Scenario 6 Advanced) | Kustomize Approach (This Scenario) |
|--------|-------------------------------------|-------------------------------------|
| **Language** | Go | Bash + Helm |
| **Complexity** | High (Go build, plugin interface) | Medium (Bash + YAML) |
| **Dependencies** | Go toolchain, crane-lib | helm, yq, bash |
| **Execution** | Plugin during crane transform | Script during kustomize build |
| **AI Assistance** | Good (Go code generation) | Excellent (Bash + Helm templates) |
| **Debugging** | Go debugger | Shell debugging, echo |
| **Portability** | Requires Go plugin binary | Portable (standard tools) |
| **Crane Integration** | Native plugin system | Custom stage + kustomization |
| **Resource Generation** | PluginResponse.NewResources | Kustomize generators |
| **Testing** | Go unit tests | Shell script testing |

## Best Practices

1. **Keep converter.sh simple** - Use yq for YAML parsing, delegate logic to Helm
2. **Test Helm chart independently** - `helm template` before integration
3. **Pre-generate if possible** - Run converter during `crane transform`, not during `crane apply`
4. **Handle errors gracefully** - Skip invalid BuildConfigs, don't fail entire conversion
5. **Validate output** - Check generated Builds before deploying
6. **Document Helm values** - Clear mapping from BuildConfig to values
7. **Version Helm chart** - Track changes to conversion logic
8. **Use Claude Code** - Let AI generate Bash + Helm, review and test

## Expected Results

✅ **Success Criteria:**
- BuildConfigs converted to Shipwright Builds
- Conversion happens via Kustomize (no Go plugin)
- Helm templates correctly map all fields
- converter.sh handles both Docker and Source strategies
- `crane apply` produces only Shipwright Builds (no BuildConfigs)
- Builds deploy successfully to target cluster
- BuildRuns execute successfully

⚠️ **Acceptable Issues:**
- Manual setup of custom stage (not automated)
- Converter script requires specific directory structure
- Some BuildConfig features not mapped (documented)

❌ **Blocking Issues:**
- Converter fails on valid BuildConfigs
- Helm template produces invalid Builds
- Kustomize build fails
- Generated Builds don't deploy

## Cleanup

```bash
# Source cluster
kubectl delete namespace buildconfig-demo

# Target cluster
kubectl delete -f output/output.yaml
kubectl delete namespace buildconfig-demo

# Local
rm -rf ~/buildconfig-migration
```

## Key Takeaways

1. **No Go plugin needed** - Complex transformations possible with Bash + Helm
2. **Kustomize generators** - Powerful for creating new resources
3. **Claude Code is ideal** - Generates Bash and Helm templates easily
4. **Crane stages are flexible** - Custom stages can use any tools
5. **Native crane apply** - Everything runs through standard Kustomize

## Next Steps

- Test with real BuildConfigs from production
- Extend Helm chart for additional BuildConfig features
- Add validation of generated Builds
- Integrate into CI/CD pipeline
- Share Helm chart with team

## Reference Implementation

**Working example:** [playground/buildconfig-kustomize-converter/](../playground/buildconfig-kustomize-converter/)

This directory contains:
- ✅ **Complete Helm chart** - Ready to use or customize
- ✅ **Tested converter script** - Works with Docker and Source strategies
- ✅ **Sample BuildConfigs** - For testing and learning
- ✅ **Documentation** - Usage guide and examples

**Quick test:**
```bash
cd playground/buildconfig-kustomize-converter/

# Test converter with samples
scripts/converter.sh samples/buildconfig-docker.yaml
scripts/converter.sh samples/buildconfig-source.yaml

# Both should output valid Shipwright Build YAML
```

For advanced plugin-based approach (requires Go), see: [playground/scenario-06-advanced-plugin-based-conversion.md](../playground/scenario-06-advanced-plugin-based-conversion.md)

---

**This scenario demonstrates crane's flexibility - complex transformations without custom Go code! 🚀**
