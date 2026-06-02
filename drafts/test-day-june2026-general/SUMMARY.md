# Crane Test Day June 2026 - Summary

This directory contains complete materials for conducting a Crane test day focused on stateless Kubernetes resource migration.

## Directory Contents

### Main Documents

1. **[README.md](./README.md)** - Main test day overview
   - Purpose and objectives
   - Scenario overview
   - Prerequisites and setup
   - Timeline and structure
   - Reporting guidelines

2. **[quick-reference.md](./quick-reference.md)** - Quick reference guide
   - Common commands
   - Directory structures
   - Kustomize patterns
   - Debugging techniques
   - Troubleshooting guide
   - Best practices

3. **[test-report-template.md](./test-report-template.md)** - Report template
   - Structured feedback form
   - Per-scenario results
   - Issue tracking
   - Overall feedback sections

### Test Scenarios

4. **[scenario-01-basic-stateless.md](./scenario-01-basic-stateless.md)**
   - **Duration:** ~25 minutes
   - **Focus:** Basic export → transform → apply workflow
   - **Application:** Simple Nginx web server
   - **Concepts:** Resource export, KubernetesPlugin, basic transformation

5. **[scenario-02-multistage.md](./scenario-02-multistage.md)**
   - **Duration:** ~70 minutes
   - **Focus:** Multi-stage transformation pipelines
   - **Application:** Multi-tier web application
   - **Concepts:** Sequential stages, plugin vs custom stages, .work directory, stage selection

6. **[scenario-03-cross-platform.md](./scenario-03-cross-platform.md)**
   - **Duration:** ~80 minutes
   - **Focus:** Cross-platform migration (Kubernetes ↔ OpenShift)
   - **Application:** Platform-aware web application
   - **Concepts:** Route/Ingress conversion, security contexts, platform-specific resources

7. **[scenario-04-customization.md](./scenario-04-customization.md)**
   - **Duration:** ~90 minutes
   - **Focus:** Environment-specific customization
   - **Application:** Production-ready multi-component application
   - **Concepts:** Kustomize overlays, resource scaling, registry changes, security hardening

## How to Use These Materials

### For Test Day Organizers

1. **Preparation:**
   - Review all scenario documents
   - Ensure access to source and target clusters
   - Build latest Crane binary
   - Prepare environment (kubectl, access credentials)

2. **During Test Day:**
   - Start with README.md overview presentation
   - Distribute quick-reference.md as cheat sheet
   - Guide participants through scenarios in order
   - Encourage documentation of issues

3. **After Test Day:**
   - Collect completed test-report-template.md from participants
   - Aggregate feedback
   - Create GitHub issues for bugs/features
   - Update documentation based on feedback

### For Individual Testers

1. **Start Here:** [README.md](./README.md)
2. **Keep Open:** [quick-reference.md](./quick-reference.md)
3. **Work Through:** Scenarios 1-4 in order
4. **Report Results:** Fill out [test-report-template.md](./test-report-template.md)

## Scenario Progression

The scenarios are designed to build on each other:

```
Scenario 1: Basic Stateless
    ↓
    Learn: Export, Transform, Apply basics
    ↓
Scenario 2: Multi-stage
    ↓
    Learn: Pipeline stages, sequential consistency
    ↓
Scenario 3: Cross-platform
    ↓
    Learn: Platform-specific handling
    ↓
Scenario 4: Customization
    ↓
    Learn: Production-ready transformations
```

## Key Learning Objectives

By completing all scenarios, participants will understand:

### Core Concepts
- ✅ Crane's three-phase workflow (export, transform, apply)
- ✅ Plugin vs custom transformation stages
- ✅ Sequential stage consistency
- ✅ Kustomize integration

### Practical Skills
- ✅ Exporting resources from running clusters
- ✅ Creating and managing transformation stages
- ✅ Using KubernetesPlugin for metadata cleanup
- ✅ Writing JSONPatch and strategic merge patches
- ✅ Customizing applications for different environments
- ✅ Debugging transformation pipelines
- ✅ Validating and deploying migrated applications

### Advanced Topics
- ✅ Multi-stage pipelines
- ✅ Cross-platform migrations
- ✅ Security context handling
- ✅ Image registry redirection
- ✅ Resource scaling
- ✅ Environment-specific configuration

## Time Requirements

