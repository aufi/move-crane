# Scenario 6: BuildConfig to Shipwright Conversion (Advanced)

**Priority:** 6 - Advanced Plugin Development with Resource Creation  
**Goal:** Demonstrate BuildConfig → Shipwright conversion using custom plugin with Helm templates

## Objective

This scenario demonstrates **advanced plugin capabilities** planned for the next crane release:
1. Create new resources (not just patch existing ones)
2. Use Helm templates within crane transform stages
3. Implement conversion logic similar to `crane convert` command
4. Combine custom plugin + Kustomize + Helm for complex transformations

**This builds on Scenario 05 and shows what will be possible in the next release.**

## Background: crane convert

Crane already has `crane convert` command that converts OpenShift BuildConfigs to Shipwright Builds:

```bash
# Current crane convert usage
crane convert BuildConfigs -n <namespace>
```

**Implementation:** `crane-lib/convert/buildconfigs.go`

The logic:
- Reads BuildConfig resources from source cluster
- Converts to Shipwright Build resources
- Handles Docker strategy → Buildah ClusterBuildStrategy
- Handles Source strategy → Source-to-Image ClusterBuildStrategy
- Processes git sources, secrets, env vars, build args
- Generates ServiceAccounts for pull/push secrets

## Goal of This Scenario

**Recreate the same conversion using crane's transform plugin system:**
- Custom plugin generates Shipwright resources
- Helm templates for resource generation
- Kustomize for final assembly
- Integration into multi-stage crane workflow

This demonstrates how users can implement similar conversions for other resource types.

## Prerequisites

### Software
- **crane:** Latest build with next-release plugin features
- **kubectl/oc:** Access to OpenShift cluster with BuildConfigs
- **helm:** For template processing (v3+)
- **Go:** For custom plugin development
- **AI assistant:** For code generation

### Cluster Requirements
- **Source cluster:** OpenShift 4.x with BuildConfig resources
- **Target cluster:** Kubernetes with Shipwright installed

### Install Shipwright on Target Cluster

```bash
# Switch to target cluster
kubectl config use-context <target-context>

# Install Shipwright Operator (example for OLM-enabled cluster)
kubectl create -f https://operatorhub.io/install/shipwright-operator.yaml

# Or via Helm
helm repo add shipwright https://shipwright-io.github.io/helm-charts
helm install shipwright-operator shipwright/operator

# Verify installation
kubectl get crd | grep shipwright
# Should see: builds.shipwright.io, buildruns.shipwright.io, etc.

# Install ClusterBuildStrategies
kubectl apply -f https://raw.githubusercontent.com/shipwright-io/build/main/samples/buildstrategy/buildah/buildstrategy_buildah_cr.yaml
kubectl apply -f https://raw.githubusercontent.com/shipwright-io/build/main/samples/buildstrategy/source-to-image/buildstrategy_source-to-image_cr.yaml

# Verify strategies
kubectl get clusterbuildstrategies
# Should see: buildah, source-to-image
```

## Understanding the Conversion

### BuildConfig → Shipwright Mapping

| OpenShift BuildConfig | Shipwright Build |
|----------------------|------------------|
| `BuildConfig` kind | `Build` kind |
| `spec.strategy.type: Docker` | `spec.strategy.name: buildah` |
| `spec.strategy.type: Source` | `spec.strategy.name: source-to-image` |
| `spec.strategy.dockerStrategy.dockerfilePath` | `spec.paramValues[].name: dockerfile` |
| `spec.strategy.dockerStrategy.env[]` | `spec.env[]` |
| `spec.strategy.sourceStrategy.from` | `spec.paramValues[].name: builder-image` |
| `spec.source.git.uri` | `spec.source.git.url` |
| `spec.source.git.ref` | `spec.source.git.revision` |
| `spec.source.sourceSecret` | `spec.source.git.cloneSecret` |
| `spec.output.to` | `spec.output.image` |
| `spec.output.pushSecret` | `spec.output.pushSecret` |

### Example Conversion

