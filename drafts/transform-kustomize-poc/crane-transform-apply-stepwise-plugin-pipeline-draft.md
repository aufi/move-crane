# Draft Proposal: Stepwise `crane transform`/`crane apply` Pipeline by Plugin Stages

## Summary

This proposal introduces a **multi-stage pipeline** model for `crane transform` and `crane apply`.

Instead of generating one combined transform output, each plugin (including default Kubernetes behavior) produces its own stage directory with:

- plugin-specific Kustomize overlay artifacts
- plugin-specific apply/render output

Stages are independent, ordered, and chainable.

---

## Motivation

Current flow merges all plugin effects into one transform/apply step. That is efficient, but hard to inspect, debug, and selectively run.

A staged model provides:

- clear provenance of changes by plugin
- easier troubleshooting and diffing
- selective execution per plugin/stage
- repeatable migration pipelines where each stage is explicit

---

## Core Design

## 1) Stage-per-plugin model

Each plugin maps to one stage directory.

The default Kubernetes transforms become the first mandatory stage.
Optional plugins (OpenShift, ImageStream, custom) are subsequent stages.

Each stage consumes previous stage output and produces next stage output.

---

## 2) Stage naming convention

Directory format:

```text
<priority>_<pluginName>[:<comment>]
```

Examples:

- `10_kubernetes:default_cleanup`
- `20_openshift:route_adjustments`
- `30_imagestream:registry_rewrite`

Rules:

- `priority` is zero-padded integer for lexical sorting (recommended width: 2–3 digits).
- `pluginName` must match plugin metadata name (normalized for filesystem safety).
- `comment` is optional, human-friendly, and non-semantic.

---

## 3) On-disk pipeline layout

Proposed structure under `--transform-dir`:

```text
transform/
  pipeline.yaml
  stages/
    10_kubernetes:default_cleanup/
      kustomization.yaml
      patches/
      reports/
      whiteouts/
      rendered.yaml
    20_openshift:route_adjustments/
      kustomization.yaml
      patches/
      reports/
      whiteouts/
      rendered.yaml
    30_imagestream:registry_rewrite/
      kustomization.yaml
      patches/
      reports/
      whiteouts/
      rendered.yaml
  final/
    rendered.yaml
```

Notes:
- `rendered.yaml` in each stage is the output of `kubectl kustomize` for that stage.
- Next stage uses previous stage `rendered.yaml` as its resource input.
- `final/rendered.yaml` equals output of last executed stage.

---

## 4) Pipeline manifest (`pipeline.yaml`)

A machine-readable index for orchestration and selective execution.

Example:

```yaml
apiVersion: crane.konveyor.io/v1alpha1
kind: TransformPipeline
stages:
  - id: 10_kubernetes:default_cleanup
    plugin: KubernetesPlugin
    priority: 10
    required: true
    enabled: true
    input: ../export
    output: stages/10_kubernetes:default_cleanup/rendered.yaml
  - id: 20_openshift:route_adjustments
    plugin: OpenShiftPlugin
    priority: 20
    required: false
    enabled: true
    input: stages/10_kubernetes:default_cleanup/rendered.yaml
    output: stages/20_openshift:route_adjustments/rendered.yaml
```

---

## CLI Changes

## `crane transform`

### New behavior

- Build ordered stage plan.
- For each stage:
  - run only that plugin against current input set
  - write stage Kustomize artifacts
  - optionally pre-render stage output (`kubectl kustomize`) for chaining

### Suggested flags

- `--stage <stage-id>`: run only one stage
- `--from-stage <stage-id>`: run from stage to end
- `--to-stage <stage-id>`: run from start to a stage
- `--stages <id1,id2,...>`: run selected stages only
- `--list-stages`: print planned stage order
- `--stage-comment <plugin=comment,...>`: annotate generated stage IDs

---

## `crane apply`

### New behavior

- Apply/render is stage-aware.
- Can execute full chain or selected stage window.
- Default behavior: run all enabled stages in order.

### Suggested flags

- `--stage <stage-id>`
- `--from-stage <stage-id>`
- `--to-stage <stage-id>`
- `--stages <id1,id2,...>`
- `--resume`: continue from first incomplete stage

---

## Execution Semantics

## Stage ordering

- Primary sort key: numeric `priority`
- Tie-breaker: plugin name
- Kubernetes default stage is always first (priority default `10`)

## Input/output chaining

- Stage 1 input: `--export-dir`
- Stage N input: stage N-1 `rendered.yaml`

## Whiteout semantics

- Whiteouts remain stage-local decisions that remove resources from that stage output.
- Downstream stages never see whiteouted resources unless explicitly restored (not supported in v1).

## Conflict semantics

- Intra-stage conflicts: resolved as today (within that plugin output context).
- Inter-stage conflicts are naturally represented by sequential overlays and render outputs.

---

## Plugin Model Impact

## v1 (minimal disruption)

No plugin protocol changes required.

- Existing plugins still emit JSONPatch operations.
- Crane converts each plugin output to that stage’s Kustomize patch files.

## v2 (optional future)

Allow plugins to emit richer stage metadata:
- recommended stage comment
- required/optional status
- suggested default priority

---

## Configuration Model

Add optional pipeline config file (example `transform-pipeline.yaml`):

```yaml
defaultStagePriority: 10
plugins:
  KubernetesPlugin:
    priority: 10
    comment: default_cleanup
    enabled: true
  OpenShiftPlugin:
    priority: 20
    comment: route_adjustments
    enabled: true
  ImageStreamPlugin:
    priority: 30
    enabled: false
```

CLI flags override file values.

---

## Benefits

- Strong traceability per plugin stage
- Easier partial reruns
- Better CI pipelines (stage-by-stage validation)
- Better troubleshooting (inspect stage-local patches/reports/output)
- Cleaner handoff between teams (platform vs app migration logic)

---

## Risks & Mitigations

1. **More files and directories**
   - Mitigation: stable structure + `pipeline.yaml` index + cleanup command.

2. **Longer runtime (multiple kustomize renders)**
   - Mitigation: support `--stage` and `--resume`; add caching in later iteration.

3. **State drift between stages**
   - Mitigation: stage outputs are immutable artifacts with checksum tracking.

4. **Complexity in selective execution**
   - Mitigation: explicit CLI semantics and strong validation for stage selection.

---

## Implementation Outline

## Phase 1 — Stage scaffolding
- add pipeline planner
- generate stage dirs and `pipeline.yaml`
- implement stage naming convention

## Phase 2 — Stage transform execution
- run one plugin per stage
- generate stage kustomization + patches + reports
- produce stage rendered output

## Phase 3 — Stage-aware apply
- add stage window flags (`--from-stage`, `--to-stage`, etc.)
- run apply/render over selected stage chain

## Phase 4 — Hardening
- determinism tests for naming/order
- resume/restart behavior
- docs and examples

---

## Acceptance Criteria

- [ ] Each plugin (including default Kubernetes) gets its own stage subdirectory.
- [ ] Stage directory names follow `<priority>_<pluginName>[:<comment>]`.
- [ ] Transform can run full pipeline or selected stages.
- [ ] Apply can run full pipeline or selected stages.
- [ ] Stage outputs are chainable and reproducible.
- [ ] Existing plugins remain functional without protocol rewrite.

---

## Example End-to-End

```bash
crane transform \
  --export-dir export \
  --transform-dir transform \
  --pipeline-config transform-pipeline.yaml

crane apply \
  --transform-dir transform \
  --from-stage 20_openshift:route_adjustments
```

This would execute from OpenShift stage onward, using prior stage artifacts as input.
