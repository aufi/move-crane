# Summary: Multi-Stage Transform Workflow with Kustomize - Specification and Implementation Plan

## Context

This documentation summarizes proposed changes to `crane transform` and `crane apply` tools toward a **Kustomize-only workflow** with support for **multi-stage pipeline** for Kubernetes manifest migration.

Source documents from `../transform-kustomize-poc`:
1. `crane-transform-apply-kustomize-implementation-plan.md` - main implementation plan
2. `crane-kustomize-ondisk-layout-rfc-draft.md` - filesystem layout specification
3. `crane-transform-apply-stepwise-plugin-pipeline-draft.md` - multi-stage pipeline proposal
4. `crane-stepwise-pipeline-cli-spec-draft.md` - CLI specification for stage-aware workflow
5. `crane-transform-plugin-execution-improvements-draft.md` - plugin execution improvements
6. `crane-kustomize-migration-task-breakdown.md` - implementation task breakdown

---

## 1. Primary Objectives

### 1.1 Migration to Kustomize-Only Workflow
- **Remove** per-resource `transform-*` JSONPatch files
- **Replace** with Kustomize overlay containing `kustomization.yaml` and patch files
- `crane apply` will render outputs exclusively via `kubectl kustomize`
- Existing plugins remain compatible (still return JSONPatch operations)

### 1.2 Introduction of Multi-Stage Pipeline
- Each plugin (including default Kubernetes plugin) has its own **stage**
- Each stage has isolated artifacts (overlay, patches, reports, resources)
- Stages are ordered by priority and can be executed selectively
- Output of each stage becomes input for the next stage (chaining)

---

## 2. On-Disk Output Structure

### 2.1 Kustomize-Only (Single-Level)

```
<TRANSFORM_DIR>/
  .crane-metadata.json
  kustomization.yaml
  resources/
    deployment.yaml
    service.yaml
    configmap.yaml
  patches/
    <namespace>--<group>-<version>--<kind>--<name>.patch.yaml
    ...
  reports/
    ignored-patches.json       # optional
  whiteouts/
    whiteouts.json             # optional
```

**Key Points:**
- `kustomization.yaml` contains `resources` (references to resource type files) and `patches` (with explicit `target` metadata)
- Resources organized by type in `resources/` directory (multi-doc YAML)
- Patch files are JSON6902 operations serialized as YAML
- Whiteouted resources excluded from their resource type files
- Deterministic patch file naming for stable Git diffs

### 2.2 Multi-Stage Pipeline

```
<TRANSFORM_DIR>/
  10_kubernetes/
    .crane-metadata.json
    kustomization.yaml
    resources/
      deployment.yaml
      service.yaml
      configmap.yaml
    patches/
    reports/
    whiteouts/
  20_openshift/
    .crane-metadata.json
    kustomization.yaml
    resources/
      deployment.yaml
      service.yaml
      route.openshift.io.yaml
    patches/
    reports/
    whiteouts/
  30_imagestream/
    ...
```

**Key Points:**
- Convention over configuration: automatic stage discovery
- Each stage directory: `<priority>_<pluginName>` (no comments/colons)
- Stage N uses `resources/` from stage N-1 as input
- First stage uses `--export-dir` as input
- No rendered.yaml - stages consume/produce `resources/` directories directly

---

## 3. `kustomization.yaml` Specification

### Structure

```yaml
resources:
  - resources/deployment.yaml
  - resources/service.yaml
  - resources/configmap.yaml

patches:
  - path: patches/ns1--apps-v1--Deployment--myapp.patch.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: myapp
      namespace: ns1
```

### Patch File (Example)

```yaml
- op: remove
  path: /spec/clusterIP
- op: replace
  path: /spec/type
  value: NodePort
```

### Target Derivation
- `group` from `apiVersion` (empty for core group)
- `version` from `apiVersion`
- `kind` from object kind
- `name` from metadata.name
- `namespace` from metadata.namespace (if present)

---

## 4. CLI Changes

### 4.1 `crane transform`

#### New Flags for Stage-Aware Workflow

```bash
--list-stages                      # print discovered stages and exit
--stage <stage-dir>                # transform only one stage
--from-stage <stage-dir>           # transform from stage to end
--to-stage <stage-dir>             # transform from start to stage
--stages <dir1,dir2,...>           # transform only selected stages
--plugin-config <path>             # YAML config with plugin priorities
--force                            # overwrite modified stage directories
```

#### Plugin Execution Improvements