**Input: BuildConfig (OpenShift)**
```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: nodejs-app
  namespace: myapp
spec:
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
      env:
      - name: NODE_ENV
        value: production
  source:
    type: Git
    git:
      uri: https://github.com/example/nodejs-app
      ref: main
    sourceSecret:
      name: git-credentials
  output:
    to:
      kind: DockerImage
      name: quay.io/myorg/nodejs-app:latest
    pushSecret:
      name: quay-push-secret
```

**Output: Shipwright Build**
```yaml
apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: nodejs-app
  namespace: myapp
spec:
  strategy:
    kind: ClusterBuildStrategy
    name: buildah
  paramValues:
  - name: dockerfile
    value: Dockerfile
  env:
  - name: NODE_ENV
    value: production
  source:
    type: Git
    git:
      url: https://github.com/example/nodejs-app
      revision: main
      cloneSecret: git-credentials
  output:
    image: quay.io/myorg/nodejs-app:latest
    pushSecret: quay-push-secret
```

## Implementation Approach

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Stage 1: Export BuildConfigs                                │
│   crane export -n <namespace>                               │
│   → export/resources/default/BuildConfig_*.yaml             │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Stage 2: KubernetesPlugin (standard cleanup)                │
│   crane transform KubernetesPlugin                          │
│   → transform/10_KubernetesPlugin/                          │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Stage 3: BuildConfigConverter (CUSTOM PLUGIN)               │
│   crane transform BuildConfigConverter                      │
│   → Reads BuildConfig resources                             │
│   → Generates Shipwright Build via Helm template            │
│   → Outputs new Build resources                             │
│   → Marks BuildConfigs for whiteout (deletion)              │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Stage 4: ShipwrightCustomization (Kustomize)                │
│   crane transform ShipwrightCustomization                   │
│   → Add labels, annotations                                 │
│   → Adjust namespaces if needed                             │
│   → Customize for target environment                        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Stage 5: Generate final output                              │
│   crane apply                                               │
│   → output/output.yaml (contains Shipwright Builds)         │
└─────────────────────────────────────────────────────────────┘
```

## Step-by-Step Implementation

### Step 1: Prepare Test BuildConfig on Source

Deploy a sample BuildConfig to source OpenShift cluster:

```bash
# Switch to source OpenShift cluster
kubectl config use-context <source-openshift-context>

# Create namespace
kubectl create namespace buildconfig-test

# Deploy sample BuildConfig with Docker strategy
cat <<'EOF' | kubectl apply -f -
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: nodejs-docker-build
  namespace: buildconfig-test
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
      - name: BUILD_LOGLEVEL
        value: verbose
      buildArgs:
      - name: NPM_MIRROR
        value: https://registry.npmjs.org/
  source:
    type: Git
    git:
      uri: https://github.com/sclorg/nodejs-ex
      ref: master
  output:
    to:
      kind: DockerImage
      name: image-registry.openshift-image-registry.svc:5000/buildconfig-test/nodejs-app:latest
  triggers:
  - type: ConfigChange
  - type: ImageChange
---
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: python-s2i-build
  namespace: buildconfig-test
  labels:
    app: python-app
    build-type: source
spec:
  strategy:
    type: Source
    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: python:3.9
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
      kind: DockerImage
      name: image-registry.openshift-image-registry.svc:5000/buildconfig-test/python-app:latest
EOF

# Verify BuildConfigs
kubectl get buildconfigs -n buildconfig-test
```

### Step 2: Create Helm Template for Shipwright Build

Create Helm chart that templates BuildConfig → Shipwright conversion:

```bash
mkdir -p ~/crane-buildconfig-converter/helm-templates/shipwright-build

# Create Chart.yaml
cat > ~/crane-buildconfig-converter/helm-templates/shipwright-build/Chart.yaml <<'EOF'
apiVersion: v2
name: shipwright-build
description: Helm template for converting BuildConfig to Shipwright Build
version: 1.0.0
EOF

