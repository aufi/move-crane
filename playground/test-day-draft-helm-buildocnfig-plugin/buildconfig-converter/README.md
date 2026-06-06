# BuildConfig to Shipwright Converter - Working Implementation

This is a **working prototype** implementation of Scenario 06 - BuildConfig to Shipwright conversion using crane plugin + Helm templates.

## Overview

**Purpose:** Demonstrate advanced crane transformation capabilities:
- Custom plugin that generates new resources (not just patches)
- Helm template integration for resource templating
- BuildConfig → Shipwright Build conversion
- Multi-stage transformation workflow

**Status:** 🚧 **Prototype for next crane release**
- Current crane (v0.0.6) doesn't support `NewResources` in PluginResponse
- This implementation shows what will be possible

## Directory Structure

```
buildconfig-converter/
├── README.md                          # This file
├── helm-chart/                        # Helm chart for Build templating
│   └── shipwright-build/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── build.yaml             # Main Build template
│           ├── serviceaccount.yaml    # Optional SA for secrets
│           └── _helpers.tpl           # Template helpers
├── plugin/                            # Custom crane plugin
│   ├── main.go                        # Plugin implementation
│   ├── go.mod
│   ├── go.sum
│   ├── build.sh                       # Build script
│   └── README.md                      # Plugin documentation
├── samples/                           # Sample BuildConfigs for testing
│   ├── buildconfig-docker.yaml        # Docker strategy example
│   ├── buildconfig-source.yaml        # Source (S2I) strategy example
│   └── buildconfig-complex.yaml       # Complex example
├── docs/                              # Additional documentation
│   ├── ARCHITECTURE.md                # How it works
│   ├── TESTING.md                     # How to test
│   └── COMPARISON.md                  # vs crane convert
└── test-migration/                    # Test workspace (gitignored)
```

## Quick Start

### Prerequisites

1. **crane** (v0.0.6+) - with NewResources support (upcoming)
2. **helm** (v3+)
3. **Go** (1.21+) - for building plugin
4. **kubectl/oc** - access to OpenShift cluster
5. **Shipwright** - installed on target cluster

### Installation

```bash
# 1. Build the plugin
cd plugin/
./build.sh

# 2. Install plugin to crane
mkdir -p ~/.local/share/crane/plugins/
cp buildconfig-converter ~/.local/share/crane/plugins/
chmod +x ~/.local/share/crane/plugins/buildconfig-converter

# 3. Verify installation
crane plugin-manager list
# Should show: BuildConfigConverter v1.0.0

# 4. Verify Helm chart
helm template test ./helm-chart/shipwright-build/
```

### Testing

```bash
# Deploy sample BuildConfig to source cluster
kubectl apply -f samples/buildconfig-docker.yaml

# Create test migration workspace
mkdir -p test-migration
cd test-migration

# Export BuildConfig
crane export -n buildconfig-test

# Transform with plugin
crane transform KubernetesPlugin
crane transform BuildConfigConverter

# Check output
ls transform/20_BuildConfigConverter/resources/
cat transform/20_BuildConfigConverter/resources/*/Build_*.yaml

# Generate final output
crane apply

# Deploy to target
kubectl apply -f output/output.yaml
```

## How It Works

### 1. Helm Chart Templates

The Helm chart (`helm-chart/shipwright-build/`) contains templates that convert BuildConfig structure to Shipwright Build:

**Input (values.yaml):**
```yaml
buildconfig:
  name: nodejs-app
  namespace: myapp
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  source:
    git:
      uri: https://github.com/example/app
      ref: main
  output:
    to:
      name: quay.io/myorg/app:latest
```

**Output (Build resource):**
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
  source:
    type: Git
    git:
      url: https://github.com/example/app
      revision: main
  output:
    image: quay.io/myorg/app:latest
