# Finding 07 — BuildConfig → Shipwright conversion, end to end

**Scope:** secondary objective. Convert a real OpenShift `BuildConfig` on the
source cluster to a Shipwright `Build` with crane + the
`crane-plugin-buildconfig-to-shipwright` plugin, apply it to the target, and run a
BuildRun to prove the converted Build actually builds and pushes an image.
Automated by `scripts/21`, `22`, `23`.

## Result

**Succeeded end to end.** An S2I nodejs BuildConfig (`bc-demo/sample-nodejs`) was
converted, applied to the target, registered by Shipwright
(`registered=True, all validations succeeded`), and a BuildRun built and pushed
the image to the target's internal registry. The BuildRun output digest matched
the resulting `sample-nodejs:latest` ImageStreamTag digest, confirming a real,
usable image was produced.

## crane v0.11.0-alpha.1 is compatible with the plugin

This is a useful test-day signal: the plugin's CI pins a specific upstream crane
commit, but the **alpha build in `$PATH` (v0.11.0-alpha.1) drives the plugin
correctly** — `crane transform` invoked the plugin, consumed its `NewResources`
output, and produced the Shipwright Build with no protocol errors.

## `crane transform BuildConfigPlugin` by plugin name

Passing the plugin **name** positionally works — crane auto-creates a stage for
it:

```
Stage for "BuildConfigPlugin" not found, attempting to create
Creating stage for plugin BuildConfigPlugin -> 10_BuildConfigPlugin
Running 1 stage(s): [10_BuildConfigPlugin]
```

So no `plugins.yaml`/stage file is needed for a single-plugin run; the binary in
`--plugin-dir` plus the name is enough.

## `--include-gk` scopes the export to just the BuildConfig

`crane export ... --include-gk build.openshift.io/BuildConfig` exported **only**
the BuildConfig — one file — instead of the whole namespace:

```
export-bc/resources/bc-demo/BuildConfig_build.openshift.io_v1_bc-demo_sample-nodejs.yaml
```

Format is `Group/Kind` (or bare `Kind`), repeatable. This keeps the conversion
input focused and avoids pulling unrelated namespace noise (SAs, RoleBindings,
etc.) that the BuildConfig conversion does not need. `--exclude-gk` is the inverse.

## Conversion details (offline)

The plugin resolves ImageStream references offline via `--optional-flags`:

- `imagestream-mapping=openshift/nodejs:20-ubi9=registry.access.redhat.com/ubi9/nodejs-20:latest`
  resolved the S2I **builder** to a concrete, publicly pullable image.
- The **output** ImageStreamTag was left to the plugin's internal-registry
  fallback: `image-registry.openshift-image-registry.svc:5000/bc-demo/sample-nodejs:latest`
  — which is the *target's own* internal registry once the Build is applied there,
  so no `registry-mapping` was needed and no "redirected off internal registry"
  warning fired.

The plugin also mapped `successful/failedBuildsHistoryLimit` → Build
`retention.succeeded/failedLimit`, and recorded every non-portable detail (dropped
triggers, dropped runPolicy, missing pushSecret) as `crane.konveyor.io/...`
annotations on the Build — the conversion is transparent about what did not carry
over. Outcome annotation: `converted-with-warnings`.

## Docker (Dockerfile) strategy → buildah — also verified

A second BuildConfig with the **Docker** strategy (`bc-demo-docker/ruby-hello-world-docker`,
`openshift/ruby-hello-world` + its `Dockerfile`) was converted and run end to end
as well. The plugin maps `strategy.type: Docker` → a buildah ClusterBuildStrategy,
selected via `--optional-flags`:

```json
{"default-build-strategy":"docker=buildah-shipwright-managed-push",
 "insecure-registries":"image-registry.openshift-image-registry.svc:5000"}
```

It emitted a Build referencing `ClusterBuildStrategy/buildah-shipwright-managed-push`,
carried `dockerfilePath` → the `dockerfile` paramValue, and set the
`registries-insecure` paramValue for the internal registry. BuildRun **Succeeded**;
pushed digest matched the `ruby-hello-world:latest` ImageStreamTag.

