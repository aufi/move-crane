# Proposal: Add `crane discover` for pre-export migration scoping and planning

## Status
Draft proposal

## Summary
Introduce a new command, `crane discover`, as a pre-export step to help users:
1. inspect source-cluster resources relevant to migration,
2. iteratively define and test selectors (for example labels/namespaces),
3. optionally generate migration-plan guidance for a specific target cluster via `--plan-target`.

This proposal intentionally keeps `discover` read-only and planning-focused.

---

## Problem
Current migration workflows often start directly with export. Some users might need an explicit discovery step first:
- to understand what exists in source,
- to constrain migration scope safely,
- to identify obvious target-side risks early.

Without this, users discover scope/mapping problems late in the pipeline (after export/transform/apply), increasing iteration cost.

---

## Goals
1. Provide a fast inventory view of migratable resources in source cluster.
2. Provide a selector playground to define migration scope confidently.
3. Optionally provide target-aware planning guidance via `--plan-target`.
4. Produce machine-readable outputs that can be consumed by scripts and/or `crane-runner` (TBD).

## Non-goals
- No direct mutation of source/target clusters.
- No automatic migration execution.
- No replacement of `export`, `transform`, `apply`, or `validate`.

---

## Proposed CLI

### Base command
```bash
crane discover [flags]
```

### Core flags (initial)
- `--source-context <name>`: kubeconfig context for source cluster.
- `--namespace <ns>[,<ns>...]`: namespace filter.
- `--all-namespaces`: include all namespaces.
- `--selector <label-selector>`: Kubernetes label selector.
- `--include-gvk <gvk>[,<gvk>...]`: optional explicit include list.
- `--exclude-gvk <gvk>[,<gvk>...]`: optional explicit exclude list.

### Target planning mode
```bash
crane discover ... --plan-target <target-context>
```

`--plan-target` is intentionally named to signal migration-plan preparation for a destination cluster.

---

## Functional behavior

## 1) Source inventory (default mode)
`discover` should output:
- resource counts by namespace and GVK,
- notable migration-impacting kinds (e.g., PVC, Route, DeploymentConfig, Ingress, CRDs),
- optional summary scores (stateful footprint, API diversity).

The output should be deterministic and script-friendly in JSON mode.

## 2) Selector playground
Users should be able to iterate filters quickly and see resulting scope.

Examples:
```bash
crane discover --source-context src --namespace app-a --selector "team=payments"
crane discover --source-context src --all-namespaces --include-gvk "apps/v1/Deployment,v1/Service"
```

Expected UX:
- clear summary of what is included/excluded,
- no side effects,
- stable output schema for CI tooling.

## 3) Target-aware planning (`--plan-target`, TBD)
When provided, `discover` should augment source inventory with planning guidance for target cluster:
- API support checks for discovered GVKs,
- highlight likely mapping requirements (e.g., StorageClass, namespace policy differences),
- identify likely identity-conversion candidates (e.g., Route/DeploymentConfig patterns),
- produce recommended next steps and command hints.

This mode should produce a plan-oriented artifact (e.g., `plan.json` / `plan.yaml`) suitable as input to later workflow stages.

---

## Output artifacts
Recommended output:
- console stdout (resolved selectors and selected objects summary)
- optional with `--plan-target`:
  - `migration-plan-hints.json` (or yaml)
  - `mapping-suggestions.json` (or yaml)

---

## Relationship to `crane-runner`
`crane discover` could help with planning/intelligence step before execution pipelines.

Recommended integration path:
1. `discover` creates scope + plan artifacts.
2. `crane-runner` consumes these artifacts as pipeline inputs.
3. execution tasks (`export`, `transform`, `apply`, `validate`) run with explicit, pre-reviewed scope.

This keeps responsibilities clean:
- `discover` = read-only analysis and planning,
- `crane-runner` = orchestration/execution.

---

## Example workflows

### A) Source-only scoping
```bash
crane discover \
  --source-context src \
  --all-namespaces \
  --selector "app.kubernetes.io/part-of=shop"
```

### B) Target plan preparation
```bash
crane discover \
  --source-context src \
  --namespace shop-prod \
  --selector "tier!=debug" \
  --plan-target dst
```

---

## MVP scope
1. Implement source inventory with namespace/label filtering.
2. Implement selector playground UX and stable output.
3. Implement `--plan-target` with basic target capability checks and plan hints.
4. Publish output schema docs for `discover` artifacts.

---

## Future extensions
- optional risk scoring model,
- richer mapping templates,
- direct handoff command generation for scripted pipelines,
- provider-specific planning packs.

---

## Expected impact
Adding `crane discover` should reduce failed migration iterations by shifting scope and compatibility decisions earlier, while remaining fully compatible with existing `export -> transform -> apply -> validate` flows and `crane-runner` orchestration.
