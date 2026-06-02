# Crane Test Day Report

**Tester Name:** [Your Name]  
**Date:** [Test Date]  
**Crane Version:** [e.g., main@20260601, or output of `crane version`]

## Environment Details

### Source Cluster
- **Platform:** [Kubernetes / OpenShift / Other]
- **Version:** [e.g., Kubernetes 1.28.0, OpenShift 4.14]
- **Cloud Provider:** [AWS / GCP / Azure / On-Premise / Minikube / Kind]
- **Notes:** [Any relevant details]

### Target Cluster
- **Platform:** [Kubernetes / OpenShift / Other]
- **Version:** [e.g., Kubernetes 1.29.0]
- **Cloud Provider:** [AWS / GCP / Azure / On-Premise / Minikube / Kind]
- **Notes:** [Any relevant details]

### Testing Platform
- **OS:** [Linux / macOS / Windows]
- **OS Version:** [e.g., Ubuntu 24.04, macOS 14.0]
- **kubectl Version:** [output of `kubectl version --client`]
- **kustomize Version:** [if using standalone]

---

## Scenario 1: Basic Stateless Application

**Status:** [ ] Passed ✅ | [ ] Passed with Issues ⚠️ | [ ] Failed ❌ | [ ] Not Tested

### Test Results

**Export Phase:**
- [ ] All resources exported successfully
- [ ] Export completed without errors
- **Time taken:** [X minutes]
- **Notes:**

**Transform Phase:**
- [ ] KubernetesPlugin created successfully
- [ ] Patches generated correctly
- [ ] Metadata cleaned as expected
- **Time taken:** [X minutes]
- **Notes:**

**Apply Phase:**
- [ ] output/output.yaml generated successfully
- [ ] Manifests are valid YAML
- [ ] Dry-run validation passed
- **Time taken:** [X minutes]
- **Notes:**

**Deployment to Target:**
- [ ] Deployment successful
- [ ] Application functional
- [ ] All pods Running/Ready
- **Time taken:** [X minutes]
- **Notes:**

### Issues Encountered

**Issue 1:**
- **Description:**
- **Phase:** [Export / Transform / Apply / Deploy]
- **Error Message:**
- **Workaround/Solution:**
- **Severity:** [Minor / Moderate / Major / Blocker]

**Issue 2:**
[Repeat as needed]

### Positive Observations

-
-
-

### Suggestions for Improvement

-
-
-

---

## Scenario 2: Multi-stage Transformation

**Status:** [ ] Passed ✅ | [ ] Passed with Issues ⚠️ | [ ] Failed ❌ | [ ] Not Tested

### Test Results

**Multi-Stage Creation:**
- [ ] Multiple stages created successfully
- [ ] Stage priorities correct
- [ ] .work/ directory structure correct
- **Time taken:** [X minutes]
- **Notes:**

**Sequential Consistency:**
- [ ] Each stage received output from previous stage
- [ ] No stale data issues
- [ ] Transformations cascaded correctly
- **Notes:**

**Stage Flexibility:**
- [ ] Plugin stages auto-regenerated
- [ ] Custom stages protected from overwrite
- [ ] Stage selection by name worked
- [ ] --force flag behavior as expected
- **Notes:**

**Final Output:**
- [ ] All transformations applied correctly
- [ ] Output reflects all stages
- **Time taken:** [X minutes]
- **Notes:**

### Issues Encountered

**Issue 1:**
- **Description:**
- **Phase:**
- **Error Message:**
- **Workaround/Solution:**
- **Severity:**

### Positive Observations

-
-
-

### Suggestions for Improvement

-
-
-

---

## Scenario 3: Cross-platform Migration

**Status:** [ ] Passed ✅ | [ ] Passed with Issues ⚠️ | [ ] Failed ❌ | [ ] Not Tested

**Migration Direction:** [Kubernetes → OpenShift / OpenShift → Kubernetes / Other]

### Test Results

**Platform Resource Conversion:**
- [ ] Source platform resources identified
- [ ] Target platform resources created
- [ ] Conversion maintained functionality
- **Conversion Type:** [Route→Ingress / Ingress→Route / Other]
- **Notes:**

**OpenshiftPlugin (if used):**
- [ ] Plugin available
- [ ] Plugin executed successfully
- [ ] Transformations appropriate
- **Notes:**

