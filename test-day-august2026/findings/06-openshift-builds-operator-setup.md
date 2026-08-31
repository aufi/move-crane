# Finding 06 — Preparing an OpenShift target for Shipwright Builds

**Scope:** secondary objective (BuildConfig → Shipwright). Getting a real
OpenShift cluster ready to *receive* the Shipwright `Build` resources the plugin
produces. Automated by `scripts/20-install-openshift-builds-operator.sh`.

## Starting point

Both test clusters (source and target) serve `build.openshift.io/v1`
(BuildConfig/Build) **natively**, but **neither ships Shipwright** — no
`shipwright.io` API group, no ClusterBuildStrategies. So the source can host the
BuildConfigs to convert, and the target needs Shipwright installed before it can
accept the converted Builds.

On OpenShift, Shipwright is delivered by the **OpenShift Builds** operator
(downstream Shipwright), available from the `redhat-operators` catalog as
`openshift-builds-operator` (v1.9.0, channel `latest`, AllNamespaces install
mode). Enabling it deploys the Shipwright build controller + webhook and the
`shipwright.io/v1beta1` CRDs via an `OpenShiftBuild/cluster` CR.

## Two gotchas worth flagging

### 1. Tekton is a hard prerequisite, and install order matters

The OpenShift Builds operator installs and its `OpenShiftBuild` reconciles, but
the `ShipwrightBuild` sub-reconcile fails hard until Tekton is present:

```
ERROR  Reconciler error  ...  error: "tekton operator not installed"
```

Tekton on OpenShift is the **OpenShift Pipelines** operator
(`openshift-pipelines-operator-rh`). The catch: the failed reconcile drops into
controller-runtime **exponential backoff**, so even after Pipelines is installed
the ShipwrightBuild does not recover promptly — during the test it sat in backoff
and only progressed after the operator pod was restarted to force a fresh
reconcile.

**Remediation (baked into script 20):** install OpenShift Pipelines and wait for
`tekton.dev` to be Ready *before* creating the `OpenShiftBuild` CR. Then the very
first ShipwrightBuild reconcile succeeds and no backoff/restart is needed.

### 2. The downstream operator ships no ClusterBuildStrategies

Upstream Shipwright has a `sample-strategies.yaml` per release. The **downstream
OpenShift Builds operator installs none** — after enablement `oc get
clusterbuildstrategy` returns "No resources found". The plugin's converted Builds
reference a strategy by name (`buildah` for Docker, `source-to-image` for S2I),
so those strategies must be installed manually or the Build never registers.

**Remediation (baked into script 20):** the four strategies used here are vendored
under `shipwright/clusterbuildstrategies/` (from shipwright-io/build
`samples/v1beta1`) and applied by the script:

| Strategy | Use |
| :-- | :-- |
| `source-to-image` | S2I builds (plugin default for `Source`) |
| `source-to-image-redhat` | S2I variant on Red Hat images |
| `buildah-strategy-managed-push` | Docker builds; pushes from the strategy honoring `registries-insecure` (needed for the in-cluster/HTTP registry) |
| `buildah-shipwright-managed-push` | Docker builds; Shipwright-managed push |

Note the plain `buildah` strategy no longer exists in the samples; the Docker
path must override the plugin default with
`--optional-flags default-build-strategy=docker=buildah-strategy-managed-push`.

## Result

After `scripts/20-install-openshift-builds-operator.sh` the target has
`shipwright.io/v1beta1` (Build/BuildRun/BuildStrategy/ClusterBuildStrategy), the
build controller + webhook Running, and the four ClusterBuildStrategies
registered. The script is idempotent — a second run reports everything
`unchanged` and re-verifies readiness.
