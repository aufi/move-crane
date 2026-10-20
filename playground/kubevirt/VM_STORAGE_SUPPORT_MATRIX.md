# KubeVirt VM storage and Crane support matrix

## Scope

This document covers storage and related dependencies of `kubevirt.io/v1`
`VirtualMachine` resources. It uses KubeVirt v1.9.1, Crane v0.11.0-alpha.1,
the local KubeVirt cleanup plugin, and the source and target Minikube test
clusters in this directory.

It does not claim support based only on API discovery. A feature is marked
tested only when this playground ran it end to end.

## KubeVirt model

`VirtualMachine.spec.template.spec` is a VirtualMachineInstance template. A
named `volume` must be referenced by a disk, LUN, CD-ROM, or virtiofs filesystem
device with the same name. The device type changes how the guest sees the
volume. It does not change how Crane must discover the volume source.

KubeVirt supports these device forms for an attached volume:

| Device form | Migration relevance |
| --- | --- |
| `disk` | Normal guest disk. Most PVC and DataVolume root disks use this form. |
| `lun` | SCSI LUN. It may use persistent reservation, which needs target KubeVirt configuration. |
| `cdrom` | Usually an ISO or read-only install media. The source may still be a PVC. |
| `filesystem` with `virtiofs` | Shares a filesystem volume with the guest. The guest must mount it and support virtiofs. |

## Volume sources

| VM volume source | Can hold persistent guest data | Storage object or external dependency | Crane v0.11.0-alpha.1 | Local cleanup plugin | Required work |
| --- | --- | --- | --- | --- | --- |
| `persistentVolumeClaim` with `volumeMode: Filesystem` | Yes | PVC contains a raw `disk.img` at its root for a KubeVirt disk. | Exports the PVC, then KubernetesPlugin whiteouts it. `transfer-pvc` creates a target PVC. The local copy returned rsync exit 12 but reported success, so data-copy support is not verified. | Keeps VM reference but does not discover the PVC. | Discover the claim, stop the VM, transfer it, restore target VM only after verification. |
| `persistentVolumeClaim` with `volumeMode: Block` | Yes | Raw block device. KubeVirt requires the `BlockVolume` feature gate. | Not usable through the command as implemented. `buildDestinationPVC` clears `spec.volumeMode`, which turns the target request into the Kubernetes Filesystem default. | No handling. | Preserve volume mode and select block transfer. Add a real Block PVC test. |
| Filesystem PVC annotated `kubevirt.io/storage.contentType: kubevirt` | Yes | KubeVirt VM disk stored as `disk.img`. | `crane-lib` has `blockrsync` logic for this case, but the CLI does not select it. | No handling. | Wire the CLI to `blockrsync`; it transfers the disk file rather than treating the PVC as arbitrary application files. |
| `dataVolume` | Yes | CDI `DataVolume` and its PVC. | No KubeVirt or CDI dependency discovery. | No handling. | Export and classify DataVolume, then transfer or re-import its backing data. Wait for CDI completion before VM start. |
| `dataVolumeTemplates` | Yes | VM-owned CDI DataVolume and PVC. | No handling. | No handling. | Preserve template semantics or convert to a target PVC/DataVolume in a deterministic order. Do not let target CDI import stale source content over transferred data. |
| `ephemeral` backed by `persistentVolumeClaim` | Backing disk is persistent, guest writes are not | PVC is read-only backing storage; KubeVirt writes a temporary COW layer. | No dependency discovery. | No handling. | Transfer backing PVC only if target cannot reach the original storage. Do not claim guest write persistence. |
| `containerDisk` | No | Registry image and optional image pull secret. | VM is preserved generically. No image reachability check or registry rewrite specific to VM disks. | Preserves the source unchanged. | Verify target image access, apply registry mapping, and copy image pull secrets if required. |
| `emptyDisk` | No across VM recreation | No PVC. KubeVirt creates a temporary qcow2 disk. | Generic VM export works. | Preserves it. | No data transfer. Record that its data is intentionally lost at cutover. |
| `hostDisk` | Host-local only | Path on source node. | Generic VM export preserves an unusable source path. | Preserves it. | Reject by default or require explicit target path mapping and data-copy workflow. |
| `configMap` | Configuration only | ConfigMap. May be a disk or virtiofs filesystem. | Generic export may include it; no reference discovery. | Preserves reference. | Discover and include referenced ConfigMaps. Validate keys and target availability. |
| `secret` | Configuration or credentials | Secret. May be disk, virtiofs filesystem, cloud-init, or access credential source. | Generic export may include it; no reference discovery. | Preserves reference. | Discover it, apply a secret migration policy, and never silently drop required secrets. |
| `serviceAccount` | No guest disk state | ServiceAccount token volume. | Generic export may whiteout default ServiceAccount. | No handling. | Discover non-default service accounts and required RBAC; validate target identity policy. |
| `cloudInitNoCloud` and `cloudInitConfigDrive` | Configuration only | Inline data, Secret, or ConfigMap. | VM is retained but its referenced Secret or ConfigMap is not discovered. | Preserves source fields. | Include referenced resources and optionally redact or map credentials. |
| `sysprep` | Configuration only | Secret or ConfigMap. | No dependency discovery. | Preserves source fields. | Include referenced resources. |
| `downwardMetrics` | No | KubeVirt-generated metrics disk or virtio serial data. | Generic VM export works. | Preserves it. | No PVC transfer; target KubeVirt configuration must support the feature. |
| `containerPath` and utility volumes | Depends on host/container path | Feature-gated KubeVirt configuration and container-local data. | Not classified. | No handling. | Reject or explicitly map. They cannot be copied as a PVC migration. |

