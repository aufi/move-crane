# Scenario 5: Custom Plugin Creation (optional)

**Priority:** 5 - Custom Plugin Development  
**Goal:** Create custom transformation plugin to extend crane's capabilities

## Objective

Test whether users can:
1. Understand crane plugin interface and architecture
2. Create a custom plugin with AI assistance
3. Implement custom transformation logic
4. Integrate plugin with crane workflow
5. Use plugin in multi-stage transformations

## Plugin Limitations (Current Release)

**Important:** Current crane plugin system supports:
- ✅ Adding JSONPatch transformations to existing resources
- ✅ Marking resources for whiteout (deletion)
- ✅ Modifying resource metadata and spec

**Not yet supported (coming in next release):**
- ❌ Creating new resources (e.g., converting BuildConfig → Shipwright Build)
- ❌ Replacing resource types entirely

**This scenario focuses on what's currently possible.**

## Example Plugin: CustomAnnotationPlugin

We'll create a plugin that adds custom annotations and labels based on resource type and namespace patterns. This is a realistic use case for:
- Adding organization-specific metadata
- Tagging resources for monitoring/alerting
- Adding compliance labels
- Conditional transformations based on resource properties

## Prerequisites

- Understanding of crane plugin architecture
- Go programming knowledge (crane plugins are Go binaries)
- Familiarity with JSONPatch format
- AI assistant (Claude, ChatGPT, etc.) for code generation

## Understanding the Plugin Interface

### Step 1: Explore Plugin Contract

```bash
# Check installed plugins
crane plugin-manager list

# Look at plugin location
ls -la ~/.local/share/crane/plugins/

# Understand the interface by checking crane-lib
# The key interface is in: crane-lib/transform/plugin.go
```

**Key Plugin Interface:**

```go
type PluginRequest struct {
    unstructured.Unstructured `json:",inline"`  // The resource to transform
    Extras map[string]string  `json:"extras,omitempty"`  // Optional flags
}

type PluginResponse struct {
    Version    string          `json:"version,omitempty"`
    IsWhiteOut bool            `json:"isWhiteOut,omitempty"`  // Mark for deletion
    Patches    jsonpatch.Patch `json:"patches,omitempty"`     // JSONPatch operations
}

type Plugin interface {
    Run(PluginRequest) (PluginResponse, error)  // Transform logic
    Metadata() PluginMetadata                   // Plugin metadata
}
```

**Document:**
- Is the plugin interface clear from documentation?
- Are there examples available?
- What questions do you have about the interface?

### Step 2: Analyze Existing Plugin

Use the OpenShift crane plugin as a reference example:

**Repository:** https://github.com/migtools/crane-plugin-openshift

```bash
# Clone the reference plugin repository
git clone https://github.com/migtools/crane-plugin-openshift
cd crane-plugin-openshift

# Explore the plugin structure
tree .

# Check the main plugin implementation
cat transform/plugin.go

# Review how it handles resources
cat transform/registry.go

# See example patches
ls -la transform/patches/
```

**What to look for in crane-plugin-openshift:**
- **Plugin structure:** How `Plugin` interface is implemented
- **Resource processing:** How plugin receives and processes resources
- **JSONPatch creation:** How to construct patch operations
- **Resource type handling:** How different kinds (Route, BuildConfig, ImageStream) are handled
- **Registry pattern:** How plugin dispatches to specific handlers
- **Error handling:** Patterns for graceful error handling
- **Testing:** Unit tests and test fixtures

**Key files to study:**
- `transform/plugin.go` - Main plugin implementation
- `transform/registry.go` - Handler registry pattern
- `transform/route.go` - Example: Route resource handler
- `transform/buildconfig.go` - Example: BuildConfig handler
- `transform/plugin_test.go` - Unit tests

**Document:**
- Are existing plugins good examples? ✓ Yes, crane-plugin-openshift is production-ready
- Is the code well-documented? Check inline comments and README
- Can you understand the pattern? Study the registry dispatching pattern

## Plugin Development with AI

### Step 3: Design Plugin Logic

**Plugin Name:** `CustomAnnotationPlugin`

