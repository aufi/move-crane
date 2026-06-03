# Crane Quick Reference - Test Day Edition

## Essential Commands

### Export
```bash
crane export -n <namespace>                    # Export namespace resources
crane export -n <namespace> --debug           # Export with debug output
crane export -n <namespace> -e <export-dir>   # Custom export directory
```

### Transform
```bash
crane transform                                # Run all discovered stages
crane transform list-plugins                   # List all available plugins, or <Tab> for autocompletion
crane transform KubernetesPlugin               # Run specific plugin stage
crane transform 20_CustomStage                 # Run specific custom stage
crane transform Stage1 Stage2 Stage3           # Run multiple stages
crane transform --force                        # Force regenerate all stages
```

### Apply
```bash
crane apply                                    # Generate final output
crane apply -t <transform-dir> -o <output-dir> # Custom directories
```

### Validation
```bash
crane validate -f output/output.yaml           # Validate output (if supported)
kubectl apply --dry-run=server -f output.yaml  # Server-side validation
kubectl apply --dry-run=client -f output.yaml  # Client-side validation
```

### Plugin Management
```bash
crane plugin-manager list                      # List installed plugins
crane plugin-manager install <path>            # Install plugin
crane plugin-manager remove <name>             # Remove plugin
```

## Directory Structure

```
migration-project/
├── export/
│   └── resources/
│       └── <namespace>/
│           ├── Deployment_*.yaml
│           ├── Service_*.yaml
│           ├── ConfigMap_*.yaml
│           └── ...
├── transform/
│   ├── 10_KubernetesPlugin/
│   │   ├── kustomization.yaml
│   │   ├── resources/
│   │   └── patches/
│   ├── 20_CustomStage/
│   │   ├── kustomization.yaml
│   │   ├── resources/
│   │   └── patches/
│   └── .work/                    # Debug directory
│       ├── 10_KubernetesPlugin/
│       │   ├── input/
│       │   └── output/
│       └── 20_CustomStage/
│           ├── input/
│           └── output/
└── output/
    └── output.yaml               # Final manifests
```

## Common Kustomize Patterns

### Change Namespace
```yaml
# In kustomization.yaml
namespace: new-namespace
```

### Add Labels
```yaml
commonLabels:
  environment: production
  team: platform
```

### Update Images
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

### Update ConfigMaps
```yaml
configMapGenerator:
- name: app-config
  literals:
  - key=value
  behavior: merge

generatorOptions:
  disableNameSuffixHash: true
```

### JSONPatch
```yaml
patches:
- path: patches/my-patch.yaml
  target:
    kind: Deployment
    name: my-app

# patches/my-patch.yaml:
# - op: replace
#   path: /spec/replicas
#   value: 3
```

## Debugging

### Check Transform Pipeline
```bash
# List all stages
ls -d transform/*/

# Check intermediate results
tree transform/.work/

# Preview stage output
kubectl kustomize transform/10_KubernetesPlugin/

# Diff input vs output for a stage
diff -r transform/.work/10_KubernetesPlugin/input/ \
        transform/.work/10_KubernetesPlugin/output/
```

### Validate Resources
```bash
# Preview final output
kubectl kustomize transform/<stage>/

# Validate syntax
kubectl apply --dry-run=client -f output/output.yaml

# Validate against cluster
kubectl apply --dry-run=server -f output/output.yaml --context=<context>
```

## Common Issues

### ConfigMap Name Hash
**Problem:** Kustomize adds hash to ConfigMap names  
**Solution:**
```yaml
generatorOptions:
  disableNameSuffixHash: true
```

### Stale Custom Stage
**Problem:** Custom stage has old data after re-running earlier stages  
**Solution:**
```bash
crane transform --force  # Regenerates all
# OR
crane transform Stage1 Stage2 Stage3  # Update specific stages
```

### JSONPatch Special Characters
**Problem:** Annotation keys with `/` or `~`  
**Solution:**
```yaml
# For key "example.com/annotation"
- op: add
  path: /metadata/annotations/example.com~1annotation  # ~1 = /
  value: "value"
```

## Test Day Priority Checklist

### Priority 1: KubernetesPlugin
- [ ] All resource types exported
- [ ] Patches generated correctly
- [ ] No manual cleanup needed
- [ ] App deploys successfully

### Priority 2: Multi-stage
- [ ] Multiple stages created
- [ ] Kustomize transformations work
- [ ] Stage iteration clear
- [ ] Documentation sufficient

### Priority 3: Cluster Resources
- [ ] Cluster resources identified
- [ ] Migration workflow clear
- [ ] Dependencies handled
- [ ] Guidance provided

### Priority 4: Validation
- [ ] Validates before deployment
- [ ] Detects incompatibilities
- [ ] Error messages helpful
- [ ] Recommendations actionable

### Priority 5: Custom Plugin
- [ ] Plugin interface documented
- [ ] AI assistance helpful
- [ ] Plugin builds and integrates
- [ ] Transformation works

## Reporting Template

```markdown
## Scenario X: [Name] - [PASS/FAIL/PARTIAL]

**Environment:**
- Source: [cluster type/version]
- Target: [cluster type/version]
- Crane: [version]

**Issues:**
1. [Blocking/Workaround-able/Docs] - [Description]
   - Error: [message]
   - Solution: [if any]

**Recommendations:**
- [suggestion 1]
- [suggestion 2]

**Questions:**
- [question 1]
- [question 2]
```

## Useful kubectl Commands

```bash
# Get all resources in namespace
kubectl get all,cm,secret,pvc,ingress -n <namespace>

# Export all resources (without crane)
kubectl get all,cm,secret,pvc -n <namespace> -o yaml

# Compare clusters
diff <(kubectl get deploy app -n ns -o yaml --context=source) \
     <(kubectl get deploy app -n ns -o yaml --context=target)

# Watch deployment
kubectl get pods -n <namespace> -w

# Check resource details
kubectl describe <resource> <name> -n <namespace>
```

## Key Questions for Test Day

1. **KubernetesPlugin:** Which resource types had issues?
2. **Multi-stage:** Iterate stage-by-stage or regenerate all?
3. **Cluster resources:** Should crane export them automatically?
4. **Validation:** What validations are missing?
5. **Custom plugin:** Is plugin development accessible?

## Tips

- Always use `--debug` flag when investigating issues
- Check `.work/` directory to understand stage flow
- Commit to git after each successful stage
- Test validation before deploying
- Document everything - blocking bugs, workarounds, suggestions

## Support

- Quick fixes: This reference guide
- Detailed scenarios: scenario-*.md files
- Issues: GitHub https://github.com/konveyor/crane/issues
