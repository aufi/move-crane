# OpenShift 4.x compatibility gaps that Crane does **not** handle

This document focuses only on changes that:

1. can make exported YAMLs fail or become incompatible when applied to a newer OpenShift 4.x cluster, and
2. are **not currently handled automatically by Crane** based on the current `crane` / `crane-lib` implementation.

> Notes:
> - This intentionally does **not** list things Crane already handles, such as removing `uid`, `resourceVersion`, `managedFields`, `status`, `clusterIP`, some `nodePort`, etc.
> - This is mainly about **API removals and schema incompatibilities**.
> - The version mapping is effectively driven by upstream Kubernetes API removals underneath OpenShift 4.x.
> - Coverage through OpenShift 4.22 was verified against the OpenShift release notes and Kubernetes API deprecation guide.

## Overview by target OpenShift version

| Target OpenShift | Underlying K8s | What becomes incompatible / stops working | Required change | Handled by Crane? |
|---|---:|---|---|---|
| **4.8** | 1.21 | No major new API removal breakpoint compared to 4.7; main risk is already-deprecated APIs that will break in later upgrades | Proactively audit `v1beta1` manifests | **No** |
| **4.9** | 1.22 | **Ingress** in `extensions/v1beta1` and `networking.k8s.io/v1beta1` is no longer served | Migrate to `networking.k8s.io/v1`, add `pathType`, change backend structure | **No** |
|  |  | **CRD** in `apiextensions.k8s.io/v1beta1` is no longer served | Migrate to `apiextensions.k8s.io/v1`, convert `spec.version` to `spec.versions[]`, use structural schemas | **No** |
|  |  | **Webhook configs** in `admissionregistration.k8s.io/v1beta1` are no longer served | Migrate to `v1`, add required fields such as `sideEffects`, `admissionReviewVersions`, etc. | **No** |
|  |  | `apiregistration.k8s.io/v1beta1` APIService | Migrate to `apiregistration.k8s.io/v1` | **No** |
|  |  | `authentication.k8s.io/v1beta1` TokenReview | Migrate to `authentication.k8s.io/v1` | **No** |
|  |  | `authorization.k8s.io/v1beta1` SAR/LSAR/SSAR/SSRR resources | Migrate to `authorization.k8s.io/v1` | **No** |
|  |  | `certificates.k8s.io/v1beta1` CSR | Migrate to `certificates.k8s.io/v1`, provide `signerName`, `usages`, etc. | **No** |
|  |  | `coordination.k8s.io/v1beta1` Lease | Migrate to `coordination.k8s.io/v1` | **No** |
|  |  | `rbac.authorization.k8s.io/v1beta1` RBAC resources | Migrate to `rbac.authorization.k8s.io/v1` | **No** |
|  |  | `scheduling.k8s.io/v1beta1` PriorityClass | Migrate to `scheduling.k8s.io/v1` | **No** |
|  |  | `storage.k8s.io/v1beta1` CSIDriver / CSINode / StorageClass / VolumeAttachment | Migrate to `storage.k8s.io/v1` | **No** |
| **4.10** | 1.23 | No major new API removal breakpoint compared to 4.9 | Continue auditing old APIs | **No** |
| **4.11** | 1.24 | No major new removal breakpoint for common manifests; however many old beta APIs are about to break in 4.12 | Audit CronJob / PDB / HPA / PSP before upgrading to 4.12 | **No** |
| **4.12** | 1.25 | **CronJob** in `batch/v1beta1` is no longer served | Migrate to `batch/v1` | **No** |
|  |  | **PodDisruptionBudget** in `policy/v1beta1` is no longer served | Migrate to `policy/v1` | **No** |
|  |  | **PodSecurityPolicy** in `policy/v1beta1` is removed entirely | Replace with another security model; PSP manifests cannot be imported | **No** |
|  |  | **HPA** in `autoscaling/v2beta1` is no longer served | Migrate to `autoscaling/v2` and update metric schema | **No** |
|  |  | `events.k8s.io/v1beta1` Event | Migrate to `events.k8s.io/v1` | **No** |
|  |  | `discovery.k8s.io/v1beta1` EndpointSlice | Migrate to `discovery.k8s.io/v1` | **No** |
|  |  | `node.k8s.io/v1beta1` RuntimeClass | Migrate to `node.k8s.io/v1` | **No** |
| **4.13** | 1.26 | **HPA** in `autoscaling/v2beta2` is no longer served | Migrate to `autoscaling/v2` | **No** |
|  |  | `flowcontrol.apiserver.k8s.io/v1beta1` is no longer served | Migrate to `v1beta2` or preferably a newer version | **No** |
| **4.14** | 1.27 | `storage.k8s.io/v1beta1` CSIStorageCapacity is no longer served | Migrate to `storage.k8s.io/v1` | **No** |
| **4.15** | 1.28 | No major new removal breakpoint for common manifests | Previous removals still apply | **No** |
| **4.16** | 1.29 | `flowcontrol.apiserver.k8s.io/v1beta2` is no longer served | Migrate to `flowcontrol.apiserver.k8s.io/v1` | **No** |
| **4.17** | 1.30 | No new upstream API removal breakpoint for common manifests. OpenShift SDN is removed, so SDN-specific cluster and network configuration is not portable to this release | Review OpenShift-specific networking resources and move the configuration to OVN-Kubernetes equivalents | **No** |
| **4.18** | 1.31 | No new upstream API removal breakpoint. The Shared Resource CSI Driver is removed. The `admissionregistration.k8s.io/v1beta1` API accidentally restored in 4.17 remains deprecated | Replace workloads that depend on the removed CSI driver; use `admissionregistration.k8s.io/v1` | **No** |
| **4.19** | 1.32 | `flowcontrol.apiserver.k8s.io/v1beta3` for `FlowSchema` and `PriorityLevelConfiguration` is no longer served | Migrate both resources to `flowcontrol.apiserver.k8s.io/v1` | **No** |
| **4.20** | 1.33 | OpenShift removes the `admissionregistration.k8s.io/v1beta1` API that was accidentally restored in 4.17. This affects `MutatingWebhookConfiguration`, `ValidatingWebhookConfiguration`, `ValidatingAdmissionPolicy`, and `ValidatingAdmissionPolicyBinding` | Migrate these resources to `admissionregistration.k8s.io/v1` and review required fields and defaults | **No** |
| **4.21** | 1.34 | No new Kubernetes API removal breakpoint for common workload manifests. The legacy `SiteConfig` and ZTP deployment workflow is removed | Replace `SiteConfig` resources with the SiteConfig Operator and `ClusterInstance` resources where relevant | **No** |
| **4.22** | 1.35 | No new Kubernetes API removal breakpoint for common workload manifests. The Dynamic Accelerator Slicer Operator is removed, so its custom resources are no longer reconciled | Replace DAS resources with the Dynamic Resource Allocation approach and verify its support level on the target cluster | **No** |