**Behavior:**
1. Add annotation `crane.konveyor.io/migrated-from: <source-namespace>` to all resources
2. Add annotation `crane.konveyor.io/migration-date: <current-date>` to all resources
3. Add label `environment: production` to Deployments and StatefulSets
4. Add label `monitoring: enabled` to Deployments with more than 1 replica
5. Add annotation `security-scan: required` to resources in specific namespaces

This demonstrates:
- Reading resource metadata (kind, namespace, name)
- Reading resource spec (replica count)
- Conditional logic based on resource properties
- Creating JSONPatch operations

### Step 4: Create Plugin with AI Assistance

**Prompt to AI assistant:**

```
I need to create a crane plugin in Go that adds custom annotations and labels to Kubernetes resources during migration.

Plugin interface (from crane-lib/transform):

type PluginRequest struct {
    unstructured.Unstructured
    Extras map[string]string
}

type PluginResponse struct {
    Version    string
    IsWhiteOut bool
    Patches    jsonpatch.Patch  // []byte of JSONPatch operations
}

type Plugin interface {
    Run(PluginRequest) (PluginResponse, error)
    Metadata() PluginMetadata
}

I want the plugin to:
1. Add annotation "crane.konveyor.io/migrated-from" with source namespace value
2. Add annotation "crane.konveyor.io/migration-date" with current date
3. Add label "environment: production" to Deployments and StatefulSets
4. Add label "monitoring: enabled" to Deployments with replicas > 1
5. Support optional flag "--source-namespace" to specify source namespace

Can you help me create this plugin? Please include:
- Main plugin struct and methods
- JSONPatch generation logic
- Binary plugin wrapper (for crane to execute as external binary)
- Basic error handling
```

**Expected AI output:**
- Plugin code structure
- JSONPatch construction
- Binary wrapper code
- Build instructions

**Document:**
- Was AI helpful in creating plugin?
- What did you need to clarify?
- What was missing or incorrect in AI response?
- How many iterations were needed?

### Step 5: Implement Plugin Code

Create `custom-annotation-plugin/main.go`:

```go
package main

import (
    "encoding/json"
    "fmt"
    "os"
    "time"

    "github.com/konveyor/crane-lib/transform"
    "github.com/konveyor/crane-lib/transform/cli"
    "k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
}

// CustomAnnotationPlugin adds migration metadata and conditional labels
type CustomAnnotationPlugin struct {
    SourceNamespace string
}

func (p *CustomAnnotationPlugin) Run(request transform.PluginRequest) (transform.PluginResponse, error) {
    // Get resource metadata
    kind := request.GetKind()
    namespace := request.GetNamespace()
    
    // Build patches
    patches := []map[string]interface{}{}
    
    // Add migration annotations
    patches = append(patches, map[string]interface{}{
        "op":    "add",
        "path":  "/metadata/annotations",
        "value": map[string]string{},
    })
    
    patches = append(patches, map[string]interface{}{
        "op":    "add",
        "path":  "/metadata/annotations/crane.konveyor.io~1migrated-from",
        "value": p.SourceNamespace,
    })
    
    patches = append(patches, map[string]interface{}{
        "op":    "add",
        "path":  "/metadata/annotations/crane.konveyor.io~1migration-date",
        "value": time.Now().Format("2006-01-02"),
    })
    
    // Conditional labels based on resource type
    if kind == "Deployment" || kind == "StatefulSet" {
        patches = append(patches, map[string]interface{}{
            "op":    "add",
            "path":  "/metadata/labels/environment",
            "value": "production",
        })
        
        // For Deployments with replicas > 1, add monitoring label
        if kind == "Deployment" {
            replicas, found, _ := unstructured.NestedInt64(request.Object, "spec", "replicas")
            if found && replicas > 1 {
                patches = append(patches, map[string]interface{}{
                    "op":    "add",
                    "path":  "/metadata/labels/monitoring",
                    "value": "enabled",
                })
            }
        }
    }
    
    // Namespace-specific annotations
    if namespace == "critical-apps" || namespace == "production" {
        patches = append(patches, map[string]interface{}{
            "op":    "add",
            "path":  "/metadata/annotations/security-scan",
            "value": "required",
        })
    }
    
    // Convert patches to JSONPatch format
    patchBytes, err := json.Marshal(patches)
    if err != nil {
        return transform.PluginResponse{}, fmt.Errorf("failed to marshal patches: %w", err)
    }
    
    return transform.PluginResponse{
        Version: string(transform.V1),
        Patches: patchBytes,
    }, nil
}

func (p *CustomAnnotationPlugin) Metadata() transform.PluginMetadata {
    return transform.PluginMetadata{
        Name:            "CustomAnnotationPlugin",
        Version:         "v1.0.0",
        RequestVersion:  []transform.Version{transform.V1},
        ResponseVersion: []transform.Version{transform.V1},
        OptionalFields: []transform.OptionalFields{
            {
                FlagName: "source-namespace",
                Help:     "Source namespace name to record in migrated-from annotation",
                Example:  "my-app-dev",
            },
        },
    }
}

func main() {
    // Read source namespace from extras (optional flags)
    sourceNamespace := "unknown"
    
    plugin := &CustomAnnotationPlugin{
        SourceNamespace: sourceNamespace,
    }
    
    // Use crane-lib CLI helper to handle stdin/stdout communication
    if err := cli.RunAndExit(plugin); err != nil {
        fmt.Fprintf(os.Stderr, "Plugin error: %v\n", err)
        os.Exit(1)
    }
}
```

