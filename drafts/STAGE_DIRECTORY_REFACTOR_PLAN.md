# Stage Directory Refactoring Plan - Option 2

## Goal

Make the stage directory structure more intuitive for users by clarifying:
- What is the input to a stage (`input-resources/`)
- What is the output from a stage (`output/`)
- Eliminate the hidden `.work/` directory

## Current Structure

```
transform/
├── 10_KubernetesPlugin/
│   ├── resources/          # ❓ confusing - unclear that this is input
│   ├── patches/
│   └── kustomization.yaml  # references: resources/
└── .work/                  # ❌ hidden, users don't go here
    └── 10_KubernetesPlugin/
        ├── input/          # materialized input (from previous stage)
        └── output/         # materialized output (after kustomize build)
```

## New Structure

```
transform/
└── 10_KubernetesPlugin/
    ├── input-resources/    # ✅ clear - input resources for stage
    ├── patches/            # patches applied to input-resources
    # ├── new-resources/    # (future) resources created by plugin (not in input)
    ├── output/             # ✅ clear - stage output (materialized)
    └── kustomization.yaml  # references: input-resources/ (and new-resources/ in future)
```

**Note on directory naming:** The names `input-resources/` and `new-resources/` (future) are chosen for maximum clarity. However, if user feedback indicates preference for shorter names, these can be changed to `input/` and `new/` respectively. The implementation should make this renaming trivial (constants or helper methods).

## Code Changes

### 1. `internal/file/file_helper.go`

#### Directory name constants:

```go
// Consider adding constants for easy renaming if requested by users:
const (
    InputResourcesDirName = "input-resources"  // could be changed to "input" if preferred
    NewResourcesDirName   = "new-resources"    // (future) could be changed to "new" if preferred
    PatchesDirName        = "patches"
    OutputDirName         = "output"
)
```

#### Modify methods:

```go
// GetResourcesDir - RENAME to GetInputResourcesDir
func (opts *PathOpts) GetInputResourcesDir(stageName string) string {
    return filepath.Join(opts.GetStageDir(stageName), InputResourcesDirName)
}

// GetResourceTypeFilePath - UPDATE to use input-resources
func (opts *PathOpts) GetResourceTypeFilePath(stageName, filename string) string {
    return filepath.Join(opts.GetInputResourcesDir(stageName), filename)
}

// GetStageOutputDir - CHANGE path from .work/<stage>/output to <stage>/output
func (opts *PathOpts) GetStageOutputDir(stageName string) string {
    return filepath.Join(opts.GetStageDir(stageName), "output")
}

// GetStageInputDir - REMOVE (not needed, input-resources/ serves this purpose)
// OR keep as alias to GetInputResourcesDir for backward compatibility in tests
```

#### Remove unused directory methods:

```go
// GetWhiteoutsDir - REMOVE (not used, whiteouts tracked in kustomization.yaml comments)
// GetReportsDir - REMOVE (not used)
// GetWhiteoutReportPath - REMOVE (not used)
// GetIgnoredPatchReportPath - REMOVE (not used)
```

#### Deprecated methods to remove:

```go
// GetStageWorkDir - REMOVE (no longer using .work/)
// func (opts *PathOpts) GetStageWorkDir(stageName string) string - DEPRECATED

// GetStageInputDir - can remain as alias, or remove
```

### 2. `internal/transform/writer.go`

#### In `WriteStage()` method:

```go
// Change:
resourcesDir := w.opts.GetResourcesDir(w.stageName)

// To:
resourcesDir := w.opts.GetInputResourcesDir(w.stageName)
```

#### In kustomization.yaml generation:

```go
// Change reference from "resources/" to "input-resources/"
resourcePaths = append(resourcePaths, filepath.Join("input-resources", filename))

// And in whiteout comments:
whiteoutComments = append(whiteoutComments, fmt.Sprintf("# - input-resources/%s", filename))
```

### 3. `internal/transform/orchestrator.go`

#### In `RunMultiStage()` method:

**Step 3: Save input snapshot - REMOVE**
```go
// REMOVE this - input-resources/ will serve as the input
// Step 3: Save input to working directory for debugging
stageInputDir := opts.GetStageInputDir(stage.DirName)
if err := o.writeResourcesToDirectory(inputResources, stageInputDir); err != nil {
    return fmt.Errorf("stage %s: failed to write input snapshot: %w", stage.DirName, err)
}
```

**Reason:** Writer already writes resources to `input-resources/`, so we avoid duplication.