```

### 2. Custom Plugin

The plugin (`plugin/main.go`) implements:

```go
func (p *BuildConfigConverterPlugin) Run(req PluginRequest) (PluginResponse, error) {
    // 1. Check if resource is BuildConfig
    if req.GetKind() != "BuildConfig" {
        return resp, nil
    }
    
    // 2. Extract BuildConfig spec
    spec := extractSpec(req)
    
    // 3. Generate Helm values
    values := buildHelmValues(spec)
    
    // 4. Execute helm template
    buildYAML := helmTemplate(values)
    
    // 5. Parse Build resource
    build := parseYAML(buildYAML)
    
    // 6. Return response
    return PluginResponse{
        NewResources: []unstructured.Unstructured{build},
        IsWhiteOut: true,  // Delete BuildConfig
    }
}
```

### 3. Multi-Stage Workflow

```
BuildConfig (export) 
    → Stage 1: KubernetesPlugin (cleanup metadata)
    → Stage 2: BuildConfigConverter (custom plugin - BC → Build)
    → Stage 3: ShipwrightCustomization (kustomize labels/annotations)
    → Final output (Shipwright Build only)
```

## Conversion Mapping

| BuildConfig | Shipwright Build |
|-------------|------------------|
| `spec.strategy.type: Docker` | `spec.strategy.name: buildah` |
| `spec.strategy.type: Source` | `spec.strategy.name: source-to-image` |
| `spec.strategy.dockerStrategy.dockerfilePath` | `spec.paramValues[dockerfile]` |
| `spec.strategy.dockerStrategy.env[]` | `spec.env[]` |
| `spec.strategy.sourceStrategy.from.name` | `spec.paramValues[builder-image]` |
| `spec.source.git.uri` | `spec.source.git.url` |
| `spec.source.git.ref` | `spec.source.git.revision` |
| `spec.source.sourceSecret.name` | `spec.source.git.cloneSecret` |
| `spec.output.to.name` | `spec.output.image` |
| `spec.output.pushSecret.name` | `spec.output.pushSecret` |

## Features

✅ **Implemented:**
- Docker strategy → buildah conversion
- Source strategy → source-to-image conversion
- Git source handling
- Environment variables
- Build args (for Docker strategy)
- Clone secrets (for Git)
- Push secrets
- Dockerfile path
- Builder image (for S2I)

⚠️ **Partial/Warning:**
- ImageStreamTag resolution (requires live cluster query)
- Multi-source builds (Shipwright limitation)
- Inline Dockerfile (not supported in buildah)
- Volumes (Shipwright limitation)

❌ **Not Implemented:**
- Binary builds
- Image source builds
- Build triggers (need separate Tekton/CronJob)
- Post-commit hooks

## Comparison with crane convert

| Feature | crane convert | This Plugin |
|---------|--------------|-------------|
| Execution | Standalone CLI | Integrated in transform |
| Source | Live cluster | Exported YAML |
| Template | Go code | Helm templates |
| Customization | Limited | Full Kustomize |
| Multi-stage | No | Yes |
| Git tracking | Separate | Integrated |
| Extensibility | Code change | Template edit |

## Testing

See [docs/TESTING.md](docs/TESTING.md) for detailed testing instructions.

**Quick test:**
```bash
# Run all tests
./plugin/test.sh

# Test Helm chart only
helm template test ./helm-chart/shipwright-build/ -f samples/helm-values-test.yaml

# Test plugin binary (mock mode)
./plugin/buildconfig-converter --test samples/buildconfig-docker.yaml
```

## Known Limitations

1. **Requires crane next release** - `NewResources` in PluginResponse not yet in stable
2. **ImageStream resolution** - Needs cluster API access (not in static YAML)
3. **Shipwright features** - Some BuildConfig features not in Shipwright
4. **Helm dependency** - Requires helm binary in PATH

## Contributing

This is a prototype. To improve:

1. **Extend Helm templates** - Add support for more BuildConfig features
2. **Handle edge cases** - Binary builds, image sources, etc.
3. **Add validation** - Validate BuildConfig before conversion
4. **Error handling** - Better error messages
5. **Unit tests** - Add Go unit tests for plugin
6. **Integration tests** - End-to-end test suite

## Resources

- **Scenario 06 Documentation:** [../test-day-june2026/scenario-06-buildconfig-conversion.md](../test-day-june2026/scenario-06-buildconfig-conversion.md)
- **crane-lib convert:** [../crane-lib/convert/buildconfigs.go](../crane-lib/convert/buildconfigs.go)
- **Shipwright Documentation:** https://shipwright.io/docs/
- **Helm Documentation:** https://helm.sh/docs/

## License

Apache 2.0 (same as crane)

---

**Status:** Prototype for testing and demonstration 🧪
