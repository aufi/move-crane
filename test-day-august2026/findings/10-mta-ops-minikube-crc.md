# Finding 10 - mta-ops 8.3.0 Minikube to CRC WordPress migration

**Scope:** stateful WordPress migration from Minikube (source) to CRC OpenShift
(target), using `mta-ops 8.3.0` (SHA `198c8853ea36739125b5977d2bb468ec787173b4`).

## Result

**Succeeded end to end.** The source WordPress instance served seed post
`#11087`; after export, transform, indirect PVC transfer, and deployment on CRC,
the target served the same exact seed post. Both PVCs were transferred with
checksum verification.

The indirect transfer used `RUNS=2` and `--keep-cloud-data`:

| Run | Duration |
| :-- | --: |
| 1 | 554.8s |
| 2 | 168.5s |

The faster second pass confirms incremental cloud staging and destination sync.

## Local topology constraints

- Direct transfer via CRC Route is not usable from the Minikube VM: CRC maps
  `*.apps-crc.testing` to the host loopback address.
- The downstream default transfer image,
  `registry.redhat.io/mta/mta-rsync-transfer-rhel9:8.3.0`, requires a Red Hat
  registry entitlement. The available CRC pull secret did not authorize this
  repository for Minikube. The successful functional test explicitly used
  `quay.io/konveyor/rsync-transfer:latest` for both `--source-image` and
  `--destination-image`. The downstream binary contract still passes: its
  default image is non-quay.io.

## PVC output behavior

Unlike the historical v0.11 test result, the transformed `mta-ops` output kept
the two source PVC manifests with storage class `standard`. Applying those after
`transfer-pvc` attempted to change the target PVC storage class
(`crc-csi-hostpath-provisioner`) and Kubernetes rejected it as immutable.

Use KubernetesPlugin's `pvc-storage-class-map` during transform so the manifest
matches the PVC created by `transfer-pvc`. The test pipeline exposes it as
`PVC_STORAGE_CLASS_MAP`; with CRC use
`standard:crc-csi-hostpath-provisioner`. The target apply then applies every
manifest, including PVCs.

## Reproduce

```bash
NAMESPACE=wordpress-mta-mkcrc WORK_SUFFIX=-mta-mkcrc \
  CRANE_BIN=mta-ops scripts/03-deploy-app-src.sh

NAMESPACE=wordpress-mta-mkcrc WORK_SUFFIX=-mta-mkcrc \
  PVC_STORAGE_CLASS_MAP=standard:crc-csi-hostpath-provisioner \
  CRANE_BIN=mta-ops scripts/05-crane-export-transform-apply.sh

NAMESPACE=wordpress-mta-mkcrc RUNS=2 KEEP_CLOUD_DATA=true \
  CLOUD_BUCKET=<new-bucket> CRANE_BIN=mta-ops \
  SOURCE_IMAGE=quay.io/konveyor/rsync-transfer:latest \
  DESTINATION_IMAGE=quay.io/konveyor/rsync-transfer:latest \
  scripts/11-transfer-pvc-indirect.sh

NAMESPACE=wordpress-mta-mkcrc WORK_SUFFIX=-mta-mkcrc scripts/08-apply-target.sh
NAMESPACE=wordpress-mta-mkcrc KUBECONFIG=kubeconfig-tgt \
  WORDPRESS_SEED_ID=<source-seed> PORT=18081 scripts/04-validate-app.sh
```