**Step 6: Update output path**
```go
// Step 6: Write output to working directory (becomes input for next stage)
stageOutputDir := opts.GetStageOutputDir(stage.DirName)
// Will now point to transform/<stage>/output/ instead of .work/<stage>/output/
if err := o.writeResourcesToDirectory(outputResources, stageOutputDir); err != nil {
    return fmt.Errorf("stage %s: failed to write output: %w", stage.DirName, err)
}
```

### 4. Tests

#### Files to modify:

- `internal/transform/orchestrator_test.go`
- `internal/transform/orchestrator_output_test.go`
- `internal/transform/writer_test.go`
- `internal/transform/writer_integration_test.go`
- `internal/file/file_helper_test.go`

#### Changes:
- Update expected paths from `resources/` to `input-resources/`
- Update expected paths from `.work/<stage>/output` to `<stage>/output`
- Remove tests relying on `.work/<stage>/input`

### 5. Documentation

#### Files to modify:

- `docs/transform-multistage.md` - main documentation
- `docs/transform.md` - basic documentation
- `docs/transform-config.md` - if it contains examples
- `docs/transform-scenarios/` - all examples
- `README.md` - if it contains examples

#### Changes:
- Update all directory structure examples
- Explain new meaning of `input-resources/` vs `output/`
- Remove mentions of `.work/` directory
- Update debugging guides

### 6. `.gitignore`

```gitignore
# REMOVE or update:
# transform/.work/

# Maybe ADD (if we want to ignore output/):
# transform/*/output/
```

**Decision:** Probably DO NOT ignore `output/`, as it's useful for debugging and committing.

## Implementation Steps

1. ✅ **Prepare plan** (this document)

2. **Update `internal/file/file_helper.go`**
   - Rename `GetResourcesDir()` to `GetInputResourcesDir()`
   - Change `GetStageOutputDir()` path
   - Remove or mark deprecated `GetStageWorkDir()`
   - Remove or alias `GetStageInputDir()`

3. **Update `internal/transform/writer.go`**
   - Use `GetInputResourcesDir()` instead of `GetResourcesDir()`
   - Change paths in `kustomization.yaml` to `input-resources/`

4. **Update `internal/transform/orchestrator.go`**
   - Remove input snapshot write (Step 3)
   - Verify output paths work correctly

5. **Update all tests**
   - `internal/transform/*_test.go`
   - `internal/file/*_test.go`
   - Run `go test ./internal/...`

6. **Update documentation**
   - `docs/transform-multistage.md`
   - `docs/transform.md`
   - Other files in `docs/`

7. **Manual testing**
   ```bash
   crane export
   crane transform
   # Check structure:
   tree transform/
   ```

8. **Update `.gitignore` (if needed)**

9. **Commit and PR**

## Backwards Compatibility

### Breaking Changes:

1. **Existing stage directories**
   - Old stages with `resources/` will not work
   - Migration or documentation needed

2. **Kustomization.yaml**
   - Existing `kustomization.yaml` files reference `resources/`
   - Will be regenerated after re-running `crane transform --force`

### Migration for users:

**Option 1: Force regeneration**
```bash
crane transform --force
# Regenerates all stages with new structure
```

**Option 2: Manual migration**
```bash
cd transform/10_KubernetesPlugin/
mv resources input-resources
sed -i 's/resources\//input-resources\//g' kustomization.yaml
```

**Option 3: Automatic migration**
- Add migration logic to orchestrator.go
- Automatically rename old `resources/` when detected
- Log warning

## Benefits of New Structure

1. ✅ **Clear input**: `input-resources/` - users immediately know this is input
2. ✅ **Clear output**: `output/` - visible result of stage
3. ✅ **No hidden directories**: Everything in stage directory, nothing in `.work/`
4. ✅ **Better debugging**: `diff input-resources/ output/` shows what the stage changed
5. ✅ **Simpler mental model**: Everything in one place
6. ✅ **Future-proof**: Structure supports `new-resources/` for plugin-created resources (future implementation)

## Future Enhancement: new-resources/ Directory

