# Extending Crane for Migrations from Managed Kubernetes to OCP 4 or 5

## Purpose

This directory supports discovery, experimental validation, and planning of Crane changes needed to migrate workloads from managed Kubernetes services into OpenShift Container Platform (OCP) 4 or 5. Azure Kubernetes Service (AKS) is the first source platform, followed by Amazon Elastic Kubernetes Service (EKS) and selected VMware Tanzu workload-cluster profiles. The same process should be reusable for other providers.

OCP is the fixed target platform, but OCP 4 and OCP 5 are separate target profiles. Upstream Kubernetes on local clusters, such as kind or minikube, provides an optional source-side control baseline without cloud integrations.

This documentation does not claim that every AKS, EKS, or Tanzu configuration is supported. Compatibility always applies to a specific combination of:

- source managed platform and exact target OCP major, minor, and patch version,
- Kubernetes versions,
- enabled add-ons, CRDs, and admission policies,
- network model and public or private connectivity,
- CSI drivers, StorageClasses, and access modes,
- Crane version and build.

## Compatibility Scope

Assessment has two independent gates:

1. **Workload manifests**: resources exported from xKS can be transformed and created on the exact OCP 4 or OCP 5 target profile, and the workload becomes functional.
2. **Persistent data**: `crane transfer-pvc` can create the target OCP PVC, run mover pods, connect the clusters, and verify the copied data on that target profile.

Passing only one gate does not make a stateful workload migration supported.

## Deployment Constraints

The solution must remain CLI-only and file-based:

- Crane must not require or install an operator on either cluster.
- Crane must not install CRDs or create Crane-specific custom resources.
- Discovery and compatibility findings must be written to local YAML, JSON, or Markdown files.
- Temporary in-cluster resources are limited to Kubernetes objects required by `transfer-pvc`, such as Pods, Services, Secrets, ConfigMaps, PVCs, and the validated OCP endpoint resource.
- Existing application CRDs and controllers may be inspected read-only to determine portability, but Crane does not install or manage them.

## Documents

| Document | Purpose |
| --- | --- |
| [PROVIDER_SUPPORT_WORKFLOW.md](PROVIDER_SUPPORT_WORKFLOW.md) | Delivery workflow for AKS, EKS, and Tanzu support, from infrastructure access through standard E2E, xKS plugin development, and user documentation |
| [PROVIDER_VALIDATION.md](PROVIDER_VALIDATION.md) | Repeatable process for validating another provider |
| [API_RESOURCE_COMPATIBILITY.md](API_RESOURCE_COMPATIBILITY.md) | Classification of incompatible API kinds, existing application CRDs, and platform dependencies |
| [OCP_TARGET_VERSIONS.md](OCP_TARGET_VERSIONS.md) | Impact analysis and validation gates for OCP 4 and OCP 5 targets |
| [TRANSFER_PVC_VALIDATION.md](TRANSFER_PVC_VALIDATION.md) | Network, security, and storage validation matrix for `transfer-pvc` |
| [AKS.md](AKS.md) | AKS dependency decisions, migration increments, validation backlog, and Crane work packages |
| [AKS_DISCOVERY.md](AKS_DISCOVERY.md) | Read-only AKS and Azure evidence collection before migration validation |
| [EKS.md](EKS.md) | Follow-up validation and implementation plan for EKS |
| [TANZU_VCF.md](TANZU_VCF.md) | TKG, VKS, and VCF distinctions, selected workload-cluster profiles, and validation scope for migration to OCP 4 or 5 |
| [TANZU_ADOPTION.md](TANZU_ADOPTION.md) | Public Tanzu usage evidence, limits of distribution statistics, and development priorities based on migration demand |
| [VALIDATION_REPORT_TEMPLATE.md](VALIDATION_REPORT_TEMPLATE.md) | Reproducible report template for a specific platform profile |
| [todo/](todo/README.md) | Required changes and checks discovered during migration runs |
| [WordPress AKS to CRC migration](wordpress-aks/migration-2026-10-21/MIGRATION_AKS_TO_CRC.md) | Complete validated procedure using Crane and indirect S3 PVC transfer |

## Work Order

Follow [the provider support workflow](PROVIDER_SUPPORT_WORKFLOW.md):

1. Obtain cloud/platform account access and prepare a versioned source and target profile.
2. Discover APIs, CRDs, networking, storage, and external dependencies.
3. Run the standard Crane tier0 and tier1 E2E suites and record applicability and failures.
4. Build provider-specific demonstration and verification applications.
5. Implement and test manifest rules in [crane-plugin-xks-to-ocp](https://github.com/migtools/crane-plugin-xks-to-ocp), with general fixes in Crane or crane-lib.
6. Verify complete migrations, including storage mappings, direct and indirect transfer, and application behavior.
7. Automate regressions and validate source/target upgrades and OCP majors independently.
8. Publish the tested support matrix and runnable user migration guides.

## Minimum Support Matrix

Each source provider must be validated against OCP independently:

| Source | Target | Manifests | Direct PVC transfer | Indirect PVC transfer |
| --- | --- | --- | --- | --- |
| AKS | OCP 4 | Independent validation | Independent validation | Required fallback |
| AKS | OCP 5 | Independent validation | Independent validation | Required fallback |
| EKS | OCP 4 | Independent validation | Independent validation | Required fallback |
| EKS | OCP 5 | Independent validation | Independent validation | Required fallback |
| Selected Tanzu product and workload-cluster profile | OCP 4 or 5 | Product and target-major validation | Product and target-major validation | Required fallback |
| Other managed Kubernetes | OCP 4 or 5 | Provider and target-major validation | Provider and target-major validation | Required fallback |
| Upstream Kubernetes | OCP 4 or 5 | Optional control test per target major | Optional control test per target major | Optional |

OCP-to-cloud and cloud-to-cloud migrations are explicitly outside the scope of these plans.

Passing against OCP 4 does not imply support for OCP 5, or the reverse. See [OCP_TARGET_VERSIONS.md](OCP_TARGET_VERSIONS.md).

## Expected Validation Outputs

- An inventory of source APIs and dependencies missing from the target.
- A decision for each problematic kind: transfer, transform, replace, or omit.
- Separate compatibility results for every tested OCP major and minor version.
- StorageClass mappings based on capabilities rather than names alone.
- A verified network topology for direct and indirect transfers.
- Reproducible tests and retained artifacts.
- A list of concrete changes in the appropriate Crane ecosystem repositories.

## Crane Baseline

When these notes were created, the `main` branch of `migtools/crane` was checked at commit `7f87cc2641ccd1e249d387402a35c35cdb4e6b4b` dated 2026-09-16. `transfer-pvc` supports `route` and `nginx-ingress` endpoints, PVC name and namespace mapping, target StorageClass selection, and indirect transfer through S3-compatible object storage using rclone configuration.

This is only the initial baseline. Every report must record its own Crane commit or release.

## Related Notes

- [OCP 4.x compatibility gaps](../ocp-4x-compatibility.md)
- [OpenShift 4.22 to 5.0 migration compatibility](../ocp-4.22-to-5.0-migration.md)
- [OCP target version impact analysis](OCP_TARGET_VERSIONS.md)
- [Namespace-scoped applications with hidden cluster dependencies](../namespace-app-cluster-dependencies.md)
- [Stateful workload migration flow](../data-migrations/STATEFUL_FLOW.md)
- [stunnel setup details](../data-migrations/STUNNEL_SETUP_DETAILS.md)
