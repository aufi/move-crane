# Crane Test Day Report

**Tester:** [Your Name]  
**Date:** [Date]  
**Crane Version:** [Output of `crane version`]

## Environment

### Source Cluster
- **Platform:** [Kubernetes / OpenShift]
- **Version:** [e.g., Kubernetes 1.30, OpenShift 4.16]
- **Provider:** [AWS / GCP / Azure / On-prem / Minikube / Kind]

### Target Cluster
- **Platform:** [Kubernetes / OpenShift]
- **Version:** [e.g., Kubernetes 1.30, OpenShift 4.16]
- **Provider:** [AWS / GCP / Azure / On-prem / Minikube / Kind]

### Testing Environment
- **OS:** [Linux / macOS / Windows]
- **OS Version:** [e.g., Ubuntu 24.04]

---

## Priority 1: KubernetesPlugin Cleanup Validation

**Status:** [ ] PASS | [ ] FAIL | [ ] PARTIAL

### Applications Tested
- [ ] WordPress + MySQL
- [ ] Microservices app
- [ ] CI/CD pipeline (OpenShift)
- [ ] Other: ___________

### Resource Types Exported
List all resource types that were successfully exported:
- [ ] Deployment
- [ ] Service
- [ ] ConfigMap
- [ ] Secret
- [ ] HorizontalPodAutoscaler
- [ ] PodDisruptionBudget
- [ ] NetworkPolicy
- [ ] Other: ___________

### Patch Generation
For each resource type, were patches generated correctly?
- [ ] Removes `metadata.uid`
- [ ] Removes `metadata.resourceVersion`
- [ ] Removes `metadata.creationTimestamp`
- [ ] Removes `metadata.managedFields`
- [ ] Removes `status` section
- [ ] Preserves user-defined fields

### Deployment Success
- [ ] All resources deployed to target cluster
- [ ] No manual cleanup required
- [ ] Application functional on target

### Issues Found

#### Issue 1: [Blocking / Workaround / Docs]
**Resource Type:** [e.g., HorizontalPodAutoscaler]  
**Description:** [What went wrong]  
**Error Message:**
```
[Paste error message]
```
**Workaround:** [If any]  
**Should be fixed:** [ ] Yes [ ] No

[Repeat for additional issues]

### Recommendations
1.
2.
3.

---

## Priority 2: Multi-stage Transformation with Kustomize

**Status:** [ ] PASS | [ ] FAIL | [ ] PARTIAL

### Stages Created
- [ ] KubernetesPlugin (auto-generated)
- [ ] Namespace change
- [ ] Label/annotation additions
- [ ] Image updates
- [ ] ConfigMap modifications
- [ ] Custom patches

### Kustomize Features Tested
- [ ] `namespace`
- [ ] `commonLabels`
- [ ] `commonAnnotations`
- [ ] `images`
- [ ] `replicas`
- [ ] `configMapGenerator`
- [ ] `secretGenerator`
- [ ] JSONPatch
- [ ] Strategic merge patch

### Iteration Workflow

**Question: Stage-by-stage vs full regeneration?**

When you needed to modify a stage, what did you do?
- [ ] Re-ran specific stages only
- [ ] Regenerated all stages with `--force`
- [ ] Manually edited each affected stage
- [ ] Other: ___________

**What worked best?**
___________________________________________

**What was confusing?**
___________________________________________

**Should crane provide better support for iteration?**
[ ] Yes - suggest: ___________
[ ] No - current approach is fine

### Sequential Consistency
- [ ] Each stage received output from previous stage (verified)
- [ ] `.work/` directory helped debugging
- [ ] Understood data flow between stages

### Issues Found

#### Issue 1: [Blocking / Workaround / Docs]
**Stage:** [e.g., 30_ImageUpdate]  
**Description:**  
**Workaround:**  

### Recommendations
1.
2.

---

## Priority 3: Cluster-Level Resources

**Status:** [ ] PASS | [ ] FAIL | [ ] PARTIAL | [ ] NOT TESTED

### Cluster Resources Tested
- [ ] CustomResourceDefinitions (CRDs)
- [ ] ClusterRole / ClusterRoleBinding
- [ ] PriorityClass
- [ ] StorageClass
- [ ] Other: ___________

### Detection
- [ ] Crane identified cluster resource dependencies
- [ ] Clear warning/message about cluster resources
- [ ] Listed what cluster resources are needed

### Export
- [ ] Cluster resources exported automatically
- [ ] Flag available to export cluster resources: [ ] Yes [ ] No
- [ ] Manual export process clear

### Migration Workflow
- [ ] Cluster resources cleaned correctly
- [ ] Order of operations clear (cluster first, then namespace)
- [ ] Dependencies handled correctly
- [ ] Application functional after migration

