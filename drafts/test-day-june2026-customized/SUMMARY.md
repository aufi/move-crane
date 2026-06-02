# Crane Test Day - Customized Materials Summary

**Created:** June 2, 2026  
**Based on:** test-day-notes.md requirements  
**Total Content:** ~4,100 lines across 9 files

## Overview

This test day is focused on validating crane's real-world stateless migration capabilities with emphasis on:

1. **KubernetesPlugin completeness** - Does it handle all resource types?
2. **Multi-stage usability** - Is the workflow clear and iteration manageable?
3. **Cluster-level resources** - Can apps with cluster dependencies be migrated?
4. **Validation features** - Does crane detect issues before deployment?
5. **Custom plugin creation** - Can users create plugins with AI assistance?

## Materials Created

### Core Documents

1. **[README.md](./README.md)** (7.8 KB, 263 lines)
   - Test day objectives aligned with priorities
   - Prerequisites and installation
   - Timeline and expected reports
   - Key questions to answer

2. **[quick-reference.md](./quick-reference.md)** (6.6 KB, 269 lines)
   - Essential crane commands
   - Directory structures
   - Common Kustomize patterns
   - Debugging techniques
   - Priority checklist
   - Test day specific tips

3. **[test-report-template.md](./test-report-template.md)** (8.3 KB, 403 lines)
   - Structured by priority areas
   - Specific questions per scenario
   - Blocking vs workaround-able issue tracking
   - Key questions from test-day-notes.md

### Test Scenarios

4. **[scenario-01-real-world-app.md](./scenario-01-real-world-app.md)** (15 KB, 625 lines)
   - **Priority 1:** KubernetesPlugin validation
   - **Duration:** ~60 minutes
   - **Applications:** WordPress+MySQL, Microservices, CI/CD
   - **Focus:** Verify all resource types export and clean correctly
   - **Validation:** Comprehensive checklists per resource type

5. **[scenario-02-multistage-kustomize.md](./scenario-02-multistage-kustomize.md)** (18 KB, 724 lines)
   - **Priority 2:** Multi-stage transformation
   - **Duration:** ~60 minutes
   - **Stages:** 6 sequential transformation stages
   - **Focus:** Kustomize integration, iteration workflow
   - **Key Question:** Stage-by-stage vs full regeneration?
   - **Tests:** Modify existing stage, add stage in middle, remove stage

6. **[scenario-03-cluster-resources.md](./scenario-03-cluster-resources.md)** (16 KB, 617 lines)
   - **Priority 3:** Cluster-level resource migration
   - **Duration:** ~60 minutes
   - **Resources:** CRDs, ClusterRoles, PriorityClass, StorageClass
   - **Focus:** Detection, export, and migration of cluster resources
   - **Tests:** Namespace-only export (expected fail), cluster resource migration, missing dependency detection

7. **[scenario-04-validation.md](./scenario-04-validation.md)** (15 KB, 593 lines)
   - **Priority 4:** Validation features
   - **Duration:** ~45 minutes
   - **Test Cases:** API version compatibility, missing CRDs, resource quotas, storage, security policies, service types
   - **Focus:** Error detection and message quality
   - **Validation:** Are recommendations actionable?

8. **[scenario-05-custom-plugin.md](./scenario-05-custom-plugin.md)** (14 KB, 533 lines)
   - **Priority 5:** Custom plugin creation
   - **Duration:** ~60 minutes
   - **Example:** BuildConfig → Shipwright conversion
   - **Focus:** Plugin development with AI assistance
   - **Tests:** Interface clarity, AI helpfulness, integration, testing

### Supporting Documents

9. **[test-day-notes.md](./test-day-notes.md)** (2.0 KB, 43 lines)
   - Original requirements document
   - Priority areas defined
   - Expected reports format
   - Key question: iterative vs regeneration

## Key Differences from Generic Test Day

### Focus Areas

**Generic test day:**
- Basic workflow understanding
- Multi-stage concept learning
- Cross-platform migration
- Production customization

**Customized test day:**
- Real-world application validation
- Resource type coverage verification
- Cluster-scope resource handling
- Validation capabilities
- Plugin extensibility

### Applications

**Generic:** Simple demo apps (nginx, static web)  
**Customized:** Real-world apps (WordPress+MySQL, microservices, CI/CD pipelines)

### Testing Approach

**Generic:** Learn crane features  
**Customized:** Validate crane completeness and find gaps

### Success Criteria

**Generic:** Understanding workflows  
**Customized:** Answering specific questions:
- Which resource types fail?
- Stage-by-stage or full regen?
- Can cluster resources be migrated?
- Are validations sufficient?
- Can users create plugins?