```bash
--plugins <name1,name2,...>        # allowlist - only these plugins
--plugin-order <name1,name2,...>   # execution order (not just conflict priority)
--report-file <path>               # machine-readable report per resource
--strict-plugin-errors             # fail immediately on any plugin error
--strict-conflicts                 # fail if any ignored patches are produced
```

### 4.2 `crane apply`

#### New Behavior
- Requires `<TRANSFORM_DIR>/kustomization.yaml` (single-stage)
- Discovers stages from directory structure (multi-stage)
- Executes `kubectl kustomize` sequentially for each stage
- Supports same stage selectors as `crane transform`

#### Output Behavior
- Default: STDOUT (rendered manifests)
- With `--output-dir`: writes `<output-dir>/all.yaml`

#### Preflight Validation
- Check for `kubectl` existence
- Check for `kustomization.yaml` existence
- Improved error messages on non-zero exit from kubectl

---

## 5. Stage Discovery and Configuration

### Convention Over Configuration

Stages are **automatically discovered** from transform directory:

1. Scan `<TRANSFORM_DIR>` for subdirectories matching: `<number>_<pluginName>`
2. Sort by numeric prefix (ascending)
3. Build execution chain automatically

### Plugin Priority Auto-Assignment

When no config provided:
1. KubernetesPlugin → priority 10
2. Other plugins sorted alphabetically
3. Assign priorities starting at 20, incrementing by 10
4. Gaps of 10 allow custom stages (e.g., `15_custom-tweaks`)

### Idempotency

**No resume logic** - transform is idempotent:
- Clean stage directories → regenerate
- Dirty stage directories → fail (require `--force`)
- Delete transform directory and re-run for clean start

---

## 6. Report Formats

### 6.1 Whiteouts (`whiteouts/whiteouts.json`)

```json
[
  {
    "apiVersion": "route.openshift.io/v1",
    "kind": "Route",
    "name": "frontend",
    "namespace": "ns1",
    "requestedBy": ["OpenShiftPlugin"]
  }
]
```

### 6.2 Ignored Patches (`reports/ignored-patches.json`)

```json
[
  {
    "resource": {
      "apiVersion": "apps/v1",
      "kind": "Deployment",
      "name": "myapp",
      "namespace": "ns1"
    },
    "path": "/spec/template/spec/containers/0/image",
    "selectedPlugin": "OpenShiftPlugin",
    "ignoredPlugin": "ImageStreamPlugin",
    "reason": "path-conflict-priority"
  }
]
```

---

## 7. Implementation Breakdown

### Epic A — `crane-lib`: Kustomize Foundations
- **A1**: Introduce `TransformArtifact` and `PatchTarget` types in runner
- **A2**: Add package for Kustomize serialization (op list → YAML patches)
- **A3**: Add resource type grouping logic
- **A4**: Define report structs (whiteouts, ignored patches)

### Epic B — `crane`: Transform Command Refactor
- **B1**: Replace per-resource file writer → generate `kustomization.yaml` + patches
- **B2**: Implement resource grouping by type into multi-doc YAML files
- **B3**: Build `resources` and `patches` lists with deterministic ordering
- **B4**: Implement stage directory dirty check with metadata file
- **B5**: Update path helpers for new layout

### Epic C — `crane`: Apply Command Refactor
- **C1**: Remove in-process JSONPatch application → delegate to `kubectl kustomize`
- **C2**: Implement output behavior (stdout / file)
- **C3**: Preflight validation (kubectl availability, kustomization.yaml existence)

### Epic D — Compatibility & Parity
- **D1**: Verify compatibility of existing plugins
- **D2**: Edge-case parity tests (remove-on-missing, array ops, conflicts, whiteout)

### Epic E — Documentation & Rollout
- **E1**: Update user-facing documentation
- **E2**: Publish plugin-author migration notes

### Epic F — Stage-Aware Pipeline (Optional)
- **F1**: Stage discovery mechanism (scan directories matching pattern)
- **F2**: Per-stage transform execution
- **F3**: Stage-aware apply with window flags
- **F4**: Plugin priority auto-assignment algorithm

---

## 8. Milestones

### M1 — Foundations (crane-lib)
- Structured transform artifacts
- Kustomize serialization
- Report models

### M2 — Transform End-to-End
- Kustomize output instead of JSONPatch files
- Resource grouping by type
- Deterministic naming and ordering

### M3 — Apply End-to-End
- kubectl kustomize as the only render mechanism
- Output handling

