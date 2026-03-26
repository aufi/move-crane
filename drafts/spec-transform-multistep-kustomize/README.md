# Specification and Implementation Plan: Multi-Stage Transform Workflow with Kustomize

## Context

This documentation summarizes proposed changes to `crane transform` and `crane apply` tools, moving toward a **Kustomize-only workflow** with support for **multi-stage pipeline** for Kubernetes manifest migration.

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
- **Replace** with a single Kustomize overlay containing `kustomization.yaml` and patch files
- `crane apply` will render outputs exclusively via `kubectl kustomize`
- Existing plugins remain compatible (still return JSONPatch operations)

### 1.2 Introduction of Multi-Stage Pipeline
- Each plugin (including default Kubernetes plugin) has its own **stage**
- Each stage has isolated artifacts (overlay, patches, reports, rendered output)
- Stages are ordered by priority and can be executed selectively
- Output of each stage becomes input for the next stage (chaining)

---

## 2. On-Disk Output Structure

### 2.1 Kustomize-Only (Single-Level)

```
<TRANSFORM_DIR>/
  kustomization.yaml
  patches/
    <namespace>--<group>-<version>--<kind>--<name>.patch.yaml
    ...
  reports/
    ignored-patches.json       # optional
  whiteouts/
    whiteouts.json             # optional
```

**Key Points:**
- `kustomization.yaml` contains `resources` (references to export files) and `patches` (with explicit `target` metadata)
- Patch files are JSON6902 operations serialized as YAML
- Whiteouted resources are excluded from `resources` list
- Deterministic patch file naming for stable Git diffs

### 2.2 Multi-Stage Pipeline

```
<TRANSFORM_DIR>/
  10_kubernetes/
    kustomization.yaml
    patches/
    reports/
    whiteouts/
    rendered.yaml             # kubectl kustomize output for this stage
  20_openshift/
    kustomization.yaml
    patches/
    reports/
    whiteouts/
    rendered.yaml
  30_imagestream/
    kustomization.yaml
    patches/
    reports/
    whiteouts/
    rendered.yaml
  final/
    rendered.yaml               # final output from last stage
```

**Key Points:**
- Convention over configuration: stage directories are discovered by lexical ordering
- Each stage directory: `<priority>_<pluginName>` (no comments/colons in directory names)
- Stage execution order determined by numeric prefix (ascending)
- Stage N uses `rendered.yaml` from stage N-1 as input
- First stage (lowest numeric prefix) uses `--export-dir` as input
- No `stage discovery` - stage discovery is automatic based on directory structure

---

## 3. `kustomization.yaml` Specification

### Structure

```yaml
resources:
  - ../export/ns1/apps_v1_deployment_myapp.yaml
  - ../export/ns1/v1_service_myapp.yaml

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
--stage <stage-dir>                # transform only one stage (e.g., "10_kubernetes")
--from-stage <stage-dir>           # transform from stage to end
--to-stage <stage-dir>             # transform from start to stage
--stages <dir1,dir2,...>           # transform only selected stages
--plugin-config <path>             # YAML config with plugin priorities
--resume                           # continue from first incomplete stage
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
- For single-stage: Requires `<TRANSFORM_DIR>/kustomization.yaml`
- For multi-stage: Discovers stages from directory structure
- Executes: `kubectl kustomize <TRANSFORM_DIR>` (single) or `kubectl kustomize <TRANSFORM_DIR>/<stage-dir>` (multi)
- Supports same stage selectors as `crane transform`

#### Stage Selectors (Multi-Stage Mode)

```bash
--list-stages                      # print discovered stages and exit
--stage <stage-dir>                # apply only one stage
--from-stage <stage-dir>           # apply from stage to end
--to-stage <stage-dir>             # apply from start to stage
--stages <dir1,dir2,...>           # apply only selected stages
--resume                           # continue from first incomplete stage
```

#### Output Behavior
- Default: STDOUT (rendered manifests from final stage)
- With `--output-dir`: writes `<output-dir>/all.yaml`

#### Preflight Validation
- Check for `kubectl` existence
- Check for `kustomization.yaml` existence (or stage directories)
- Improved error messages on non-zero exit from kubectl

---

## 5. Stage Discovery and Configuration

### Convention Over Configuration

Stages are **automatically discovered** from the transform directory structure:

1. Scan `<TRANSFORM_DIR>` for subdirectories matching pattern: `<number>_<pluginName>`
2. Sort discovered stages by numeric prefix (ascending)
3. Build execution chain automatically

**Example directory structure:**
```
transform/
  10_kubernetes/     # executes first
  20_openshift/      # executes second
  30_imagestream/    # executes third
```

### Optional Plugin Configuration File

Optional `--plugin-config` file for setting plugin priorities:

```yaml
plugins:
  KubernetesPlugin:
    priority: 10
    enabled: true
  OpenShiftPlugin:
    priority: 20
    enabled: true
  ImageStreamPlugin:
    priority: 30
    enabled: false
