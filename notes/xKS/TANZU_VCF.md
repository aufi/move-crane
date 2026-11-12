# Tanzu Kubernetes Grid, VKS, and VCF migrations to OCP 4 or 5

## Purpose

This document refines the selected VMware Tanzu workload-cluster profiles in the [xKS plan](README.md). It supports discovery, experimental validation, and planning of Crane changes for migration to OpenShift Container Platform, OCP 4 or 5. AKS remains the first source platform, followed by EKS and selected Tanzu profiles.

OCP is the fixed target. OCP 4 and OCP 5 require separate validation against exact major, minor, and patch releases. This analysis does not establish support for any Tanzu configuration.

## Conclusion

Crane needs to distinguish the source cluster type, but "TKG before Broadcom versus VCF after Broadcom" is not the right technical boundary.

Most application migration logic can be shared between standalone Tanzu Kubernetes Grid workload clusters and Supervisor-managed workload clusters. Discovery, prerequisites, and validation must distinguish the actual Kubernetes deployment and its integrations. Testing one profile does not establish support for the others.

This analysis concerns migration of Kubernetes applications and their persistent data to OCP 4 or 5. VMware infrastructure migration, OCP-to-cloud migration, and cloud-to-cloud migration are outside the scope of the xKS plan.

## Compatibility scope

Assess each selected source profile through two independent gates:

1. Workload manifests can be exported, transformed, and created on the exact target OCP release, and the application becomes functional.
2. `crane transfer-pvc` can create target PVCs, run mover Pods, connect the clusters or staging backend, and verify the copied data on that target profile.

Passing only one gate does not establish support for a stateful workload migration. Passing against OCP 4 does not establish support for OCP 5, or the reverse. Use the [OCP target version gates](OCP_TARGET_VERSIONS.md).

Record the source product and release, cluster type, source and target Kubernetes versions, installed add-ons and CRDs, admission policies, network topology, CSI drivers, StorageClasses, access modes, and Crane/plugin versions for every result. Use the [validation report template](VALIDATION_REPORT_TEMPLATE.md).

## Deployment constraints

