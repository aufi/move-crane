# Crane Test Day - June 2026

**Date:** June 1, 2026  
**Focus:** Stateless migration of Kubernetes resources using Crane tool

## Test Day Purpose

This test day focuses on validating Crane functionality for **stateless migration** of Kubernetes applications between clusters. We focus on transformation workflows without Persistent Volume data migration.

## What is Crane?

Crane is a migration tool from the Konveyor community that helps migrate Kubernetes workloads between clusters. It works on the principle of:

1. **Export** - Inspect running application and export all associated resources
2. **Transform** - Transform exported manifests using plugins
3. **Apply** - Apply transformed manifests to destination cluster
4. **Transfer** (optional) - Migrate persistent data

## Test Scenarios

### Scenario 1: Basic Stateless Application
- Simple application without stateful components
- Test basic export → transform → apply workflow
- [Detailed instructions](./scenario-01-basic-stateless.md)

### Scenario 2: Multi-stage Transformation
- Application requiring multiple transformation steps
- Test multi-stage pipeline with different plugins
- [Detailed instructions](./scenario-02-multistage.md)

### Scenario 3: Cross-platform Migration
- Migration from vanilla Kubernetes to OpenShift (or vice versa)
- Test platform-specific transformations
- [Detailed instructions](./scenario-03-cross-platform.md)

### Scenario 4: Customization for Target Environment
- Application requiring modifications for new environment
- Test manual edits and custom patches
- [Detailed instructions](./scenario-04-customization.md)

## Prerequisites

### Software
- `crane` binary (version from main branch, build from June 1, 2026)
- `kubectl` for working with Kubernetes API
- `kustomize` (embedded in crane, but standalone useful for debugging)
- Access to two Kubernetes clusters:
  - **Source cluster** - source cluster with running application
  - **Target cluster** - destination cluster for migration

### Knowledge
- Basic Kubernetes knowledge (Deployments, Services, ConfigMaps, Secrets)
- Basic Kustomize knowledge
- Working with kubectl

## Crane Installation

```bash
# Build from main branch
cd /home/maufart/go/src/github.com/konveyor/move-crane/crane
go build -o crane main.go

# Move to PATH
sudo cp crane /usr/local/bin/

# Verification
crane version
```

## Testing Structure

Each scenario contains:

1. **Scenario Description** - What we're testing and why
2. **Test Environment Setup** - Application setup on source cluster
3. **Migration Steps** - Detailed export → transform → apply procedure
4. **Validation** - How to verify successful migration
5. **Expected Results** - What should work
6. **Known Issues** - What might fail and why
7. **Reporting** - What and how to report

## Reporting Results

### What to Report

For each scenario please record:

1. **Environment**
   - Kubernetes version on source/target cluster
   - Crane binary version
   - OS and other relevant information

2. **Test Result**
   - ✅ Passed - works as expected
   - ⚠️ Passed with issues - works but with minor problems
   - ❌ Failed - doesn't work

3. **Details**
   - What worked well
   - What didn't work or had problems
   - Error messages, logs
   - Screenshots if relevant

4. **Improvement Suggestions**
   - What could be better
   - Missing features
   - UX/documentation problems

### Report Format

Use the template in [test-report-template.md](./test-report-template.md)

## Documentation and References

- [Multi-Stage Transform Guide](../../notes/transform-multistage.md)
- [Crane README](../../crane/README.md)
- [Crane Runner Examples](https://github.com/konveyor/crane-runner/tree/main/examples)

## Contacts and Support

- GitHub Issues: https://github.com/konveyor/crane/issues
- Konveyor Community: https://www.konveyor.io/

## Timeline

- **Setup (30 min)**: Crane installation, cluster preparation
- **Scenario 1 (45 min)**: Basic stateless application
- **Scenario 2 (60 min)**: Multi-stage transformation
- **Scenario 3 (60 min)**: Cross-platform migration
- **Scenario 4 (45 min)**: Customization
- **Wrap-up (30 min)**: Discussion, reporting

**Total: ~4.5 hours**

## Tips & Tricks

1. **Debugging**: Use `--debug` flag for more information
   ```bash
   crane export --debug
   ```

2. **Inspect intermediate results**: Check `.work/` directory during multi-stage transforms
   ```bash
   ls -la transform/.work/10_KubernetesPlugin/output/
   ```

3. **Dry-run before apply**: Always test before applying to target cluster
   ```bash
   kubectl apply --dry-run=client -f output/output.yaml
   ```

4. **Git for versioning**: Commit export and transform results
   ```bash
   git add export/ transform/ output/
   git commit -m "Migration checkpoint: after transform"
   ```

5. **Kustomize preview**: Check what kustomize produces
   ```bash
   kubectl kustomize transform/10_KubernetesPlugin/
   ```

## Expected Outputs

At the end of test day we should have:

- ✅ Validated 4 migration scenarios
- ✅ Documented issues and improvement suggestions
- ✅ Test reports for each scenario
- ✅ Feedback on documentation and UX
- ✅ List of feature requests / bug reports

---

Good luck with testing! 🚀