```

**Priority determines:**
- Stage directory numeric prefix
- Execution order (lower numbers execute first)

**Note:** If no config file is provided, plugins execute in default discovery order with auto-assigned priorities.

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

### 6.3 Transform Decision Report (New, Proposed)

```json
{
  "resource": "apps/v1 Deployment ns/myapp",
  "pluginsRun": ["KubernetesPlugin", "OpenShiftPlugin"],
  "whiteout": {
    "applied": false,
    "by": null
  },
  "patchStats": {
    "generated": 6,
    "applied": 4,
    "ignored": 2
  },
  "ignoredPatches": [...]
}
```

---

## 7. Implementation Plan (Breakdown)

### Epic A — `crane-lib`: Kustomize Foundations
- **A1**: Introduce `TransformArtifact` and `PatchTarget` types in runner
- **A2**: Add package for Kustomize serialization (op list → YAML patches)
- **A3**: Define report structs (whiteouts, ignored patches)

### Epic B — `crane`: Transform Command Refactor
- **B1**: Replace per-resource file writer → generate `kustomization.yaml` + patches
- **B2**: Build `resources` and `patches` lists with deterministic ordering
- **B3**: Update path helpers for new layout

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

### Epic F — Stage-Aware Pipeline (Optional Extension)
- **F1**: Stage discovery mechanism (scan directories matching `<num>_<plugin>` pattern)
- **F2**: Per-stage transform execution
- **F3**: Stage-aware apply with window flags
- **F4**: Resume/restart behavior

---

## 8. Milestones

### M1 — Foundations (crane-lib)
- Structured transform artifacts
- Kustomize serialization
- Report models

### M2 — Transform End-to-End
- Kustomize output instead of JSONPatch files
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
**Mitigation:** Immutable artifacts + checksum tracking (future iteration)

### Performance Overhead
**Risk:** Multiple kubectl kustomize renders slow down workflow
**Mitigation:** `--stage`, `--resume` flags + future caching

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

### `crane apply` MUST fail when:
- `kubectl` is missing
- `kustomization.yaml` is missing
- `kubectl kustomize` exits with non-zero
- (stage-aware) Dependency output from previous stage is missing

---

## 13. Determinism Requirements

For stable Git diffs, output must be deterministic:
- ✅ Stable sort for `resources`
- ✅ Stable sort for `patches`
- ✅ Stable sort for report entries
- ✅ Deterministic patch file naming
- ✅ Deterministic stage naming (for pipeline workflow)

---

## 14. Open Questions

1. **Resources reference**: Use direct references to export files or copies/symlinks?
2. **Patch grouping**: One patch file per resource or multiple grouped by plugin?
3. **Report schema**: Formal schema for reports (JSON Schema/OpenAPI)?
4. **kubectl passthrough**: Support `--enable-helm` and other kubectl kustomize flags?
5. **Stage naming collision**: How to handle multiple plugins with same priority number?
6. **Core group handling**: Group field empty or "core" for core resources?
7. **Strict mode granularity**: Fail-fast per resource or aggregate at end?
8. **Stage discovery pattern**: Enforce exact `<num>_<plugin>` or allow variations?

---

## 15. Acceptance Criteria (Overall)

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
- [ ] Stage directory names are `<priority>_<plugin>` (no comments)
- [ ] Both transform and apply support stage selectors
- [ ] Stage outputs are chainable and reproducible
- [ ] Stage discovery is automatic based on directory structure
- [ ] Resume behavior works correctly

---

## 16. Recommended Issue Mapping

For implementation tracking:

1. **crane-lib**: Add TransformArtifact + PatchTarget structs
2. **crane-lib**: Add kustomize serializer package
3. **crane-lib**: Add whiteout/ignored-patches report structs
4. **crane**: Refactor transform to emit kustomization.yaml + patches
5. **crane**: Add deterministic ordering for overlay artifacts
6. **crane**: Refactor apply to kubectl kustomize only
7. **crane**: Add apply preflight checks and output behavior
8. **crane+crane-lib**: Add plugin compatibility fixture suite
9. **docs**: Update usage docs and migration notes
10. **crane**: Add stage discovery mechanism (directory scan) (optional)
11. **crane**: Add stage-aware CLI flags for transform/apply (optional)
12. **crane**: Add stage execution orchestration logic (optional)

---

## 17. Usage Examples

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
crane transform \
  --stage 20_openshift

# Transform window
crane transform \
  --from-stage 20_openshift \
  --to-stage 30_imagestream

# Apply selected stages
crane apply \
  --transform-dir transform \
  --stages 20_openshift,30_imagestream \
  --output-dir output

# Resume
crane transform --resume
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

## 18. Reference Code Touchpoints

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