**Related Issue:** [#415 - Support new resources in transform plugins](https://github.com/migtools/crane/issues/415)

**Note:** This refactoring prepares the structure for a future feature where plugins can create new resources (not just patch existing ones).

### Planned Usage:

```
transform/
└── 20_OpenshiftPlugin/
    ├── input-resources/    # resources from previous stage (or export)
    ├── patches/            # modifications to input-resources
    ├── new-resources/      # (future) resources created from scratch by plugin
    │   └── Route_route.openshift.io_v1_default_myapp.yaml
    ├── output/             # combined result: input-resources + patches + new-resources
    └── kustomization.yaml  # references both input-resources/ and new-resources/
```

### Example Use Cases:

1. **OpenshiftPlugin** creating Routes for Services
2. **SecurityPlugin** creating NetworkPolicies or PodSecurityPolicies
3. **ObservabilityPlugin** creating ServiceMonitors or PrometheusRules
4. **Custom stages** adding ConfigMaps, Secrets, or other resources

### Implementation Notes (for future):

- `new-resources/` would be listed separately in `kustomization.yaml` resources
- Plugins would indicate new resources via a flag in `TransformArtifact`
- Writer would separate new resources from patched resources
- Output would include both transformed input-resources and new-resources

This refactoring does NOT implement `new-resources/` - it only ensures the directory structure can accommodate it later without another breaking change.

## Risks and Mitigation

### Risk 1: Breaking change for existing projects
**Mitigation:**
- Document migration procedure
- Automatic detection and migration (optional)
- Clear release notes

### Risk 2: Kustomize expects resources/
**Mitigation:**
- Kustomize supports arbitrary paths in `kustomization.yaml`
- `input-resources/` is a valid name
- Test with embedded kustomize

### Risk 3: Tests will break
**Mitigation:**
- Systematically update all tests
- Run full test suite before merge

## Open Questions

1. **Keep `GetStageInputDir()` as deprecated alias?**
   - Pro: Backward compatibility in tests
   - Con: Adds confusion
   - **Decision:** REMOVE, not needed

2. **What about `.work/` directory in .gitignore?**
   - **Decision:** Remove from .gitignore, directory will no longer be used

3. **Auto-migrate or just document?**
   - **Decision:** Document first, auto-migration later (if needed)

4. **Commit output/ to git?**
   - **Decision:** YES - it's useful for code review and debugging
   - Exception: User can add to .gitignore if they don't want it

5. **Use `input-resources/` and `new-resources/` or shorter `input/` and `new/`?**
   - Pro (longer names): Maximum clarity, immediately obvious what they contain
   - Pro (shorter names): Less verbose, cleaner tree output
   - **Decision:** Start with `input-resources/` and `new-resources/` for clarity
   - Use constants to make future renaming trivial if user feedback prefers shorter names

## Example of New Structure After Transform

```
transform/
├── 10_KubernetesPlugin/
│   ├── input-resources/               # ← input (e.g., from export/)
│   │   ├── default/
│   │   │   └── Deployment_apps_v1_default_myapp.yaml
│   │   └── _cluster/
│   │       └── ClusterRole_rbac.authorization.k8s.io_v1_clusterscoped_myrole.yaml
│   ├── patches/                       # ← transformations
│   │   └── deployment_myapp_default.yaml
│   # ├── new-resources/               # (future) new resources created by plugin
│   #     └── ServiceAccount_v1_default_myapp-sa.yaml
│   ├── output/                        # ← output (materialized after kustomize)
│   │   ├── default/
│   │   │   └── Deployment_apps_v1_default_myapp.yaml  # (with patches applied)
│   │   └── _cluster/
│   │       └── ClusterRole_rbac.authorization.k8s.io_v1_clusterscoped_myrole.yaml
│   └── kustomization.yaml
│
└── 20_OpenshiftPlugin/
    ├── input-resources/               # ← input (= output from previous stage!)
    │   ├── default/
    │   │   └── Deployment_apps_v1_default_myapp.yaml  # (already has patches from stage 1)
    │   └── _cluster/
    │       └── ClusterRole_rbac.authorization.k8s.io_v1_clusterscoped_myrole.yaml
    ├── patches/
    │   └── deployment_myapp_default.yaml
    # ├── new-resources/               # (future) e.g., Route created by OpenshiftPlugin
    #     └── Route_route.openshift.io_v1_default_myapp.yaml
    ├── output/
    │   └── ...
    └── kustomization.yaml
```

## Timeline

- **Plan preparation**: ✅ Done
- **Code implementation**: ~2-3 hours
- **Test updates**: ~1-2 hours
- **Documentation updates**: ~1 hour
- **Testing**: ~1 hour
- **Review and merge**: ~varies

**Total effort**: ~6-8 hours of work

## Next Steps

1. Approve this plan
2. Create feature branch `refactor/stage-directory-structure`
3. Implement changes following steps above
4. Test
5. Create PR with clear description of breaking changes
