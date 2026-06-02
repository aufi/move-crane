# Crane Test Day - June 2026

**Focus:** Real-world stateless migration validation  
**Duration:** 4-5 hours

## Objectives

This test day validates Crane's ability to handle real-world stateless Kubernetes/OpenShift migrations across these priority areas:

### Priority 1: KubernetesPlugin Cleanup Validation
**Goal:** Verify that KubernetesPlugin correctly cleans ALL resource types to enable migration to target cluster

**Test:** Real-world stateless deployments successfully migrate without manual intervention

### Priority 2: Multi-stage Transformation with Kustomize
**Goal:** Ensure multi-stage transforms with custom Kustomize changes are clear and user-friendly

**Test:** Users can successfully apply namespace changes, label additions, and image updates through custom stages

### Priority 3: Cluster-level Resource Migration
**Goal:** Correctly migrate cluster-level resources (ClusterRole, ClusterRoleBinding, CRDs, etc.) referenced by applications

**Test:** Applications with cluster-level dependencies start successfully on target cluster

### Priority 4: Validation
**Goal:** Crane validates manifests and reports migration blockers

**Test:** Validation catches issues and provides actionable guidance

### Priority 5: Custom Plugin Creation
**Goal:** Users can create custom plugins with assistance (example: BuildConfig → Shipwright)

**Test:** Successfully create and use custom transformation plugin

## Prerequisites

### Hardware/Software
- **Machine:** Linux, macOS, or Windows
- **Crane:** Latest build from main branch
- **kubectl/oc:** Compatible with cluster versions
- **Git:** For tracking migration state

### Cluster Access
Must have access to BOTH:
- **Source cluster:** OpenShift 4.x OR upstream Kubernetes (minikube/kind)
- **Target cluster:** OpenShift 4.x OR upstream Kubernetes (minikube/kind)

Recommended combinations:
- OpenShift 4.16 → OpenShift 4.16 (same version)
- Kubernetes 1.30 → Kubernetes 1.30 (same version)
- OpenShift 4.16 → Kubernetes 1.30 (cross-platform)

### Permissions
- **Namespace-level:** Create, read, update, delete resources
- **Cluster-level:** Read and create ClusterRole, ClusterRoleBinding, CRDs (for Priority 3 tests)

## Test Scenarios

### [Scenario 1: Real-World Application Migration](./scenario-01-real-world-app.md) (~60 min)
**Priority 1: KubernetesPlugin Validation**

Deploy and migrate real-world applications:
- WordPress with MySQL (stateless startup - DBs pre-populated)
- Microservices application (multiple deployments, services, configs)
- Application with various resource types (HPA, PDB, NetworkPolicy)

**Key validation:**
- All resource types export correctly
- KubernetesPlugin generates appropriate patches
- No manual cleanup required
- Application starts on target cluster

### [Scenario 2: Multi-stage Transformation](./scenario-02-multistage-kustomize.md) (~60 min)
**Priority 2: Kustomize Integration**

Transform application through multiple stages:
1. KubernetesPlugin cleanup
2. Namespace change (dev → production)
3. Label/annotation additions
4. Image registry changes
5. Custom modifications

**Key validation:**
- Clear workflow for creating custom stages
- Kustomize transformations apply correctly
- Documentation is sufficient
- Iteration workflow is clear

### [Scenario 3: Cluster-Level Resources](./scenario-03-cluster-resources.md) (~60 min)
**Priority 3: Cluster-Scoped Migration**

Migrate application with cluster-level dependencies:
- Custom Resource Definitions (CRDs)
- ClusterRoles and ClusterRoleBindings
- PriorityClasses
- StorageClasses
- ValidatingWebhookConfiguration

**Key validation:**
- Cluster-level resources detected and exported
- Dependencies correctly identified
- Migration successful with cluster-admin rights
- Clear guidance when resources cannot be migrated

### [Scenario 4: Validation Testing](./scenario-04-validation.md) (~45 min)
**Priority 4: Validation Features**

Test crane's validation capabilities:
- Validate against target cluster API
- Detect incompatible resources
- Report missing dependencies
- Suggest fixes for common issues