# Create values schema
cat > ~/crane-buildconfig-converter/helm-templates/shipwright-build/values.yaml <<'EOF'
# Input BuildConfig fields (extracted by plugin)
buildconfig:
  name: ""
  namespace: ""
  strategy:
    type: ""  # Docker or Source
    dockerStrategy:
      dockerfilePath: ""
      env: []
      buildArgs: []
    sourceStrategy:
      from:
        kind: ""
        name: ""
      env: []
  source:
    type: ""  # Git, Binary, etc.
    git:
      uri: ""
      ref: ""
    sourceSecret: ""
  output:
    to:
      name: ""
    pushSecret: ""

# Conversion settings
conversion:
  # Map Docker strategy to buildah
  dockerStrategyMapping: "buildah"
  # Map Source strategy to s2i
  sourceStrategyMapping: "source-to-image"
  # Add conversion annotations
  addAnnotations: true
EOF

# Create main template
cat > ~/crane-buildconfig-converter/helm-templates/shipwright-build/templates/build.yaml <<'EOF'
{{- $bc := .Values.buildconfig -}}
{{- $strategy := "" -}}
{{- $paramValues := list -}}

{{- if eq $bc.strategy.type "Docker" -}}
  {{- $strategy = .Values.conversion.dockerStrategyMapping -}}
  {{- if $bc.strategy.dockerStrategy.dockerfilePath -}}
    {{- $paramValues = append $paramValues (dict "name" "dockerfile" "value" $bc.strategy.dockerStrategy.dockerfilePath) -}}
  {{- end -}}
  {{- range $bc.strategy.dockerStrategy.buildArgs -}}
    {{- $paramValues = append $paramValues (dict "name" "build-args" "value" (printf "%s=%s" .name .value)) -}}
  {{- end -}}
{{- else if eq $bc.strategy.type "Source" -}}
  {{- $strategy = .Values.conversion.sourceStrategyMapping -}}
  {{- if $bc.strategy.sourceStrategy.from.name -}}
    {{- $imageName := $bc.strategy.sourceStrategy.from.name -}}
    {{- if eq $bc.strategy.sourceStrategy.from.kind "ImageStreamTag" -}}
      {{- $imageName = printf "image-registry.openshift-image-registry.svc:5000/%s/%s" $bc.strategy.sourceStrategy.from.namespace $imageName -}}
    {{- end -}}
    {{- $paramValues = append $paramValues (dict "name" "builder-image" "value" $imageName) -}}
  {{- end -}}
{{- end -}}

apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: {{ $bc.name }}
  namespace: {{ $bc.namespace }}
  labels:
    {{- if $bc.labels }}
    {{- toYaml $bc.labels | nindent 4 }}
    {{- end }}
    converted-from: buildconfig
    crane.konveyor.io/converted: "true"
  {{- if .Values.conversion.addAnnotations }}
  annotations:
    crane.konveyor.io/source-kind: BuildConfig
    crane.konveyor.io/source-name: {{ $bc.name }}
    crane.konveyor.io/conversion-date: {{ now | date "2006-01-02T15:04:05Z07:00" }}
  {{- end }}
spec:
  strategy:
    kind: ClusterBuildStrategy
    name: {{ $strategy }}
  {{- if $paramValues }}
  paramValues:
  {{- range $paramValues }}
  - name: {{ .name }}
    value: {{ .value | quote }}
  {{- end }}
  {{- end }}
  {{- if or $bc.strategy.dockerStrategy.env $bc.strategy.sourceStrategy.env }}
  env:
  {{- if eq $bc.strategy.type "Docker" }}
  {{- toYaml $bc.strategy.dockerStrategy.env | nindent 2 }}
  {{- else if eq $bc.strategy.type "Source" }}
  {{- toYaml $bc.strategy.sourceStrategy.env | nindent 2 }}
  {{- end }}
  {{- end }}
  {{- if eq $bc.source.type "Git" }}
  source:
    type: Git
    git:
      url: {{ $bc.source.git.uri }}
      {{- if $bc.source.git.ref }}
      revision: {{ $bc.source.git.ref }}
      {{- end }}
      {{- if $bc.source.sourceSecret }}
      cloneSecret: {{ $bc.source.sourceSecret }}
      {{- end }}
  {{- end }}
  output:
    image: {{ $bc.output.to.name }}
    {{- if $bc.output.pushSecret }}
    pushSecret: {{ $bc.output.pushSecret }}
    {{- end }}
