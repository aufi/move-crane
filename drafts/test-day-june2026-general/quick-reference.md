# Crane Quick Reference Guide

## Common Commands

### Export

```bash
# Export specific namespace
crane export -n <namespace>

# Export to custom directory
crane export -n <namespace> -e <export-dir>

# Export with debug output
crane export -n <namespace> --debug
```

### Transform

```bash
# Run all discovered stages
crane transform

# Run specific stage by name
crane transform KubernetesPlugin

# Run specific stage by directory
crane transform 10_KubernetesPlugin

# Run specific stage by base name
crane transform CustomEdits

# Run multiple stages
crane transform KubernetesPlugin OpenshiftPlugin CustomEdits

# Force regenerate all stages (WARNING: overwrites custom stages)
crane transform --force

# Use custom transform directory
crane transform -t <transform-dir>

# Skip specific plugins
crane transform -s <plugin1>,<plugin2>

# List available plugins
crane transform list-plugins

# Show optional plugin flags
crane transform optionals
```

### Apply

```bash
# Generate final output
crane apply

# Use custom directories
crane apply -t <transform-dir> -o <output-dir>

# With debug output
crane apply --debug
```

### Plugin Manager

```bash
# List installed plugins
crane plugin-manager list

# Install plugin
crane plugin-manager install <plugin-url-or-path>

# Remove plugin
crane plugin-manager remove <plugin-name>
```

## Directory Structure

### After Export

```
export/
└── resources/
    └── <namespace>/
        ├── ConfigMap_<ns>_<name>.yaml
        ├── Deployment_apps_v1_<ns>_<name>.yaml
        ├── Secret_<ns>_<name>.yaml
        └── Service_<ns>_<name>.yaml
```

### After Transform (Single Stage)

```
transform/
└── 10_KubernetesPlugin/
    ├── kustomization.yaml
    ├── patches/
    │   ├── <ns>--<group>-<version>--<kind>--<name>.patch.yaml
    │   └── ...
    └── resources/
        ├── configmap.yaml
        ├── deployment.yaml
        ├── secret.yaml
        └── service.yaml
```

### After Transform (Multi-Stage)

```
transform/
├── 10_KubernetesPlugin/
│   ├── kustomization.yaml
│   ├── patches/
│   └── resources/
├── 20_OpenshiftPlugin/
│   ├── kustomization.yaml
│   ├── patches/
│   └── resources/
├── 50_CustomEdits/
│   ├── kustomization.yaml
│   ├── patches/
│   └── resources/
└── .work/                      # Debugging directory
    ├── 10_KubernetesPlugin/
    │   ├── input/
    │   └── output/
    └── 20_OpenshiftPlugin/
        ├── input/
        └── output/
```

### After Apply

```
output/
└── output.yaml                 # Multi-document YAML with all resources
```

## Stage Types

### Plugin Stage (Auto-regenerating)

**Naming:** `<priority>_<PluginName>Plugin`

**Examples:**
- `10_KubernetesPlugin`
- `15_OpenshiftPlugin`

**Behavior:**
- Auto-regenerates on every transform run
- No --force needed
- Don't manually edit (changes will be overwritten)

### Custom Stage (Manual edit protection)

**Naming:** `<priority>_<CustomName>` (no "Plugin" suffix)

**Examples:**
- `50_CustomEdits`
- `90_FinalTweaks`

**Behavior:**
- Resources copied from previous stage
- Protected from overwrite (requires --force)
- Safe for manual editing
- Perfect for custom patches

## Stage Selection Patterns

```bash
# By full directory name
crane transform 10_KubernetesPlugin

# By plugin name (must end with "Plugin")
crane transform KubernetesPlugin

# By base name (finds existing or creates new)
crane transform CustomEdits

# Mixed formats
crane transform 10_KubernetesPlugin OpenshiftPlugin CustomEdits
```

## Kustomize Patterns in Stages

### Change Namespace

```yaml
# In kustomization.yaml
namespace: new-namespace
```

### Add Labels to All Resources

```yaml
commonLabels:
  environment: production
  team: platform
```

### Add Annotations to All Resources

```yaml
commonAnnotations:
  crane.konveyor.io/migrated: "true"
```

### Update ConfigMap Values

```yaml
configMapGenerator:
- name: app-config
  behavior: merge
  literals:
  - key1=new-value
  - key2=another-value
```

### Update Secret Values

```yaml
secretGenerator:
- name: app-secrets
  behavior: merge
  literals:
  - password=new-password
  - api-key=new-key
```

### Change Image References

```yaml
images:
- name: nginx:1.25
  newName: registry.example.com/nginx
  newTag: 1.25.0
```

### Scale Replicas

```yaml
replicas:
- name: deployment-name
  count: 5
```

### JSONPatch

```yaml
patches:
- path: patches/my-patch.yaml
  target:
    kind: Deployment
    name: my-deployment
```

**patches/my-patch.yaml:**
```yaml
- op: replace
  path: /spec/replicas
  value: 3
- op: add
  path: /spec/template/spec/containers/0/env/-
  value:
    name: NEW_VAR
    value: "new-value"
- op: remove
  path: /metadata/annotations/old-annotation
```

### Strategic Merge Patch

```yaml
patches:
- path: patches/strategic.yaml
```