### Permissions
- [ ] Required cluster-admin permissions (documented)
- [ ] Clear error if insufficient permissions

### Issues Found

#### Issue 1: [Blocking / Workaround / Docs]
**Resource Type:** [e.g., CRD]  
**Description:**  
**Workaround:**  

### Recommendations
1.
2.

---

## Priority 4: Validation

**Status:** [ ] PASS | [ ] FAIL | [ ] PARTIAL | [ ] NOT TESTED

### Validation Command
- [ ] `crane validate` command exists
- [ ] Can validate against target cluster
- [ ] Provides useful exit codes

### Validations Performed
- [ ] API version compatibility
- [ ] Missing CRDs
- [ ] Resource quota violations
- [ ] LimitRange violations
- [ ] Missing StorageClasses
- [ ] Security policy violations
- [ ] Service type compatibility

### Error Messages
**Quality:** [ ] Excellent [ ] Good [ ] Needs Improvement [ ] Poor

**Were error messages:**
- [ ] Clear and specific
- [ ] Identified problematic resources
- [ ] Explained what's wrong
- [ ] Suggested how to fix

### Example Error Message

**What failed:**
___________________________________________

**Error message received:**
```
[Paste error]
```

**Was it helpful?** [ ] Yes [ ] No  
**What would make it better:**
___________________________________________

### Issues Found

#### Issue 1: [Blocking / Workaround / Docs]
**Validation Type:**  
**Description:**  

### Recommendations
1.
2.

---

## Priority 5: Custom Plugin Creation

**Status:** [ ] PASS | [ ] FAIL | [ ] PARTIAL | [ ] NOT TESTED

### Plugin Created
**Plugin Name:** ___________  
**Purpose:** [e.g., BuildConfig → Shipwright]

### Development Process

**AI Assistant Used:** [ ] Yes [ ] No  
**AI Assistant Name:** [e.g., Claude, ChatGPT, GitHub Copilot]

**AI Assistance Quality:**
- [ ] Very helpful - generated working code
- [ ] Somewhat helpful - needed modifications
- [ ] Not helpful - had to start from scratch

**What AI did well:**
___________________________________________

**What AI struggled with:**
___________________________________________

### Plugin Interface
- [ ] Plugin interface documented
- [ ] Examples available
- [ ] Input/output contract clear
- [ ] Testing capabilities available

### Integration
- [ ] Plugin recognized by crane
- [ ] Used successfully in transform pipeline
- [ ] Worked alongside other plugins
- [ ] Didn't break existing functionality

### Testing
- [ ] Could test plugin standalone
- [ ] Could test in crane pipeline
- [ ] Error handling worked

### Issues Found

#### Issue 1: [Blocking / Workaround / Docs]
**Area:** [e.g., Plugin interface, Build, Integration]  
**Description:**  
**Workaround:**  

### Recommendations
1.
2.

---

## Overall Assessment

### What Worked Well
1.
2.
3.

### Blocking Issues
Issues that prevent using crane for production migrations:
1.
2.

### Workaround-able Issues
Issues that can be worked around but should be fixed:
1.
2.

### Documentation Gaps
Missing or unclear documentation:
1.
2.
3.

### Feature Requests
New features that would improve crane:
1.
2.
3.

---

## Time Spent

| Scenario | Time | Status |
|----------|------|--------|
| Setup | ___ min | - |
| Scenario 1: Real-World Apps | ___ min | PASS/FAIL |
| Scenario 2: Multi-stage | ___ min | PASS/FAIL |
| Scenario 3: Cluster Resources | ___ min | PASS/FAIL |
| Scenario 4: Validation | ___ min | PASS/FAIL |
| Scenario 5: Custom Plugin | ___ min | PASS/FAIL |
| **Total** | **___ min** | - |

---

## Key Questions Answered

**1. Stage-by-stage vs full regeneration?**  
Answer: ___________________________________________

**2. Should crane export cluster resources automatically?**  
Answer: ___________________________________________

**3. Are validation messages helpful enough?**  
Answer: ___________________________________________

**4. Is custom plugin creation accessible?**  
Answer: ___________________________________________

**5. What resource types need better handling?**  
Answer: ___________________________________________

---

## Additional Notes

[Any other observations, context, or feedback]

---

## Would You Recommend Crane?

[ ] Yes - ready for production  
[ ] Yes - with fixes for blocking issues  
[ ] No - too many issues  
[ ] Undecided - need more testing

**Why:**
___________________________________________

---

**Thank you for participating in the Crane Test Day!**

Please submit this report to: [GitHub Issue URL / Email / Form]