EOF
```

### Step 3: Create Custom Plugin - BuildConfigConverterPlugin

**AI Prompt for plugin generation:**

```
Create a crane plugin in Go that converts BuildConfig resources to Shipwright Build resources.

Requirements:
1. Read BuildConfig resources from previous stage
2. Extract relevant fields (strategy, source, output, env, etc.)
3. Generate values.yaml for Helm template
4. Execute Helm template to generate Shipwright Build YAML
5. Return PluginResponse with:
   - Generated Build resource as new file
   - Mark original BuildConfig for whiteout (deletion)

Plugin interface (crane-lib v0.0.10+):

type PluginRequest struct {
    unstructured.Unstructured  // Input resource
    Extras map[string]string    // Optional parameters
}

type PluginResponse struct {
    Version    string
    IsWhiteOut bool              // Set true to delete this resource
    Patches    jsonpatch.Patch   // JSONPatch operations
    NewResources []unstructured.Unstructured  // NEW: Generated resources
}

type Plugin interface {
    Run(PluginRequest) (PluginResponse, error)
    Metadata() PluginMetadata
}

The plugin should:
- Only process BuildConfig resources (skip others)
- Extract all fields from BuildConfig
- Handle both Docker and Source strategies
- Generate Helm values from extracted data
- Call "helm template" to generate Build YAML
- Parse generated YAML into unstructured.Unstructured
- Return as NewResources in PluginResponse
- Mark original BuildConfig with IsWhiteOut=true

Helm template location: ~/crane-buildconfig-converter/helm-templates/shipwright-build

Example structure:
```go
package main

import (
    "os/exec"
    "k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
    "github.com/konveyor/crane-lib/transform"
)

type BuildConfigConverterPlugin struct {
    HelmChartPath string
}

func (p *BuildConfigConverterPlugin) Run(req transform.PluginRequest) (transform.PluginResponse, error) {
    // 1. Check if resource is BuildConfig
    // 2. Extract fields
    // 3. Generate Helm values
    // 4. Execute helm template
    // 5. Parse output
    // 6. Return NewResources + IsWhiteOut
}
```
```

**Expected AI-generated plugin** (abbreviated):

```go
package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/konveyor/crane-lib/transform"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/yaml"
)

type BuildConfigConverterPlugin struct {
	HelmChartPath string
}

func (p *BuildConfigConverterPlugin) Metadata() transform.PluginMetadata {
	return transform.PluginMetadata{
		Name:        "BuildConfigConverter",
		Version:     "v1.0.0",
		Description: "Converts OpenShift BuildConfig to Shipwright Build using Helm templates",
	}
}

func (p *BuildConfigConverterPlugin) Run(req transform.PluginRequest) (transform.PluginResponse, error) {
	resp := transform.PluginResponse{
		Version: "v1",
	}

	// Only process BuildConfig resources
	if req.GetKind() != "BuildConfig" {
		return resp, nil
	}

	// Extract BuildConfig spec
	spec, found, err := unstructured.NestedMap(req.Object, "spec")
	if err != nil || !found {
		return resp, fmt.Errorf("failed to get BuildConfig spec: %w", err)
	}

	// Build Helm values from BuildConfig
	values := map[string]interface{}{
		"buildconfig": map[string]interface{}{
			"name":      req.GetName(),
			"namespace": req.GetNamespace(),
			"labels":    req.GetLabels(),
			"strategy":  spec["strategy"],
			"source":    spec["source"],
			"output":    spec["output"],
		},
		"conversion": map[string]interface{}{
			"dockerStrategyMapping": "buildah",
			"sourceStrategyMapping": "source-to-image",
			"addAnnotations":        true,
		},
	}

	// Write values to temp file
	valuesFile, err := p.writeHelmValues(values)
	if err != nil {
		return resp, err
	}
	defer os.Remove(valuesFile)

	// Execute helm template
	buildYAML, err := p.executeHelmTemplate(valuesFile)
	if err != nil {
		return resp, err
	}

	// Parse generated Build resource
	var build unstructured.Unstructured
	if err := yaml.Unmarshal(buildYAML, &build); err != nil {
		return resp, fmt.Errorf("failed to parse generated Build: %w", err)
	}

	// Return response with new Build resource and whiteout for BuildConfig
	resp.NewResources = []unstructured.Unstructured{build}
	resp.IsWhiteOut = true // Delete original BuildConfig

	return resp, nil
}