**Note:** This is simplified example. Real implementation needs:
- Proper error handling for missing annotations/labels paths
- Check if annotations/labels already exist before adding
- Handle optional flags from Extras map
- More sophisticated JSONPatch path handling
- Testing

**Document:**
- Was the code structure clear?
- What parts were confusing?
- What additional helpers would be useful?

### Step 6: Build Plugin

```bash
# Create plugin directory
mkdir -p custom-annotation-plugin
cd custom-annotation-plugin

# Initialize Go module
go mod init custom-annotation-plugin

# Add crane-lib dependency
go get github.com/konveyor/crane-lib/transform

# Create main.go (with code from above)
# Then build

go build -o custom-annotation-plugin main.go

# Install plugin
mkdir -p ~/.local/share/crane/plugins/
cp custom-annotation-plugin ~/.local/share/crane/plugins/CustomAnnotationPlugin
chmod +x ~/.local/share/crane/plugins/CustomAnnotationPlugin
```

**Document:**
- Was build process straightforward?
- Were dependencies clear?
- Any build errors encountered?
- How long did build take?

### Step 7: Test Plugin Recognition

```bash
# List plugins
crane plugin-manager list

# Should show: CustomAnnotationPlugin
```

**Document:**
- Did crane recognize the plugin?
- Was it listed correctly?
- Any errors during plugin discovery?

### Step 8: Create Test Application

```bash
# Create test namespace on source cluster
kubectl config use-context <source-context>
kubectl create namespace plugin-test

# Deploy test application
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: plugin-test
  labels:
    app: test
spec:
  replicas: 3
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: app
        image: nginx:1.25
---
apiVersion: v1
kind: Service
metadata:
  name: test-service
  namespace: plugin-test
spec:
  selector:
    app: test
  ports:
  - port: 80
    targetPort: 80
EOF
```

### Step 9: Export and Transform with Custom Plugin

```bash
# Create working directory
mkdir -p ~/crane-test-custom-plugin
cd ~/crane-test-custom-plugin

# Export
crane export -n plugin-test

# Transform with KubernetesPlugin first
crane transform KubernetesPlugin

# Transform with custom plugin
crane transform CustomAnnotationPlugin

# Check transform output
tree transform/

# Should have both stages:
# transform/
# ├── 10_KubernetesPlugin/
# └── 15_CustomAnnotationPlugin/
```

**Document:**
- Did plugin stage get created?
- Was priority assigned correctly?
- How to control stage order/priority?

### Step 10: Inspect Plugin Transformations

```bash
# Check patches generated by custom plugin
cat transform/15_CustomAnnotationPlugin/patches/plugin-test--apps-v1--Deployment--test-app.patch.yaml

# Should contain patches for:
# - crane.konveyor.io/migrated-from annotation
# - crane.konveyor.io/migration-date annotation
# - environment: production label (Deployment)
# - monitoring: enabled label (replicas > 1)

# Preview transformed resource
kubectl kustomize transform/15_CustomAnnotationPlugin/ | grep -A 15 "kind: Deployment"
```

