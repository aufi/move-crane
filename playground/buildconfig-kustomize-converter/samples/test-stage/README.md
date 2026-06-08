# Test Stage - Runtime Generation Example

This directory demonstrates **runtime generation** with Kustomize generators.

## Key Concept

The converter.sh script is **NOT run manually**. Instead, Kustomize executes it **during build time**.

## Files

- `kustomization.yaml` - Main Kustomize configuration
- `generator-config.yaml` - Generator plugin configuration
- `../../scripts/converter.sh` - Converter script (executed at runtime)
- `../buildconfig-*.yaml` - Sample BuildConfigs (input)

## How It Works

```
kustomize build --enable-alpha-plugins --enable-exec .
  ↓
Read kustomization.yaml
  ↓
Read generators: [generator-config.yaml]
  ↓
Execute: ../../scripts/converter.sh ../buildconfig-*.yaml
  ↓
Capture stdout (Shipwright Build YAML)
  ↓
Apply patches (remove BuildConfigs)
  ↓
Output final YAML
```

## Testing

```bash
cd samples/test-stage/

# Test runtime generation
kustomize build --enable-alpha-plugins --enable-exec .

# Should output Shipwright Builds (NOT BuildConfigs)

# Verify converter is called (not reading pre-generated file)
KUSTOMIZE_PLUGIN_DEBUG=true kustomize build --enable-alpha-plugins --enable-exec .
```

## Important Notes

**❌ DO NOT do this:**
```bash
# WRONG - Pre-generation
../../scripts/converter.sh ../buildconfig-*.yaml > builds.yaml
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- builds.yaml  # This is stale, not runtime generated!
EOF
```

**Problems:**
- Generated file becomes stale if BuildConfigs change
- Manual step required (easy to forget)
- No guarantee output matches current input

**✅ DO this instead:**
```bash
# CORRECT - Runtime generation
cat > kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
generators:
- generator-config.yaml  # Executes converter at runtime
EOF

# Test runtime execution
kustomize build --enable-alpha-plugins --enable-exec .
# Converter executes NOW, generates fresh output every time
```

**Benefits:**
- Always fresh data (no staleness)
- No manual steps
- Repeatable and deterministic

## Use in Crane

When used in a crane transform stage:

```bash
# Stage structure
transform/20_BuildConfigConversion/
├── kustomization.yaml          # Points to generator-config.yaml
├── generator-config.yaml       # Configures converter.sh execution
├── converter.sh               # Converter script
├── helm-chart/                # Helm templates
└── resources/                 # BuildConfigs from previous stage

# crane apply will:
cd transform/20_BuildConfigConversion/
kustomize build --enable-alpha-plugins --enable-exec .
# Converter runs, generates Builds
```

## Comparison

| Approach | When Conversion Happens |
|----------|------------------------|
| **Pre-generation** | During stage creation (manual) |
| **Runtime (this)** | During `crane apply` / `kustomize build` |

Runtime generation is better because:
- ✅ Always fresh
- ✅ Repeatable
- ✅ No manual steps
- ✅ crane apply owns full workflow