func (p *BuildConfigConverterPlugin) writeHelmValues(values map[string]interface{}) (string, error) {
	valuesYAML, err := yaml.Marshal(values)
	if err != nil {
		return "", err
	}

	tmpFile, err := os.CreateTemp("", "helm-values-*.yaml")
	if err != nil {
		return "", err
	}
	defer tmpFile.Close()

	if _, err := tmpFile.Write(valuesYAML); err != nil {
		return "", err
	}

	return tmpFile.Name(), nil
}

func (p *BuildConfigConverterPlugin) executeHelmTemplate(valuesFile string) ([]byte, error) {
	cmd := exec.Command("helm", "template", "shipwright-build",
		p.HelmChartPath,
		"-f", valuesFile,
	)

	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("helm template failed: %s: %w", stderr.String(), err)
	}

	return out.Bytes(), nil
}

func main() {
	homeDir, _ := os.UserHomeDir()
	helmChartPath := filepath.Join(homeDir, "crane-buildconfig-converter/helm-templates/shipwright-build")

	plugin := &BuildConfigConverterPlugin{
		HelmChartPath: helmChartPath,
	}

	transform.RunMain(plugin)
}
```

### Step 4: Build and Install Plugin

```bash
# Create plugin directory
mkdir -p ~/crane-buildconfig-converter/plugin
cd ~/crane-buildconfig-converter/plugin

# Save AI-generated plugin code
# (paste the code above into main.go)
cat > main.go <<'EOF'
# ... (AI-generated code from above)
EOF

# Initialize Go module
go mod init crane-buildconfig-converter
go mod tidy

# Build plugin
go build -o buildconfig-converter main.go

# Install to crane plugin directory
mkdir -p ~/.local/share/crane/plugins/
cp buildconfig-converter ~/.local/share/crane/plugins/

# Verify plugin
crane plugin-manager list
# Should show: BuildConfigConverter v1.0.0
```

### Step 5: Export BuildConfigs from Source

```bash
# Create migration workspace
mkdir -p ~/buildconfig-migration
cd ~/buildconfig-migration

# Export BuildConfigs from source OpenShift
crane export -n buildconfig-test