### M4 — Hardening + Docs
- Plugin compatibility suite
- Edge-case regression tests
- Documentation

### M5 — Stage-Aware Pipeline (Optional)
- Multi-stage directory layout with convention-based discovery
- Stage selectors in CLI
- Stage execution orchestration

---

## 9. Benefits

### Kustomize-Only Workflow
✅ Standard tooling (kubectl, kustomize)
✅ More readable Git diffs
✅ Easier change inspection (patch files vs JSONPatch per-resource)
✅ Compatibility with existing Kustomize workflows
✅ No required changes to plugins

### Multi-Stage Pipeline
✅ Strong traceability of changes per plugin
✅ Easier debugging (inspect per-stage artifacts)
✅ Selective execution (only certain stages)
✅ Better CI/CD integration (stage-by-stage validation)
✅ Clear separation of concerns (platform vs app migration)
✅ Convention over configuration - automatic stage discovery

---

## 10. Risks and Mitigations

### Kustomize Render Differences
**Risk:** Kustomize may render differently than old in-process JSONPatch applier
**Mitigation:** Fixture-based parity tests before merge

### Plugin Compatibility
**Risk:** Edge cases in JSONPatch operations (remove-on-missing, array indices)
**Mitigation:** Explicit documentation of behavior differences + regression tests

### kubectl Dependency
**Risk:** Hard dependency on kubectl at runtime
**Mitigation:** Preflight check + clear operator documentation

### Stage State Drift
**Risk:** Inconsistencies between stage outputs on reruns
**Mitigation:** Dirty check with SHA256 hashing

### Performance Overhead
**Risk:** Multiple kubectl kustomize renders slow down workflow
**Mitigation:** `--stage` flags for selective execution

---

## 11. Compatibility and Backward Compatibility

### Existing Plugins
- ✅ No required changes to plugin contract in phase 1
- ✅ Plugins continue to return JSONPatch operations
- ✅ Crane converts ops → Kustomize patch files

### Legacy Workflow
- ❌ `transform-*` JSONPatch files are removed
- ❌ In-process JSONPatch application in `crane apply` is removed
- ⚠️ Migration note: users must transition to new output layout

### CLI Flags
- ✅ Existing flags (`--skip-plugins`, `--plugin-priorities`, `--optional-flags`) remain
- ➕ New flags are additive (backward compatible when unused)

---

## 12. Validation Rules

### `crane transform` MUST fail when:
- Target identity cannot be derived (missing apiVersion/kind/name)
- Patch serialization fails
- kustomization.yaml cannot be written
- (strict mode) Plugin error or conflict occurs
- Stage directory is dirty (without `--force`)

### `crane apply` MUST fail when:
- `kubectl` is missing
- `kustomization.yaml` is missing
- `kubectl kustomize` exits with non-zero
- (stage-aware) `resources/` directory from previous stage is missing or empty

---

## 13. Determinism Requirements

For stable Git diffs, output must be deterministic:
- ✅ Stable sort for `resources` list (lexically by filename)
- ✅ Preserve creation order for resources within each type file
- ✅ Stable sort for `patches` (lexically by filename)
- ✅ Stable sort for report entries
- ✅ Deterministic patch file naming
- ✅ Deterministic resource type file naming (kind + group, no version)
- ✅ Deterministic stage naming

---

## 14. Design Decisions

All open questions have been resolved:

1. **Resource Type File Ordering**: Preserve creation order
2. **Patch Grouping**: One patch file per resource within stage directory
3. **Report Schema**: JSON format with documented structure (formal schema TBD)
4. **kubectl Passthrough**: Support via `--kustomize-flags`
5. **Stage Naming Collision**: Priority numbers MUST be unique
6. **Core Group Handling**: Follow existing crane behavior (empty or "core")
7. **Strict Mode Granularity**: Aggregate mode
8. **Stage Discovery Pattern**: Enforce exact `<num>_<plugin>` pattern
9. **Empty Resource Types**: Omit empty files
10. **Version in Filename**: Do NOT include version

---

## 15. Error Handling

**Principle**: Idempotent re-execution on failure

- No partial state recovery
- All errors require full re-run from clean state
- Clear error messages identifying failing stage and resource
- Strict modes available for fail-fast behavior

---

## 16. Stage Validation

**Minimal validation between stages**:
- ✅ Check `resources/` directory exists
- ✅ Check `resources/` directory not empty
- ❌ No semantic validation of content
- Rest handled by kubectl kustomize