## PVC characteristics

`volumeMode` and access mode are independent:

| PVC characteristic | Meaning for VM migration | Current Crane status |
| --- | --- | --- |
| `Filesystem` | The transfer pod mounts a directory. A KubeVirt disk is normally `disk.img` in that directory. | Attempted locally, but the rsync failure was incorrectly returned as success. |
| `Block` | The transfer pod must use a `volumeDevice` and copy the raw device. | Library support exists in `crane-lib/state_transfer/transfer/blockrsync`, but the CLI never selects it and clears the target volume mode. Unsupported. |
| `ReadWriteOnce` | Source VM and transfer pod cannot simultaneously mount the claim. Stop the source VM first. | The test flow stops `configured-vm` before transfer. Crane does not infer VM ownership itself. |
| `ReadWriteMany` | May mount on both sides, but a live copy can be application-inconsistent. | No workload quiescing or consistency policy. |
| `ReadOnlyMany` | Often install media or shared read-only data. | No classification. It may not need copying if target can reach the original source. |
| StorageClass, snapshots, clone and populator behavior | Defines how target storage is provisioned and restored. | Only a target storage-class override is exposed. No KubeVirt or CDI storage policy. |

## KubeVirt-managed persistent state

These resources are not ordinary entries in `spec.template.spec.volumes`, but
can create or require PVC-backed state. The plugin must detect them before
declaring a migration complete.

| Feature | Persistent state | Required migration behavior |
| --- | --- | --- |
| Persistent TPM | KubeVirt-managed state PVC | Preserve only when the target has compatible TPM support and the state is intentionally migrated. |
| Persistent UEFI NVRAM | KubeVirt-managed state PVC | Preserve only when firmware and machine type are compatible. |
| Memory dump | User-selected PVC receives a dump | Treat as data only if the migration requires crash artifacts. It is not a boot disk. |
| Backend storage and persistent VM state | KubeVirt controller state PVC | Do not migrate live runtime controller state across clusters. Recreate it on the target unless KubeVirt documents a compatible procedure. |
| Hotplug volume requests | Runtime add/remove volume state | Quiesce and reconcile to the desired VM template before export. Do not export runtime attachment pods or VMI status. |

## Networking dependencies

