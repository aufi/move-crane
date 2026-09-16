# DeploymentConfig to Deployment Conversion: Implementation Plan

## Status

Draft implementation plan for [migtools/crane#929](https://github.com/migtools/crane/issues/929).

## Goal

Add an opt-in transformation to `crane-plugin-openshift` that replaces an OpenShift
`apps.openshift.io/v1` `DeploymentConfig` with a Kubernetes `apps/v1` `Deployment`.
The conversion must be deterministic, auditable, and safe when unsupported behavior is
encountered.

## Key Decisions

- Implement the conversion in the existing `OpenShiftPlugin`.
- Enable it with `convert-deploymentconfigs=true`; keep the default `false` to preserve
  existing OpenShift-to-OpenShift workflows.
- Use `PluginResponse.IsWhiteOut` and `PluginResponse.NewResources` rather than changing
  `apiVersion` and `kind` through JSONPatch.
- Never whiteout a DeploymentConfig unless a valid replacement was generated.
- Record conversion warnings both in plugin logs and in an annotation on the generated
  Deployment.
- Skip unsafe conversions and leave the original DeploymentConfig active with status and
  reason annotations.

## Supported Conversion

Map the following fields:

| DeploymentConfig field | Deployment field |
|---|---|
| `metadata.name`, `namespace`, labels, annotations | Equivalent metadata fields |
| `spec.replicas` | `spec.replicas` |
| `spec.selector` | `spec.selector.matchLabels` |
| `spec.template` | `spec.template` |
| `spec.minReadySeconds` | `spec.minReadySeconds` |
| `spec.revisionHistoryLimit` | `spec.revisionHistoryLimit` |
| `spec.paused` | `spec.paused` |
| `Rolling` strategy | `RollingUpdate` strategy |
| `maxSurge`, `maxUnavailable` | Equivalent rolling update fields |
| `Recreate` strategy | `Recreate` strategy |

Treat an empty DeploymentConfig strategy type as the OpenShift default `Rolling` strategy.
Preserve PVC `claimName` references and apply the existing `pvc-rename-map` option before
creating the Deployment.

Do not copy server-managed metadata, owner references, finalizers, or `status`. Apply the
existing OpenShift security-context cleanup to the generated Deployment.

## Unsupported Behavior

Skip conversion by default when the DeploymentConfig uses behavior whose removal could
change application correctness:

- `Custom` strategy or `customParams`
- pre, mid, or post lifecycle hooks
- `spec.test: true`
- missing pod template
- a selector that cannot validly select the pod template

Convert with actionable warnings when dropping behavior that does not prevent creating a
usable Deployment:

- `ImageChange` triggers
- rolling update period, polling interval, or timeout
- deployer resources, labels, annotations, or active deadline

A `ConfigChange` trigger requires no replacement because a Kubernetes Deployment already
rolls out when its pod template changes. Document the behavioral differences for manual
rollouts, image automation, rollback history, and lifecycle hooks.

## Implementation Steps

### 1. Update `crane-plugin-openshift`

- Upgrade `github.com/konveyor/crane-lib` to a revision containing `NewResources`.
- Add and parse the `convert-deploymentconfigs` optional flag.
- Add a focused converter returning a Deployment, warnings, and a supported/skipped result.
- Match the full source GVK, not only `kind: DeploymentConfig`.
- On success, return the original resource as whiteout and the Deployment in
  `NewResources`.
- On skip, keep the DeploymentConfig active and add deterministic conversion status and
  reason annotations through patches.
- Add a size-capped conversion warnings annotation to successful output.
- Update the plugin README and add a field support matrix.

### 2. Reject generated-resource collisions in `crane`

- Detect a generated Deployment that has the same GVK, namespace, and name as an existing
  active resource.
- Fail the transform with an actionable error instead of relying on writer ordering or
  last-occurrence-wins behavior.
- Add a regression test for the collision.

### 3. Integration and Release

- Add an end-to-end fixture containing a DeploymentConfig, Service, and PVC reference.
- Run `KubernetesPlugin` before `OpenShiftPlugin`, then verify `crane apply` produces only
  the replacement Deployment.
- Validate the generated manifests against a Kubernetes target or server-side dry run.
- Document `crane v0.11.0-alpha.1` or newer as the minimum supported Crane version.
- Publish and register a compatible OpenShift plugin release.

## Test Coverage

- Conversion disabled by default
- Exact source GVK matching
- Rolling, default Rolling, and Recreate strategies
- Selectors, pod templates, metadata, replicas including zero, and paused workloads
- Containers, probes, environment variables, resources, ServiceAccounts, and PVCs
- PVC rename mapping
- ImageChange and other lossy-field warnings
- Safe skip for custom strategies, lifecycle hooks, test mode, and invalid input
- No whiteout when conversion is skipped or fails
- Removal of runtime metadata and status
- Deterministic output and repeat execution
- Collision with an existing Deployment
- End-to-end transform, apply, and validate flow

## Compatibility Risk

An older Crane binary ignores the unknown `newResources` response field but still honors
`isWhiteOut`. Running the new conversion with such a binary could therefore remove the
DeploymentConfig without creating its replacement. The opt-in default and documented
minimum Crane version are required safeguards. A future plugin protocol capability check
would be the complete solution, but is outside this issue.

## Completion Criteria

- Existing OpenShift plugin behavior is unchanged unless conversion is explicitly enabled.
- Supported DeploymentConfigs produce valid `apps/v1` Deployments.
- Unsupported DeploymentConfigs remain in output with an actionable reason.
- Every dropped semantic is visible in logs, annotations, or documentation.
- No source resource is whiteouted without a valid, non-conflicting replacement.