**patches/strategic.yaml:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
spec:
  template:
    spec:
      containers:
      - name: app
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
```

## Debugging

### Check Transform Pipeline

```bash
# List all stages
ls -d transform/*/

# Check .work directory for intermediate results
tree transform/.work/

# See what Stage 1 produced (input to Stage 2)
ls transform/.work/10_KubernetesPlugin/output/

# Diff input vs output for a stage
diff -r transform/.work/20_CustomStage/input/ \
        transform/.work/20_CustomStage/output/
```

### Preview Kustomize Output

```bash
# Preview specific stage
kubectl kustomize transform/10_KubernetesPlugin/

# Preview and save to file
kubectl kustomize transform/10_KubernetesPlugin/ > preview.yaml

# Preview with custom kustomize args
kubectl kustomize transform/10_KubernetesPlugin/ --enable-helm
```

### Validate Output

```bash
# Client-side validation
kubectl apply --dry-run=client -f output/output.yaml

# Server-side validation (against target cluster)
kubectl apply --dry-run=server -f output/output.yaml --context=<target-context>

# Validate specific resource types
kubectl apply --dry-run=client -f output/output.yaml | grep "^kind:"
```

### Debug Crane Issues

```bash
# Run with debug flag
crane export --debug -n <namespace>
crane transform --debug
crane apply --debug

# Check Crane version
crane version

# List installed plugins
crane plugin-manager list

# Check plugin directory
ls -la ~/.local/share/crane/plugins/
```

## Common Troubleshooting

### Issue: "Stage requires output from previous stage"

**Cause:** Running stage without its predecessor.

**Solution:**
```bash
# Run all stages
crane transform

# Or run from first stage
crane transform 10_KubernetesPlugin 20_NextStage
```

### Issue: "Plugin found in multiple stages"

**Cause:** Same plugin in multiple stage directories.

**Solution:**
```bash
# Use exact stage directory name
crane transform 10_KubernetesPlugin
```

### Issue: Custom stage has stale data

**Cause:** Previous stages were re-run but custom stage wasn't updated.

**Solution:**
```bash
# Re-run all stages
crane transform

# Or force regenerate (WARNING: loses manual edits)
crane transform --force
```

### Issue: ConfigMap name hash breaks references

**Cause:** Kustomize's configMapGenerator adds hash suffix.

**Solution:**
```yaml
# Add to kustomization.yaml
generatorOptions:
  disableNameSuffixHash: true
```

### Issue: JSONPatch path with special characters

**Cause:** JSONPatch requires escaping for `/` and `~`.

**Solution:**
```yaml
# For annotation key "example.com/annotation"
- op: add
  path: /metadata/annotations/example.com~1annotation
  value: "value"

# Escape rules:
# ~ becomes ~0
# / becomes ~1
```

## Best Practices

### Stage Organization

1. **Use priority spacing:**
   - Good: 10, 20, 30, 50, 90
   - Bad: 1, 2, 3, 4 (no room to insert)

2. **Plugin stages first, custom stages last:**
   ```
   10_KubernetesPlugin
   15_OpenshiftPlugin
   50_CustomEdits      # Custom stage uses output from plugins
   90_FinalTweaks
   ```

3. **Descriptive stage names:**
   - Good: `50_ProductionCustomization`
   - Bad: `50_Custom`

### Git Workflow

```bash
# Initialize Git for migration tracking
git init
git add export/ transform/ output/
git commit -m "Initial export and transform"

# Commit after each significant change
git add transform/20_CustomStage/
git commit -m "Add custom production settings"

# Ignore .work directory (regenerated each time)
echo "transform/.work/" >> .gitignore
```

### Security

```bash
# Never commit production secrets
echo "production-secrets.yaml" >> .gitignore
echo "**/secret*.yaml" >> .gitignore

# Use placeholder values in kustomization.yaml
secretGenerator:
- name: app-secrets
  literals:
  - password=REPLACE_IN_PRODUCTION
  - api-key=REPLACE_IN_PRODUCTION
```

### Testing

```bash
# Always preview before applying
kubectl kustomize transform/<stage>/

# Always dry-run before real apply
kubectl apply --dry-run=client -f output/output.yaml

# Test in staging first
kubectl apply -f output/output.yaml --context=staging-cluster

# Then production
kubectl apply -f output/output.yaml --context=prod-cluster
```

## Quick Workflow Examples

### Simple Migration

```bash
crane export -n myapp
crane transform
crane apply
kubectl apply -f output/output.yaml --context=target-cluster
```

### Multi-Stage with Customization

```bash
crane export -n myapp
crane transform KubernetesPlugin
crane transform ProductionSettings
# Edit transform/20_ProductionSettings/kustomization.yaml
crane apply
kubectl apply -f output/output.yaml --context=prod-cluster
```

### Cross-Platform Migration

```bash
crane export -n myapp
crane transform KubernetesPlugin OpenshiftPlugin
crane transform PlatformConversion
# Manually convert Ingress → Route in PlatformConversion stage
crane apply
oc apply -f output/output.yaml --context=openshift-cluster
```

## Useful kubectl Commands

```bash
# Export all resources from namespace (without Crane)
kubectl get all,cm,secret,pvc,ingress -n <namespace> -o yaml

# List all resources in namespace
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n <namespace>

# Get all resources with labels
kubectl get all -n <namespace> -l app=myapp

# Compare resources between clusters
diff <(kubectl get deployment myapp -n myns -o yaml --context=cluster1) \
     <(kubectl get deployment myapp -n myns -o yaml --context=cluster2)
```

## Additional Resources

- [Crane Documentation](../../crane/README.md)
- [Multi-Stage Transform Guide](../../notes/transform-multistage.md)
- [Kustomize Documentation](https://kubectl.docs.kubernetes.io/references/kustomize/)
- [JSONPatch Specification](http://jsonpatch.com/)
- [Konveyor Community](https://www.konveyor.io/)
