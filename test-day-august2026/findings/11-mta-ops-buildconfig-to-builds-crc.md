# Finding 11 - mta-ops BuildConfigToBuilds on a single CRC cluster

**Scope:** `mta-ops 8.3.0` BuildConfig to OpenShift Builds (Shipwright)
conversion, with CRC used as both the source and target cluster.

## Result

**Succeeded end to end.** A real OpenShift `BuildConfig` was exported from
`bc-mta-crc-clean`, transformed by the embedded `BuildConfigToBuildsPlugin`, applied
as a Shipwright `Build`, and executed as a `BuildRun`.

The BuildRun `sample-nodejs-run-fjnp8` succeeded. Its output digest exactly
matched the destination `sample-nodejs:latest` ImageStreamTag:

```text
sha256:236dd3e0eb45d030964e04b39cee837d6a09f6b64323c53cf65bd5e32a922afb
```

## Conversion details

- The plugin was invoked by its new name: `BuildConfigToBuildsPlugin`.
- The source `BuildConfig` was exported with
  `--include-gk build.openshift.io/BuildConfig`.
- S2I builder `openshift/nodejs:20-ubi9` was mapped to
  `registry.access.redhat.com/ubi9/nodejs-20:latest`.
- The converted Build used `ClusterBuildStrategy/source-to-image` and the CRC
  internal image registry as its output.
- The BuildConfig triggers were removed before deployment to prevent a legacy
  OpenShift build from racing the Shipwright BuildRun. The BuildRun was started
  explicitly by the test.
- `runPolicy` was intentionally reported as a conversion warning.

## Docker/buildah strategy

The Docker BuildConfig fixture was also converted and executed successfully in
`bc-mta-crc-docker`. The plugin mapped `strategy.type: Docker` to
`ClusterBuildStrategy/buildah-shipwright-managed-push`, preserved `Dockerfile`,
and set the internal CRC registry as an insecure registry.

BuildRun `ruby-hello-world-docker-run-5crkh` succeeded. Its output and
`ruby-hello-world:latest` ImageStreamTag shared this digest after a 60-second
stability check:

```text
sha256:4d40d7e76420d1e392291c24b6fec5609e80d7d39f5bec71dafd9c009c90b624
```

The strategy was applied from
`shipwright/clusterbuildstrategies/buildstrategy_buildah_shipwright_managed_push_cr.yaml`.
It requires `GRANT_PRIVILEGED_SCC=true`. Its Shipwright-managed push also needs
`SETUP_INTERNAL_PUSH=true`, which configures an annotated internal-registry
push secret for the `pipeline` ServiceAccount.

## Script change

`scripts/21-deploy-buildconfig-src.sh` now uses a temporary Kustomize overlay
to set the requested namespace. This avoids `oc apply -n` rejecting a source
fixture that contains a different `metadata.namespace`.

The same overlay disables BuildConfig triggers by default. In an initial run
with the original `ConfigChange` trigger, OpenShift started `sample-nodejs-1`
after the Shipwright BuildRun and overwrote the ImageStreamTag with a different
digest. The clean run had no OpenShift `Build` resources after a 60-second
stability check, and the BuildRun and ImageStreamTag digests remained equal.

`scripts/21` and `scripts/22` accept `KUBECONFIG_SRC`, allowing CRC to be used
as the source without replacing the stored Minikube source kubeconfig.

## Reproduce

```bash
NAMESPACE=bc-mta-crc-clean KUBECONFIG_SRC=kubeconfig-tgt scripts/21-deploy-buildconfig-src.sh

NAMESPACE=bc-mta-crc-clean KUBECONFIG_SRC=kubeconfig-tgt CRANE_BIN=mta-ops \
  SKIP_PLUGIN_BUILD=true WORK_SUFFIX=-bc-mta-crc-clean \
  scripts/22-crane-buildconfig-convert.sh

NAMESPACE=bc-mta-crc-clean WORK_SUFFIX=-bc-mta-crc-clean \
  scripts/23-apply-shipwright-target.sh
```

Docker/buildah case:

```bash
KUBECONFIG=kubeconfig-tgt oc apply -f \
  shipwright/clusterbuildstrategies/buildstrategy_buildah_shipwright_managed_push_cr.yaml

NAMESPACE=bc-mta-crc-docker KUBECONFIG_SRC=kubeconfig-tgt \
  BC_FILE=test-app/buildconfig/ruby-hello-world-docker-buildconfig.yaml \
  scripts/21-deploy-buildconfig-src.sh

NAMESPACE=bc-mta-crc-docker KUBECONFIG_SRC=kubeconfig-tgt CRANE_BIN=mta-ops \
  SKIP_PLUGIN_BUILD=true WORK_SUFFIX=-bc-mta-crc-docker \
  OPTIONAL_FLAGS='{"default-build-strategy":"docker=buildah-shipwright-managed-push","insecure-registries":"image-registry.openshift-image-registry.svc:5000"}' \
  scripts/22-crane-buildconfig-convert.sh

NAMESPACE=bc-mta-crc-docker BUILD_NAME=ruby-hello-world-docker \
  WORK_SUFFIX=-bc-mta-crc-docker GRANT_PRIVILEGED_SCC=true \
  SETUP_INTERNAL_PUSH=true scripts/23-apply-shipwright-target.sh
```
