# KubeVirt migration implementation backlog

## Summary

| Priority | Task | Primary repository | Outcome | Dependencies |
| --- | --- | --- | --- | --- |
| P0 | Fail on rsync errors | `crane` | `transfer-pvc` fails on a non-zero rsync exit code | None |
| P0 | Preserve target PVC `volumeMode` | `crane` | A Block PVC remains Block on the target | None |
| P0 | Select the correct VM disk transfer | `crane` | Use blockrsync for Block PVCs and KubeVirt disk images | Preserve volume mode |
| P0 | Add transfer preflight and diagnostics | `crane` | Endpoint failures do not stop source VMs; failures retain evidence | Rsync failure handling |
| P1 | Add `KubeVirtPlugin` | `crane-lib`, `crane` | Safely render `VirtualMachine` manifests | Correct PVC transfer |
| P1 | Discover VM dependencies | `crane-lib` | Auditable plan for PVCs, CDI, configuration, and networking | KubeVirtPlugin |
| P1 | Add target KubeVirt preflight | `crane` | Detect missing KubeVirt, CDI, storage, and networking capabilities | Dependency discovery |
| P1 | Implement VM cutover workflow | `crane` | Stop RWO source VM, verify data, then start target VM | P0 and P1 tasks |
| P2 | Add storage and networking policy | `crane-lib`, `crane` | Support portable forms and reject unsupported forms | Dependency discovery |
| P2 | Add KubeVirt end-to-end tests | `crane` | Coverage for storage, CDI, networking, and VM state | P0 and P1 tasks |
| P3 | Distribute and orchestrate | `crane-plugins` | Published plugin | Stable CLI and tests |

## Context

Related playground material:

- [FINDINGS.md](FINDINGS.md)
- [VM_STORAGE_SUPPORT_MATRIX.md](VM_STORAGE_SUPPORT_MATRIX.md)
- [kubevirt-cleanup-plugin/](kubevirt-cleanup-plugin/)

The local test confirmed that generic Crane export discovers
`kubevirt.io/v1 VirtualMachine` resources. Generic transformation removes most
runtime objects, but leaves KubeVirt finalizers and does not discover VM
dependencies. The test-only `KubeVirtCleanupPlugin` removes VM runtime metadata
and VMI resources, but does not handle storage, CDI, or networking.

## P0: PVC transfer correctness

### 1. Fail on non-zero rsync exit codes

**Repository:** `crane`  
**Code:** `cmd/transfer-pvc/transfer-pvc.go`

`followClientLogs()` returns the rsync exit code, but
`TransferPVCCommand.run()` continues with cleanup and returns `nil`. A transfer
with rsync `exit=12` can therefore be reported as successful.

Implementation:

- Return an error immediately after a non-zero rsync exit code.
- Define and document whether rsync exit code 23 can ever be accepted.
- Do not report `--verify` as successful unless verification completed.
- Report copy, verification, and cleanup separately.

Acceptance criteria:

- Rsync exit code 12 produces a non-zero CLI exit code.
- The summary reports `PVC data copy: failed`.
- An integration test proves that a bound target PVC cannot hide a copy failure.

### 2. Preserve `spec.volumeMode` on the target PVC

**Repository:** `crane`  
**Code:** `buildDestinationPVC()` in `cmd/transfer-pvc/transfer-pvc.go`

The current implementation clears `pvc.Spec.VolumeMode`. Kubernetes then uses
the Filesystem default, so a Block PVC changes type on the target.

Implementation:

- Preserve source `spec.volumeMode`.
- Allow a mode mapping only as an explicit user decision.
- Validate the volume mode of an existing target PVC before transfer.

Acceptance criteria:

- Filesystem PVCs remain Filesystem.
- Block PVCs remain Block.
- A target PVC with a different mode stops the transfer before copy.

### 3. Select blockrsync for Block and KubeVirt VM disks

**Repository:** `crane`, with tests in `crane-lib`

`crane-lib` already contains `state_transfer/transfer/blockrsync`. It supports
Block PVCs and Filesystem PVCs marked
`kubevirt.io/storage.contentType: kubevirt`, where the VM disk is `disk.img`.
The CLI always creates the generic rsync transfer instead.

Implementation:

- Classify claims by `volumeMode` and KubeVirt content type annotation.
- Select blockrsync for Block PVCs and KubeVirt disk-image PVCs.
- Keep the generic rsync path for ordinary application filesystem claims.
- Include the classification and selected transfer method in the report.

Acceptance criteria:

- Block PVC transfer uses `volumeDevices`, not `volumeMounts`.
- KubeVirt `disk.img` uses the blockrsync path.
- A test verifies a guest-visible checksum or marker after migration.

### 4. Add transfer preflight and failure diagnostics

**Repository:** `crane`

The local NGINX ingress test required `--subdomain` and an explicit
`--ingress-class nginx`. These must be validated before a cutover stops a source
VM.

Implementation:

- Add read-only endpoint, ingress class, subdomain, DNS, target reachability,
  storage class, and PVC access preflight.
- Add an option to retain client/server Pods, logs, Service, and Ingress after
  failure.
- Do not remove diagnostic resources before reporting the root error.

Acceptance criteria:

- A missing subdomain or ingress class fails before transfer Pods exist and
  before source VM shutdown.
- Failed transfer output identifies the Pod and includes the rsync error.