**Validation:**
- [ ] Annotations added correctly
- [ ] Labels added conditionally (based on kind and replicas)
- [ ] No errors in patches
- [ ] JSONPatch escape characters correct (~1 for /)

### Step 11: Apply and Deploy

```bash
# Generate final output
crane apply

# Check output has custom metadata
cat output/output.yaml | grep -A 10 "annotations:"
cat output/output.yaml | grep -A 10 "labels:"

# Deploy to target cluster
kubectl config use-context <target-context>
kubectl create namespace plugin-test
kubectl apply -f output/output.yaml

# Verify custom metadata
kubectl get deployment test-app -n plugin-test -o yaml | grep "crane.konveyor.io"
kubectl get deployment test-app -n plugin-test -o yaml | grep "environment:"
kubectl get deployment test-app -n plugin-test -o yaml | grep "monitoring:"
```

**Final validation:**
- [ ] Custom annotations present
- [ ] Custom labels present on appropriate resources
- [ ] Conditional logic worked correctly
- [ ] Application still functions

## Alternative Plugin Ideas

If CustomAnnotationPlugin is too complex, try simpler examples:

### 1. Simple Annotation Plugin
Adds one annotation to all resources - good for testing mechanics.

### 2. Label by Namespace Plugin  
Adds labels based on namespace naming patterns (`-dev`, `-prod`, etc.)

### 3. Resource Size Classifier
Adds labels based on resource requests/limits (small/medium/large)

### 4. Whiteout Plugin
Marks specific resource types for deletion (auto-generated Secrets, etc.)

## Validation Checklist

### Plugin Interface Understanding
- [ ] Plugin interface documented and clear
- [ ] PluginRequest/PluginResponse structure understood
- [ ] JSONPatch format understood
- [ ] Binary plugin wrapper pattern clear

### Development Process
- [ ] AI assistance helpful for code generation
- [ ] Code structure matches expectations
- [ ] Dependencies manageable
- [ ] Build process straightforward

### Integration
- [ ] Plugin recognized by crane
- [ ] Works in transform pipeline
- [ ] Works with other plugins
- [ ] Doesn't break existing functionality

### Testing
- [ ] Can test plugin logic
- [ ] Error handling works
- [ ] Edge cases considered

## Expected Results

✅ **Success:**
- Plugin created with AI assistance
- Plugin builds successfully
- Plugin integrates with crane
- Transformations work correctly
- Clear understanding of plugin development

⚠️ **Acceptable:**
- Some trial and error required
- AI needs multiple iterations
- Manual testing needed

❌ **Blocking:**
- Plugin interface undocumented or unclear
- Cannot integrate plugin with crane
- AI cannot assist meaningfully
- Build process too complex

## Key Questions

1. Is plugin interface well documented?
2. Can AI assistants create functional plugins?
3. Is plugin development accessible to users?
4. How easy is plugin integration?
5. What additional helpers/examples would help?
6. Should crane provide plugin scaffolding tool?

## Documentation Gaps

Based on your experience, what documentation should exist:

- [ ] Plugin interface specification
- [ ] Plugin development guide (step-by-step)
- [ ] Example plugins (simple to complex)
- [ ] JSONPatch construction guide
- [ ] Testing plugins guide
- [ ] Debugging plugin issues
- [ ] Plugin distribution/sharing

## AI Assistance Quality

Rate the AI assistance:
- Code generation quality: _____
- Understanding of crane interface: _____
- Error handling suggestions: _____
- Number of iterations needed: _____
- What could improve: _____

## Plugin Limitations Note

**Current limitations:** Plugin system cannot create new resources (coming in next release).

**Current capabilities focus on:**
- Adding/modifying metadata (labels, annotations)
- Modifying spec fields
- Conditional transformations
- Marking resources for whiteout

**Future capabilities will include:**
- Convert between resource types (e.g., BuildConfig → Shipwright)
- Generate new supporting resources
- Split/merge resources

**Action:** Document any use cases requiring resource creation for prioritization.

## Next Steps

- Document plugin creation experience
- Note all issues encountered
- Suggest improvements
- Identify documentation gaps
- Complete test day reporting
