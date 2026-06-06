# BuildConfigConverter Plugin

Custom crane plugin that converts OpenShift BuildConfig resources to Shipwright Build resources.

## Overview

This plugin demonstrates:
- Reading BuildConfig resources from crane export
- Extracting BuildConfig spec and metadata
- Generating Helm values from BuildConfig data
- Executing Helm template to generate Shipwright Build
- Returning new resources via PluginResponse.NewResources
- Marking original BuildConfig for deletion (whiteout)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Plugin receives: BuildConfig (as unstructured)          │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Extract: name, namespace, strategy, source, output, etc │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Build Helm values.yaml with extracted data             │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Execute: helm template <chart> -f values.yaml          │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Parse generated YAML into unstructured.Unstructured    │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ Return PluginResponse:                                  │
│   - NewResources: [Build]                               │
│   - IsWhiteOut: true (delete BuildConfig)               │
└─────────────────────────────────────────────────────────┘
```

## Building

```bash
# Build plugin
./build.sh

# Output: ./buildconfig-converter
```

## Testing

### Standalone Test Mode

Test the plugin without crane:

```bash
# Test with Docker strategy BuildConfig
./buildconfig-converter --test ../samples/buildconfig-docker.yaml

# Test with Source strategy BuildConfig
./buildconfig-converter --test ../samples/buildconfig-source.yaml

# Test with complex BuildConfig
./buildconfig-converter --test ../samples/buildconfig-complex.yaml
```

Expected output:
```
=== Running plugin test ===

Processing BuildConfig: buildconfig-test/nodejs-docker-build
✓ Converted BuildConfig nodejs-docker-build to Shipwright Build

Plugin Response:
  IsWhiteOut: true
  NewResources: 1

--- Generated Resource 1 ---
Kind: Build
Name: nodejs-docker-build
Namespace: buildconfig-test

apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: nodejs-docker-build
  namespace: buildconfig-test
  ...
spec:
  strategy:
    kind: ClusterBuildStrategy
    name: buildah
  ...

=== Test completed successfully ===
```

### Integration with Crane

**Note:** Requires crane v0.1.0+ with NewResources support.

```bash
# Install plugin
mkdir -p ~/.local/share/crane/plugins/
cp buildconfig-converter ~/.local/share/crane/plugins/

# Verify
crane plugin-manager list
# Should show: BuildConfigConverter v1.0.0

# Use in transformation
cd ~/migration-workspace
crane export -n buildconfig-test
crane transform BuildConfigConverter

# Check output
ls transform/20_BuildConfigConverter/resources/
```

## Configuration

### Helm Chart Path

The plugin looks for the Helm chart in this order:

1. **Environment variable:** `HELM_CHART_PATH`
   ```bash
   export HELM_CHART_PATH=/path/to/helm-chart/shipwright-build
   ./buildconfig-converter --test sample.yaml
   ```

2. **Relative to plugin binary:**
   ```
   buildconfig-converter/
   ├── plugin/buildconfig-converter      # Binary here
   └── helm-chart/shipwright-build/      # Chart auto-detected
   ```

3. **Default:** `~/crane-buildconfig-converter/helm-chart/shipwright-build`

## Plugin Interface

### Input: PluginRequest

```go
type PluginRequest struct {
    unstructured.Unstructured  // The BuildConfig resource
    Extras map[string]string    // Optional parameters
}
```

### Output: PluginResponse

```go
type PluginResponse struct {
    Version      string                        // "v1"
    IsWhiteOut   bool                          // true = delete BuildConfig
    Patches      []byte                        // Not used
    NewResources []unstructured.Unstructured   // Generated Build resources
}
```

## Conversion Logic

### Docker Strategy

**Input:**
```yaml
spec:
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: docker/Dockerfile
      env:
      - name: NODE_ENV
        value: production
```

**Output:**
```yaml
spec:
  strategy:
    kind: ClusterBuildStrategy
    name: buildah
  paramValues:
  - name: dockerfile
    value: docker/Dockerfile
  env:
  - name: NODE_ENV
    value: production
```

### Source Strategy

**Input:**
```yaml
spec:
  strategy:
    type: Source
    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: python:3.11
        namespace: openshift
```

**Output:**
```yaml
spec:
  strategy:
    kind: ClusterBuildStrategy
    name: source-to-image
  paramValues:
  - name: builder-image
    value: image-registry.openshift-image-registry.svc:5000/openshift/python:3.11
```

## Dependencies

- **helm** - Must be installed and in PATH
- **k8s.io/apimachinery** - For unstructured types
- **sigs.k8s.io/yaml** - For YAML parsing

## Limitations

1. **Helm dependency** - Requires helm binary at runtime
2. **ImageStream resolution** - Uses static conversion (not live cluster lookup)
3. **Binary builds** - Not yet implemented
4. **Triggers** - BuildConfig triggers not converted (need Tekton/CronJob)
5. **Inline Dockerfile** - Not supported (Shipwright limitation)

## Extending

To add support for more features:

1. **Modify Helm template** (`../helm-chart/shipwright-build/templates/build.yaml`)
2. **Update buildHelmValues()** to extract additional fields
3. **Rebuild plugin:** `./build.sh`
4. **Test:** `./buildconfig-converter --test <sample.yaml>`

## Troubleshooting

### helm: command not found

Install helm:
```bash
# Fedora/RHEL
sudo dnf install helm

# macOS
brew install helm

# Direct download
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Helm template fails

Test Helm chart manually:
```bash
cd ../helm-chart/shipwright-build/
helm template test . --debug
```

### Plugin not found by crane

```bash
# Check installation
ls -la ~/.local/share/crane/plugins/

# Re-install
cp buildconfig-converter ~/.local/share/crane/plugins/
chmod +x ~/.local/share/crane/plugins/buildconfig-converter

# Verify
crane plugin-manager list
```

## Development

### Code Structure

- `main.go` - Plugin implementation
- `BuildConfigConverterPlugin` - Main plugin struct
- `Run()` - Plugin entry point
- `buildHelmValues()` - Extract BuildConfig → Helm values
- `executeHelmTemplate()` - Run helm template
- `parseGeneratedResources()` - Parse YAML output

### Adding New Features

Example: Add timeout support

1. Update `buildHelmValues()`:
```go
values := map[string]interface{}{
    "buildconfig": map[string]interface{}{
        // ... existing fields
        "timeout": extractTimeout(spec),
    },
}
```

2. Update Helm template to use timeout
3. Rebuild and test

## License

Apache 2.0 (same as crane)
