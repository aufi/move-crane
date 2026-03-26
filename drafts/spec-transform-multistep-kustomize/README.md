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

## 0. Export Directory Structure (Input to Transform)

### Current `crane export` Output Format

The `crane export` command produces the following directory structure:

```
<EXPORT_DIR>/
  resources/
    <namespace>/
      Deployment_apps_v1_<namespace>_<name>.yaml
      Service__v1_<namespace>_<name>.yaml
      ConfigMap__v1_<namespace>_<name>.yaml
      Secret__v1_<namespace>_<name>.yaml
      ...
    <namespace2>/
      ...
  failures/
    <namespace>/
      <resource-name>.yaml  # error reports
```

**Key Characteristics:**
- **One file per resource** - Each Kubernetes resource is exported as a separate YAML file
- **Filename pattern**: `<Kind>_<APIGroup>_<APIVersion>_<Namespace>_<Name>.yaml`
  - APIGroup is empty string (shown as `__`) for core resources
  - Examples: `Deployment_apps_v1_default_nginx.yaml`, `Service__v1_default_nginx.yaml`
- **Namespace organization** - Resources grouped by namespace in subdirectories
- **Single-document YAML** - Each file contains exactly one Kubernetes resource
- **Failures directory** - Contains error reports for resources that couldn't be exported

**Example export structure:**
```
export/
  resources/
    default/
      Deployment_apps_v1_default_nginx.yaml
      Service__v1_default_nginx.yaml
      ConfigMap__v1_default_nginx-config.yaml
    app-namespace/
      Deployment_apps_v1_app-namespace_frontend.yaml
      Service__v1_app-namespace_frontend.yaml
```

This per-resource file organization differs from the transform output (which groups by type), requiring aggregation during transform.

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
  .crane-metadata.json         # metadata for dirty check
  kustomization.yaml
  resources/
    deployment.yaml                    # all Deployment resources (multi-doc YAML)
    service.yaml                       # all Service resources (multi-doc YAML)
    configmap.yaml                     # all ConfigMap resources (multi-doc YAML)
    route.openshift.io.yaml            # all Route resources (multi-doc YAML)
    ...
  patches/
    <namespace>--<group>-<version>--<kind>--<name>.patch.yaml
    ...
  reports/
    ignored-patches.json       # optional
  whiteouts/
    whiteouts.json             # optional
```

**Key Points:**
- `kustomization.yaml` contains `resources` (list of resource type files) and `patches` (with explicit `target` metadata)
- Resources are organized by type in `resources/` directory
- Each resource type file is a multi-document YAML containing all resources of that type (separated by `---`)
- Patch files are JSON6902 operations serialized as YAML
- Whiteouted resources are excluded from their respective resource type files
- Deterministic naming: `<kind>.yaml` for core types, `<kind>.<group>.yaml` for non-core types

### 2.2 Multi-Stage Pipeline

```
<TRANSFORM_DIR>/
  10_kubernetes/
    .crane-metadata.json                   # metadata for dirty check
    kustomization.yaml
    resources/
      deployment.yaml                      # multi-doc YAML with all Deployments
      service.yaml                         # multi-doc YAML with all Services
      configmap.yaml                       # multi-doc YAML with all ConfigMaps
      ...
    patches/
      ns1--apps-v1--Deployment--myapp.patch.yaml
      ...
    reports/
      ignored-patches.json
    whiteouts/
      whiteouts.json
  20_openshift/
    .crane-metadata.json
    kustomization.yaml
    resources/
      deployment.yaml                      # from previous stage + patches applied
      service.yaml                         # from previous stage + patches applied
      route.openshift.io.yaml              # new resources added by this stage
      ...
    patches/
      ...
    reports/
    whiteouts/
  30_imagestream/
    .crane-metadata.json
    kustomization.yaml
    resources/
      deployment.yaml                      # from previous stage + patches applied
      service.yaml                         # from previous stage + patches applied
      route.openshift.io.yaml              # from previous stage + patches applied
      imagestream.image.openshift.io.yaml  # new resources added by this stage
      ...
    patches/
    reports/
    whiteouts/
```

**Key Points:**
- Convention over configuration: stage directories are discovered by lexical ordering
- Each stage directory: `<priority>_<pluginName>` (no comments/colons in directory names)
- Stage execution order determined by numeric prefix (ascending)
- Resources organized by type in `resources/` subdirectory (one file per resource type)
- Each resource type file contains all resources of that type as multi-document YAML
- Stage N uses `resources/` from stage N-1 as input
- First stage (lowest numeric prefix) uses `--export-dir` as input
- No `stage discovery` - stage discovery is automatic based on directory structure
- **No rendered.yaml** - stages consume and produce `resources/` directories directly
- `crane apply` executes `kubectl kustomize` on each stage in sequence

---

## 3. `kustomization.yaml` Specification

### Structure

```yaml
resources:
  - resources/deployment.yaml
  - resources/service.yaml
  - resources/configmap.yaml
  - resources/route.openshift.io.yaml

