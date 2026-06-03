# Crane Test Day - June 2026

**Focus:** Real-world stateless application migration

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
- **Source cluster:** OpenShift 4.x (OR upstream Kubernetes (minikube/kind))
- **Target cluster:** OpenShift 4.x (OR upstream Kubernetes (minikube/kind))

Recommended combinations:
- OpenShift 4.16-20 → OpenShift 4.16-20 (same versions, recommended)
- Kubernetes 1.3x → Kubernetes 1.3x (same versions current minikube/kind, fallback without OpenShift access)

### Permissions
- **Namespace-level:** Create, read, update, delete resources
- **Cluster-level:** Read and create ClusterRole, ClusterRoleBinding, CRDs, etc. (for Priority 3 tests)

## Test Scenarios

### [Scenario 1: Real-World Application Migration](./scenario-01-real-world-app.md)
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

### [Scenario 2: Multi-stage Transformation](./scenario-02-multistage-kustomize.md)
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

### [Scenario 3: Cluster-Level Resources](./scenario-03-cluster-resources.md)
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

### [Scenario 4: Validation Testing](./scenario-04-validation.md)
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

### [Scenario 5: Custom Plugin Creation](./scenario-05-custom-plugin.md)
**Priority 5: Plugin Development**

Create custom plugin with AI assistance:
- BuildConfig (OpenShift) → Shipwright Build conversion
- Custom transformation logic
- Integration with crane workflow

**Key validation:**
- Plugin creation process is clear
- Plugin integrates correctly
- Transformation works as expected

## Installation

### Crane Binary

Download from https://github.com/migtools/crane or clone repo and build locally.

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

## Some Questions to Answer

1. **Resource coverage:** Are there resource types that KubernetesPlugin doesn't handle correctly?

2. **Iterative transform workflow:** Does it make sense to work on `transform/` directory iteratively stage-by-stage, or regenerate the whole directory when changes are needed?

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
