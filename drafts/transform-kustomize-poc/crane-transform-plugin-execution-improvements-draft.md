# Draft Proposal: Improvements Around `crane transform` Plugin Execution

## Summary

This proposal suggests targeted changes to make `crane transform` behavior easier to control, easier to debug, and safer in mixed-plugin environments.

The current model is flexible, but several behaviors are implicit (plugin selection, ordering, conflict resolution). The goal is to make those behaviors explicit and operator-friendly without breaking existing workflows.

---

## Current Behavior (Observed)

Today, `crane transform`:

1. Loads plugins from multiple locations (including built-in Kubernetes plugin).
2. Deduplicates by plugin name (first match wins).
3. Runs all selected plugins for each resource.
4. Collects patch operations and merges conflicts by patch path.
5. Uses `--plugin-priorities` only for collision resolution.
6. If any plugin returns `IsWhiteOut=true`, whiteout wins for that resource.

This works, but there are practical gaps:

- No first-class “run only these plugins” mode.
- Plugin discovery precedence is implicit.
- Conflicts are recorded (`ignored-patches`) but not surfaced clearly in CLI summary.
- Whiteout origin is not always obvious to users.

---

## Goals

- Add explicit control over plugin inclusion/execution order.
- Improve observability of why a resource changed, conflicted, or was whiteouted.
- Keep backward compatibility with current flags and plugin contracts.
- Minimize disruption for existing automation/scripts.

---

## Proposed Changes

## 1) Add explicit plugin selection flag

### New flag

- `--plugins <name1,name2,...>`

### Behavior

- If `--plugins` is provided, only those plugins are allowed to run.
- `--skip-plugins` still applies, but `--plugins` is evaluated first.
- Unknown plugin names should produce a clear validation error before processing resources.

### Why

This avoids fragile “skip everything except X” patterns and makes intent explicit.

---

## 2) Add deterministic plugin execution order flag

### New flag

- `--plugin-order <name1,name2,...>`

### Behavior

- Controls execution order of plugins (not only conflict priority).
- Unlisted plugins run after listed ones in stable discovery order.
- If both `--plugin-order` and `--plugin-priorities` are set:
  - `--plugin-order` controls run order.
  - `--plugin-priorities` controls patch conflict winner.

### Why
n
Currently users can influence conflict winner but not run order semantics. For debugging and reproducibility, both are useful.

---

## 3) Add transform decision report output

### New flag

- `--report-file <path>` (JSON or YAML)

### Suggested schema

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
  "ignoredPatches": [
    {
      "path": "/spec/template/spec/containers/0/image",
      "selectedPlugin": "OpenShiftPlugin",
      "ignoredPlugin": "ImageStreamPlugin",
      "reason": "path-conflict-priority"
    }
  ]
}
```

### Why

Machine-readable report simplifies CI checks, PR reviews, and migration audits.

---

## 4) Improve whiteout traceability

### Internal behavior

- Track plugin names that requested whiteout for each resource.
- Keep current whiteout precedence (whiteout wins), but expose source plugin(s) in logs/report.

### CLI summary example

- `WHITEOUT: route/default/frontend (requested by: OpenShiftPlugin)`

### Why

Whiteout is a strong action; users need direct attribution.

---

## 5) Add strict mode for plugin errors/conflicts

### New flags

- `--strict-plugin-errors` (fail immediately if any plugin fails for any resource)
- `--strict-conflicts` (fail if any ignored patch is produced)

### Why

Current behavior can be too permissive for regulated or production migration pipelines. Strict mode makes failure conditions explicit.

---

## Compatibility

- Existing behavior remains default if new flags are not used.
- `--skip-plugins`, `--plugin-priorities`, and `--optional-flags` remain valid.
- No required changes to existing plugin binaries in phase 1.

---

## Suggested Implementation Plan

## Phase 1 (Low risk)

- Add `--plugins` allowlist.
- Add `--report-file` output.
- Add better log lines for whiteout attribution.

## Phase 2 (Medium risk)

- Add `--plugin-order` and deterministic ordering guarantees.
- Add strict conflict/error modes.

## Phase 3 (Optional)

- Extend plugin response contract with richer diagnostics (e.g., reasons/categories), if needed.

---

## Affected Areas

- `crane` CLI command and option validation (`cmd/transform`)
- plugin loading/filtering and ordering logic (`internal/plugin`)
- runner reporting surfaces (`crane-lib/transform/runner` integration)
- docs/examples (`crane` + plugin repos)

---

## Open Questions

1. Should `--plugins` implicitly disable built-in plugin unless explicitly listed?
2. Should strict modes return non-zero after full run (aggregate) or fail-fast per resource?
3. Is JSON report enough, or should SARIF-like output be supported for CI systems?
4. Should conflict resolution optionally support per-path policies in future (not just per-plugin priority)?

---

## Acceptance Criteria

- [ ] Users can run only selected plugins without skip-list workarounds.
- [ ] Users can generate a per-resource transform decision report.
- [ ] Whiteout decisions are attributable to plugin name(s).
- [ ] Strict modes can enforce fail-on-plugin-error and fail-on-conflict.
- [ ] Existing pipelines continue to work unchanged by default.

---

## Reference Code Paths

- `crane` transform command orchestration:
  - `https://github.com/migtools/crane/blob/main/cmd/transform/transform.go`
- Plugin discovery/filtering:
  - `https://github.com/migtools/crane/blob/main/internal/plugin/plugin_helper.go`
- Runner merge/conflict behavior:
  - `https://github.com/konveyor/crane-lib/blob/v0.1.5/transform/runner.go`
- Plugin request/response model:
  - `https://github.com/konveyor/crane-lib/blob/v0.1.5/transform/plugin.go`

---

## Short Example CLI (Target UX)

```bash
crane transform \
  --export-dir export \
  --transform-dir transform \
  --plugins KubernetesPlugin,OpenShiftPlugin \
  --plugin-order OpenShiftPlugin,KubernetesPlugin \
  --plugin-priorities OpenShiftPlugin,KubernetesPlugin \
  --optional-flags '{"registry-replacement":"docker.io=quay.io"}' \
  --report-file transform-report.json
```