The VM interface is defined in `spec.template.spec.domain.devices.interfaces`
and each interface refers by name to an entry in `spec.template.spec.networks`.
These fields are declarative and Crane will preserve them as opaque VM spec
data. That is not sufficient to make them usable on another cluster.

| Network type or dependency | KubeVirt behavior | Crane and cleanup plugin status | Required migration behavior |
| --- | --- | --- | --- |
| Pod network with `masquerade` binding | The guest receives an address behind the virt-launcher Pod network and NAT. Its Pod IP changes at cutover. | VM spec is preserved. No target CNI validation or guest reachability test. | Preserve the interface. Validate target CNI and recreate Service objects. Treat guest IP as non-portable. |
| Pod network with `bridge` binding | Guest is connected to the Pod network at layer 2. Some cluster CNIs do not support it. | Preserved without validation. | Require an explicit target capability check. Reject or transform when target CNI does not support bridge binding. |
| Pod network with `slirp` or `passt` binding | User-mode networking. Capability and behavior can differ by KubeVirt version. | Preserved without validation. | Check the target KubeVirt feature configuration and test guest outbound connectivity. |
| Multus `NetworkAttachmentDefinition` | A VM references `multus.networkName`; the NAD selects a secondary CNI and may include VLAN, IPAM, MAC, routes, and device configuration. | Generic export may export a NAD if it is included, but Crane does not follow the VM reference. The plugin does not inspect it. | Discover each referenced NAD. Include it only if its CNI configuration is portable; otherwise require a target NAD mapping. |
| Multus IPAM with DHCP, Whereabouts, static addresses, or routes | Guest addressing can be assigned by a CNI or fixed in NAD configuration. | No discovery or collision detection. | Allocate or map target addresses before start. Do not start source and target VM with the same static IP on a shared network. |
| Explicit interface MAC address | `macAddress` can be required by DHCP reservations, licenses, or firewalls. | Preserved as opaque data. | Preserve only after checking target network allows the MAC and that no running target workload conflicts. |
| SR-IOV, macvtap, host-device, DRA, or binding plugin | Depends on node NICs, resource names, device plugins, and often privileged target configuration. | No capability detection. | Reject by default. Permit only with an explicit source-to-target resource mapping and target preflight. |
| KubeVirt network binding plugin | VM interface refers to a KubeVirt cluster-level binding plugin. | No discovery. | Compare target `KubeVirt.spec.configuration.networkConfiguration.binding` with the source and fail if missing. |
| Kubernetes Service, EndpointSlice, DNS, NetworkPolicy | Services select virt-launcher Pods by VM template labels. EndpointSlices and Pods are runtime objects. NetworkPolicy affects the Pod network, not necessarily every secondary CNI. | KubernetesPlugin removes EndpointSlices and runtime Pods. It preserves Services and NetworkPolicies generically. | Keep Services and policies when selectors remain valid. Regenerate endpoint objects on target. Validate policy behavior for each CNI. |
| `subdomain`, `hostname`, DNS policy, DNS config | Creates guest and Pod DNS behavior. It can refer to cluster-local names or external resolvers. | Preserved without validation. | Retain configuration but validate target DNS domains, resolver reachability, and dependent Services. |
| Cloud-init network data | VM may configure addresses, routes, and DNS independently of the Pod CNI. | Preserved inline; Secret/ConfigMap dependency discovery is missing. | Include referenced cloud-init data and map static addresses, gateways, and DNS to the target network. |
| Live migration network and migration policy | KubeVirt runtime uses a migration network and controller state. It is not a cross-cluster migration mechanism. | Runtime VMI status should be removed. | Do not migrate `VirtualMachineInstanceMigration` objects or status. Recreate target VM instead. |
| `transfer-pvc` ingress endpoint | This is migration-control traffic, not guest networking. It requires target ingress, DNS/subdomain, TLS, and source-to-target reachability. | Current CLI requires manual `--subdomain` and explicit `--ingress-class` in this test. | Preflight and report endpoint reachability before stopping the source VM. |