## Timeline

| Time | Activity | Priority |
|------|----------|----------|
| 0:00 - 0:20 | Setup & Introduction | - |
| 0:20 - 1:20 | Scenario 1: Real-World Apps | P1 |
| 1:20 - 1:35 | Break | - |
| 1:35 - 2:35 | Scenario 2: Multi-stage | P2 |
| 2:35 - 2:50 | Break | - |
| 2:50 - 3:50 | Scenario 3: Cluster Resources | P3 |
| 3:50 - 4:05 | Break | - |
| 4:05 - 4:50 | Scenario 4: Validation | P4 |
| 4:50 - 5:00 | Break | - |
| 5:00 - 6:00 | Scenario 5: Custom Plugin | P5 |
| 6:00 - 6:30 | Reports & Discussion | - |

**Total:** ~6 hours

## Expected Outputs

### Bug Reports

**Blocking bugs:** Issues that prevent migration completion

**Workaround-able bugs:** Issues that can be resolved with manual steps

Examples:
- Resource type X not exported
- Patch for resource type Y incorrect
- Cluster resources not detected
- Validation misses issue Z

### Documentation Needs

- Missing docs for workflows tested
- Unclear existing documentation
- Needed examples
- Better error messages

### Key Questions Answered

1. **Stage iteration:** Does it make sense to work stage-by-stage or regenerate all?
2. **Resource coverage:** Which resource types need better handling?
3. **Cluster resources:** Should crane export cluster resources automatically?
4. **Validation:** What validations are missing or inadequate?
5. **Plugin creation:** Is the process accessible with AI assistance?

## How to Use These Materials

### For Test Day Organizers

1. Review README.md for objectives and setup
2. Ensure clusters meet prerequisites
3. Have participants work through scenarios in priority order
4. Collect reports using test-report-template.md
5. Focus on answering the key questions

### For Testers

1. Start with README.md
2. Keep quick-reference.md open for commands
3. Work through scenarios 1-5 sequentially
4. Document everything in test-report-template.md
5. Focus on finding gaps, not just learning

### For Documentation Teams

1. Use findings to improve crane docs
2. Add examples for real-world apps
3. Document cluster resource workflows
4. Improve error messages based on feedback
5. Create plugin development guide

## Success Metrics

By end of test day, we should know:

✅ **Priority 1:** KubernetesPlugin resource type coverage and gaps  
✅ **Priority 2:** Multi-stage workflow usability and iteration best practices  
✅ **Priority 3:** Cluster resource migration capabilities and limitations  
✅ **Priority 4:** Validation coverage and error message quality  
✅ **Priority 5:** Custom plugin creation feasibility and documentation needs

## File Organization

```
drafts/test-day-june2026-customized/
├── README.md                          # Main overview
├── SUMMARY.md                         # This file
├── quick-reference.md                 # Command cheat sheet
├── test-report-template.md           # Structured feedback form
├── test-day-notes.md                 # Original requirements
├── scenario-01-real-world-app.md     # Priority 1
├── scenario-02-multistage-kustomize.md  # Priority 2
├── scenario-03-cluster-resources.md  # Priority 3
├── scenario-04-validation.md         # Priority 4
└── scenario-05-custom-plugin.md      # Priority 5
```

## Prerequisites Verification

Before starting test day, verify:

### Clusters
- [ ] Source cluster accessible (OpenShift 4.x OR Kubernetes 1.30)
- [ ] Target cluster accessible (OpenShift 4.x OR Kubernetes 1.30)
- [ ] Cluster-admin access (for cluster resource scenarios)
- [ ] Namespace creation permissions

### Tools
- [ ] Crane binary (main branch, latest)
- [ ] kubectl/oc configured
- [ ] Git for versioning
- [ ] Go (for custom plugin scenario)

### Knowledge
- [ ] Basic Kubernetes concepts
- [ ] YAML syntax
- [ ] kubectl commands
- [ ] Basic Go (for plugin scenario)

## Related Documentation

- [Crane README](../../crane/README.md)
- [Multi-Stage Transform Guide](../../notes/transform-multistage.md)
- [Generic Test Day Materials](../test-day-june2026/)

## Contributing

Found issues with test day materials?
1. Test them in real scenario
2. Document problems
3. Submit PR with improvements
4. Or file issue with feedback

## Contact

For questions about these materials:
- GitHub: https://github.com/konveyor/crane/issues
- Konveyor: https://www.konveyor.io/

---

**These materials are specifically designed to answer real-world migration questions and validate crane's production readiness.**
