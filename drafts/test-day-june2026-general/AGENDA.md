# Crane Test Day - June 2026
## Stateless Kubernetes Migration Testing

**Duration:** 5.5 hours | **Focus:** Export → Transform → Apply workflows

---

## Schedule

| Time | Activity | Duration |
|------|----------|----------|
| 0:00 - 0:30 | **Setup & Introduction** | 30 min |
| | • Install Crane binary<br>• Verify cluster access<br>• Overview presentation | |
| 0:30 - 1:15 | **Scenario 1: Basic Stateless** | 45 min |
| | • Simple nginx application<br>• Export → Transform → Apply<br>• KubernetesPlugin basics | |
| 1:15 - 2:30 | **Break + Q&A** | 15 min |
| 2:30 - 3:30 | **Scenario 2: Multi-stage** | 60 min |
| | • Multi-tier application<br>• Sequential transformation stages<br>• Debug with .work/ directory | |
| 3:30 - 3:45 | **Break + Q&A** | 15 min |
| 3:45 - 5:05 | **Scenario 3: Cross-platform** | 80 min |
| | • Kubernetes ↔ OpenShift<br>• Route/Ingress conversion<br>• Platform-specific handling | |
| 5:05 - 5:20 | **Break + Q&A** | 15 min |
| 5:20 - 6:50 | **Scenario 4: Customization** | 90 min |
| | • Production environment setup<br>• Resource scaling, registry changes<br>• Security hardening | |
| 6:50 - 7:20 | **Wrap-up & Reports** | 30 min |
| | • Complete test reports<br>• Group discussion<br>• Next steps | |

---

## Quick Reference

### Essential Commands
```bash
# Export
crane export -n <namespace>

# Transform (all stages)
crane transform

# Transform (specific stages)
crane transform KubernetesPlugin CustomStage

# Apply
crane apply

# Deploy
kubectl apply -f output/output.yaml
```

### Directory Structure
```
project/
├── export/resources/<namespace>/    # Exported YAML
├── transform/
│   ├── 10_KubernetesPlugin/        # Plugin stage (auto-regen)
│   ├── 20_CustomStage/             # Custom stage (protected)
│   └── .work/                      # Debug intermediate results
└── output/output.yaml              # Final manifests
```

### Stage Types
- **Plugin stages** (e.g., `10_KubernetesPlugin`): Auto-regenerate, don't edit
- **Custom stages** (e.g., `50_CustomEdits`): Protected, safe to edit

---

## Learning Objectives

### Scenario 1: Basics
✓ Understand export → transform → apply workflow  
✓ Use KubernetesPlugin for metadata cleanup  
✓ Generate redeployable manifests

### Scenario 2: Multi-stage
✓ Create sequential transformation pipelines  
✓ Understand stage consistency  
✓ Debug with .work/ directory  
✓ Mix plugin and custom stages

### Scenario 3: Cross-platform
✓ Handle platform-specific resources  
✓ Convert Ingress ↔ Route  
✓ Adjust security contexts  
✓ Use OpenshiftPlugin (if available)

### Scenario 4: Customization
✓ Customize for target environment  
✓ Use Kustomize overlays  
✓ Scale and adjust resources  
✓ Change registries and namespaces  
✓ Add security policies

---

## Prerequisites Checklist

### Software Installed
- [ ] `crane` binary (main branch)
- [ ] `kubectl` configured
- [ ] Git
- [ ] Text editor

### Access Verified
- [ ] Source cluster connection
- [ ] Target cluster connection
- [ ] Namespace creation permissions

### Knowledge
- [ ] Basic Kubernetes (Pods, Deployments, Services)
- [ ] kubectl commands
- [ ] YAML syntax

---

## What to Report

### For Each Scenario
1. **Status:** Pass ✅ / Pass with Issues ⚠️ / Fail ❌
2. **What worked well**
3. **What didn't work**
4. **Time spent**
5. **Suggestions**

### Overall
- Documentation quality
- CLI usability
- Error messages
- Feature requests
- Bugs found

**Report Template:** See `test-report-template.md`

---

## Tips & Tricks

### Debugging
```bash
# Use --debug flag
crane transform --debug

# Preview kustomize output
kubectl kustomize transform/10_KubernetesPlugin/

# Check intermediate results
ls transform/.work/10_KubernetesPlugin/output/

# Dry-run before apply
kubectl apply --dry-run=client -f output/output.yaml
```

### Common Issues

**"Stage requires output from previous stage"**  
→ Run all stages: `crane transform`

**"Plugin found in multiple stages"**  
→ Use exact directory name: `crane transform 10_KubernetesPlugin`

**ConfigMap name hash breaks references**  
→ Add to kustomization.yaml:
```yaml
generatorOptions:
  disableNameSuffixHash: true
```

---

## Resources

- **Main Guide:** `README.md`
- **Quick Ref:** `quick-reference.md`
- **Scenarios:** `scenario-01-*.md` through `scenario-04-*.md`
- **Report:** `test-report-template.md`

---

## Support

- GitHub Issues: https://github.com/konveyor/crane/issues
- Konveyor: https://www.konveyor.io/

---

**Remember:**
- Document everything (screenshots, errors, thoughts)
- Ask questions early and often
- Test incrementally, don't wait until the end
- Have fun! 🚀

---

*Test Day Materials v1.0 | June 2026*