## Most important real-world incompatibilities

These are the most likely migration blockers in practice.

| Priority | Resource / API | Problem type | Handled by Crane? |
|---|---|---|---|
| 1 | `Ingress` in `v1beta1` | Removed API + schema change | **No** |
| 1 | `CRD` in `apiextensions.k8s.io/v1beta1` | Removed API + major schema change | **No** |
| 1 | `WebhookConfiguration` in `v1beta1` | Removed API + required field changes | **No** |
| 1 | `CronJob` in `batch/v1beta1` | Removed API | **No** |
| 1 | `PDB` in `policy/v1beta1` | Removed API | **No** |
| 1 | `HPA` in `autoscaling/v2beta1` or `v2beta2` | Removed API + schema change | **No** |
| 1 | `PodSecurityPolicy` | Completely removed | **No** |
| 1 | `FlowSchema` / `PriorityLevelConfiguration` in `flowcontrol.apiserver.k8s.io/v1beta3` | Removed API in OCP 4.19 | **No** |
| 1 | `ValidatingAdmissionPolicy` / `ValidatingAdmissionPolicyBinding` in `admissionregistration.k8s.io/v1beta1` | Removed API in OCP 4.20 | **No** |
| 2 | Operator custom resources | CRD/schema/operator mismatch | **No** |
| 2 | OpenShift `Route` / `BuildConfig` / `ImageStream` / `DeploymentConfig` | Functional / semantic incompatibility | **No** |
| 2 | `config.openshift.io/*` | Cluster-specific resources | **No** |

## What Crane does **not** handle across all OpenShift versions

These are general gaps, independent of a specific OCP minor version.

| Area | Problem | Handled by Crane? |
|---|---|---|
| `apiVersion` upgrades | Does not rewrite old API versions to new ones | **No** |
| Schema migrations | Does not restructure manifests for newer APIs | **No** |
| CRD compatibility | Does not compare CRD schemas across clusters | **No** |
| Operator compatibility | Does not understand operator version-specific requirements | **No** |
| OpenShift-specific semantics | Does not handle Route / DC / BC / IS / SCC logic | **No** |
| Target admission policies | Does not validate against SCC / PSA / webhooks | **No** |
| Cluster-scoped portability | Does not identify cluster-bound resources automatically | **No** |

## Simplified summary by target version

| Target OCP | Main new risk that Crane does not handle |
|---|---|
| **4.9** | Ingress v1beta1, CRD v1beta1, webhook v1beta1, other old beta APIs |
| **4.12** | CronJob v1beta1, PDB v1beta1, PSP, HPA v2beta1 |
| **4.13** | HPA v2beta2, flowcontrol v1beta1 |
| **4.14** | CSIStorageCapacity v1beta1 |
| **4.16** | flowcontrol v1beta2 |
| **4.17** | OpenShift SDN removal; SDN-specific configuration is not portable |
| **4.18** | Shared Resource CSI Driver removal; admissionregistration v1beta1 remains deprecated |
| **4.19** | flowcontrol v1beta3; cgroup v1 workload assumptions |
| **4.20** | admissionregistration v1beta1, including validating admission policy resources |
| **4.21** | Legacy SiteConfig/ZTP resources and workflow |
| **4.22** | Dynamic Accelerator Slicer custom resources |

## Practical takeaway

If you migrate exported manifests from **OpenShift 4.A to 4.B**, then on top of Crane output you still need to do at least:

1. scan all `apiVersion` values
2. compare them with the removals between `4.A` and `4.B`
3. manually or programmatically convert resources with schema changes
4. separately review:
   - CRDs and custom resources
   - OpenShift-specific resources
   - cluster-scoped configuration resources

## Scope beyond OpenShift 4.22

OpenShift 5 release documentation is now public, but migration from OpenShift 4.x to 5.x is outside the scope of this document. See [OpenShift 4.22 to 5.0 migration compatibility](ocp-4.22-to-5.0-migration.md) for the pre-release analysis.

## Sources

- [Kubernetes Deprecated API Migration Guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)
- [OpenShift Container Platform 4.17 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/release_notes/ocp-4-17-release-notes)
- [OpenShift Container Platform 4.18 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/release_notes/ocp-4-18-release-notes)
- [OpenShift Container Platform 4.19 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/release_notes/ocp-4-19-release-notes)
- [OpenShift Container Platform 4.20 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/release_notes/ocp-4-20-release-notes)
- [OpenShift Container Platform 4.21 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/release_notes/ocp-4-21-release-notes)
- [OpenShift Container Platform 4.22 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/release_notes/ocp-4-22-release-notes)
