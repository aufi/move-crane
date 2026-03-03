# Crane CLI Redesign Proposal: Unified `transform` Workflow + `validate-target`

## Status
Draft proposal

## Motivation
Today, users typically run:
1. `crane transform`
2. `crane apply`

This works, but migration workflows (especially across heterogeneous clusters) need a tighter loop between:
- transformation,
- render/apply preparation,
- target compatibility validation,
- iterative adjustment when incompatibilities are detected.

This proposal introduces:
- a unified `transform` command group,
- a new `validate-target` command,
- an iterative orchestration mode driven by a target context.

---

## Goals
1. Keep existing behavior available and familiar.
2. Provide a first-class iterative migration loop.
3. Detect target incompatibilities early and report them clearly.
4. Enable deterministic, auditable auto-adjustment with plugin-based remediation.
5. Stop safely when no known remediation exists.

## Non-goals
- Fully automatic conversion for all Kubernetes/OpenShift differences.
- Replacing external capacity planning tools for deep infra sizing.
- Hiding unresolved errors; unresolved states must remain explicit.

---

## Proposed CLI Shape (revised)

Primary documented flow:
1. `crane transform prepare`
2. `crane transform apply`
3. `crane validate-target --target-context <context-name>`

`validate-target` returns actionable errors/findings; orchestration remains user-scripted.

## `crane transform` (command group)

### `crane transform prepare`
Equivalent to current `crane transform`.
- Input: `export-dir`, plugin config, optionals.
- Output: transform patches, whiteouts, optional ignored patch artifacts.

### `crane transform apply`
Equivalent to current `crane apply`, but nested under `transform`.
- Input: `export-dir`, `transform-dir`.
- Output: rendered manifests in `output-dir`.

### `crane transform target-context <context>` (optional, discussion track)
Candidate orchestration mode for future discussion.
- Not part of the required initial scope.
- If implemented later, it may run an iterative flow (`prepare -> apply -> validate-target -> remediate`).
- For now, users can script orchestration externally using `prepare`, `apply`, and `validate-target`.

---

## New Top-level Command: `crane validate-target`

Purpose: verify that manifests intended for import (typically from `output-dir`, after at least one `transform apply`) are importable into a target cluster.

### Suggested interface
```bash
crane validate-target \
  --target-context <context> \
  --input-dir <output-dir> \
  [--export-dir <export-dir>] \
  [--storage-class-map <src=dst,...>] \
  [--format json|table] \
  [--fail-on-warn]
```

### Validation domains

#### 1) Target reachability, authentication, and create permissions
Checks:
- kubeconfig context exists,
- API server reachable,
- auth token/cert valid,
- discovery access is available,
- the user/service account can `create` every resource type (GVK/resource endpoint) present in the exported/input manifests.

Implementation note:
- perform a SubjectAccessReview-style check (`can-i create`) per discovered target resource mapped from the input objects,
- report missing create permissions as hard failures before deeper compatibility checks.

Fail examples:
- unknown context,
- x509/auth errors,
- timeout/unreachable API endpoint,
- RBAC denies `create` for one or more required resource types.

#### 2) Resource API compatibility and creatability
Checks:
- every object GVK from input manifests is discoverable on target,
- API version compatibility (preferred + served versions),
- server-side dry-run create/apply viability,
- key dependencies exist or are mappable (e.g., StorageClass references).

Includes:
- unknown kinds (e.g., OpenShift-only resources on upstream),
- unsupported/deprecated API versions,
- schema validation failures,
- immutable field conflicts (reported as actionable failures/warnings).

#### 3) Sizing / capacity fit
Checks (best-effort, explicit confidence level):
- PVC requested storage vs target storage class/quota constraints,
- aggregate CPU/memory requests vs allocatable capacity and quotas,
- optional node-placement feasibility hints (taints/affinity/topology).

Output should classify certainty:
- `hard-fail`: definitely insufficient (quota exceeded, impossible request),
- `warn`: uncertain estimate (insufficient telemetry, dynamic autoscaling dependencies),
- `pass`.

---

## Iterative Remediation in `transform target-context`

## Core behavior
The orchestration must be deterministic and auditable.
- Rule-driven mapping from `validate-target` findings to remediation actions.
- No silent changes.
- Every iteration emits artifacts.

### Example remediation mapping (initial set)
- Missing `route.openshift.io/Route` on target:
  - activate `RouteToIngress` plugin (if available).
- Missing `apps.openshift.io/DeploymentConfig`:
  - activate `DeploymentConfigToDeployment` plugin.
- StorageClass not found:
  - apply `StorageClassMap` plugin/options.
- PodSecurity/SCC-related incompatibility:
  - apply `SecurityContextAdjust` plugin profile.

### Stop conditions
- `PASS`: all required checks pass.
- `UNRESOLVED`: failures remain but no remediation rule applies.
- `MAX_ITERATIONS`: safety stop after configurable loop count (default 5).

---

## Artifacts and Reporting

For each run, write machine-readable and human-readable artifacts:
- `artifacts/transform-report.<iteration>.json`
- `artifacts/apply-report.<iteration>.json`
- `artifacts/validate-target-report.<iteration>.json`
- `artifacts/iteration-summary.md`

Final summary should include:
- iteration count,
- applied remediations,
- remaining blockers,
- final status (`PASS`, `UNRESOLVED`, `MAX_ITERATIONS`).

---

## Backward Compatibility Plan

1. Keep `crane transform` behavior as alias to `crane transform prepare`.
2. Keep `crane apply` as alias to `crane transform apply` (with deprecation notice).
3. Add deprecation window and release notes before alias removal (if ever).

---

## Suggested Exit Codes

- `0`: success (`PASS`)
- `2`: unresolved incompatibilities (`UNRESOLVED`)
- `3`: max iterations reached without success
- `4`: input/config error
- `5`: target connectivity/auth failure

Consistent exit codes make CI integration straightforward.

---

## Security and Safety Considerations

- `validate-target` must be read-only by default, using discovery and server dry-run.
- No mutation of target resources unless explicitly enabled in future modes.
- Clearly separate validation from execution.
- Sanitized logs for secrets and credentials.

---

## Implementation Notes (High-level)

- Reuse existing `transform` and `apply` internals where possible.
- Implement `validate-target` on top of client-go discovery + dry-run apply.
- Introduce a small remediation engine:
  - input: normalized check findings,
  - output: plugin toggles/options for next iteration.
- Keep remediation rules data-driven (configurable map), not hardcoded branches only.

---

## Open Questions

1. Should `validate-target` consume `output-dir` only, or allow direct `export-dir` checks too?
2. How strict should sizing checks be by default (`warn` vs `fail` thresholds)?
3. Where should remediation rule packs live (core vs external plugin pack)?
4. Should `transform target-context` support `--dry-run-loop` (plan only, no file overwrite)?

---

## Minimal MVP Scope

1. Add command aliases and nested structure:
   - `transform prepare`
   - `transform apply`
2. Add `validate-target --target-context <context-name>` with domains (1) and (2) first.
3. Ensure `validate-target` output is script-friendly (stable exit codes + JSON report).
4. Add domain (3) sizing checks in phase 2.
5. Keep `transform target-context` out of MVP (optional, future discussion).

---

## Expected Outcome

This redesign turns transform/apply from a linear two-step process into a practical migration loop that:
- validates target compatibility early,
- self-adjusts where safe and known,
- stops transparently when human intervention is needed.
