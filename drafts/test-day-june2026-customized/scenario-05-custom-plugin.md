# Scenario 5: Custom Plugin Creation with AI Assistance

**Priority:** 5 - Custom Plugin Development  
**Duration:** ~60 minutes  
**Goal:** Create custom transformation plugin (BuildConfig → Shipwright)

## Objective

Test whether users can:
1. Create a custom crane plugin with AI assistance
2. Implement custom transformation logic
3. Integrate plugin with crane workflow
4. Use plugin in multi-stage transformations

## Example: BuildConfig to Shipwright Build Conversion

**Context:** OpenShift BuildConfig is OpenShift-specific and won't work on vanilla Kubernetes. Shipwright is a Kubernetes-native build framework that works cross-platform.

**Goal:** Create plugin to convert BuildConfig resources to Shipwright Build resources.

## Prerequisites

- Understanding of crane plugin architecture
- Go programming knowledge (crane plugins are Go binaries)
- Familiarity with BuildConfig (OpenShift) and Shipwright

## Plugin Development Steps

### Step 1: Understand Plugin Interface

```bash
# Check existing plugin structure
ls -la ~/.local/share/crane/plugins/

# Examine plugin interface documentation
# (This should be in crane docs)

# List available plugins
crane plugin-manager list

# Understand plugin requirements
# - Input: Resource YAML
# - Output: Transformed YAML
# - Plugin contract: JSON patches or replaced resources
```

**Document:**
- Is plugin interface well documented?
- Are there plugin examples?
- Is it clear how to create a plugin?

### Step 2: Create Plugin Scaffold with AI

**Prompt to AI assistant:**

```
I need to create a crane plugin that converts OpenShift BuildConfig resources 
to Shipwright Build resources. 

BuildConfig structure:
- apiVersion: build.openshift.io/v1
- kind: BuildConfig
- source: git repository
- strategy: Docker, Source, etc.
- output: ImageStream or external registry

Shipwright Build structure:
- apiVersion: shipwright.io/v1beta1
- kind: Build
- source: git repository
- strategy: Dockerfile location
- output: image repository

Can you help me create a Go plugin for crane that:
1. Detects BuildConfig resources
2. Converts them to Shipwright Build format
3. Returns appropriate transformations
```

**Expected AI output:**
- Plugin code structure
- Conversion logic
- How to build and integrate

**Document:**
- Was AI helpful in creating plugin?
- What did you need to clarify?
- What was missing from AI response?

### Step 3: Implement Plugin

Create `buildconfig-to-shipwright-plugin/main.go`:

```go
package main

import (
    "encoding/json"
    "fmt"
    "os"
    
    buildv1 "github.com/openshift/api/build/v1"
    shipwrightv1beta1 "github.com/shipwright-io/build/pkg/apis/build/v1beta1"
    "sigs.k8s.io/yaml"
)

// Plugin input/output structures
type PluginInput struct {
    Resources []Resource `json:"resources"`
}

type Resource struct {
    Content []byte `json:"content"`
}

type PluginOutput struct {
    Patches []Patch `json:"patches"`
}

type Patch struct {
    Target PatchTarget `json:"target"`
    Ops    []PatchOp   `json:"ops"`
}

type PatchTarget struct {
    Group     string `json:"group"`
    Version   string `json:"version"`
    Kind      string `json:"kind"`
    Name      string `json:"name"`
    Namespace string `json:"namespace"`
}

type PatchOp struct {
    Op    string      `json:"op"`
    Path  string      `json:"path"`
    Value interface{} `json:"value,omitempty"`
}

func main() {
    // Read input from stdin
    var input PluginInput
    if err := json.NewDecoder(os.Stdin).Decode(&input); err != nil {
        fmt.Fprintf(os.Stderr, "Error reading input: %v\n", err)
        os.Exit(1)
    }

    output := PluginOutput{
        Patches: []Patch{},
    }

    // Process each resource
    for _, res := range input.Resources {
        // Try to parse as BuildConfig
        var bc buildv1.BuildConfig
        if err := yaml.Unmarshal(res.Content, &bc); err != nil {
            continue // Not a BuildConfig, skip
        }

        if bc.Kind != "BuildConfig" {
            continue
        }

        // Convert BuildConfig to Shipwright Build
        build := convertBuildConfigToShipwrightBuild(&bc)

        // Create replacement patch
        buildYAML, err := yaml.Marshal(build)
        if err != nil {
            fmt.Fprintf(os.Stderr, "Error marshaling Build: %v\n", err)
            continue
        }

        var buildMap map[string]interface{}
        if err := yaml.Unmarshal(buildYAML, &buildMap); err != nil {
            fmt.Fprintf(os.Stderr, "Error unmarshaling to map: %v\n", err)
            continue
        }

        patch := Patch{
            Target: PatchTarget{
                Group:     "build.openshift.io",
                Version:   "v1",
                Kind:      "BuildConfig",
                Name:      bc.Name,
                Namespace: bc.Namespace,
            },
            Ops: []PatchOp{
                {
                    Op:    "replace",
                    Path:  "/",
                    Value: buildMap,
                },
            },
        }

        output.Patches = append(output.Patches, patch)
    }

    // Write output to stdout
    if err := json.NewEncoder(os.Stdout).Encode(output); err != nil {
        fmt.Fprintf(os.Stderr, "Error writing output: %v\n", err)
        os.Exit(1)
    }
}

func convertBuildConfigToShipwrightBuild(bc *buildv1.BuildConfig) *shipwrightv1beta1.Build {
    build := &shipwrightv1beta1.Build{}
    build.APIVersion = "shipwright.io/v1beta1"
    build.Kind = "Build"
    build.Name = bc.Name
    build.Namespace = bc.Namespace
    
    // Copy labels
    build.Labels = bc.Labels

    // Convert source
    if bc.Spec.Source.Git != nil {
        build.Spec.Source.URL = bc.Spec.Source.Git.URI
        build.Spec.Source.Revision = bc.Spec.Source.Git.Ref
    }

    // Convert strategy
    if bc.Spec.Strategy.DockerStrategy != nil {
        build.Spec.Strategy.Name = "buildah"  // or another Shipwright strategy
        if bc.Spec.Strategy.DockerStrategy.DockerfilePath != "" {
            build.Spec.Dockerfile = bc.Spec.Strategy.DockerStrategy.DockerfilePath
        }
    }

    // Convert output
    if bc.Spec.Output.To != nil {
        // Parse ImageStream reference or registry URL
        build.Spec.Output.Image = parseOutputImage(bc.Spec.Output.To.Name)
    }

    return build
}

func parseOutputImage(imageStreamRef string) string {
    // Logic to convert ImageStream reference to registry URL
    // This is simplified - real implementation would be more complex
    return "registry.example.com/" + imageStreamRef
}
```

**Note:** This is a simplified example. Real implementation needs:
- Proper error handling
- Complete field mapping
- Testing
- Documentation

### Step 4: Build Plugin

```bash
# Create plugin directory
mkdir -p buildconfig-to-shipwright-plugin
cd buildconfig-to-shipwright-plugin

# Initialize Go module
go mod init buildconfig-to-shipwright-plugin

# Add dependencies
go get github.com/openshift/api/build/v1
go get github.com/shipwright-io/build/pkg/apis/build/v1beta1
go get sigs.k8s.io/yaml

# Build plugin
go build -o buildconfig-to-shipwright main.go

# Install plugin
mkdir -p ~/.local/share/crane/plugins/
cp buildconfig-to-shipwright ~/.local/share/crane/plugins/BuildConfigToShipwrightPlugin
chmod +x ~/.local/share/crane/plugins/BuildConfigToShipwrightPlugin
```

**Document:**
- Was build process straightforward?
- Were dependencies clear?
- Any build errors?

### Step 5: Test Plugin Standalone

Create test BuildConfig:

```bash
cat > test-buildconfig.yaml <<EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: myapp
  namespace: test
spec:
  source:
    git:
      uri: https://github.com/example/myapp
      ref: main
  strategy:
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: myapp:latest
EOF

# Test plugin directly (if crane has plugin test capability)
crane plugin-manager test BuildConfigToShipwrightPlugin test-buildconfig.yaml

# Or manually
# Create plugin input JSON
cat > plugin-input.json <<EOF
{
  "resources": [
    {
      "content": "$(cat test-buildconfig.yaml | base64)"
    }
  ]
}
EOF

# Run plugin
cat plugin-input.json | ~/.local/share/crane/plugins/BuildConfigToShipwrightPlugin
```

**Expected output:**
- JSON with patches
- Replacement of BuildConfig with Shipwright Build

**Document:**
- Did plugin execute successfully?
- Was output correct?
- Were there errors?

### Step 6: Integrate Plugin with Crane

```bash
# Verify plugin is recognized
crane plugin-manager list

# Should show: BuildConfigToShipwrightPlugin

# Create test namespace with BuildConfig on source cluster
kubectl config use-context <source-context>
kubectl create namespace buildconfig-test

# Deploy BuildConfig
kubectl apply -f test-buildconfig.yaml

# Also deploy a simple Deployment to verify normal resources still work
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: buildconfig-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: nginx:1.25
EOF
```

