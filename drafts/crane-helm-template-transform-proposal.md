# Proposal: Add Helm template rendering support to `crane transform`

## Motivation

`crane transform` is currently strong at:
- patching existing resources,
- filtering resources through whiteouts,
- sequencing multiple transformation stages,
- materializing intermediate results through Kustomize.

What it does *not* provide well today is a true templating layer.

This becomes limiting in scenarios where a transform should:
- generate a new resource from structured input,
- reuse one set of values across multiple generated resources,
- support conditional generation,
- support loops or repeated blocks,
- express complex value substitution without encoding everything as low-level patches.

Typical examples include:
- generating Shipwright `Build` / `Task` resources from existing source resources,
- producing Tekton or CI-related resources from application metadata,
- generating replacement resources when a source resource is whiteouted,
- building richer transformation outputs than simple "patch existing object" logic.

For these use cases, Helm templating is a good fit:
- mature and widely understood,
- expressive enough for `if`, `range`, reusable helpers, and computed values,
- produces plain YAML that can be handed back to Kustomize and the existing Crane pipeline.

## Goal

Add support to `crane transform` for a stage that renders resources from Helm templates, while keeping Kustomize as the stage materialization and downstream composition engine.

In other words:

- Helm is used as a *generation layer*,
- Kustomize remains the *composition and patching layer*,
- Crane remains the *pipeline orchestrator*.

## High-level design

Introduce a new transform stage mode that can render Helm templates as part of a multi-stage transform pipeline.

Conceptually, a Helm-backed stage would work like this:

1. Stage input is the materialized output of the previous stage, just like any other stage.
2. Crane prepares values/config for Helm rendering.
3. Crane runs `helm template`.
4. The rendered YAML is written into the stage `resources/`.
5. Existing stage patches and Kustomize processing still apply.
6. The materialized output of this stage becomes input for the next stage.

This preserves the existing multi-stage contract:
- stage N consumes previous stage output,
- stage N produces a materialized output,
- stage N+1 consumes that output.

## Proposed use cases

### 1. Generate new resources from prior stage state

Example:
- source stage contains OpenShift `BuildConfig`,
- transform stage converts this into Shipwright `Build` resources,
- Helm templates make the output easier to express than a large set of patches.

### 2. Whiteout + replacement generation

Example:
- source resource is marked for whiteout,
- Helm stage generates one or more replacement resources,
- final output contains generated replacements instead of the original object.

### 3. Parameterized custom stages

Example:
- a custom stage wants to generate several related resources from shared values,
- instead of writing many repetitive YAML files by hand, the user maintains:
  - a Helm chart,
  - values,
  - optional Kustomize patches.

## Proposed stage model

There are two reasonable integration options.

### Option A: Helm-backed custom stage

Treat a stage as a custom stage with additional Helm metadata/config.

Example layout:

```text
transform/
└── 30_HelmShipwright/
    ├── chart/
    │   ├── Chart.yaml
    │   ├── values.yaml
    │   └── templates/
    │       └── build.yaml
    ├── resources/
    ├── patches/
    ├── kustomization.yaml
    └── .crane-stage.yaml
```

Where `.crane-stage.yaml` might declare:

```yaml
mode: helm
chartPath: ./chart
valuesFile: ./chart/values.yaml
releaseName: crane-stage
```

Behavior:
- Crane detects `mode: helm`,
- runs `helm template`,
- writes rendered manifests into `resources/`,
- then continues with normal stage materialization through Kustomize.

### Option B: Helm-backed plugin-like stage

A stage name or metadata maps to a built-in Helm renderer stage type.

Example:
- `40_HelmRenderer`
- or explicit stage config saying `renderer: helm`

This is more opinionated, but less flexible than stage-local config.

## Recommended direction

I recommend **Option A**:
- Helm support should be a property of a custom stage, not a hardcoded plugin naming convention.
- This keeps the model closer to the existing user-managed custom stage concept.
- It also makes the stage self-contained and easier to review and debug.

## Interaction with current Crane pipeline

### Input handling

A Helm-backed stage should still receive the current materialized output of the previous stage.

That means Crane may need to prepare Helm values from:
- static stage-local values files,
- optional stage config,
- optionally derived data from previous stage resources.

The simplest first version should support only:
- stage-local `chart/`
- stage-local `values.yaml`

No dynamic extraction from prior resources is required initially.

### Output handling

The Helm render result should be treated as generated stage resources.

Recommended flow:
1. Render Helm templates into YAML.
2. Split rendered YAML into per-resource files.
3. Store those files in `transform/<stage>/resources/`.
4. Let `kustomization.yaml` reference them as active resources.
5. Apply stage patches as usual.
6. Materialize with `kubectl kustomize` or `oc kustomize`.

This keeps the stage debuggable and consistent with the current multistage model.

### Apply behavior

No special behavior should be needed in `crane apply`.

As long as the stage produces standard Kustomize-compatible resources, apply can continue to operate on the final stage exactly as it does today.

## Why Helm instead of trying to extend pure Kustomize

Kustomize is good at:
- overlays,
- patches,
- transformations,
- deterministic composition.

It is not a true templating system.

While KRM functions could also solve this, Helm gives us:
- existing template language,
- existing user familiarity,
- immediate support for loops, conditionals, and helper templates,
- plain YAML output that fits naturally into the Crane stage model.

This avoids re-inventing a templating DSL inside Crane.

## MVP scope

A good minimal implementation would support:

1. A custom stage mode that declares Helm rendering.
2. Stage-local chart directory.
3. Stage-local values file.
4. `helm template` execution during transform.
5. Writing rendered output into stage `resources/`.
6. Preserving existing `patches/` and `kustomization.yaml` flow.
7. Compatibility with later stages and `crane apply`.

## Non-goals for initial version

These can come later:

- deriving Helm values automatically from prior stage objects,
- remote chart references,
- Helm dependency resolution beyond local charts,
- Helm release lifecycle semantics,
- full Helm runtime/install integration,
- replacing Kustomize with Helm entirely.

This proposal is specifically about:
- using Helm as a rendering/generation layer inside `crane transform`,
- not about turning Crane into a Helm deployment tool.

## Suggested UX

Possible CLI behavior:

```bash
crane transform --transform-dir transform --stage 30_HelmShipwright
```

Where Crane sees stage-local config and knows it is a Helm-rendered custom stage.

Possible stage config:

```yaml
apiVersion: crane.migtools.io/v1alpha1
kind: StageConfig
mode: helm
helm:
  chartPath: ./chart
  valuesFile: ./chart/values.yaml
  releaseName: crane-stage
```

## Benefits

- Adds real templating capability without abandoning the current multistage design.
- Keeps Crane pipeline semantics intact.
- Makes generation-heavy transforms much easier to express.
- Enables cleaner implementations for replacement-resource scenarios.
- Lets users keep using Kustomize patches after Helm rendering.
- Makes advanced transforms more maintainable than giant patch sets.

## Risks and review topics

- How stage config should be represented.
- Whether Helm-rendered files are always fully regenerated.
- How to preserve user-managed stage content vs generated content.
- Whether Helm should be an optional external dependency.
- How to keep rendered output deterministic and reviewable.
- How whiteout + generated replacement semantics should be defined.

## Recommendation

Add Helm template rendering as an optional generation mode for custom multistage transform stages.

This gives Crane:
- a real templating layer where needed,
- while preserving its existing strengths in staged transformation, whiteouts, and Kustomize-based materialization.