**Key validation:**
- Validation catches real issues
- Error messages are actionable
- Recommendations are helpful

### [Scenario 5: Custom Plugin Creation](./scenario-05-custom-plugin.md) (~60 min)
**Priority 5: Plugin Development**

Create custom plugin with AI assistance:
- BuildConfig (OpenShift) → Shipwright Build conversion
- Custom transformation logic
- Integration with crane workflow

**Key validation:**
- Plugin creation process is clear
- Plugin integrates correctly
- Transformation works as expected

## Timeline

| Time | Activity | Duration |
|------|----------|----------|
| 0:00 - 0:20 | Setup & Introduction | 20 min |
| 0:20 - 1:20 | Scenario 1: Real-World Apps | 60 min |
| 1:20 - 1:35 | Break | 15 min |
| 1:35 - 2:35 | Scenario 2: Multi-stage | 60 min |
| 2:35 - 2:50 | Break | 15 min |
| 2:50 - 3:50 | Scenario 3: Cluster Resources | 60 min |
| 3:50 - 4:05 | Break | 15 min |
| 4:05 - 4:50 | Scenario 4: Validation | 45 min |
| 4:50 - 5:00 | Break | 10 min |
| 5:00 - 6:00 | Scenario 5: Custom Plugin | 60 min |
| 6:00 - 6:30 | Reports & Discussion | 30 min |

**Total: ~6 hours**

## Installation

### Crane Binary

```bash
# Build from main branch
cd /path/to/crane/repo
go build -o crane main.go

# Install to PATH
sudo cp crane /usr/local/bin/

# Verify
crane version
```

### Cluster Setup

Ensure you have kubeconfig access to both clusters:

```bash
# List available contexts
kubectl config get-contexts

# Test source cluster
kubectl cluster-info --context=<source-context>

# Test target cluster  
kubectl cluster-info --context=<target-context>
```

## Expected Reports

Please document:

### 1. Blocking Bugs
Issues that prevent migration from completing:
- Error message
- Steps to reproduce
- Expected vs actual behavior
- Workaround (if any)

### 2. Workaround-able Bugs
Issues that can be resolved with manual intervention:
- What failed initially
- What manual steps were needed
- Should this be automated?

### 3. Documentation & Recommendations
- Missing documentation
- Unclear workflows
- UX improvements
- Feature requests

Use the [test report template](./test-report-template.md) for structured feedback.

## Key Questions to Answer

1. **Iterative workflow:** Does it make sense to work on `transform/` directory iteratively stage-by-stage, or regenerate the whole directory when changes are needed?

2. **Resource coverage:** Are there resource types that KubernetesPlugin doesn't handle correctly?

3. **Cluster-level resources:** What should crane do when cluster-level resources cannot be migrated (permissions, conflicts, etc.)?

4. **Validation feedback:** Are validation error messages helpful enough?

5. **Plugin creation:** Is the process of creating custom plugins accessible to users?

## Documentation Validation

Part of this test day is ensuring adequate documentation exists. Please note:
- Missing documentation for workflows you attempted
- Confusing or incomplete existing docs
- Examples that would have helped
- Better error messages needed

## Support Resources

- **Quick Reference:** [quick-reference.md](./quick-reference.md)
- **Main Crane Docs:** [../../crane/README.md](../../crane/README.md)
- **Multi-stage Guide:** [../../notes/transform-multistage.md](../../notes/transform-multistage.md)
- **GitHub Issues:** https://github.com/konveyor/crane/issues

## Success Criteria

By end of test day, we should know:

✅ **Priority 1:** KubernetesPlugin correctly handles all tested resource types  
✅ **Priority 2:** Multi-stage transformation workflow is clear and functional  
✅ **Priority 3:** Cluster-level resource migration works or has clear guidance  
✅ **Priority 4:** Validation catches issues and provides helpful feedback  
✅ **Priority 5:** Custom plugin creation is feasible with documentation/assistance

---

Let's validate Crane with real-world scenarios! 🚀