Follow the CLI-only, file-based constraints in the [xKS plan](README.md#deployment-constraints):

- Crane does not require or install an operator on either cluster, install CRDs, or create Crane-specific custom resources.
- Discovery inspects existing platform and application dependencies read-only and writes findings to local YAML, JSON, or Markdown files.
- Temporary in-cluster resources are limited to the Kubernetes objects required by `transfer-pvc` and the validated OCP endpoint resource.
- Target controllers and external integrations are prerequisites prepared by their owners. Crane does not install or manage them.
- Transformations produce local artifacts. `crane apply` renders files; deployment to OCP is a separate operator action.

## Product names and architecture

| Name | What it describes | Implication for migration |
| --- | --- | --- |
| Tanzu Kubernetes Grid with a standalone management cluster, often called TKGm | A dedicated management cluster provisions Kubernetes workload clusters through Cluster API | Export applications from a workload cluster rather than the management cluster |
| Tanzu Kubernetes Grid Service, often called TKGs, now vSphere Kubernetes Service, VKS | A service on vSphere Supervisor that provisions Kubernetes workload clusters | Export applications from the provisioned workload cluster rather than its parent Supervisor namespace |
| VMware Cloud Foundation, VCF | The broader private-cloud infrastructure platform, which existed before the acquisition | "VCF" alone does not identify the Kubernetes source |
| vSphere Pods running directly on Supervisor | Container workloads running through the Supervisor environment rather than inside a separate workload cluster | Requires a separate migration assessment |
| Tanzu Kubernetes Grid Integrated Edition, TKGI | A separate product with different cluster management architecture | Treat as another source profile if customers require it |

Broadcom explicitly describes VKS as "formerly known as TKG Service." Its documentation also distinguishes standalone TKG management clusters from Supervisor-based management. See [About Tanzu Kubernetes Grid](https://techdocs.broadcom.com/us/en/vmware-tanzu/standalone-components/tanzu-kubernetes-grid/2-5/tkg/about-tkg-index.html) and the [standalone TKG versus VKS comparison](https://techdocs.broadcom.com/us/en/vmware-tanzu/standalone-components/tanzu-kubernetes-grid/2-5/tkg/migrate-tkgs-migration.html).

VKS is the relevant successor name for TKG Service. VCF is not a replacement name for all TKG deployments.

The acquisition date does not identify the architecture. An older deployment may already use Supervisor, while an existing customer may still run standalone TKG.

## Differences that affect Crane

For applications using ordinary Deployments, StatefulSets, Services, Secrets, and PVCs, the basic workflow remains export, transform, render, and deploy to OpenShift. Persistent-data transfer is a separate operation.

Differences become important where the application depends on the source platform.

| Area | Differences to inspect | Consequence for Crane |
| --- | --- | --- |
| Cluster access | Standalone TKG and Supervisor-managed clusters can use different authentication and credential helpers | Document and verify a usable workload-cluster kubeconfig, including credential renewal |
| Storage | Standalone TKG commonly uses vSphere CSI directly. Supervisor-managed clusters can use paravirtual CSI, pvCSI, through Supervisor and its storage policies | Discover the actual driver and StorageClasses. Map storage capabilities and copy application data |
| Exposure | NSX, Avi/NSX ALB, Contour, or other implementations may provide load balancing and ingress | Inspect annotations and custom resources. Replace source-specific behavior with an explicit OpenShift configuration |
| Network security | Antrea or Calico policies, NSX rules, and external firewalls may affect application traffic | Exported Kubernetes manifests may not capture all required security behavior |
| Add-ons | Package-managed controllers, secret integrations, Harbor, and other services vary by installation | Assess each application dependency and record its target equivalent as an owner-managed prerequisite |
| Runtime restrictions | Kubernetes version, admission policy, node OS, security settings, and scheduling constraints vary | Validate application Pods and transfer-mover Pods on the exact source/target profile |

These are discovery categories, not assumptions that every Tanzu or VKS installation has the listed components.

### Storage and persistent-data transfer

Broadcom documents that a PVC in a Supervisor-managed workload cluster can produce a corresponding PVC on Supervisor, with provisioning mediated through pvCSI. These are two representations of the source storage path, not two independent application volumes to migrate. See [Storage for Supervisor-managed TKG clusters](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere-supervisor/8-0/vsphere-supervisor-concepts-and-planning/tanzu-kubernetes-grid-architecture-and-components/storage-for-tanzu-kubernetes-grid-clusters.html).

For `crane transfer-pvc`, validate whether the mover can:

- Mount the application PVC with its actual access mode and topology constraints.
- Run under source admission and security rules.
- Reach the target OpenShift endpoint for direct transfer or the staging backend for indirect transfer.
- Copy and preserve the data and metadata required by the application.

A different storage backend does not automatically require a different copy mechanism, but it does require validation. Create target PVCs using an explicit target storage mapping rather than reusing source PV handles or storage-policy references.

See [PVC transfer validation](TRANSFER_PVC_VALIDATION.md) for the shared validation process.

## Migration boundary

Distinguish these source contexts before export:

| Source context | Assessment |
| --- | --- |
| Application namespace inside a workload cluster | Fits the existing xKS-to-OpenShift application migration model |
| vSphere Namespace on Supervisor containing cluster definitions, VMs, and infrastructure resources | Is not equivalent to an application namespace |
| Applications running directly as vSphere Pods | Needs separate export, runtime, storage, and mover validation |

Cluster API `Cluster` and `Machine` objects, and legacy `TanzuKubernetesCluster` objects, describe how VMware creates the source cluster. They should not become application configuration on OpenShift.

The transition from `TanzuKubernetesCluster` APIs to Cluster API matters to platform discovery and automation, but usually does not change an application's Deployment or StatefulSet transformation. Broadcom documents that transition in the [VKS release notes](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere-supervisor/8-0/release-notes/vmware-tanzu-kubernetes-grid-service-release-notes.html).

## Recommended support model

See [Tanzu adoption evidence and development priorities](TANZU_ADOPTION.md) for public customer-count estimates, their limitations, lifecycle-driven migration pressure, and a provisional development order. No reliable public usage split between these distributions was found in that research.

Use one VMware Tanzu/VKS source family with independently validated candidate profiles. The table describes validation scope, not established support.

| Profile | Initial scope |
| --- | --- |
| Standalone TKG workload cluster on vSphere | Application manifests and filesystem PVC migration |
| Legacy Supervisor-managed TKG Service workload cluster | Same scope, with its exact release and integrations recorded |
| VKS workload cluster on a named vSphere/VCF release | Same scope, independently validated |
| Direct Supervisor/vSphere Pod workloads | Outside the initial workload-cluster scope; requires a separate scope decision and assessment |
| TKGI | Additional candidate workload-cluster profile only if selected for validation |

Share transformation rules according to the dependency discovered, such as Contour `HTTPProxy`, Avi annotations, Antrea policies, or storage-policy references. Use the product profile to guide discovery and testing.

The existing [provider support workflow](PROVIDER_SUPPORT_WORKFLOW.md) already requires an exact Tanzu product, release, cluster type, CSI implementation, and exposure stack. Apply the same manifest and persistent-data gates described in the [xKS scope](README.md), with independent validation for each claimed OpenShift target profile.

For every selected workload-cluster profile, use this minimum matrix:

| Source | Target | Manifests | Direct PVC transfer | Indirect PVC transfer |
| --- | --- | --- | --- | --- |
| Exact selected Tanzu/VKS product, release, and workload-cluster profile | Exact OCP 4 release | Independent validation | Independent validation | Required fallback |
| Exact selected Tanzu/VKS product, release, and workload-cluster profile | Exact OCP 5 release | Independent validation | Independent validation | Required fallback |

Retain separate results for each transport and target major. Record untested combinations as unknown.

## Validation work order and outputs

Follow the [provider support workflow](PROVIDER_SUPPORT_WORKFLOW.md) and [provider validation procedure](PROVIDER_VALIDATION.md):

1. Obtain platform access and usable source/target kubeconfigs. Prepare an exact workload-cluster and OCP target profile with repeatable setup instructions.
2. Discover APIs, CRDs, networking, storage, and external dependencies. Record each problematic kind or field and its transfer, transform, replace, or omit decision using [API resource compatibility](API_RESOURCE_COMPATIBILITY.md).
3. Run the standard Crane tier0 and tier1 E2E suites. Retain applicability decisions, failures, logs, and tool versions.
4. Build demonstration applications that exercise the installed exposure stack and selected CSI storage policy. Add policy, RWX, identity, or secret integrations only for the corresponding support claims.
5. Implement and test manifest rules in [crane-plugin-xks-to-ocp](https://github.com/migtools/crane-plugin-xks-to-ocp). Put general fixes in Crane or crane-lib and retain auditable transformation fixtures.
6. Verify complete migrations, including target storage provisioning, direct transfer, the required indirect fallback, data checks, and application behavior.
7. Automate regression coverage and validate source/target upgrades and OCP majors independently.
8. Publish the tested matrix, remaining limitations, and runnable user migration procedure.

Retain an API/dependency inventory, capability-based StorageClass mappings, verified transfer topology, separate manifest and persistent-data results, reproducible artifacts, and concrete follow-up work in the appropriate Crane ecosystem repositories. Every report must identify its own Crane commit or release rather than assuming the initial baseline in the README.

### Information to collect from a customer

- Exact product and release, including whether it is standalone TKG, Supervisor-managed TKG Service/VKS, or TKGI.
- Whether the application runs inside a workload cluster or directly on Supervisor.
- vSphere/VCF version, Kubernetes version, and TKr/VKr release where applicable.
- Installed CSI drivers, StorageClasses, storage policies, access modes, volume modes, and topology.
- CNI, network policies, ingress/Gateway controllers, load balancer implementation, and external firewall dependencies.
- Authentication, registry, secret-management, and other external application dependencies.
- Source-to-target or source-to-staging connectivity for persistent-data transfer.

The useful intake question is "Which product, version, cluster type, storage, and networking stack?" rather than only "Tanzu or VCF?"

## Evidence and limits

Vendor documentation reviewed on 2026-11-12. This is an architecture and migration-scope analysis, not evidence of a completed Crane migration test.

- [About Tanzu Kubernetes Grid](https://techdocs.broadcom.com/us/en/vmware-tanzu/standalone-components/tanzu-kubernetes-grid/2-5/tkg/about-tkg-index.html) distinguishes standalone management clusters, Supervisor, and TKGI.
- [Standalone TKG versus VKS and migration considerations](https://techdocs.broadcom.com/us/en/vmware-tanzu/standalone-components/tanzu-kubernetes-grid/2-5/tkg/migrate-tkgs-migration.html) provides an architecture comparison. Some feature comparisons reflect older release assumptions. Use release-specific documentation for capabilities.
- [Storage for Supervisor-managed TKG clusters](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere-supervisor/8-0/vsphere-supervisor-concepts-and-planning/tanzu-kubernetes-grid-architecture-and-components/storage-for-tanzu-kubernetes-grid-clusters.html) describes storage-policy propagation and pvCSI.
- [VKS 3.3.3 and earlier release notes](https://techdocs.broadcom.com/us/en/vmware-cis/vsphere/vsphere-supervisor/8-0/release-notes/vmware-tanzu-kubernetes-grid-service-release-notes.html) describe lifecycle decoupling and the TKC API transition.
- [VKS release notes in the VCF documentation](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/release-notes/vks-release-notes.html) and [Managing VKS with vSphere Supervisor](https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vcf-service-administration-and-development/9-1/managing-vsphere-kubernetes-service.html) describe the current service and its administration.