| Activity | Duration |
|----------|----------|
| Setup | 30 min |
| Scenario 1 | 25 min |
| Scenario 2 | 70 min |
| Scenario 3 | 80 min |
| Scenario 4 | 90 min |
| Wrap-up | 30 min |
| **Total** | **~5.5 hours** |

**Note:** Times are estimates. Actual duration may vary based on:
- Cluster performance
- Network speed
- Participant experience level
- Discussion and Q&A time

## Prerequisites Checklist

### Required Software
- [ ] `crane` binary (built from main branch)
- [ ] `kubectl` (compatible version)
- [ ] Access to source Kubernetes cluster
- [ ] Access to target Kubernetes cluster
- [ ] Git (for version control)
- [ ] Text editor (VS Code, vim, nano, etc.)

### Optional but Useful
- [ ] `kustomize` standalone binary
- [ ] `jq` for JSON processing
- [ ] `yq` for YAML processing
- [ ] `tree` for directory visualization
- [ ] `diff` tools (meld, vimdiff, etc.)

### Knowledge Prerequisites
- [ ] Basic Kubernetes concepts
- [ ] kubectl commands
- [ ] YAML syntax
- [ ] Basic shell scripting

### Cluster Requirements
- [ ] Namespace creation permissions
- [ ] Resource deployment permissions
- [ ] Access to both source and target clusters
- [ ] Sufficient cluster resources for test applications

## Expected Outcomes

### By End of Test Day

**Participants will have:**
- ✅ Hands-on experience with Crane workflows
- ✅ Understanding of stateless migration patterns
- ✅ Knowledge of multi-stage transformations
- ✅ Completed test reports with feedback

**Project will gain:**
- ✅ Real-world testing feedback
- ✅ Identified bugs and edge cases
- ✅ UX/documentation improvement suggestions
- ✅ Feature requests prioritized by user needs
- ✅ Validation of core functionality

## Customization Options

These materials can be adapted for:

### Shorter Sessions (2-3 hours)
- Focus on Scenarios 1 and 2 only
- Skip cross-platform (Scenario 3)
- Simplify customization (Scenario 4)

### Specific Use Cases
- OpenShift-only: Focus on Scenario 3 with OpenshiftPlugin
- GitOps integration: Add GitOps deployment to Scenario 4
- CI/CD pipelines: Integrate Crane into automation workflow

### Different Experience Levels
- **Beginners:** More guidance, slower pace, Q&A time
- **Intermediate:** Standard scenarios, some exploration
- **Advanced:** Minimal guidance, encourage experimentation, edge case testing

## Support and Resources

### During Test Day
- Quick reference guide for command syntax
- Scenario documents for step-by-step guidance
- Organizers/mentors for troubleshooting

### Documentation
- [Crane README](../../crane/README.md)
- [Multi-Stage Transform Guide](../../notes/transform-multistage.md)
- [Crane Runner Examples](https://github.com/konveyor/crane-runner/tree/main/examples)

### Community
- GitHub Issues: https://github.com/konveyor/crane/issues
- Konveyor Community: https://www.konveyor.io/

## Post-Test Day Actions

1. **Aggregate Feedback:**
   - Compile all test reports
   - Identify common issues
   - Categorize feedback (bugs, features, docs, UX)

2. **Create GitHub Issues:**
   - File bugs with reproduction steps
   - Create feature requests with use cases
   - Tag documentation improvements

3. **Update Documentation:**
   - Fix identified documentation gaps
   - Add troubleshooting entries
   - Update examples based on feedback

4. **Iterate on Crane:**
   - Prioritize bug fixes
   - Evaluate feature requests
   - Improve UX based on feedback

5. **Share Results:**
   - Blog post about test day
   - Community meeting presentation
   - Thank participants

## Version History

- **2026-06-01:** Initial test day materials created
  - 4 comprehensive scenarios
  - Quick reference guide
  - Test report template
  - Focus on stateless migration

## License

These materials are part of the Crane project under the [Apache 2.0 License](../../LICENSE).

## Contributing

Found an issue or have suggestions for improving these test day materials?

1. Test them in a real scenario
2. Document your findings
3. Submit a PR with improvements
4. Or file an issue with feedback

## Contact

For questions about these test day materials:
- Create an issue in the Crane repository
- Reach out via Konveyor community channels

---

**Happy Testing!** 🚀
