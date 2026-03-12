# Implementation Plan: Move `crane transform`/`crane apply` to Kustomize-Only

## Objective

Implement a single supported workflow:

1. `crane transform` generates **Kustomize artifacts** (not per-resource JSONPatch files).
2. `crane apply` renders output exclusively via:
   - `kubectl kustomize <transform-dir>`
3. Existing plugins remain usable by converting their JSONPatch operations into Kustomize-compatible JSON6902 patch files.

This requires coordinated changes in **`crane`** and **`crane-lib`**.

---

## Decision

**No dual mode. No legacy jsonpatch-file mode.**

- `transform-*` JSONPatch files are removed from the workflow.
- `crane-lib/apply.Applier` JSONPatch apply path is removed from CLI usage.
- `crane apply` becomes a kustomize renderer/orchestrator only.

---

## Current Baseline (for reference)

- Plugins return `PluginResponse{ IsWhiteOut, Patches(jsonpatch.Patch) }`.
- `transform.Runner` merges/sanitizes patch ops and returns marshaled patch bytes.
- `crane transform` writes one `transform-*` file (JSONPatch) per resource.
- `crane apply` reads export + transform files and applies JSONPatch in-process.

---

## Target Architecture

## A) `crane transform` output layout

`--transform-dir` becomes a Kustomize overlay root:

```text
transform/
  kustomization.yaml
  patches/
    ns1--apps-v1--Deployment--myapp.patch.yaml
    ns1--route-v1--Route--frontend.patch.yaml
  whiteouts/
    whiteouts.json
  reports/
    ignored-patches.json
```

Notes:
- `resources` in `kustomization.yaml` reference exported manifests from `--export-dir` (relative paths).
- Whiteouted resources are excluded from `resources`.
- Patch files contain the same logical operations produced by plugins, serialized for Kustomize.

## B) Patch representation

Use Kustomize JSON6902-compatible patch files and `patches` with explicit `target`.

Patch file example:

```yaml
- op: remove
  path: /spec/clusterIP
- op: replace
  path: /spec/type
  value: NodePort
```

`kustomization.yaml` entry example:

```yaml
patches:
  - path: patches/ns1--apps-v1--Deployment--myapp.patch.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: myapp
      namespace: ns1
```

## C) `crane apply`

`crane apply` runs only:

```bash
kubectl kustomize <transform-dir>
```

Recommended behavior:
- stdout: rendered multi-doc YAML
- if `--output-dir` is provided: write `<output-dir>/all.yaml`

---

## Workstream 1: `crane-lib`

## 1.1 Runner output model for Kustomize writing

Keep plugin execution + patch sanitization logic, but expose structured output needed for Kustomize serialization:

```go
type TransformArtifact struct {
    HaveWhiteOut   bool
    JSONPatchOps   []jsonpatch.Operation
    IgnoredPatches []PluginOperation
    Target         PatchTarget
}

type PatchTarget struct {
    Group     string
    Version   string
    Kind      string
    Name      string
    Namespace string
}
```

## 1.2 Plugin contract continuity

Keep plugin contract unchanged in phase 1:
- existing plugins continue returning JSONPatch ops.
- crane/crane-lib converts these ops into Kustomize patch files.

## 1.3 New serializer helpers

Add package (example): `transform/kustomize`:
- op list -> patch YAML
- object -> patch target metadata
- deterministic patch file naming

## 1.4 Tests

- target derivation tests
- patch serialization tests
- unchanged conflict/priority semantics tests
- whiteout precedence tests

---

## Workstream 2: `crane transform`

## 2.1 Remove JSONPatch transform file writing

Replace per-resource `transform-*` output with:
- in-memory artifact collection
- generated `kustomization.yaml`
- generated `patches/*.patch.yaml`
- `whiteouts/whiteouts.json`
- `reports/ignored-patches.json` (if any)

## 2.2 Whiteout behavior

If any plugin returns `IsWhiteOut=true` for a resource:
- resource is not included in `resources`
- optional trace record stored in `whiteouts/whiteouts.json`

## 2.3 Deterministic ordering

Ensure deterministic ordering for:
- `resources`
- `patches`
- report entries

This keeps Git diffs stable.

---

## Workstream 3: `crane apply`

## 3.1 Replace applier loop

Remove in-process JSONPatch application from command path.

Implementation:
- validate `<transform-dir>/kustomization.yaml` exists
- execute `kubectl kustomize <transform-dir>` with `exec.CommandContext`
- return stdout/stderr transparently

## 3.2 Output handling

- default: stream rendered manifests to stdout
- with `--output-dir`: write `<output-dir>/all.yaml`

## 3.3 Preconditions

Fail fast with actionable errors when:
- `kubectl` is not installed
- transform dir is invalid
- kustomize render fails

---

## Workstream 4: Compatibility of existing plugins

## 4.1 Guarantee

Existing plugins are still valid if they emit JSONPatch ops (`add/remove/replace/...`) because Kustomize JSON6902 uses the same operation model.

## 4.2 Edge cases to lock down

Define and test behavior for:
- remove on missing path
- array index operations
- ordering-sensitive operations

If Kustomize behavior differs from old applier options, codify expected behavior in release notes and tests.

---

## Risks & Mitigations

1. **Render differences vs legacy apply path**
   - Mitigation: fixture-based parity tests before merge.

2. **Incorrect patch target mapping**
   - Mitigation: strict target derivation tests for core + non-core APIs.

3. **Hard dependency on kubectl**
   - Mitigation: explicit preflight check and clear operator documentation.

4. **Whiteout regression**
   - Mitigation: unit/integration tests ensuring excluded resources never render.

---

## Test Strategy

## Unit
- kustomization generation
- patch file serialization
- target derivation
- whiteout exclusion
- ignored patch reporting

## Integration
- export fixtures + plugins -> overlay snapshot
- `kubectl kustomize` succeeds on generated overlay

## Semantic regression
- compare resulting rendered manifests against known-good fixtures

---

## Delivery Plan

## Phase 1: Core refactor
- add kustomize serialization helpers in crane-lib
- switch `transform` writer to kustomize artifacts

## Phase 2: Apply refactor
- switch `apply` to `kubectl kustomize` execution only
- remove old apply loop from command logic

## Phase 3: Hardening
- parity fixtures
- docs update
- cleanup dead jsonpatch file-path code in `crane`

---

## Concrete Code Touchpoints

### `crane`
- `cmd/transform/transform.go`
- `cmd/apply/apply.go`
- `internal/file/file_helper.go` (path helpers for patches/reports/whiteouts)

### `crane-lib`
- `transform/runner.go`
- new package (proposed): `transform/kustomize/*`
- optional cleanup/deprecation of `apply/applier.go` usage from CLI flow

---

## Acceptance Criteria

- [ ] `transform` always generates a valid Kustomize overlay (`kustomization.yaml` + patch files).
- [ ] `apply` renders manifests only via `kubectl kustomize`.
- [ ] Existing plugins require no immediate change.
- [ ] Whiteout behavior stays equivalent (resource excluded from render).
- [ ] Deterministic output for stable diffs.