The local test disables the Pod interface with `autoattachPodInterface: false`.
It verifies VM and PVC migration mechanics only; it does not validate a guest
network migration.

## OpenShift Virtualization differences

The KubeVirt plugin must stay platform-neutral because KubeVirt also runs on
upstream Kubernetes. The following items are specific to OpenShift
Virtualization and belong in OpenShift-specific validation or transformation.

| Area | OpenShift Virtualization difference | Required migration behavior | Owner |
| --- | --- | --- | --- |
| Installation and lifecycle | KubeVirt is commonly managed by OpenShift Virtualization, OLM, and the HyperConverged Operator in `openshift-cnv`. | Do not migrate KubeVirt CRDs, operator deployments, HyperConverged CRs, OLM resources, or operator namespaces. Verify target virtualization readiness. | `OpenShiftPlugin` and `crane validate` |
| Security admission | OpenShift uses SCC admission in addition to Kubernetes security controls. The virtualization operator grants KubeVirt components required privileges. | Do not export or recreate SCCs for VM workloads. Validate target admission and reject unsupported privileged dependencies. | `OpenShiftPlugin` |
| Storage configuration | CDI uses target storage classes, StorageProfiles, CSI snapshots, cloning support, and platform storage policies. | Map storage class, retain PVC volume mode, validate CDI and StorageProfile, and handle snapshots or clones explicitly. | Generic transfer plus OpenShift target preflight |
| PVC transfer endpoint | OpenShift can expose `transfer-pvc` through a Route. Upstream Kubernetes normally requires an ingress controller. | Select and validate Route only for OpenShift targets. Validate DNS, TLS, and source-to-target reachability before stopping the source VM. | `crane transfer-pvc` and `OpenShiftPlugin` |
| Networking | OVN-Kubernetes and Multus resources can depend on OpenShift network operators, SR-IOV Operator, MAC policy, and node resources. | Discover NADs generically. Check target OpenShift operators and require mappings for non-portable network resources. | KubeVirt discovery plus OpenShift preflight |
| Service exposure | A guest Service can be exposed with an OpenShift Route. EndpointSlices and virt-launcher Pods are runtime objects. | Keep Service selectors compatible with VM template labels, regenerate endpoints, and process Route resources only for OpenShift targets. | `OpenShiftPlugin` |
| Image access | `containerDisk` can refer to an OpenShift internal registry, ImageStream, custom CA, cluster image policy, or pull secret. | Resolve or replace ImageStream and internal registry references. Validate target image pull access and copy required secrets by policy. | `OpenShiftPlugin` |
| Project bootstrap objects | Projects include managed `builder` and `deployer` service accounts, generated pull secrets, service CA ConfigMaps, and RoleBindings. | Keep these objects out of the migration output. Existing OpenShiftPlugin cleanup should remain active. | `OpenShiftPlugin` |
| Templates and OLM | Source projects can contain OpenShift Templates, ImageStreams, BuildConfigs, Subscriptions, and CSVs unrelated to VM runtime. | Migrate only objects explicitly required by the dependency plan. Never treat a cluster operator as an application dependency. | `OpenShiftPlugin` |
| Console and RBAC | Console access and KubeVirt subresources can require OpenShift RBAC and console integration. | Validate target user access separately. Do not change VM manifests to compensate for missing console permissions. | `crane validate` and UI integration |

The split of responsibility is therefore:

- `KubeVirtPlugin`: VM cleanup, storage and configuration dependency discovery,
  runtime-object filtering, and generic KubeVirt capability checks.
- `OpenShiftPlugin`: Route support, SCC and project bootstrap policy,
  ImageStream/internal-registry resolution, and OpenShift operator validation.
- `crane transfer-pvc`: transfer correctness, Block and KubeVirt-disk transfer,
  destination PVC correctness, and endpoint preflight.

## Current implementation comparison