The docker/buildah case needed two things the S2I case did not — both are
OpenShift/Shipwright environment requirements, not plugin issues:

1. **Privileged SCC for the build SA.** The buildah ClusterBuildStrategy runs a
   privileged (or `SETFCAP`/root) build container, which the default
   `pipelines-scc` forbids (`PodAdmissionFailed: ... privileged: Invalid value:
   true`). Granted with `oc adm policy add-scc-to-user privileged -z pipeline`.
   (Script 23: `GRANT_PRIVILEGED_SCC=true`.)
2. **An annotated push secret.** Shipwright's image-processing push step (used by
   the `*-shipwright-managed-push` strategies) authenticates from a Tekton-wired
   docker secret. The `pipeline` SA's auto-created `*-dockercfg-*` secret already
   holds a working internal-registry token, but Tekton creds-init ignores it
   because it lacks the `tekton.dev/docker-0` annotation → the push gets **401
   Unauthorized**. Fix: repackage that token as a `dockerconfigjson` secret,
   annotate it (`tekton.dev/docker-0=https://image-registry...svc:5000`), and set
   it as the Build's `output.pushSecret`. (Script 23: `SETUP_INTERNAL_PUSH=true`.)
   The S2I *redhat* builder reads the SA token directly, so it never needed this.

### Two buildah strategies — pick the right one

Both come from the upstream `shipwright-io/build` samples (the downstream operator
ships none — see finding 06):

- **`buildah-strategy-managed-push`** — buildah does the push itself
  (`buildah push docker://…`). It runs fine under `pipelines-scc` (no privileged),
  but on the internal registry the push fails with **`authentication required`**:
  buildah does not pick up the Tekton-mounted credentials for a bearer-token
  registry, even with an annotated `pushSecret`.
- **`buildah-shipwright-managed-push`** — buildah writes the image locally
  (`oci:…`) and **Shipwright's own image-processing step** pushes it, the same
  mechanism the working S2I strategies use. This is the one that succeeds against
  the internal registry (with the privileged SCC + annotated push secret above).

## Gotchas

- **`oc get build` is ambiguous.** Both `build.openshift.io` and `shipwright.io`
  expose a `builds` resource, so `oc get build <name>` hits the OpenShift one and
  reports the Shipwright Build as "not found". Use the fully-qualified
  `builds.shipwright.io` / `buildruns.shipwright.io` (scripts do).
- **Internal-registry push needs a push-capable SA.** The converted Build has no
  pushSecret (the plugin warns about it). The BuildRun must use a ServiceAccount
  that can push to the internal registry — here the namespace `pipeline` SA
  (auto-created by the Pipelines operator, carries a dockercfg secret) granted
  `system:image-builder`.

## Reproduce

S2I nodejs case:

```bash
scripts/21-deploy-buildconfig-src.sh       # BuildConfig on the source
scripts/22-crane-buildconfig-convert.sh    # export --include-gk -> transform BuildConfigPlugin -> apply
scripts/23-apply-shipwright-target.sh      # apply Build on target, run BuildRun, verify digest
```

Docker/buildah case:

```bash
NAMESPACE=bc-demo-docker \
  BC_FILE=test-app/buildconfig/ruby-hello-world-docker-buildconfig.yaml \
  bash scripts/21-deploy-buildconfig-src.sh

NAMESPACE=bc-demo-docker WORK_SUFFIX=-bc-docker \
  OPTIONAL_FLAGS='{"default-build-strategy":"docker=buildah-shipwright-managed-push","insecure-registries":"image-registry.openshift-image-registry.svc:5000"}' \
  bash scripts/22-crane-buildconfig-convert.sh

NAMESPACE=bc-demo-docker BUILD_NAME=ruby-hello-world-docker WORK_SUFFIX=-bc-docker \
  GRANT_PRIVILEGED_SCC=true SETUP_INTERNAL_PUSH=true \
  bash scripts/23-apply-shipwright-target.sh
```
