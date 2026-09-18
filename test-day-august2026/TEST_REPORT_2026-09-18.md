# Test Report - 2026-09-18

## Scope

Validated `mta-ops 8.3.0` (SHA
`198c8853ea36739125b5977d2bb468ec787173b4`) with a local Minikube source,
CRC OpenShift target, indirect PVC transfer, and BuildConfig to OpenShift Builds
(Shipwright) conversion.

## Environment

| Role | Environment | Status at end of session |
| :-- | :-- | :-- |
| Kubernetes source | Minikube v1.35.1 | Stopped, retained |
| OpenShift source and target | CRC OpenShift 4.22.7 / Kubernetes v1.35.6 | Running |

Created isolated test-day kubeconfigs:

- `kubeconfig-src` for Minikube
- `kubeconfig-tgt` for CRC
- `kubeconfig-merged` with `src` and `tgt` contexts for `transfer-pvc`

`scripts/00-prepare-local-clusters.sh` was added to reproduce this setup from
the local `minikube` and `crc-admin` contexts.

## Binary Contract

`CRANE_BIN=mta-ops scripts/30-check-downstream-binary.sh` passed.

Validated:

- Required commands: `export`, `transform`, `apply`, `validate`, and
  `transfer-pvc`.
- Upstream-only commands are absent.
- Embedded plugins: `KubernetesPlugin`, `OpenShiftPlugin`, and
  `BuildConfigToBuildsPlugin`.
- Default transfer image is the downstream non-Quay image:
  `registry.redhat.io/mta/mta-rsync-transfer-rhel9:8.3.0`.

## WordPress Migration: Minikube to CRC

The stateful WordPress application was deployed in namespace
`wordpress-mta-mkcrc` on Minikube and validated with source seed post `#11087`.

The following pipeline completed successfully:

1. `mta-ops export`, `transform`, and `apply` generated isolated artifacts with
   suffix `-mta-mkcrc`.
2. Both PVCs were transferred through S3-compatible cloud storage to CRC using
   checksum verification.
3. The transformed manifests were applied to CRC.
4. The target WordPress application returned HTTP 200 and the exact seed post
   `#11087`.

### Incremental PVC Transfer

The S3 transfer used `RUNS=2` and `--keep-cloud-data`:

| Run | Duration |
| :-- | --: |
| First run | 554.8s |
| Second run | 168.5s |

The faster second run confirmed incremental staging and destination sync.

### PVC Storage Class Mapping

`mta-ops` retained source PVC manifests. The Minikube source uses storage class
`standard`, while CRC uses `crc-csi-hostpath-provisioner`. Applying an unmapped
manifest after `transfer-pvc` attempted to change the immutable PVC storage
class and failed.

The test pipeline now accepts `PVC_STORAGE_CLASS_MAP` and passes it to
KubernetesPlugin through `--stage-optionals`. This value was validated:

```bash
PVC_STORAGE_CLASS_MAP=standard:crc-csi-hostpath-provisioner
```

The mapped PVC manifests applied successfully to the pre-existing PVCs created
by `transfer-pvc`.

### Transfer Image Constraint

The downstream default transfer image requires a valid Red Hat registry
entitlement. Minikube could not pull it, even after copying the available CRC
pull secret, because those credentials were not entitled to the MTA repository.

For the functional transfer test only, both transfer images were overridden
with the reachable public image:

```text
quay.io/konveyor/rsync-transfer:latest
```

The downstream default-image contract remains separately validated. See
`REGISTRY_REDHAT_IO_EXTERNAL_CLUSTER_SETUP.md` for the intended entitlement and
pull-secret configuration on external Kubernetes clusters.

### Local Networking Constraint

Direct transfer through a CRC Route is not usable from the Minikube VM because
CRC maps `*.apps-crc.testing` to the host loopback address. Indirect transfer
through S3-compatible storage is the supported local test path.

## BuildConfig to OpenShift Builds

CRC was used as both the OpenShift BuildConfig source and the Shipwright target.
`scripts/21` and `scripts/22` now accept `KUBECONFIG_SRC`, so this does not
replace the retained Minikube kubeconfig.

### S2I Conversion

- Source namespace: `bc-mta-crc-clean`
- Plugin: embedded `BuildConfigToBuildsPlugin`
- Strategy: `ClusterBuildStrategy/source-to-image`
- BuildRun: `sample-nodejs-run-fjnp8`
- Result: succeeded
- Digest:
  `sha256:236dd3e0eb45d030964e04b39cee837d6a09f6b64323c53cf65bd5e32a922afb`

The BuildRun digest matched `sample-nodejs:latest` after a 60-second stability
check.

### Docker/Buildah Conversion

- Source namespace: `bc-mta-crc-docker`
- Strategy: `ClusterBuildStrategy/buildah-shipwright-managed-push`
- BuildRun: `ruby-hello-world-docker-run-5crkh`
- Result: succeeded
- Digest:
  `sha256:4d40d7e76420d1e392291c24b6fec5609e80d7d39f5bec71dafd9c009c90b624`

The BuildRun digest matched `ruby-hello-world:latest` after a 60-second
stability check. This scenario required the local
`buildah-shipwright-managed-push` ClusterBuildStrategy, privileged SCC for the
`pipeline` ServiceAccount, and an annotated internal-registry push secret.

### BuildConfig Trigger Handling

An initial test allowed the source BuildConfig `ConfigChange` trigger to run.
Its legacy OpenShift Build later overwrote the ImageStreamTag created by the
Shipwright BuildRun. `scripts/21-deploy-buildconfig-src.sh` now disables source
BuildConfig triggers by default using a temporary Kustomize overlay. Set
`DISABLE_TRIGGERS=false` only when testing trigger-conversion warnings.

## Documentation and Test Assets

- Added `REGISTRY_REDHAT_IO_EXTERNAL_CLUSTER_SETUP.md`.
- Added findings 10 and 11 for the WordPress and BuildConfigToBuilds results.
- Updated the README with local topology, storage mapping, and CRC self-hosted
  conversion instructions.
- Added optional `SOURCE_IMAGE` and `DESTINATION_IMAGE` overrides to PVC
  transfer scripts for functional testing when the downstream image cannot be
  pulled.

## GitHub Follow-up

Created https://github.com/migtools/crane/issues/988.

The issue requests that `transform list-plugins` expose each plugin's origin
(`embedded` or external discovery directory) and automatic run mode (`default`
or `opt-in`). The associated implementation proposal is in
`drafts/mta-ops-transform-list-plugins-provenance-plan.md`.

## Cleanup Follow-up

- The indirect transfer used bucket
  `crane-mta-ops-mkcrc-20260918-414bb133` with `--keep-cloud-data`; remove its
  staged PVC data and the bucket when no longer needed.
- CRC contains test namespaces `wordpress-mta-mkcrc`, `bc-mta-crc`,
  `bc-mta-crc-clean`, and `bc-mta-crc-docker`.
- Minikube is stopped but retained.