patches:
  - path: patches/ns1--apps-v1--Deployment--myapp.patch.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: myapp
      namespace: ns1
```

### Resource Type File Format

Each resource type file contains multiple resources separated by `---`:

```yaml
# resources/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: ns1
spec:
  replicas: 3
  ...
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: apper-app
  namespace: ns2
spec:
  replicas: 2
  ...
```

### Resource Type File Naming Convention

- **Core types**: `<kind>.yaml` (lowercase)
  - Examples: `deployment.yaml`, `service.yaml`, `configmap.yaml`, `secret.yaml`
- **Non-core types**: `<kind>.<group>.yaml` (lowercase)
  - Examples: `route.openshift.io.yaml`, `imagestream.image.openshift.io.yaml`
- **CRDs**: `<kind>.<group>.yaml`
  - Examples: `application.argoproj.io.yaml`, `certificate.cert-manager.io.yaml`

**Note**: Version is NOT included in filename - it is specified in the resource YAML itself via `apiVersion` field.

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
--force                            # overwrite modified stage directories (skip dirty check)
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
- Executes `kubectl kustomize <stage-dir>` sequentially for each stage
- Outputs final rendered YAML from last executed stage
- Supports same stage selectors as `crane transform`

**Multi-Stage Execution Flow**:
1. Discover stages (e.g., `10_kubernetes/`, `20_openshift/`, `30_imagestream/`)
2. For each stage in order:
   - Execute: `kubectl kustomize <transform-dir>/<stage-dir>`
   - Capture output (rendered YAML)
3. Final output is rendered YAML from last stage
4. Write to STDOUT or `--output-dir/all.yaml`

#### Stage Selectors (Multi-Stage Mode)

```bash
--list-stages                      # print discovered stages and exit
--stage <stage-dir>                # apply only one stage
--from-stage <stage-dir>           # apply from stage to end
--to-stage <stage-dir>             # apply from start to stage
--stages <dir1,dir2,...>           # apply only selected stages
```

#### Output Behavior
- Default: STDOUT (rendered manifests from final stage)
- With `--output-dir`: writes `<output-dir>/all.yaml`

#### kubectl Passthrough Flags
- `--kustomize-flags <flags>`: Pass additional flags to `kubectl kustomize`

**Example**:
```bash
crane apply --kustomize-flags="--enable-helm --load-restrictor=LoadRestrictionsNone"
```

#### Preflight Validation
- Check for `kubectl` existence
- Check for `kustomization.yaml` existence (or stage directories)
- Improved error messages on non-zero exit from kubectl

---

## 4.3. Multi-Stage Data Flow

### Stage Input/Output Chain

```
┌─────────────────────────────────────────────────────────────────────┐
│                         EXPORT DIRECTORY                            │
│  (individual files per resource, organized by namespace)            │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      STAGE 1: 10_kubernetes                         │
│                                                                     │
│  INPUT: Read from export/ (individual YAML files)                  │
│         - Deployment_apps_v1_ns1_myapp.yaml                        │
│         - Service__v1_ns1_myapp.yaml                               │
│         - ConfigMap__v1_ns1_config.yaml                            │
│                                                                     │
│  PROCESS:                                                           │
│    1. Run plugin against each resource                             │
│    2. Collect patches and whiteouts                                │
│    3. Group resources by type (kind + group)                       │
│    4. Write resources/ directory (multi-doc YAML by type)          │
│    5. Write patches/ directory (one file per resource)             │
│    6. Generate kustomization.yaml                                  │
│    7. Execute: kubectl kustomize → rendered.yaml                   │
│                                                                     │
│  OUTPUT:                                                            │
│    resources/deployment.yaml        (multi-doc, input for next)    │
│    resources/service.yaml           (multi-doc, input for next)    │
│    resources/configmap.yaml         (multi-doc, input for next)    │
│    patches/*.patch.yaml                                            │
│    kustomization.yaml                                              │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      STAGE 2: 20_openshift                          │
│                                                                     │
│  INPUT: Read from 10_kubernetes/resources/ (multi-doc YAML files)  │
│         - deployment.yaml                                          │
│         - service.yaml                                             │
│         - configmap.yaml                                           │
│                                                                     │
│  PROCESS:                                                           │
│    1. Read all YAML files from 10_kubernetes/resources/            │
│    2. Parse each multi-doc file into individual resources          │
│    3. Run plugin against each resource                             │
│    4. Collect patches and whiteouts                                │
│    5. Group resources by type                                      │
│    6. Write resources/ directory (multi-doc YAML by type)          │
│    7. Write patches/ directory (one file per resource)             │
│    8. Generate kustomization.yaml (references resources/)          │
│                                                                     │
│  OUTPUT:                                                            │
│    resources/deployment.yaml        (multi-doc, input for next)    │
│    resources/service.yaml           (multi-doc, input for next)    │
│    resources/route.openshift.io.yaml (multi-doc, new)             │
│    patches/*.patch.yaml                                            │
│    kustomization.yaml                                              │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      STAGE N: 30_imagestream                        │
│                                                                     │
│  INPUT: Read from 20_openshift/resources/ (multi-doc YAML files)   │
│  PROCESS: (same as stage 2)                                        │
│  OUTPUT: resources/, patches/, kustomization.yaml                  │
└─────────────────────┬───────────────────────────────────────────────┘
                      │
                      ▼
                  Last Stage
    30_imagestream/resources/*.yaml files
    (crane apply uses kubectl kustomize on each stage)
```

### Key Data Transformations

**Stage 1 (First Stage):**
- **Input format**: Individual YAML files (one per resource)
- **Input source**: `--export-dir/resources/<namespace>/*.yaml`
- **Aggregation**: Groups individual files by resource type (kind + group)
- **Output format**: Multi-document YAML files (one per resource type)

**Stage N (Subsequent Stages):**
- **Input format**: Multi-document YAML files by type
- **Input source**: `<transform-dir>/<prev-stage>/resources/*.yaml`
- **Disaggregation**: Parse each multi-doc file into individual resources
- **Re-aggregation**: Group by resource type (kind + group)
- **Output format**: Multi-document YAML files (one per resource type) in `resources/`

### Resource Type Grouping Algorithm

For each stage:

1. **Read Input**:
   - Stage 1: Read all YAML files from export directory
   - Stage N: Read all `*.yaml` files from previous stage's `resources/` directory, split each by `---`

2. **Parse Resources**:
   - Extract `apiVersion`, `kind`, `metadata.name`, `metadata.namespace`
   - Derive group from `apiVersion` (part before `/` or empty for core)

3. **Group by Type**:
   - Key: `<kind>.<group>` (e.g., `deployment`, `route.openshift.io`)
   - Value: List of resources of that type (preserve order)

4. **Run Plugin**:
   - Execute plugin for each resource
   - Collect patches and whiteouts

5. **Write Resources**:
   - For each type group, create `resources/<kind>.<group>.yaml`
   - Write resources separated by `---`
   - Exclude whiteouted resources

6. **Write Patches**:
   - One patch file per resource: `patches/<ns>--<group>-<version>--<kind>--<name>.patch.yaml`

7. **Generate kustomization.yaml**:
   - `resources`: List all files in `resources/` directory (relative paths)
   - `patches`: List all patches with explicit targets

**Note**: No rendered.yaml is generated during transform. The `resources/` directory is the output that next stage consumes.

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

### Plugin Priority Auto-Assignment

When `--plugin-config` is not provided, plugins are assigned priorities automatically:

**Algorithm**:
1. Discover all available plugins from `--plugin-dir` and built-ins
2. Sort plugins alphabetically by name (case-insensitive)
3. Assign priorities starting at 10, incrementing by 10 for each plugin

**Example**:
```
Available plugins: [OpenShiftPlugin, KubernetesPlugin, ImageStreamPlugin]
Sorted:            [ImageStreamPlugin, KubernetesPlugin, OpenShiftPlugin]
Assigned priorities:
  - ImageStreamPlugin  → 10
  - KubernetesPlugin   → 20
  - OpenShiftPlugin    → 30
```

**Resulting stage directories**:
```
transform/
  10_imagestream/
  20_kubernetes/
  30_openshift/
```

**Override**: KubernetesPlugin (built-in default) always gets priority 10 unless explicitly configured otherwise.

**Final algorithm with override**:
1. Assign KubernetesPlugin priority 10
2. Discover remaining plugins
3. Sort remaining plugins alphabetically
4. Assign priorities starting at 20, incrementing by 10

**Corrected example**:
```
Available plugins: [OpenShiftPlugin, KubernetesPlugin, ImageStreamPlugin]
KubernetesPlugin  → 10 (built-in default)
Remaining sorted:  [ImageStreamPlugin, OpenShiftPlugin]
Assigned priorities:
  - KubernetesPlugin   → 10
  - ImageStreamPlugin  → 20
  - OpenShiftPlugin    → 30
```

**Gaps of 10**: Allow users to manually insert custom stages (e.g., `15_custom-tweaks`) between auto-assigned plugins.

### Idempotency and Re-execution

**Design Principle**: `crane transform` is **idempotent** - running it multiple times with the same input produces the same output.

**No Resume Logic**: There is no `--resume` flag. Instead:
- Clean stage directories → regenerate (idempotent)
- Dirty stage directories → fail (require `--force` or manual cleanup)
- User should delete transform directory and re-run if needed

**Workflow**:
1. First run: `crane transform` → creates all stage directories
2. User modifies `10_kubernetes/patches/something.yaml`
3. Second run: `crane transform` → **FAILS** (dirty check)
4. User options:
   - Use `--force` to regenerate all stages (lose modifications)
   - Manually delete/backup `10_kubernetes/` → re-run (preserve other stages)
   - Delete entire `transform/` directory → re-run (full clean start)

**Rationale**:
- Simpler implementation (no partial state tracking)
- Clearer semantics (regenerate vs preserve)
- Explicit user control over modifications
- Transform is typically fast enough to re-run completely

**Non-Goal**: Incremental/partial updates - if source changes, re-run full transform.

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
- **A3**: Add resource type grouping logic (group resources by kind/group)
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

### Epic F — Stage-Aware Pipeline (Optional Extension)
- **F1**: Stage discovery mechanism (scan directories matching `<num>_<plugin>` pattern)
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
- Resource grouping by type into multi-doc YAML files
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
- `kustomization.yaml` is missing in target stage
- `kubectl kustomize` exits with non-zero
- (stage-aware) `resources/` directory from previous stage is missing or empty

---

## 13. Determinism Requirements

For stable Git diffs, output must be deterministic:
- ✅ Stable sort for `resources` list in kustomization.yaml (lexically by filename)
- ✅ Preserve creation order for resources within each resource type file
- ✅ Stable sort for `patches` (lexically by filename)
- ✅ Stable sort for report entries
- ✅ Deterministic patch file naming
- ✅ Deterministic resource type file naming (kind + group, no version)
- ✅ Deterministic stage naming (for pipeline workflow)

---

## 14. Design Decisions

### 1. Resource Type File Ordering
**Decision**: Preserve creation order - resources appear in the same order they were discovered/processed.

**Rationale**: Maintains original sequence from export, easier to trace back to source.

### 2. Patch Grouping
**Decision**: One patch file per resource, located within the plugin's stage directory.

**Example**:
```
10_kubernetes/
  patches/
    ns1--apps-v1--Deployment--myapp.patch.yaml
20_openshift/
  patches/
    ns1--route-v1--Route--frontend.patch.yaml
```

**Rationale**: Clear attribution to plugin stage, easier debugging.

### 3. Report Schema
**Decision**: Use JSON format with documented structure. Formal JSON Schema/OpenAPI specification TBD (to be evaluated in future iteration).

**Rationale**: Start with documented examples, add formal schema if tooling integration requires it.

### 4. kubectl Passthrough Flags
**Decision**: Support passthrough via `--kustomize-flags` (or similar mechanism).

**Example**:
```bash
crane apply --kustomize-flags="--enable-helm --load-restrictor=LoadRestrictionsNone"
```

**Rationale**: Allows advanced users to leverage full kustomize capabilities without restricting functionality.

### 5. Stage Naming Collision
**Decision**: Priority numbers MUST be unique across all plugins. Collision results in error - plugins cannot share directory name.

**Rationale**: Directory name = `<priority>_<plugin>`, so same priority means same directory. This is invalid.

### 6. Core Group Handling
**Decision**: Follow existing crane behavior - use empty group field for core resources, "core" as fallback if group cannot be determined.

**Rationale**: Maintains backward compatibility with existing crane semantics.

### 7. Strict Mode Granularity
**Decision**: Aggregate mode - collect all errors/conflicts, report at end, exit with non-zero code.

**Rationale**: Operators can see full scope of issues in single run.

### 8. Stage Discovery Pattern
**Decision**: Enforce strict pattern `<number>_<pluginName>` via regex validation.

**Pattern**: `^[0-9]+_[a-zA-Z0-9_-]+$`

**Valid**: `10_kubernetes`, `20_openshift`, `100_custom-plugin`
**Invalid**: `10-kubernetes`, `kubernetes_10`, `10_kubernetes:comment`

**Rationale**: Unambiguous parsing, prevents configuration errors.

### 8a. Non-Existent Plugin in Stage Directory
**Decision**: Stage directories with non-existent plugin names are treated as **user-created custom transformations**.

**Behavior**:

**During `crane transform`**:
- Skip stage directories for plugins that don't exist
- Log informational message: "Skipping stage `<stage-dir>` - plugin not found (treated as custom transformation)"
- Do not fail or error - allows users to manually create custom stages

**During `crane apply`**:
- Process all discovered stage directories regardless of plugin existence
- Plugin name is informational only (for traceability)
- Execute `kubectl kustomize` on each stage in order

**Example scenario**:
```
transform/
  10_kubernetes/        # created by crane transform
  15_custom-tweaks/     # manually created by user
  20_openshift/         # created by crane transform
  25_my-adjustments/    # manually created by user
```

- `crane transform` creates `10_kubernetes/` and `20_openshift/`, skips the custom ones
- User manually creates `15_custom-tweaks/` and `25_my-adjustments/` with custom kustomization.yaml
- `crane apply` processes all four stages in numeric order

**Rationale**:
- Enables manual intervention and custom transformations
- Allows hybrid automated + manual migration workflows
- User can insert custom stages between plugin stages
- No coupling between transform and apply regarding plugin availability

### 8b. Stage Directory Dirty Check and Overwrite Protection
**Decision**: `crane transform` performs dirty check on existing stage directories to prevent accidental overwrite of user modifications.

**Dirty Check Mechanism**:
- When stage directory already exists, check if content was modified after creation
- Use metadata file (e.g., `.crane-metadata.json`) containing:
  - Creation timestamp
  - Plugin name and version
  - Content checksum/hash
- If content differs from expected generated output → directory is "dirty"

**Behavior**:

**Without `--force` flag**:
```bash
crane transform --export-dir export --transform-dir transform
```
- If stage directory exists and is clean (unmodified) → overwrite without warning
- If stage directory exists and is dirty (user-modified) → **FAIL** with error:
  ```
  Error: Stage directory '10_kubernetes' contains user modifications.
  Use --force to overwrite, or remove/rename the directory.
  ```
- Custom stage directories (non-existent plugins) are never checked or overwritten

**With `--force` flag**:
```bash
crane transform --export-dir export --transform-dir transform --force
```
- Overwrite all existing stage directories regardless of modification status
- Custom stage directories (non-existent plugins) are still skipped

**Metadata File Format** (`.crane-metadata.json`):
```json
{
  "createdAt": "2026-03-26T14:30:00Z",
  "createdBy": "crane-transform",
  "plugin": "kubernetes",
  "pluginVersion": "v0.1.0",
  "craneVersion": "v1.5.0",
  "contentHashes": {
    "kustomization.yaml": "sha256:abc123...",
    "resources/deployment.yaml": "sha256:def456...",
    "resources/service.yaml": "sha256:789abc...",
    "patches/ns1--apps-v1--Deployment--myapp.patch.yaml": "sha256:012def...",
    "reports/ignored-patches.json": "sha256:345678...",
    "whiteouts/whiteouts.json": "sha256:901234..."
  }
}
```

**Hash Algorithm Details**:
- **Algorithm**: SHA256
- **Scope**: Individual files (not directory tree)
- **Excluded files**: `rendered.yaml` (generated output, not source)
- **Excluded files**: `.crane-metadata.json` itself
- **Hash computation**: SHA256 of file content bytes (UTF-8 encoded)
- **Storage format**: `sha256:<hex-digest>` (64 hex characters)

**Dirty Check Logic**:
1. Read existing `.crane-metadata.json`
2. For each file in `contentHashes`:
   - Compute current SHA256 hash of file
   - Compare with stored hash
   - If any hash differs → directory is "dirty"
3. If `.crane-metadata.json` missing → treat as clean (first run)
4. If file listed in metadata is missing → dirty
5. If new files exist not in metadata → dirty

**Hash Computation Example** (Go pseudocode):
```go
func computeFileHash(path string) (string, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return "", err
    }
    hash := sha256.Sum256(data)
    return fmt.Sprintf("sha256:%x", hash), nil
}
```

**Example Workflow**:
1. User runs `crane transform` → creates `10_kubernetes/`
2. User manually edits `10_kubernetes/patches/something.yaml`
3. User runs `crane transform` again → **FAILS** with dirty check error
4. User runs `crane transform --force` → overwrites with fresh transform output
5. Or user renames `10_kubernetes/` to `10_kubernetes.backup/` → transform succeeds

**Rationale**:
- Prevents accidental loss of user modifications
- Makes manual edits explicit and intentional
- Clear error messages guide user to safe resolution
- Metadata enables smart detection of modifications
- Force flag provides escape hatch when needed

### 9. Empty Resource Types
**Decision**: Omit empty resource type files. Only create files for resource types that contain at least one resource.

**Rationale**: Cleaner directory structure, no maintenance of empty files.

### 10. Version in Filename
**Decision**: Do NOT include version in resource type filenames.

**Format**:
- Core types: `<kind>.yaml` (e.g., `deployment.yaml`, `service.yaml`)
- Non-core types: `<kind>.<group>.yaml` (e.g., `route.openshift.io.yaml`, `imagestream.image.openshift.io.yaml`)

**Rationale**:
- Simpler naming convention
- Resources of same kind/group belong together regardless of version
- Version is already present in the resource YAML itself (apiVersion field)
- Reduces filename churn during API version migrations
- If multiple versions exist for same kind, they are grouped in single file (multi-doc YAML)

---

## 15. Error Handling Strategy

### Idempotent Re-execution on Failure

**Principle**: All errors during transform or apply require **full re-run** from clean state.

### Transform Error Handling

**When errors occur during `crane transform`**:
1. Transform stops immediately at the failing stage
2. Partial output may exist in transform directory
3. User must resolve the error and re-run transform
4. Options for re-run:
   - Delete entire `<TRANSFORM_DIR>` → clean re-run
   - Use `--force` → overwrite all stages
   - Manually delete failing stage directory → re-run that stage only

**No partial state recovery** - transform is atomic per stage.

**Common Error Scenarios**:

| Error | Cause | Resolution |
|-------|-------|------------|
| Plugin execution fails | Plugin crashes or returns error | Fix plugin or skip with `--skip-plugins`, re-run transform |
| Patch serialization fails | Invalid JSONPatch operations from plugin | Fix plugin output, re-run transform |
| Resource parsing fails | Malformed YAML in export or previous stage | Fix source data, re-run transform |
| Kustomization.yaml write fails | Filesystem permissions, disk full | Fix system issue, re-run transform |
| Dirty check fails | User modified stage directory | Use `--force` or delete modified stage, re-run |

**Error Output**:
- Clear error message identifying failing stage and resource
- Stack trace (if `--debug` enabled)
- Exit code: non-zero

**Strict Mode Errors** (with `--strict-plugin-errors` or `--strict-conflicts`):
- Fail immediately on first plugin error or conflict
- Aggregate mode: Collect all errors, report at end, fail

### Apply Error Handling

**When errors occur during `crane apply`**:
1. Apply stops immediately at the failing stage
2. No resources are applied to cluster (render only)
3. User must fix the error and re-run apply

**Common Error Scenarios**:

| Error | Cause | Resolution |
|-------|-------|------------|
| `kubectl` not found | kubectl not installed or not in PATH | Install kubectl, re-run apply |
| `kustomization.yaml` missing | Stage directory incomplete or corrupted | Re-run transform, then apply |
| `resources/` directory empty | Stage produced no resources (all whiteouted?) | Verify transform output is correct |
| `kubectl kustomize` fails | Invalid Kustomize syntax or circular refs | Fix transform output, re-run transform |
| Previous stage resources missing | Dependency chain broken | Re-run transform from clean state |

**Error Output**:
- Stage that failed
- kubectl stderr output (if applicable)
- Exit code: non-zero

### No Rollback or Partial Recovery

**Design Decision**: No automatic rollback or partial recovery mechanisms.

**Rationale**:
- Transform is fast enough to re-run completely
- Simpler implementation and clearer semantics
- Explicit user control over what to preserve

**User Workflow on Error**:
1. Error occurs during transform or apply
2. Read error message to identify cause
3. Fix the cause (plugin, source data, system issue)
4. Delete problematic stage or use `--force`
5. Re-run command

---

## 16. Stage Chaining Validation

### Minimal Validation Between Stages

**Principle**: Validate only that input exists, not its content.

### Transform Validation

**Stage N reading from Stage N-1**:
- ✅ Check: `<transform-dir>/<prev-stage>/resources/` directory exists
- ✅ Check: `resources/` directory is not empty (contains at least one .yaml file)
- ❌ No check: Whether specific resource types exist
- ❌ No check: Whether resources are valid Kubernetes YAML
- ❌ No check: Whether resources match expected schema

**Validation Logic**:
```
if stage > 1:
  prev_stage_resources = <transform-dir>/<prev-stage>/resources/
  if not exists(prev_stage_resources):
    FAIL: "Stage <prev-stage> resources/ directory not found"
  if is_empty(prev_stage_resources):
    FAIL: "Stage <prev-stage> resources/ directory is empty"
```

**Rationale**: Rest is on the user - stages are independent transformations.

### Apply Validation

**Per-stage validation before `kubectl kustomize`**:
- ✅ Check: `kustomization.yaml` exists
- ✅ Check: `resources/` directory exists (if referenced in kustomization.yaml)
- ❌ No check: Whether resources are semantically valid

**kubectl kustomize handles**:
- YAML syntax validation
- Kustomize schema validation
- Resource reference validation
- Patch target existence validation

**If kubectl kustomize fails** → error propagated to user

---

## 17. Patch Target Resolution in Multi-Stage Pipeline

### Stage Independence Principle

**Each stage operates independently** - no cross-stage patch target validation.

### Patch Target Matching

**Within a single stage**:
1. Plugin generates patches for resources in stage input
2. Patch target derived from resource metadata (kind, group, version, name, namespace)
3. Kustomize matches patch to resource by target selector

**Example - Successful Match**:
```
Stage 20_openshift:
  Input: 10_kubernetes/resources/deployment.yaml (contains myapp Deployment)
  Plugin: Generates patch for myapp Deployment
  Patch file: ns1--apps-v1--Deployment--myapp.patch.yaml
  Target:
    kind: Deployment
    name: myapp
    namespace: ns1
  Result: Patch applied successfully by kubectl kustomize
```

### Missing Patch Target Scenarios

**Scenario 1: Previous stage whiteouted the resource**

```
Stage 10_kubernetes:
  - Whiteouts Route "frontend" (OpenShift-specific resource)
  - Route NOT in 10_kubernetes/resources/ output

Stage 20_openshift:
  - Tries to patch Route "frontend"
  - Patch file generated: ns1--route-v1--Route--frontend.patch.yaml
  - Target not found in 20_openshift/resources/ (came from 10_kubernetes)
  - Result: kubectl kustomize fails with "patch target not found"
```

**Resolution**: User must adjust plugin logic to not generate patches for whiteouted resources.

**Scenario 2: Plugin expects resource that doesn't exist**

```
Stage 30_imagestream:
  - Expects Deployment "myapp" to exist
  - Deployment was removed/renamed in stage 20_openshift
  - Patch generated but target missing
  - Result: kubectl kustomize fails
```

**Resolution**: User must ensure stage order and plugin logic are compatible.

### No Cross-Stage Validation

**Design Decision**: `crane transform` does NOT validate that patch targets will exist in the same stage.

**Why**:
- Stages run independently
- Plugin operates on input resources, not knowing future patches
- Validation happens at `kubectl kustomize` time (during apply)

**User Responsibility**:
- Ensure plugin order is correct (e.g., don't whiteout before patching)
- Ensure plugins don't generate patches for non-existent resources
- Test with `crane apply` to catch mismatches

### Debugging Patch Target Issues

**If `kubectl kustomize` fails with "patch target not found"**:

1. Check which stage failed (error message includes stage dir)
2. Inspect `<stage>/patches/` to see which patches were generated
3. Inspect `<stage>/resources/` to see which resources exist
4. Check `<prev-stage>/whiteouts/whiteouts.json` for removed resources
5. Adjust plugin logic or stage order
6. Re-run transform

**Example Debug Workflow**:
```bash
# Apply fails
crane apply --transform-dir transform
# Error: Stage 20_openshift: patch target "Route/frontend" not found

# Investigate
cat transform/10_kubernetes/whiteouts/whiteouts.json
# Shows: Route "frontend" was whiteouted

cat transform/20_openshift/patches/ns1--route-v1--Route--frontend.patch.yaml
# Patch exists but target doesn't

# Resolution: Skip OpenShift plugin or fix whiteout logic
crane transform --skip-plugins OpenShiftPlugin --force
crane apply --transform-dir transform
```

---

## 18. Acceptance Criteria (Overall)

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
- [ ] Idempotent behavior - re-running transform produces same output
- [ ] Dirty check prevents accidental overwrite of user modifications

---

## 16. Implementation Details Summary

### Key Algorithms

**1. Stage Input Source Selection**:
```go
func getStageInputSource(stageNumber int, stageName string, exportDir string, transformDir string) string {
    if stageNumber == firstStageNumber {
        return filepath.Join(exportDir, "resources")
    } else {
        prevStageName := getPreviousStageName(stageNumber)
        return filepath.Join(transformDir, prevStageName, "resources")
    }
}
```

**2. Resource Type File Naming**:
```go
func getResourceTypeFilename(kind string, apiGroup string) string {
    kindLower := strings.ToLower(kind)
    if apiGroup == "" {
        // Core API resources
        return kindLower + ".yaml"
    } else {
        // Non-core API resources
        return kindLower + "." + apiGroup + ".yaml"
    }
}

// Examples:
// kind="Deployment", group="apps" → "deployment.apps.yaml"
// kind="Service", group="" → "service.yaml"
// kind="Route", group="route.openshift.io" → "route.route.openshift.io.yaml"
```

**3. Dirty Check Decision**:
```go
func isStageDirectoryDirty(stageDir string) (bool, error) {
    metadataPath := filepath.Join(stageDir, ".crane-metadata.json")

    // If metadata doesn't exist, treat as clean (first run)
    if !fileExists(metadataPath) {
        return false, nil
    }

    metadata := readMetadata(metadataPath)

    // Check each file hash
    for filePath, expectedHash := range metadata.ContentHashes {
        fullPath := filepath.Join(stageDir, filePath)

        if !fileExists(fullPath) {
            return true, nil // File deleted = dirty
        }

        currentHash := computeSHA256(fullPath)
        if currentHash != expectedHash {
            return true, nil // Hash mismatch = dirty
        }
    }

    // Check for new files not in metadata
    actualFiles := listAllFiles(stageDir, exclude=[".crane-metadata.json"])
    metadataFiles := keys(metadata.ContentHashes)

    if hasNewFiles(actualFiles, metadataFiles) {
        return true, nil // New files = dirty
    }

    return false, nil // Clean
}
```

**4. Stage Discovery**:
```go
func discoverStages(transformDir string) []Stage {
    stages := []Stage{}
    pattern := regexp.MustCompile(`^([0-9]+)_([a-zA-Z0-9_-]+)$`)

    dirs := listDirectories(transformDir)

    for _, dir := range dirs {
        matches := pattern.FindStringSubmatch(dir.Name)
        if matches != nil {
            priority := parseInt(matches[1])
            pluginName := matches[2]

            stages = append(stages, Stage{
                Priority: priority,
                PluginName: pluginName,
                Path: filepath.Join(transformDir, dir.Name),
            })
        }
    }

    // Sort by priority ascending
    sort.Slice(stages, func(i, j int) bool {
        return stages[i].Priority < stages[j].Priority
    })

    return stages
}
```

**5. Multi-Doc YAML Aggregation**:
```go
func aggregateResourcesByType(resources []Resource) map[string][]Resource {
    grouped := make(map[string][]Resource)

    for _, resource := range resources {
        kind := resource.Kind
        group := extractGroupFromAPIVersion(resource.APIVersion)

        filename := getResourceTypeFilename(kind, group)
        grouped[filename] = append(grouped[filename], resource)
    }

    return grouped
}

func writeMultiDocYAML(filename string, resources []Resource) error {
    var buffer bytes.Buffer

    for i, resource := range resources {
        if i > 0 {
            buffer.WriteString("\n---\n")
        }

        yamlBytes, err := yaml.Marshal(resource)
        if err != nil {
            return err
        }

        buffer.Write(yamlBytes)
    }

    return writeFile(filename, buffer.Bytes())
}
```

**6. Stage Resources Validation**:
```go
func validateStageInput(stageName string, inputPath string) error {
    if !directoryExists(inputPath) {
        return fmt.Errorf("stage %s: input directory not found: %s", stageName, inputPath)
    }

    files := listFiles(inputPath, "*.yaml")
    if len(files) == 0 {
        return fmt.Errorf("stage %s: input directory is empty: %s", stageName, inputPath)
    }

    return nil
}
```

---

## 17. Recommended Issue Mapping

For implementation tracking:

1. **crane-lib**: Add TransformArtifact + PatchTarget structs
2. **crane-lib**: Add kustomize serializer package
3. **crane-lib**: Add resource type grouping logic
4. **crane-lib**: Add whiteout/ignored-patches report structs
5. **crane**: Refactor transform to emit kustomization.yaml + patches
6. **crane**: Implement resource type file generation (multi-doc YAML)
7. **crane**: Add deterministic ordering for overlay artifacts and resources
8. **crane**: Refactor apply to kubectl kustomize only
9. **crane**: Add apply preflight checks and output behavior
10. **crane+crane-lib**: Add plugin compatibility fixture suite
11. **docs**: Update usage docs and migration notes
12. **crane**: Implement dirty check with SHA256 hashing
13. **crane**: Add error handling with idempotent re-run semantics
14. **crane**: Add stage input validation (resources/ directory existence check)
15. **crane**: Add stage discovery mechanism (directory scan) (optional)
16. **crane**: Add stage-aware CLI flags for transform/apply (optional)
17. **crane**: Add stage execution orchestration logic (optional)
18. **crane**: Add plugin priority auto-assignment algorithm (optional)

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