## P1: KubeVirt transformation and workflow

### 5. Add a supported KubeVirtPlugin

**Repositories:** `crane-lib` for transformation and `crane` for registration
and stage workflow

The playground POC removes KubeVirt finalizers, status, server metadata, and
selected controller annotations. It whiteouts VMI resources.

Implementation:

- Add a supported standalone `KubeVirtPlugin`.
- Remove controller-owned metadata only from KubeVirt resources.
- Whiteout VMI, launcher Pods, ControllerRevisions, Events, and other runtime
  objects recreated by target controllers.
- Preserve user metadata and declared `runStrategy`.

Acceptance criteria:

- Output contains no source UID, resourceVersion, status, finalizers, or
  controller annotations.
- Output retains the desired VirtualMachine specification.
- Target apply creates Ready VMIs for running VMs and no VMI for a halted VM.

### 6. Discover VM dependencies

**Repository:** `crane-lib`

Treat `VirtualMachine.spec` as a dependency graph rather than an opaque YAML
object.

Discover:

- Direct PVCs, ephemeral PVCs, DataVolumes, and DataVolumeTemplates.
- Secrets, ConfigMaps, and ServiceAccounts referenced by volumes, cloud-init,
  sysprep, and access credentials.
- NetworkAttachmentDefinitions, binding plugins, and cloud-init network data.
- InstanceTypes, Preferences, DataSources, snapshots, hotplug requests,
  persistent TPM, UEFI state, and memory dump PVCs.

Acceptance criteria:

- Transform writes machine-readable and human-readable dependency reports.
- Each item is marked transfer, external, map, or reject.
- An unresolved reference fails validation.

### 7. Add target KubeVirt preflight

**Repository:** `crane`

Implementation:

- Check KubeVirt CRDs, API version, and Available condition.
- Check CDI CRDs and CDI availability for DataVolumes.
- Check storage class, BlockVolume, TPM/UEFI requirements, binding plugins, and
  required NADs.
- Check container image access and required image pull secrets.

Acceptance criteria:

- `crane validate` identifies the missing target capability, VM, and relevant
  specification field.
- Validation is read-only.

### 8. Implement VM cutover workflow

**Repository:** `crane`

Implementation:

- Store the source `runStrategy` in the migration plan.
- Stop or suspend source VMs that use RWO PVCs.
- Create target VMs with `runStrategy: Halted`.
- Transfer and verify storage and dependencies.
- Restore the requested target run strategy only after validation.
- Keep the source shut down until explicit rollback or cutover confirmation.

Acceptance criteria:

- A transfer Pod never competes with a source VM for an RWO claim.
- A target VM cannot start before storage and dependencies are ready.
- Cutover state is repeatable and written to disk.

## P2: storage and networking policy

### 9. Classify storage sources

**Repositories:** `crane-lib`, `crane`

Support direct Filesystem and Block PVCs, KubeVirt `disk.img`, DataVolumes, and
DataVolumeTemplates. Mark `containerDisk` and `emptyDisk` as no-data-transfer
sources. Require mapping or reject `hostDisk`, `containerPath`, and other
host-local storage. Define consistency policy for RWX and read-only claims.

Acceptance criteria:

- Every VM volume source in the support matrix is supported, conditionally
  supported, or rejected.
- No host-local or Block storage falls back silently to Filesystem handling.

### 10. Discover and validate VM networking

**Repositories:** `crane-lib`, `crane`

Discover Pod binding, Multus NADs, binding plugins, static IPs, MAC addresses,
cloud-init network data, Services, and NetworkPolicies. Validate target CNI and
KubeVirt capabilities for bridge, passt, slirp, SR-IOV, macvtap, and host
devices. Require explicit source-to-target mappings for node-specific networks.

Acceptance criteria:

- Missing target NADs fail validation before apply.
- SR-IOV and macvtap VMs without mappings cannot migrate as apparently valid.
- Service selectors remain valid for target virt-launcher Pod labels.

## P2: test coverage

### 11. Add KubeVirt end-to-end scenarios

**Repository:** `crane`

Add scenarios for:

- Filesystem PVC, Block PVC, and KubeVirt `disk.img` with guest-visible checks.
- CDI HTTP import, CDI clone, DataVolumeTemplate, and DataSource.
- RWO, RWX, and read-only claims.
- Cloud-init Secret and ConfigMap dependencies.
- Multus NADs and expected SR-IOV/macvtap rejection.
- Persistent TPM, UEFI state, hotplug disks, and memory dumps.
- `containerDisk`, `emptyDisk`, `hostDisk`, and `containerPath` policy.

Acceptance criteria:

- Supported cases validate target VM state and guest data.
- Unsupported cases fail before cutover with an actionable error.

## P3: distribution and orchestration

### 12. Publish the KubeVirt plugin

**Repository:** `crane-plugins`

Publish only after the plugin API, dependency report, and end-to-end tests are
stable. Keep it separate from OpenShiftPlugin because KubeVirt also runs on
upstream Kubernetes.

## Recommended order

1. Complete tasks 1 through 4 so data transfer cannot falsely report success.
2. Complete task 5 and basic tests for safe VM manifest import.
3. Complete tasks 6 through 8 for an auditable stateful cutover.
4. Complete tasks 9 through 11 for CDI, Block storage, and networking coverage.
5. Complete task 12 after the CLI workflow is stable.