# Verify exported BuildConfigs
ls -la export/resources/buildconfig-test/
grep "kind: BuildConfig" export/resources/buildconfig-test/*.yaml

# Should see files like:
# BuildConfig_build.openshift.io_v1_buildconfig-test_nodejs-docker-build.yaml
# BuildConfig_build.openshift.io_v1_buildconfig-test_python-s2i-build.yaml
```

### Step 6: Multi-Stage Transformation

```bash
# Stage 1: KubernetesPlugin (standard cleanup)
crane transform KubernetesPlugin

# Verify Stage 1
tree transform/10_KubernetesPlugin/
cat transform/10_KubernetesPlugin/kustomization.yaml

# Stage 2: BuildConfigConverter (custom plugin)
crane transform BuildConfigConverter

# Verify Stage 2 - should have Shipwright Builds
tree transform/20_BuildConfigConverter/
ls -la transform/20_BuildConfigConverter/resources/

# Check generated Build resources
cat transform/20_BuildConfigConverter/resources/buildconfig-test/Build_*.yaml

# Verify BuildConfigs marked for deletion
# (should not appear in Stage 2 output)
ls transform/20_BuildConfigConverter/resources/buildconfig-test/ | grep -i buildconfig
# Should return nothing - BuildConfigs were whited out

# Stage 3: ShipwrightCustomization (optional - add labels/annotations)
crane transform ShipwrightCustomization

# Create custom kustomization for Stage 3
cat > transform/30_ShipwrightCustomization/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- build.yaml

namespace: buildconfig-test

commonLabels:
  environment: production
  managed-by: crane
  converted-from: buildconfig

commonAnnotations:
  crane.konveyor.io/migration-batch: "2026-06-05"
  shipwright.io/verify-repository: "true"

# Customize builder image versions if needed
images:
- name: image-registry.openshift-image-registry.svc:5000/openshift/python
  newName: registry.redhat.io/ubi9/python-39
  newTag: latest
EOF
```

### Step 7: Validate Conversion

```bash
# Generate final output
crane apply

# Inspect generated Shipwright Builds
cat output/output.yaml

# Validate structure
grep "kind: Build" output/output.yaml
grep "apiVersion: shipwright.io" output/output.yaml

# Validate conversion for Docker strategy
yq eval 'select(.kind == "Build" and .metadata.name == "nodejs-docker-build") | .spec.strategy.name' output/output.yaml
# Should output: buildah

yq eval 'select(.kind == "Build" and .metadata.name == "nodejs-docker-build") | .spec.paramValues[] | select(.name == "dockerfile")' output/output.yaml
# Should show dockerfile path

# Validate conversion for Source strategy
yq eval 'select(.kind == "Build" and .metadata.name == "python-s2i-build") | .spec.strategy.name' output/output.yaml
# Should output: source-to-image

yq eval 'select(.kind == "Build" and .metadata.name == "python-s2i-build") | .spec.paramValues[] | select(.name == "builder-image")' output/output.yaml
# Should show python builder image

# Validate environment variables preserved
yq eval 'select(.kind == "Build") | .spec.env' output/output.yaml

# Validate Git sources
yq eval 'select(.kind == "Build") | .spec.source.git' output/output.yaml

# Dry-run validation on target cluster
kubectl config use-context <target-context>
kubectl apply --dry-run=server -f output/output.yaml
```

### Step 8: Deploy to Target Cluster with Shipwright

```bash
# Apply converted Builds to target cluster
kubectl apply -f output/output.yaml

# Verify Builds created
kubectl get builds -n buildconfig-test
kubectl describe build nodejs-docker-build -n buildconfig-test

# Trigger BuildRun for Docker build
kubectl create -f - <<EOF
apiVersion: shipwright.io/v1beta1
kind: BuildRun
metadata:
  name: nodejs-docker-build-run-1
  namespace: buildconfig-test
spec:
  build:
    name: nodejs-docker-build
EOF

# Watch BuildRun
kubectl get buildrun -n buildconfig-test -w

# Check BuildRun logs
kubectl logs -f buildrun/nodejs-docker-build-run-1 -n buildconfig-test

# Verify image pushed
kubectl get buildrun nodejs-docker-build-run-1 -n buildconfig-test -o yaml | grep "output:"
```

## Validation Checklist

### Plugin Development
- [ ] Helm template correctly maps all BuildConfig fields
- [ ] Plugin reads BuildConfig resources
- [ ] Plugin generates valid Helm values
- [ ] Plugin executes helm template successfully
- [ ] Plugin returns NewResources with Build
- [ ] Plugin marks BuildConfig with IsWhiteOut
- [ ] Plugin handles both Docker and Source strategies

### Conversion Accuracy
- [ ] Docker strategy → buildah ClusterBuildStrategy
- [ ] Source strategy → source-to-image ClusterBuildStrategy
- [ ] dockerfilePath → paramValues dockerfile
- [ ] sourceStrategy.from → paramValues builder-image
- [ ] Environment variables preserved
- [ ] Build args converted
- [ ] Git source URL and revision correct
- [ ] Git clone secret preserved
- [ ] Output image name correct
- [ ] Push secret preserved

### Multi-Stage Integration
- [ ] Stage 1 (KubernetesPlugin) runs
- [ ] Stage 2 (BuildConfigConverter) generates Builds
- [ ] Stage 2 removes BuildConfigs (whiteout)
- [ ] Stage 3 (ShipwrightCustomization) adds labels
- [ ] Final output contains only Builds (no BuildConfigs)
- [ ] Kustomize processing works correctly

### Target Deployment
- [ ] Shipwright installed on target cluster
- [ ] ClusterBuildStrategies available (buildah, s2i)
- [ ] Build resources apply successfully
- [ ] BuildRun can be created
- [ ] BuildRun executes successfully
- [ ] Image is built and pushed
- [ ] No errors in BuildRun logs

## Comparison with crane convert

### Similarities
- Both convert BuildConfig → Shipwright Build
- Both handle Docker and Source strategies
- Both preserve environment variables
- Both handle git sources and secrets
- Both map output and push secrets

### Differences

| Aspect | crane convert | This Plugin Approach |
|--------|---------------|----------------------|
| **Execution** | Standalone command | Integrated in transform workflow |
| **Source** | Reads from live cluster | Reads from exported YAML |
| **Templating** | Hardcoded in Go | Helm templates (customizable) |
| **Customization** | Limited | Full Kustomize customization |
| **Multi-stage** | Single conversion | Part of multi-stage pipeline |
| **Git tracking** | Separate export | Integrated with crane export |
| **Extensibility** | Requires Go code change | Helm template modification |

## Advanced: Extending the Plugin

### Add Support for ImageStream Resolution

Modify Helm template to resolve ImageStreamTags:

```yaml
# In templates/build.yaml
{{- if eq $bc.strategy.sourceStrategy.from.kind "ImageStreamTag" -}}
  {{- $parts := split ":" $bc.strategy.sourceStrategy.from.name -}}
  {{- $isName := index $parts 0 -}}
  {{- $isTag := index $parts 1 -}}
  {{- $namespace := $bc.strategy.sourceStrategy.from.namespace | default $bc.namespace -}}
  
  # Resolve ImageStreamTag to actual image
  # Plugin needs to query ImageStream from source cluster
  {{- $imageName = printf "image-registry.openshift-image-registry.svc:5000/%s/%s:%s" $namespace $isName $isTag -}}
{{- end -}}
```

### Add Support for Build Triggers

Shipwright doesn't have triggers like BuildConfig, but you can create a separate CronJob or Tekton Pipeline:

```yaml
# In templates/trigger-pipeline.yaml (optional)
{{- if $bc.triggers -}}
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: {{ $bc.name }}-trigger
spec:
  tasks:
  - name: build
    taskRef:
      name: shipwright-build
    params:
    - name: buildName
      value: {{ $bc.name }}
{{- end -}}
```

### Add Support for Build Secrets

Generate ServiceAccount with imagePullSecrets:

```yaml
# In templates/serviceaccount.yaml
{{- if or $bc.spec.output.pushSecret $bc.spec.source.sourceSecret -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $bc.name }}-builder
  namespace: {{ $bc.namespace }}
secrets:
{{- if $bc.spec.source.sourceSecret }}
- name: {{ $bc.spec.source.sourceSecret }}
{{- end }}
{{- if $bc.spec.output.pushSecret }}
- name: {{ $bc.spec.output.pushSecret }}
{{- end }}
{{- end -}}
```

Then reference ServiceAccount in Build:

```yaml
spec:
  serviceAccount: {{ $bc.name }}-builder
```

## Troubleshooting

### Plugin Not Found

```bash
# Error: plugin "BuildConfigConverter" not found

# Check plugin installation
ls -la ~/.local/share/crane/plugins/

# Re-install plugin
cp buildconfig-converter ~/.local/share/crane/plugins/
chmod +x ~/.local/share/crane/plugins/buildconfig-converter

# Verify
crane plugin-manager list
```

### Helm Template Fails

```bash
# Error: helm template execution failed

# Test Helm template manually
cd ~/crane-buildconfig-converter/helm-templates/shipwright-build

# Create test values
cat > test-values.yaml <<EOF
buildconfig:
  name: test-build
  namespace: test
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  source:
    type: Git
    git:
      uri: https://github.com/example/repo
      ref: main
  output:
    to:
      name: quay.io/test/image:latest
EOF

# Test template
helm template test . -f test-values.yaml

# Check for errors in template syntax
```

### BuildConfig Not Converted

```bash
# BuildConfig still in output, Build not generated

# Check if plugin processed the resource
grep "IsWhiteOut" transform/20_BuildConfigConverter/patches/*.patch.yaml

# Check plugin logs (if available)
crane transform BuildConfigConverter --debug

# Verify plugin returns NewResources
# Check plugin code: resp.NewResources should contain Build
```

### Shipwright Build Fails

```bash
# BuildRun fails on target cluster

# Check ClusterBuildStrategy exists
kubectl get clusterbuildstrategy buildah
kubectl get clusterbuildstrategy source-to-image

# Check Build spec
kubectl describe build <build-name>

# Check BuildRun logs
kubectl logs buildrun/<buildrun-name>

# Common issues:
# - Git clone fails (check cloneSecret)
# - Image push fails (check pushSecret)
# - Builder image not found (check paramValues)
```

## Comparison with Scenario 05

| Aspect | Scenario 05 | Scenario 06 |
|--------|-------------|-------------|
| **Complexity** | Medium | Advanced |
| **Plugin capability** | Patch existing resources | Create new resources |
| **Transformation** | Modify metadata | Convert resource types |
| **Templating** | No templates | Helm templates |
| **Use case** | Add annotations/labels | BuildConfig → Shipwright |
| **Implementation** | Direct JSONPatch | Helm + Plugin |
| **Release** | Current crane | Next crane release |

## Expected Results

✅ **Success Criteria:**
- Plugin successfully converts BuildConfig to Shipwright Build
- Helm templates correctly map all fields
- Multi-stage transformation workflow integrates plugin
- Original BuildConfigs removed (whiteout)
- Shipwright Builds deploy and run on target cluster
- Conversion matches crane convert output

⚠️ **Acceptable Issues:**
- Some BuildConfig features not supported in Shipwright (documented in conversion)
- Manual adjustment needed for ImageStream resolution
- Triggers require separate implementation (Tekton/CronJob)

❌ **Blocking Issues:**
- Plugin fails to generate Build resources
- Helm template syntax errors
- NewResources not supported in current crane release
- Build resources invalid on target cluster

## Cleanup

### Source Cluster

```bash
kubectl delete namespace buildconfig-test
```

### Target Cluster

```bash
kubectl delete -f output/output.yaml
kubectl delete buildruns --all -n buildconfig-test
kubectl delete namespace buildconfig-test
```

### Local Files

```bash
rm -rf ~/buildconfig-migration
rm -rf ~/crane-buildconfig-converter
rm ~/.local/share/crane/plugins/buildconfig-converter
```

## Key Takeaways

1. **Plugin + Helm = Powerful**: Combining custom plugins with Helm templates enables complex resource transformations
2. **Declarative conversion**: Helm templates make conversion logic visible and customizable
3. **Multi-stage workflow**: Conversion integrates seamlessly into crane transform pipeline
4. **Resource creation**: Next crane release will support creating new resources via plugins
5. **crane convert alternative**: Plugin approach offers more flexibility than standalone crane convert
6. **Kustomize integration**: Converted resources can be further customized with Kustomize

## Next Steps

- Try converting your own BuildConfigs
- Extend Helm template for additional BuildConfig features
- Create similar plugins for other resource type conversions (DeploymentConfig, Template, etc.)
- Integrate into CI/CD pipeline for automated migrations
- Share plugin and templates with team

---

**This scenario demonstrates the future of crane transformation capabilities! 🚀**