**Manual Conversion (if required):**
- [ ] Manual conversion completed
- [ ] Resources validated
- **Time taken:** [X minutes]
- **Notes:**

**Security Context Handling:**
- [ ] Security contexts adjusted correctly
- [ ] No SCC violations (OpenShift)
- [ ] Pods started successfully
- **Notes:**

**Deployment to Target:**
- [ ] Application deployed successfully
- [ ] Routing works (Ingress/Route)
- [ ] Application functional
- **Time taken:** [X minutes]
- **Notes:**

### Issues Encountered

**Issue 1:**
- **Description:**
- **Phase:**
- **Error Message:**
- **Workaround/Solution:**
- **Severity:**

### Positive Observations

-
-
-

### Suggestions for Improvement

-
-
-

---

## Scenario 4: Customization for Target Environment

**Status:** [ ] Passed ✅ | [ ] Passed with Issues ⚠️ | [ ] Failed ❌ | [ ] Not Tested

### Test Results

**Customization Configuration:**
- [ ] Namespace change successful
- [ ] ConfigMap updates applied
- [ ] Replica scaling worked
- [ ] Resource limits adjusted
- [ ] Image registry updated
- [ ] Storage class changed
- **Time taken:** [X minutes]
- **Notes:**

**Kustomize Features Used:**
- [ ] commonLabels
- [ ] commonAnnotations
- [ ] configMapGenerator
- [ ] secretGenerator
- [ ] images
- [ ] replicas
- [ ] patches (JSONPatch)
- [ ] patches (Strategic Merge)
- **Notes:**

**Additional Resources:**
- [ ] Ingress created
- [ ] NetworkPolicy created
- [ ] Other resources added
- **Notes:**

**Deployment to Target:**
- [ ] All customizations applied correctly
- [ ] Application functional with new configuration
- [ ] Security policies enforced
- **Time taken:** [X minutes]
- **Notes:**

### Issues Encountered

**Issue 1:**
- **Description:**
- **Phase:**
- **Error Message:**
- **Workaround/Solution:**
- **Severity:**

### Positive Observations

-
-
-

### Suggestions for Improvement

-
-
-

---

## Overall Feedback

### What Worked Well

1.
2.
3.

### What Needs Improvement

1.
2.
3.

### Documentation Feedback

**Clarity:**
- [ ] Excellent | [ ] Good | [ ] Needs Improvement

**Completeness:**
- [ ] Excellent | [ ] Good | [ ] Needs Improvement

**Specific Documentation Issues:**
-
-

### UX/CLI Feedback

**Ease of Use:**
- [ ] Excellent | [ ] Good | [ ] Needs Improvement

**Error Messages:**
- [ ] Helpful | [ ] Adequate | [ ] Confusing

**Specific UX Issues:**
-
-

### Feature Requests

1.
2.
3.

### Bug Reports

**Bug 1:**
- **Summary:**
- **Steps to Reproduce:**
- **Expected Behavior:**
- **Actual Behavior:**
- **Severity:** [Low / Medium / High / Critical]

**Bug 2:**
[Repeat as needed]

---

## Time Summary

| Scenario | Time Spent | Status |
|----------|-----------|--------|
| Setup | [X min] | - |
| Scenario 1 | [X min] | [Pass/Fail] |
| Scenario 2 | [X min] | [Pass/Fail] |
| Scenario 3 | [X min] | [Pass/Fail] |
| Scenario 4 | [X min] | [Pass/Fail] |
| **Total** | **[X min]** | - |

---

## Additional Notes

[Any additional observations, thoughts, or context that don't fit above]

---

## Attachments

- [ ] Screenshots attached
- [ ] Log files attached
- [ ] Example manifests attached
- [ ] Error outputs attached

**Files:** [List files or link to shared location]

---

**Would you participate in future test days?** [ ] Yes | [ ] No | [ ] Maybe

**Would you recommend Crane to others?** [ ] Yes | [ ] No | [ ] Maybe

**Overall Rating:** [ ] ⭐ | [ ] ⭐⭐ | [ ] ⭐⭐⭐ | [ ] ⭐⭐⭐⭐ | [ ] ⭐⭐⭐⭐⭐

---

**Thank you for participating in the Crane Test Day!**

Please submit this report to: [GitHub Issue / Email / Form Link]
