# Quick Start - Runtime Generation

## ⚡ TL;DR

```bash
# 1. Export from OpenShift
crane export -n myapp

# 2. Standard transform
crane transform KubernetesPlugin

# 3. Create BuildConfig conversion stage
cd transform/
mkdir 20_BuildConfigConversion
cd 20_BuildConfigConversion/

# 4. Setup converter (copy from playground)
cp -r ../10_KubernetesPlugin/resources .
cp -r /path/to/playground/buildconfig-kustomize-converter/helm-chart .
cp /path/to/playground/buildconfig-kustomize-converter/scripts/converter.sh .
chmod +x converter.sh

# 5. Configure RUNTIME generation
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

# 6. Test runtime execution
kustomize build --enable-alpha-plugins --enable-exec .

# 7. Apply (converter runs again at runtime)
cd ../..
crane apply
```

## ✅ What This Does

1. **Exports** BuildConfigs from OpenShift cluster
2. **Transforms** with standard KubernetesPlugin (cleanup)
3. **Creates** custom stage for BuildConfig→Shipwright conversion
4. **Configures** Kustomize generator (NOT pre-generation!)
5. **Tests** that converter.sh executes during kustomize build
6. **Applies** migration (converter runs fresh every time)

## 🎯 Key Concept: Runtime Generation

```
crane apply
  ↓
kustomize build transform/20_BuildConfigConversion/
  ↓
Reads kustomization.yaml → sees generators
  ↓
EXECUTES converter.sh (RUNTIME!)
  ↓
Generates Shipwright Builds fresh
  ↓
Applies patches (removes BuildConfigs)
  ↓
Outputs final YAML
```

## ❌ Common Mistakes

### WRONG - Pre-generation

```bash
# DON'T DO THIS!
./converter.sh resources/*BuildConfig*.yaml > builds/generated-builds.yaml
cat > kustomization.yaml <<EOF
resources:
- builds/generated-builds.yaml  # Stale, pre-generated
EOF
```

**Problem:** Generated files become stale, manual step required.

### CORRECT - Runtime generation

```bash
# DO THIS!
cat > generator-config.yaml <<EOF
apiVersion: someteam.example.com/v1
kind: ShipwrightGenerator
...
EOF

cat > kustomization.yaml <<EOF
generators:
- generator-config.yaml  # Executes at runtime
EOF
```

**Benefit:** Fresh generation every `crane apply`, no manual steps.

## 🔧 Verify Runtime Execution

```bash
# Test that converter runs during build
cd transform/20_BuildConfigConversion/
kustomize build --enable-alpha-plugins --enable-exec .

# Debug mode - see what executes
KUSTOMIZE_PLUGIN_DEBUG=true kustomize build --enable-alpha-plugins --enable-exec .

# Verify fresh generation
crane apply
grep "name: myapp-build" output/output.yaml

# Modify a BuildConfig, re-run
yq eval -i '.metadata.name = "updated-build"' resources/*BuildConfig*.yaml
crane apply
grep "name: updated-build" output/output.yaml  # Should see new name!
```

## 📁 Final Directory Structure

```
migration-workspace/
├── export/                           # crane export output
├── transform/
│   ├── 10_KubernetesPlugin/         # Standard cleanup
│   │   ├── kustomization.yaml
│   │   └── resources/
│   └── 20_BuildConfigConversion/    # Custom stage
│       ├── kustomization.yaml       # Uses generators
│       ├── generator-config.yaml    # Exec plugin config
│       ├── converter.sh             # Executed at runtime
│       ├── helm-chart/              # Helm templates
│       └── resources/               # BuildConfigs from previous stage
└── output/
    └── output.yaml                  # Final result (Shipwright Builds)
```

## 🚀 Next Steps

1. **Test converter** with sample BuildConfigs first
2. **Validate** Helm templates work independently
3. **Setup stage** as shown above
4. **Test runtime** with `kustomize build`
5. **Apply** with `crane apply`
6. **Verify** Builds in output/output.yaml

## 📚 More Information

- **Full README:** README.md
- **Scenario 06:** ../../test-day-june2026/scenario-06-buildconfig-kustomize-conversion.md
- **Sample Stage:** samples/test-stage/
- **Converter Script:** scripts/converter.sh
- **Helm Chart:** helm-chart/buildconfig-to-shipwright/

---

**Remember:** Conversion happens **at `crane apply` time**, NOT before! 🎯
