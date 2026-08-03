# Enhancement Review: BuildConfig to Shipwright Conversion Plugin

Review of [konveyor/enhancements#300](https://github.com/konveyor/enhancements/pull/300) based on API-level comparison between OpenShift BuildConfig (`build.openshift.io/v1`) and Shipwright Build (`shipwright.io/v1beta1`), and analysis of the existing PoC in [crane-lib/convert](https://github.com/migtools/crane-lib/tree/main/convert).

---

## Critical: Nonexistent Buildah Strategy Parameters

The enhancement (and the PoC it builds on) maps several BuildConfig fields to buildah ClusterBuildStrategy parameters that **do not exist** in the [upstream strategy definition](https://github.com/shipwright-io/build/tree/main/samples/v1beta1/buildstrategy/buildah). A Shipwright Build referencing undefined parameters will fail at submission time.

### Affected mappings

| BuildConfig Field | Mapped To (PoC/Enhancement) | Exists in Upstream Buildah? |
|---|---|---|
| `dockerStrategy.from` | `paramValues: runtime-stage-from` | No |
| `dockerStrategy.noCache` | `paramValues: no-cache` | No |
| `dockerStrategy.forcePull` | `paramValues: pull = "always"` | No |
| `dockerStrategy.imageOptimizationPolicy` | `paramValues: squash = "true"` | No |

The upstream `buildah` strategy only defines: `dockerfile`, `build-args`, `target`, `storage-driver`, `registries-block`, `registries-insecure`, `registries-search`.

### Suggested resolution

The enhancement should pick one of these approaches and document it explicitly:

**Option A — Ship a custom ClusterBuildStrategy.** Define a `crane-buildah` strategy that extends upstream `buildah` with the additional parameters (`from`, `no-cache`, `pull`, `squash`). The plugin would reference `crane-buildah` by default. This is the most complete solution but adds a deployment dependency.

**Option B — Use buildah CLI arguments via `build-args`.** Some of these can be handled via buildah's own CLI flags passed through the existing `build-args` parameter (e.g., `--layers=false` for noCache, `--pull=always` for forcePull, `--squash` for squash). The `from` base image is harder — it would require rewriting the Dockerfile's `FROM` line, which conflicts with the offline/non-destructive principle.

**Option C — Move these to the "Known unsupported fields" table.** Accept that these features can't be mapped without a custom strategy and document them as gaps with clear warnings.

The conversion example in the enhancement currently shows `runtime-stage-from` in the output YAML — this must be updated to match whichever approach is chosen.

---

## Missing Field Mappings With Direct Equivalents

Five BuildConfig fields have trivial 1:1 Shipwright equivalents. They are neither in the enhancement's scope nor listed as known gaps — they are simply absent from the document.

| BuildConfig Field | Shipwright Field | Mapping Complexity |
|---|---|---|
| `completionDeadlineSeconds` | `spec.timeout` | Trivial — convert `int64` seconds to `metav1.Duration` |
| `successfulBuildsHistoryLimit` | `spec.retention.succeededLimit` | Trivial — `*int32` to `*uint` |
| `failedBuildsHistoryLimit` | `spec.retention.failedLimit` | Trivial — `*int32` to `*uint` |
| `nodeSelector` | `spec.nodeSelector` | Trivial — identical `map[string]string` type |
| `output.imageLabels` | `spec.output.labels` | Trivial — `[]ImageLabel` (name/value) to `map[string]string` |

### Suggested resolution

Add these to the field mapping tables in the enhancement. They require minimal implementation effort and significantly improve conversion completeness. If any are intentionally deferred, add them to the "Known unsupported fields" table with a rationale.

---

## Resource Limits Mapping Is Mischaracterized

The "Known unsupported fields" table states: *"Resource limits (CPU/memory) — Shipwright supports resource overrides but mapping is not implemented in this version."*

This implies the mapping is impossible or impractical. In reality, Shipwright supports `spec.strategy.stepResources` which allows overriding CPU/memory per build step. The mapping is not trivial (BuildConfig sets limits per build, Shipwright sets them per step), but it's feasible.

### Suggested resolution

Change the table entry to: *"Resource limits (CPU/memory) — Shipwright supports per-step resource overrides via `strategy.stepResources`; mapping deferred to a future version because BuildConfig sets limits per build while Shipwright sets them per step."* This clarifies it's a design decision, not a limitation.

---

## Git Proxy Handling Is Underspecified

The source mapping table states that `git.httpProxy/httpsProxy` maps to a warning because Shipwright's Git clone runs in a separate container and proxy must be configured at the cluster level via `GIT_CONTAINER_TEMPLATE`.

However, the existing PoC already implements a practical workaround: it converts proxy settings to `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` environment variables on the Build spec (`spec.env`). This approach works because Shipwright injects `spec.env` into all build steps.

### Suggested resolution

Document the env var injection approach in the source mapping table instead of (or in addition to) the warning. Update the entry to:

| BuildConfig Source | Shipwright Source | Notes |
|---|---|---|
| `git.httpProxy/httpsProxy/noProxy` | `spec.env: HTTP_PROXY, HTTPS_PROXY, NO_PROXY` | Injected as build env vars. Warning emitted that cluster-level Git container proxy config may also be needed for the clone step. |

---

## Plugin Flags Missing Review-Agreed Options

The PR review discussion with @rromannissen agreed on a layered ImageStream resolution approach requiring specific flags. The Open Questions section was updated to reflect this decision, but the "Plugin flags" section in Implementation Details still lists the old flag set.

### Current (incomplete)

```
--search-registries
--insecure-registries
--block-registries
--strategy-mapping
```

### Missing flags from review decisions

| Flag | Purpose | Agreed In |
|---|---|---|
| `--registry-mapping` | Explicit ImageStreamTag → registry URL mapping (highest priority in layered fallthrough) | Open Question 1 resolution |
| `--imagestream-mapping` | Path to co-exported ImageStream data for offline resolution | Open Question 1 resolution |
| `--default-build-strategy` | Override default ClusterBuildStrategy name (complements `--strategy-mapping`) | Open Question 2 resolution |

### Suggested resolution

Update the plugin flags section to include all agreed flags and document the layered fallthrough order:

1. `--registry-mapping` (explicit override, highest priority)
2. `--imagestream-mapping` (co-exported ImageStream data)
3. Fallback to internal OpenShift registry URL pattern with warning

---

## Conversion Example Inconsistency

The example output YAML shows `runtime-stage-from` in `paramValues`, but:
- The "Strategy mapping" table says "base image mapped" without specifying the param name
- The "Source mapping" table doesn't mention this field at all
- As noted above, this param doesn't exist in upstream buildah

### Suggested resolution

After resolving the nonexistent params issue (see first section), update the conversion example to match the chosen approach. If the `from` base image can't be mapped, remove it from the example and add a comment showing what was lost.

---

## Minor: Unsupported Strategy Handling Flow

The enhancement states that unsupported strategies (Custom, JenkinsPipeline) produce a "warning + passthrough." The conversion logic section says:

> 1. Whiteout the original BuildConfig
> 2. Generate a new Shipwright Build CR

This ordering means the whiteout happens before strategy validation. If the strategy is unsupported, the BuildConfig would be whiteout'd without a replacement — effectively deleting it.

### Suggested resolution

The processing flow should check strategy support **before** creating the whiteout:

1. Check strategy type
2. If unsupported → return empty response (passthrough) with warning
3. If supported → whiteout original + generate Shipwright Build

This was flagged by CodeRabbit in the PR review and acknowledged but it's worth verifying the enhancement text reflects the corrected flow.

---

## Minor: `--strategy-mapping` Flag Format

The enhancement mentions `--strategy-mapping` to override ClusterBuildStrategy names but doesn't specify the expected format. The local proposal document shows `docker=my-buildah,s2i=my-s2i` as an example.

### Suggested resolution

Add the format to the enhancement: `--strategy-mapping docker=<name>,s2i=<name>` with an example.

---

## Summary

| # | Issue | Severity | Action |
|---|---|---|---|
| 1 | Nonexistent buildah strategy params (`runtime-stage-from`, `no-cache`, `pull`, `squash`) | Critical | Pick approach (custom strategy / CLI args / mark unsupported), update example |
| 2 | Five trivial field mappings missing from scope | Medium | Add to field mapping tables or explicitly defer |
| 3 | Resource limits mischaracterized as unsupported | Low | Reword to "deferred" with rationale |
| 4 | Git proxy handling underspecified | Low | Document env var injection approach from PoC |
| 5 | Plugin flags missing review-agreed options | Medium | Add `--registry-mapping`, `--imagestream-mapping` |
| 6 | Conversion example uses nonexistent param | Critical | Update after resolving #1 |
| 7 | Unsupported strategy whiteout ordering | Low | Clarify flow: check strategy before whiteout |
| 8 | `--strategy-mapping` format unspecified | Low | Add format and example |
