# Task Breakdown: Kustomize-Only Migration for `crane transform` and `crane apply`

## Purpose

Engineering task plan for implementation tracking across:
- `crane`
- `crane-lib`

Aligned with:
- `crane-transform-apply-kustomize-implementation-plan.md`
- `crane-kustomize-ondisk-layout-rfc-draft.md`

---

## Epic A — `crane-lib`: Kustomize artifact foundations

## A1. Introduce structured transform artifact model

**Goal**: Return structured data needed for Kustomize writer.

**Tasks**
- [ ] Add `TransformArtifact` and `PatchTarget` types in `crane-lib/transform`.
- [ ] Extend runner response to expose:
  - [ ] `HaveWhiteOut`
  - [ ] sanitized op list
  - [ ] ignored operations with plugin attribution
  - [ ] per-resource target metadata
- [ ] Preserve current conflict and priority semantics.

**Acceptance**
- [ ] Runner unit tests cover old + new response shape.
- [ ] No behavior regressions in conflict resolution.

---

## A2. Add Kustomize serialization package

**Goal**: Convert runner artifacts into files for Kustomize.

**Tasks**
- [ ] Create package `transform/kustomize` (or equivalent).
- [ ] Implement op-list -> YAML patch serializer.
- [ ] Implement deterministic patch filename builder.
- [ ] Implement kustomization model structs + marshal helpers.

**Acceptance**
- [ ] Golden tests for patch YAML output.
- [ ] Deterministic naming tests with edge-case input.

---

## A3. Whiteout and ignored-patch report models

**Goal**: Provide standard report payloads consumable by `crane`.

**Tasks**
- [ ] Define report structs for whiteouts.
- [ ] Define report structs for ignored patches.
- [ ] Add stable sort utilities for deterministic report output.

**Acceptance**
- [ ] Report JSON is stable across repeated runs.

---

## Epic B — `crane`: transform command rewrite (Kustomize output)

## B1. Replace transform file writer

**Goal**: Remove per-resource `transform-*` JSONPatch file output.

**Tasks**
- [ ] Refactor transform command to collect artifacts per resource.
- [ ] Generate `<transform-dir>/kustomization.yaml`.
- [ ] Generate `<transform-dir>/patches/*.patch.yaml`.
- [ ] Generate optional reports:
  - [ ] `whiteouts/whiteouts.json`
  - [ ] `reports/ignored-patches.json`

**Acceptance**
- [ ] No `transform-*` files are produced.
- [ ] Produced overlay passes `kubectl kustomize` in fixture tests.

---

## B2. Resource and patch target assembly

**Goal**: Correct and deterministic kustomization entries.

**Tasks**
- [ ] Build `resources` list from non-whiteout export files.
- [ ] Build `patches` entries with explicit target metadata.
- [ ] Ensure stable sort order for `resources` and `patches`.

**Acceptance**
- [ ] Re-running transform with same input yields byte-stable files (except timestamps if any).

---

## B3. Path helper updates

**Goal**: Update internal file helper paths for new layout.

**Tasks**
- [ ] Add helper methods for patch/report/whiteout output paths.
- [ ] Remove/retire obsolete transform JSONPatch path helpers from usage.

**Acceptance**
- [ ] No command path references obsolete `transform-*` naming.

---

## Epic C — `crane`: apply command rewrite (Kustomize render only)

## C1. Replace in-process JSONPatch apply loop

**Goal**: `apply` delegates rendering to kubectl kustomize.

**Tasks**
- [ ] Remove command-path dependency on `crane-lib/apply.Applier`.
- [ ] Execute `kubectl kustomize <transform-dir>` via process exec.
- [ ] Stream stdout/stderr properly.

**Acceptance**
- [ ] `crane apply` works with generated overlay only.
- [ ] JSONPatch file inputs are no longer required/used.

---

## C2. Output behavior

**Goal**: Keep predictable CLI output contract.

**Tasks**
- [ ] If `--output-dir` is set, write rendered output to `<output-dir>/all.yaml`.
- [ ] Otherwise print rendered output to stdout.

**Acceptance**
- [ ] Output behavior documented and tested.

---

## C3. Preflight validation

**Goal**: Fast, actionable failure modes.

**Tasks**
- [ ] Validate `kustomization.yaml` presence.
- [ ] Validate `kubectl` availability.
- [ ] Improve errors for non-zero render exits.

**Acceptance**
- [ ] Error messages point directly to operator action.

---

## Epic D — Compatibility and behavior parity

## D1. Existing plugin compatibility verification

**Goal**: Ensure no immediate plugin rewrites needed.

**Tasks**
- [ ] Build fixture matrix with current first-party plugins.
- [ ] Verify plugin JSONPatch outputs convert correctly to Kustomize patch files.
- [ ] Validate rendered manifests are semantically correct.

**Acceptance**
- [ ] Existing plugins pass compatibility fixture suite.

---

## D2. Edge-case parity tests

**Goal**: Lock down tricky semantics.

**Tasks**
- [ ] Add tests for remove-on-missing-path operations.
- [ ] Add tests for array index operations and order dependence.
- [ ] Add tests for conflicting plugin patches with priorities.
- [ ] Add tests for whiteout precedence over patches.

**Acceptance**
- [ ] Regression suite green in CI.

---

## Epic E — Documentation and rollout

## E1. User-facing docs update

**Tasks**
- [ ] Update `crane` README/examples for Kustomize-only flow.
- [ ] Add migration note: JSONPatch transform files removed.
- [ ] Document transform output layout and apply behavior.

**Acceptance**
- [ ] New docs match actual CLI behavior.

---

## E2. Contributor/plugin-author note

**Tasks**
- [ ] Publish short note: existing JSONPatch-returning plugins remain supported.
- [ ] Document any known behavior differences caused by Kustomize evaluation.

**Acceptance**
- [ ] Plugin maintainers can validate compatibility quickly.

---

## Suggested Issue Map (ready to copy)

1. `crane-lib`: Add TransformArtifact + PatchTarget in transform runner
2. `crane-lib`: Add kustomize serializer package for JSON6902 patch files
3. `crane-lib`: Add whiteout/ignored-patches report structs and sort helpers
4. `crane`: Refactor transform command to emit kustomization.yaml + patches
5. `crane`: Add deterministic ordering and naming for overlay artifacts
6. `crane`: Refactor apply command to execute kubectl kustomize only
7. `crane`: Add apply preflight checks and output file behavior
8. `crane+crane-lib`: Add fixture parity suite (plugin compatibility + edge cases)
9. `docs`: Update usage docs and migration notes for kustomize-only mode

---

## Milestones

## M1 — Foundations (crane-lib)
- A1, A2 complete

## M2 — Transform end-to-end
- B1, B2, B3 complete

## M3 — Apply end-to-end
- C1, C2, C3 complete

## M4 — Hardening + docs
- D1, D2, E1, E2 complete

---

## Definition of Done (overall)

- [ ] `crane transform` outputs valid Kustomize overlay artifacts only.
- [ ] `crane apply` renders only via `kubectl kustomize`.
- [ ] Existing plugins work without immediate code changes.
- [ ] CI includes compatibility + edge-case regression suites.
- [ ] Docs and migration notes are published.