### Step 7: Use Plugin in Migration

```bash
# Create working directory
mkdir -p ~/crane-test-custom-plugin
cd ~/crane-test-custom-plugin

# Export
crane export -n buildconfig-test

# Check BuildConfig was exported
ls export/resources/buildconfig-test/ | grep BuildConfig

# Transform with KubernetesPlugin
crane transform KubernetesPlugin

# Transform with custom plugin
crane transform BuildConfigToShipwrightPlugin

# Check transform output
tree transform/

# Should have:
# transform/
# ├── 10_KubernetesPlugin/
# └── 15_BuildConfigToShipwrightPlugin/  (or similar)

# Inspect BuildConfig transformation
cat transform/15_BuildConfigToShipwrightPlugin/resources/buildconfig.yaml
# Should now be Shipwright Build instead of BuildConfig

# Apply
crane apply

# Check output
cat output/output.yaml | grep -A 20 "kind: Build"
# Should show Shipwright Build, not BuildConfig
```

**Validation:**
- [ ] Plugin appears in crane plugin list
- [ ] Plugin stage created in transform
- [ ] BuildConfig converted to Shipwright Build
- [ ] Other resources unchanged
- [ ] Final output has Shipwright Build

### Step 8: Deploy to Target Cluster

```bash
# Switch to target cluster (vanilla Kubernetes with Shipwright installed)
kubectl config use-context <target-context>

# Install Shipwright (if not already installed)
kubectl apply -f https://github.com/shipwright-io/build/releases/download/v0.12.0/release.yaml

# Wait for Shipwright to be ready
kubectl wait --for=condition=ready pod -l control-plane=shipwright-build -n shipwright-build --timeout=300s

# Create namespace
kubectl create namespace buildconfig-test

# Apply migrated resources
kubectl apply -f output/output.yaml

# Verify
kubectl get builds -n buildconfig-test
kubectl get deployment -n buildconfig-test

# Check that Shipwright Build was created
kubectl describe build myapp -n buildconfig-test
```

**Final validation:**
- [ ] Shipwright Build created successfully
- [ ] No BuildConfig resources (wouldn't work on vanilla K8s anyway)
- [ ] Regular Deployment still works
- [ ] Build can be triggered (optional)

## Plugin Development Checklist

### Plugin Interface
- [ ] Plugin interface documented
- [ ] Examples available
- [ ] Clear input/output contract
- [ ] Testing capabilities

### Development Process
- [ ] AI assistance helpful
- [ ] Code structure clear
- [ ] Dependencies manageable
- [ ] Build process straightforward

### Integration
- [ ] Plugin recognized by crane
- [ ] Can be used in transform pipeline
- [ ] Works with other plugins
- [ ] Doesn't break existing functionality

### Testing
- [ ] Can test plugin standalone
- [ ] Can test plugin in crane pipeline
- [ ] Error handling works
- [ ] Edge cases covered

## Expected Results

✅ **Success:**
- Plugin created with AI assistance
- Plugin builds successfully
- Plugin integrates with crane
- Transformation works correctly
- Documentation sufficient

⚠️ **Acceptable:**
- Some trial and error required
- AI needs multiple iterations
- Manual testing needed

❌ **Blocking:**
- Plugin interface undocumented
- Cannot integrate plugin with crane
- AI cannot assist meaningfully
- No way to test plugin

## Time Estimate

- Planning and AI consultation: 15 min
- Plugin implementation: 20 min
- Build and testing: 10 min
- Integration with crane: 10 min
- End-to-end test: 5 min
- **Total: ~60 minutes**

## Alternative: Simpler Plugin

If BuildConfig→Shipwright is too complex, try simpler plugin:

### Example: Add Custom Annotations Plugin

```go
// Plugin that adds custom annotation to all resources
// Much simpler - just adds annotation to metadata

func main() {
    // Read resources
    // For each resource, add patch:
    // - op: add
    //   path: /metadata/annotations/migration.example.com~1migrated-by
    //   value: custom-plugin
}
```

This tests the plugin mechanism without complex conversion logic.

## Key Questions

1. Is plugin interface well documented?
2. Can AI assistants create functional plugins?
3. Is plugin development accessible to users?
4. How easy is plugin integration?
5. Can plugins be shared/distributed?
6. Are there plugin examples in crane repo?

## Documentation Needed

- Plugin interface specification
- Plugin development guide
- Example plugins (simple to complex)
- Testing plugins guide
- Distribution/sharing plugins
- Debugging plugin issues

## Next Steps

- Document plugin creation experience
- Note all issues encountered
- Suggest plugin interface improvements
- Provide example plugin code
- Complete test day reporting
