# Extending Crane for Migrations Between OCP and Managed Kubernetes

## Purpose

This directory supports discovery, experimental validation, and planning of Crane changes needed to migrate workloads between OpenShift Container Platform 4 (OCP 4) and managed Kubernetes services. Azure Kubernetes Service (AKS) is the first target, followed by Amazon Elastic Kubernetes Service (EKS). The same process should be reusable for other providers.

OCP 4 remains the primary reference platform. Upstream Kubernetes on local clusters, such as kind or minikube, provides a control baseline without cloud integrations.

This documentation does not claim that every AKS or EKS configuration is supported. Compatibility always applies to a specific combination of:

- source and target platforms and versions,
- Kubernetes versions,
- enabled add-ons, CRDs, and admission policies,
- network model and public or private connectivity,
- CSI drivers, StorageClasses, and access modes,
- Crane version and build.

## Compatibility Scope

Assessment has two independent gates:

1. **Workload manifests**: exported resources can be transformed and created on the target, and the workload becomes functional.
2. **Persistent data**: `crane transfer-pvc` can create the target PVC, run mover pods, connect the clusters, and verify the copied data.

Passing only one gate does not make a stateful workload migration supported.

## Deployment Constraints

The solution must remain CLI-only and file-based:

- Crane must not require or install an operator on either cluster.
- Crane must not install CRDs or create Crane-specific custom resources.
- Discovery and compatibility findings must be written to local YAML, JSON, or Markdown files.
- Temporary in-cluster resources are limited to standard Kubernetes objects required by `transfer-pvc`, such as Pods, Services, Secrets, ConfigMaps, PVCs, and Ingresses or OCP Routes.
- Existing application CRDs and controllers may be inspected read-only to determine portability, but Crane does not install or manage them.

## Documents

| Document | Purpose |
| --- | --- |
| [PROVIDER_VALIDATION.md](PROVIDER_VALIDATION.md) | Repeatable process for validating another provider |
| [API_RESOURCE_COMPATIBILITY.md](API_RESOURCE_COMPATIBILITY.md) | Classification of incompatible API kinds, existing application CRDs, and platform dependencies |
| [TRANSFER_PVC_VALIDATION.md](TRANSFER_PVC_VALIDATION.md) | Network, security, and storage validation matrix for `transfer-pvc` |
| [AKS.md](AKS.md) | Initial validation and implementation plan for AKS |
| [EKS.md](EKS.md) | Follow-up validation and implementation plan for EKS |
| [VALIDATION_REPORT_TEMPLATE.md](VALIDATION_REPORT_TEMPLATE.md) | Reproducible report template for a specific platform profile |

## Work Order

1. Freeze reference versions of OCP, kind/minikube, and the managed cluster.
2. Run general discovery and build an API difference matrix.
3. Validate stateless workloads and platform transformations.
4. Validate dynamic provisioning and StorageClass mapping.
5. Validate direct `transfer-pvc` through an endpoint on the target cluster.
6. Validate indirect transfer through object storage for private or disconnected clusters.
7. Repeat both migration directions and at least one target minor-version upgrade.
8. Derive concrete changes for Crane, plugins, and documentation from the findings.

## Minimum Support Matrix

Each provider must track these directions independently:

| Source | Target | Manifests | Direct PVC transfer | Indirect PVC transfer |
| --- | --- | --- | --- | --- |
| OCP 4 | Managed Kubernetes | Required | Required when networking permits | Required fallback |
| Managed Kubernetes | OCP 4 | Required | Required when networking permits | Required fallback |
| Upstream Kubernetes | Managed Kubernetes | Control test | Control test | Optional |
| Managed Kubernetes | Upstream Kubernetes | Control test | Control test | Optional |

Cross-cloud managed-to-managed migrations are a later phase, but the methodology must not preclude them.

## Expected Validation Outputs

- An inventory of source APIs and dependencies missing from the target.
- A decision for each problematic kind: transfer, transform, replace, or omit.
- StorageClass mappings based on capabilities rather than names alone.
- A verified network topology for direct and indirect transfers.
- Reproducible tests and retained artifacts.
- A list of concrete changes in the appropriate Crane ecosystem repositories.

## Crane Baseline

When these notes were created, the `main` branch of `migtools/crane` was checked at commit `7f87cc2641ccd1e249d387402a35c35cdb4e6b4b` dated 2026-09-16. `transfer-pvc` supports `route` and `nginx-ingress` endpoints, PVC name and namespace mapping, target StorageClass selection, and indirect transfer through S3-compatible object storage using rclone configuration.

This is only the initial baseline. Every report must record its own Crane commit or release.

## Related Notes

- [OCP 4.x compatibility gaps](../ocp-4x-compatibility.md)
- [Namespace-scoped applications with hidden cluster dependencies](../namespace-app-cluster-dependencies.md)
- [Stateful workload migration flow](../data-migrations/STATEFUL_FLOW.md)
- [stunnel setup details](../data-migrations/STUNNEL_SETUP_DETAILS.md)
