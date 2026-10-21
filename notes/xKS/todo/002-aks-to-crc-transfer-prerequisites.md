# 002: AKS to local CRC transfer prerequisites

## Status

The first [2026-10-21 transfer attempt](../wordpress-aks/migration-2026-10-21/TRANSFER_PVC_CRC.md) was blocked on target health and network connectivity. It failed while creating the destination PVC, before copying any data.

Update later on 2026-10-21: these prerequisites were resolved for the [successful retry](../wordpress-aks/migration-2026-10-21/TRANSFER_PVC_CRC_INDIRECT.md). The old CRC instance was deleted on request and replaced with a clean 16 GiB instance. Namespace creation and S3 preflight from both clusters passed. Both PVCs were transferred through S3 and verified independently. Direct access to the local CRC router remains unconfigured and was not needed. The checklist below retains the original investigation scope; remaining runtime and implementation questions are tracked in [003](003-indirect-transfer-validation.md).

## Observed blockers

1. CRC cannot create namespace `marek-test`. The Tekton namespace admission webhook has no service endpoints. Its Pod is Pending; events report insufficient memory and an untolerated taint. Node `crc` has `DiskPressure=True` and a disk-pressure NoSchedule taint. Memory requests consume approximately 97% of allocatable memory.
2. CRC uses `apps-crc.testing`, which resolves locally to loopback and returns NXDOMAIN from an AKS Pod. Source movers cannot directly reach this local router through its current default addressing.

The first condition caused the actual Crane failure. The second was independently demonstrated during preflight and would remain after namespace creation is fixed.

## Required preparation and validation

- [x] Resolve CRC disk pressure and memory capacity through an agreed cleanup or resource adjustment. The user requested deletion; CRC was recreated with 16 GiB RAM and a 60 GiB disk.
- [x] Restore namespace admission. The fresh cluster has no Tekton installation or leftover Tekton webhook. Namespace creation succeeded.
- [x] Create destination namespace `marek-test` and verify the target StorageClass `crc-csi-hostpath-provisioner` can provision and mount storage for a mover. Both transferred claims are Bound.
- [x] Select the transport. Indirect S3 staging was selected, and upload/download preflight passed from both clusters.
- [x] Verify mover image access and source/target Pod admission for this installed Crane build and CRC profile. The target PodSecurity warning is tracked separately in 003.
- [x] Quiesce WordPress and stop MySQL after prerequisites pass. Original replica counts were one each; both remain stopped.
- [x] Transfer `wordpress-pv-claim` and `mysql-pv-claim`, recording errors, cleanup, and independent content checks. Target application ownership requirements remain in 003.
- [ ] Verify transferred data and application behavior before any cutover. Record whether source workloads remain stopped or are restored after the test.

## Crane follow-ups

- [ ] Assess whether transfer preflight should explicitly report a missing destination namespace before attempting PVC creation.
- [ ] Assess DNS/TCP diagnostics from the source mover environment. CLI access to the destination API is not proof of transfer connectivity.
- [ ] Record an exact source commit for the installed Crane executable. This attempt's build reports only `main` for version and SHA; the executable hash is retained in the run report.

These findings do not establish an AKS or OpenShift storage incompatibility. The attempt did not reach destination provisioning, mover admission, or rsync.