---

## 17. Patch Target Resolution

**Stage independence**:
- Each stage operates independently
- No cross-stage patch target validation
- If previous stage whiteouted resource, next stage cannot patch it
- Validation happens at `kubectl kustomize` time
- User responsible for correct stage order and plugin logic

---

## 18. Acceptance Criteria

### Kustomize-Only
- [ ] `crane transform` always generates valid Kustomize overlay
- [ ] `crane apply` renders only via `kubectl kustomize`
- [ ] Existing plugins work without changes
- [ ] Whiteout behavior remains equivalent
- [ ] Deterministic output for stable diffs
- [ ] CI includes compatibility + edge-case regression suites
- [ ] Documentation is updated

### Stage-Aware Pipeline (Optional)
- [ ] Each plugin has its own stage subdirectory
- [ ] Stage directory names are `<priority>_<plugin>`
- [ ] Both transform and apply support stage selectors
- [ ] Stage outputs are chainable and reproducible
- [ ] Stage discovery is automatic
- [ ] Idempotent behavior
- [ ] Dirty check prevents accidental overwrite

---

## 19. Recommended Issue Mapping

1. **crane-lib**: Add TransformArtifact + PatchTarget structs
2. **crane-lib**: Add kustomize serializer package
3. **crane-lib**: Add resource type grouping logic
4. **crane-lib**: Add whiteout/ignored-patches report structs
5. **crane**: Refactor transform to emit kustomization.yaml + patches
6. **crane**: Implement resource type file generation (multi-doc YAML)
7. **crane**: Add deterministic ordering for overlay artifacts
8. **crane**: Implement dirty check with SHA256 hashing
9. **crane**: Add error handling with idempotent re-run semantics
10. **crane**: Add stage input validation
11. **crane**: Refactor apply to kubectl kustomize only
12. **crane**: Add apply preflight checks and output behavior
13. **crane+crane-lib**: Add plugin compatibility fixture suite
14. **docs**: Update usage docs and migration notes
15. **crane**: Add stage discovery mechanism (optional)
16. **crane**: Add stage-aware CLI flags (optional)
17. **crane**: Add stage execution orchestration (optional)
18. **crane**: Add plugin priority auto-assignment (optional)

---

## 20. Usage Examples

### Basic Kustomize Workflow

```bash
# Transform
crane transform \
  --export-dir export \
  --transform-dir transform

# Apply
crane apply \
  --transform-dir transform \
  --output-dir output
```

### Stage-Aware Workflow

```bash
# List stages
crane transform --list-stages

# Transform full pipeline
crane transform \
  --export-dir export \
  --transform-dir transform \
  --plugin-config plugin-config.yaml

# Transform only one stage
crane transform --stage 20_openshift

# Transform window
crane transform \
  --from-stage 20_openshift \
  --to-stage 30_imagestream

# Apply selected stages
crane apply \
  --transform-dir transform \
  --stages 20_openshift,30_imagestream \
  --output-dir output

# Force overwrite modified stages
crane transform --force
```

### Plugin Control

```bash
crane transform \
  --plugins KubernetesPlugin,OpenShiftPlugin \
  --plugin-order OpenShiftPlugin,KubernetesPlugin \
  --plugin-priorities OpenShiftPlugin,KubernetesPlugin \
  --report-file transform-report.json \
  --strict-conflicts
```

---

## 21. Reference Code Touchpoints

### crane
- `cmd/transform/transform.go` - transform command orchestration
- `cmd/apply/apply.go` - apply command orchestration
- `internal/file/file_helper.go` - path helpers
- `internal/plugin/plugin_helper.go` - plugin discovery/filtering

### crane-lib
- `transform/runner.go` - plugin execution + patch merge
- `transform/kustomize/*` (new) - serialization helpers
- `transform/plugin.go` - plugin request/response model
- `apply/applier.go` - (to be removed from CLI usage)

---

## Conclusion

This specification defines a comprehensive transformation of the crane workflow toward:

1. **Standardization** on Kustomize as the only mechanism for patch application
2. **Improved observability** through structured reports and stage isolation
3. **Flexibility** in the form of selective stage execution and plugin control
4. **Determinism** for stable Git-friendly outputs
5. **Backward compatibility** for existing plugins (no rewrite required)

The implementation is designed incrementally with clear milestones and acceptance criteria.

**Timeline**: 11-14 weeks for full implementation (core + optional multi-stage)
