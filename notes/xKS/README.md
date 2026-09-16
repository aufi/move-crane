# Extending Crane for Migrations from Managed Kubernetes to OCP 4 or 5

## Purpose

This directory supports discovery, experimental validation, and planning of Crane changes needed to migrate workloads from managed Kubernetes services into OpenShift Container Platform (OCP) 4 or 5. Azure Kubernetes Service (AKS) is the first source platform, followed by Amazon Elastic Kubernetes Service (EKS). The same process should be reusable for other providers.

OCP is the fixed target platform, but OCP 4 and OCP 5 are separate target profiles. Upstream Kubernetes on local clusters, such as kind or minikube, provides an optional source-side control baseline without cloud integrations.

This documentation does not claim that every AKS or EKS configuration is supported. Compatibility always applies to a specific combination of:

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
| [PROVIDER_VALIDATION.md](PROVIDER_VALIDATION.md) | Repeatable process for validating another provider |
| [API_RESOURCE_COMPATIBILITY.md](API_RESOURCE_COMPATIBILITY.md) | Classification of incompatible API kinds, existing application CRDs, and platform dependencies |
| [OCP_TARGET_VERSIONS.md](OCP_TARGET_VERSIONS.md) | Impact analysis and validation gates for OCP 4 and OCP 5 targets |
| [TRANSFER_PVC_VALIDATION.md](TRANSFER_PVC_VALIDATION.md) | Network, security, and storage validation matrix for `transfer-pvc` |
| [AKS.md](AKS.md) | Initial validation and implementation plan for AKS |
| [EKS.md](EKS.md) | Follow-up validation and implementation plan for EKS |
| [VALIDATION_REPORT_TEMPLATE.md](VALIDATION_REPORT_TEMPLATE.md) | Reproducible report template for a specific platform profile |

## Work Order

1. Freeze reference versions of the source managed cluster, exact OCP 4 or OCP 5 target, and optional kind/minikube source baseline.
2. Run general discovery and build an API difference matrix.
3. Validate stateless workloads and platform transformations.
4. Validate dynamic provisioning and StorageClass mapping.
5. Validate direct `transfer-pvc` through the target endpoint contract, currently an OCP Route.
6. Validate indirect transfer through object storage for private or disconnected clusters.
7. Repeat after at least one source provider and target OCP minor-version upgrade; validate OCP 4 and OCP 5 independently.
8. Derive concrete changes for Crane, plugins, and documentation from the findings.

## Minimum Support Matrix

Each source provider must be validated against OCP independently:

| Source | Target | Manifests | Direct PVC transfer | Indirect PVC transfer |
| --- | --- | --- | --- | --- |
| AKS | OCP 4 | Independent validation | Independent validation | Required fallback |
| AKS | OCP 5 | Independent validation | Independent validation | Required fallback |
| EKS | OCP 4 | Independent validation | Independent validation | Required fallback |
| EKS | OCP 5 | Independent validation | Independent validation | Required fallback |
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
- [OCP target version impact analysis](OCP_TARGET_VERSIONS.md)
- [Namespace-scoped applications with hidden cluster dependencies](../namespace-app-cluster-dependencies.md)
- [Stateful workload migration flow](../data-migrations/STATEFUL_FLOW.md)
- [stunnel setup details](../data-migrations/STUNNEL_SETUP_DETAILS.md)
