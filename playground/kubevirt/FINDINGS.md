# Crane KubeVirt migration findings

Tested on 2026-10-20 with Crane `v0.11.0-alpha.1`, KubeVirt `v1.9.1`, and two
local Minikube clusters.

The complete storage source and support comparison is in
[VM_STORAGE_SUPPORT_MATRIX.md](VM_STORAGE_SUPPORT_MATRIX.md).

## Completed flow

1. `crane export` exported `VirtualMachine` and `PersistentVolumeClaim`.
2. `crane transform` and `crane apply` rendered the three VM resources.
3. `crane transfer-pvc` created the target `configured-data` PVC.
4. `kubectl apply` created target VMs, and the VM referencing the PVC reached
   `Running` and `Ready=True`.

## Required Crane work

### Add a KubeVirt transform plugin

Crane has no KubeVirt-specific code or plugin. The generic KubernetesPlugin
removed runtime `VirtualMachineInstance` and Pod resources only when they were
excluded at export. A KubeVirt plugin should:

- remove controller-owned metadata from `VirtualMachine`, including KubeVirt
  finalizers, `status`, `uid`, `resourceVersion`, and generation fields;
- exclude `VirtualMachineInstance`, launcher Pods, ControllerRevisions, Events,
  and other controller-generated resources by default;
- discover PVC, DataVolume, DataSource, Secret, ConfigMap, and NetworkAttachment
  references in a VM spec;
- stop or suspend running VMs before a PVC cutover and restore the requested
  `runStrategy` only after target storage is ready;
- validate that KubeVirt is installed on the target before applying VM resources.

`kubevirt-cleanup-plugin/` is a test-only binary implementation of the first
two cleanup items. It passed unit tests and removed KubeVirt finalizers from a
real Crane-rendered VM manifest. The plugin-rendered output was applied to the
target cluster after deleting the target VMs. `web-vm` and `configured-vm`
reached `Running` and `Ready=True`, while `configured-vm` attached the target
`configured-data` PVC.

### Make PVC transfer fail on rsync errors

The local transfer reached phase 6 with `rsync` exit code 12 and zero sent
files, then reported `PVC data copy: succeeded`. This is an implementation bug,
not a block-volume limitation. Both test PVCs have `volumeMode: Filesystem`.

`cmd/transfer-pvc/transfer-pvc.go` stores the exit code returned by
`followClientLogs` and prints it in phase 6, but does not return an error when
the code is non-zero. It runs cleanup and returns `nil`. The deferred summary
therefore sees no command error. `transferSummaryStatus` knows that exit code 12
means failure, but only affects the printed summary.

After phase 6, return `phases.Fail(...)` for every non-zero rsync exit code.
Keep a deliberately documented policy for code 23 if partial copies are ever
acceptable, but do not claim a verified VM disk migration in that case. Target
PVC binding alone does not prove that its contents migrated.

### Improve ingress preflight

`transfer-pvc --endpoint nginx-ingress` requires `--subdomain`. It also failed
to infer the Minikube `nginx` IngressClass and attempted to create an Ingress
with an empty `spec.ingressClassName`. The command should validate both values
before stopping the source workload and reliably select the default ingress
class.

## Current test limitations

`configured-data` is a KubeVirt filesystem PVC initialized as a VM data disk.
This test verifies resource orchestration and volume attachment. It does not yet
verify a guest-visible data checksum because the rsync exit-code issue must be
fixed first.

## VM storage requirements

- Stop or suspend every VM that owns a ReadWriteOnce PVC before transfer. A
  filesystem PVC cannot be mounted by the transfer pod while it is attached to
  a running VM.
- A `containerDisk` is an image pulled from a registry, not PVC data. It must
  remain reachable from the target cluster or be mirrored separately.
- Test block-mode PVCs separately. The current test uses filesystem mode, so it
  cannot prove whether the transfer implementation uses `volumeMounts` only or
  also handles raw block `volumeDevices`.
- Handle CDI DataVolumes and their PVCs as a unit. A VM spec can reference a
  DataVolume rather than a PVC directly; importing or transferring only one of
  those objects leaves the target VM unusable.
- Copy Secrets, ConfigMaps, and NetworkAttachmentDefinitions referenced by a VM
  spec before starting the target VM.
- Verify data from inside the guest after transfer. A bound PVC and a Ready VMI
  only prove attachment, not disk consistency.

## KubeVirt VM storage types and Crane support

KubeVirt can attach several volume sources to a VM. Only some represent
persistent data that must move between clusters.

| VM volume source | Persistent data | Crane status | Notes |
| --- | --- | --- | --- |
| `persistentVolumeClaim` with `volumeMode: Filesystem` | Yes | Exported as a PVC. The KubernetesPlugin removes it from rendered output for a separate `transfer-pvc` step. The local test created the target PVC, but rsync exit handling is defective, so data-copy success is not proven. | KubeVirt normally stores a `disk.img` file on a filesystem-mode PVC. |
| `persistentVolumeClaim` with `volumeMode: Block` | Yes | Not tested and not confirmed. | The transfer implementation must attach the PVC as a block `volumeDevice`, not only as a mounted directory. Add an end-to-end test before claiming support. |
| CDI `DataVolume` or `dataVolumeTemplates` | Yes, through its resulting PVC | Not KubeVirt-aware. | Crane must discover both the DataVolume and its backing PVC, transfer the data, and preserve the ordering needed by CDI and the VM. |
| `ephemeral` backed by a PVC | No persistent guest writes | Not a data-migration target. | The backing PVC is read-only and guest writes use a temporary copy-on-write layer. The backing PVC may still need to exist on the target. |
| `containerDisk` | No | No PVC transfer needed. | The target must pull the container image or use an independently mirrored image. |
| `emptyDisk` | No | No PVC transfer needed. | KubeVirt recreates it when the VM starts. |
| `cloudInitNoCloud`, `cloudInitConfigDrive`, ConfigMap, Secret, ServiceAccount | Configuration only | Generic resource export may include referenced objects, but no KubeVirt dependency discovery exists. | A KubeVirt plugin should retain and validate every referenced object. |

Access modes such as `ReadWriteOnce` and `ReadWriteMany` are independent of
`volumeMode`. For VM migration, `ReadWriteOnce` needs a stopped source VM before
the transfer pod can mount the PVC. `ReadWriteMany` may be mountable by both
clusters, but a live copy still needs an application-consistency plan.
