# Draft CLI Specification: Stepwise Plugin Pipeline for `crane transform` and `crane apply`

## Status

Draft

## Scope

This document specifies CLI behavior for stage-aware execution where each plugin (including default Kubernetes transforms) is represented as an ordered pipeline stage.

Related drafts:
- `crane-transform-apply-stepwise-plugin-pipeline-draft.md`
- `crane-kustomize-ondisk-layout-rfc-draft.md`

---

## Terminology

- **Stage**: one plugin execution unit with its own Kustomize overlay and rendered output.
- **Stage ID**: filesystem/stable identifier in format:
  - `<priority>_<pluginName>[:<comment>]`
- **Pipeline**: ordered list of stages persisted in `pipeline.yaml`.

---

## General Rules

1. Kustomize-only workflow.
2. Default Kubernetes stage is mandatory and first by default.
3. Stage order is deterministic:
   - primary: numeric priority asc
   - secondary: plugin name asc
4. Every stage has isolated artifacts under:
   - `<transform-dir>/stages/<stage-id>/...`

---

## `crane transform` CLI

## Command

```bash
crane transform [flags]
```

## Core flags

- `--export-dir <path>` (default: `export`)
- `--transform-dir <path>` (default: `transform`)
- `--plugin-dir <path>`
- `--skip-plugins <name1,name2,...>`
- `--plugin-priorities <name1,name2,...>`
- `--optional-flags <json>`

## New stage-aware flags

- `--pipeline-config <path>`
  - Optional YAML file defining stage priority/comment/enabled defaults.

- `--list-stages`
  - Print resolved stage plan and exit (no files written).

- `--stage <stage-id>`
  - Transform only one stage.

- `--from-stage <stage-id>`
  - Transform from given stage through end.

- `--to-stage <stage-id>`
  - Transform from start through given stage.

- `--stages <id1,id2,...>`
  - Transform only explicit stage set (preserving pipeline order among selected).

- `--stage-comment <plugin=comment,...>`
  - Override generated stage comments by plugin name.

- `--resume`
  - Continue from first incomplete stage based on on-disk artifacts.

## Selection precedence

If more than one selector is provided, evaluation order MUST be:

1. `--stage`
2. `--stages`
3. `--from-stage`/`--to-stage`
4. `--resume`
5. default full pipeline

Conflicting selectors at same level MUST fail.

## Transform outputs per stage

For each executed stage:

- `kustomization.yaml`
- `patches/*.patch.yaml`
- optional `reports/ignored-patches.json`
- optional `whiteouts/whiteouts.json`
- `rendered.yaml` (output of `kubectl kustomize` for chaining)

Pipeline index at root:

- `<transform-dir>/pipeline.yaml`

---

## `crane apply` CLI

## Command

```bash
crane apply [flags]
```

## Core flags

- `--transform-dir <path>` (default: `transform`)
- `--output-dir <path>` (optional)

## Stage-aware flags

- `--list-stages`
- `--stage <stage-id>`
- `--from-stage <stage-id>`
- `--to-stage <stage-id>`
- `--stages <id1,id2,...>`
- `--resume`

Selection semantics MUST match `crane transform`.

## Apply behavior

- Default: execute selected stage chain in order.
- Each stage render command:
  - `kubectl kustomize <transform-dir>/stages/<stage-id>`
- Persist stage render result to stage `rendered.yaml`.
- Final output:
  - stdout if `--output-dir` absent
  - `<output-dir>/all.yaml` if present

---

## Pipeline Config File (`--pipeline-config`)

## Example

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
    comment: registry_rewrite
    enabled: false
```

## Merge order

1. built-in defaults
2. pipeline config file
3. CLI overrides

---

## Error Cases (Normative)

## Invalid stage selectors

- stage not found -> exit non-zero with list of valid stage IDs
- mutually conflicting selectors -> exit non-zero with usage hint

## Invalid stage naming

- generated ID collision -> fail with explicit collision details
- invalid filesystem chars after normalization -> fail and report offending source values

## Missing prerequisites

- missing `kubectl` -> fail with install hint
- missing `pipeline.yaml` for apply -> fail with “run transform first” guidance
- missing prior stage output during selected apply chain -> fail with stage dependency message

## Render failures

- any `kubectl kustomize` non-zero exit -> fail immediately with stage ID and stderr

---

## Exit Codes (Proposed)

- `0` success
- `2` usage/validation error
- `3` pipeline/stage resolution error
- `4` external dependency error (kubectl missing)
- `5` render/transform execution failure

---

## Examples

## List stages

```bash
crane transform --export-dir export --transform-dir transform --list-stages
```

## Transform full pipeline

```bash
crane transform --export-dir export --transform-dir transform
```

## Transform one stage

```bash
crane transform --transform-dir transform --stage 20_openshift:route_adjustments
```

## Transform stage window

```bash
crane transform --transform-dir transform --from-stage 20_openshift:route_adjustments --to-stage 30_imagestream:registry_rewrite
```

## Apply selected stages and write output file

```bash
crane apply --transform-dir transform --stages 20_openshift:route_adjustments,30_imagestream:registry_rewrite --output-dir output
```

---

## Acceptance Criteria

- [ ] Stage selection behavior is identical between transform and apply.
- [ ] Selection precedence and conflicts are documented and enforced.
- [ ] Errors are actionable and include stage IDs.
- [ ] CLI behavior is deterministic and test-covered.