| Capability | Crane export/transform/apply | KubeVirtCleanupPlugin | Missing behavior |
| --- | --- | --- | --- |
| Export `VirtualMachine` CR | Generic discovery exports it. | Not applicable. | Must require target KubeVirt CRD/operator as a preflight. |
| Remove VM status and KubeVirt finalizers | KubernetesPlugin does not remove KubeVirt finalizers. | Tested. Removes finalizers, status, server metadata, and selected controller annotations. | Expand tests for every controller annotation and newer KubeVirt versions. |
| Exclude runtime objects | Generic KubernetesPlugin whiteouts owner-referenced resources; explicit export filters avoid VMI, launcher Pods, and ControllerRevisions. | Whiteouts VMI only. | Add explicit rules for runtime resources and KubeVirt revisions; export should avoid Events. |
| Discover direct PVC references | No. PVC is whiteouted as a general rule. | No. | Parse all VM template volumes, data volume templates, hotplug requests, memory dumps, and persistent state. |
| Transfer Filesystem PVC | Separate command. Current result is untrustworthy on rsync failure. | Not applicable. | Fail on non-zero rsync exit, retain diagnostics, and verify content. |
| Transfer Block PVC or KubeVirt `disk.img` | CLI does not select the available blockrsync implementation. | Not applicable. | Select blockrsync by PVC mode or KubeVirt content annotation; preserve volume mode. |
| CDI DataVolumes | No dependency handling. | No. | Add CDI discovery, ordering, and target preflight. |
| Configuration dependencies | No VM-aware discovery. | No. | Discover ConfigMaps, Secrets, ServiceAccounts, network attachments, instance types, preferences, and storage profiles. |
| Network dependencies | No VM-aware discovery or target CNI preflight. | No. | Discover networks, NADs, binding plugins, Service selectors, policies, cloud-init network data, and static addresses. |
| Cutover lifecycle | No VM-aware sequencing. | No. | Stop/suspend source VM, transfer each required volume, apply dependencies, apply halted target VM, verify, then restore requested run strategy. |

## Required implementation order

1. Fix `transfer-pvc` failure semantics. Return an error immediately after a
   non-zero rsync exit code. Preserve the final logs and transfer resources on
   failure or add an explicit diagnostic retention option.
2. Make `transfer-pvc` retain `spec.volumeMode` and select `blockrsync` for
   Block PVCs and PVCs marked as KubeVirt VM disks. Add Filesystem and Block
   integration tests that verify bytes inside the guest.
3. Turn `KubeVirtCleanupPlugin` into a supported transform stage. Add resource
   filtering, unit fixtures for VM metadata, and target KubeVirt preflight.
4. Add dependency discovery and an auditable transfer plan. It must list every
   VM, PVC, DataVolume, Secret, ConfigMap, NetworkAttachmentDefinition,
   InstanceType, Preference, network binding, and unsupported host-local
   dependency.
5. Implement cutover orchestration as an explicit workflow. Preserve the
   original run strategy in an artifact, create target VMs halted, and start
   them only after storage and dependency checks pass.
6. Add scenario coverage for direct filesystem PVCs, block PVCs, CDI import,
   CDI clone, DataVolume templates, RWX claims, hotplug disks, persistent TPM,
   UEFI state, ConfigMap/Secret cloud-init, Multus networking, and rejected
   hostDisk/containerPath cases.

## Sources

- KubeVirt v1.9.1 API: `https://github.com/kubevirt/api/blob/v1.9.1/core/v1/types.go`
- KubeVirt storage guide: `https://kubevirt.io/user-guide/storage/disks_and_volumes/`
- KubeVirt CDI guide: `https://kubevirt.io/user-guide/storage/containerized_data_importer/`
- `crane-lib/transform/kubernetes/kubernetes.go`
- `crane-lib/state_transfer/transfer/pvc_list.go`
- `crane-lib/state_transfer/transfer/blockrsync/`
- `crane/cmd/transfer-pvc/transfer-pvc.go`
