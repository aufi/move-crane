# OpenShift 4.x compatibility gaps that Crane does **not** handle

This document focuses only on changes that:

1. can make exported YAMLs fail or become incompatible when applied to a newer OpenShift 4.x cluster, and
2. are **not currently handled automatically by Crane** based on the current `crane` / `crane-lib` implementation.

> Notes:
> - This intentionally does **not** list things Crane already handles, such as removing `uid`, `resourceVersion`, `managedFields`, `status`, `clusterIP`, some `nodePort`, etc.
> - This is mainly about **API removals and schema incompatibilities**.
> - The version mapping is effectively driven by upstream Kubernetes API removals underneath OpenShift 4.x.

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
| **4.17+** | 1.30+ | Depends on the exact minor version; more upstream removals continue | Check the deprecation guide for the exact target version | **No** |

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

## Practical takeaway

If you migrate exported manifests from **OpenShift 4.A to 4.B**, then on top of Crane output you still need to do at least:

1. scan all `apiVersion` values
2. compare them with the removals between `4.A` and `4.B`
3. manually or programmatically convert resources with schema changes
4. separately review:
   - CRDs and custom resources
   - OpenShift-specific resources
   - cluster-scoped configuration resources

## What to expect for a future OpenShift 5 line

At the time of writing, there is no stable public "OpenShift 5 API deprecations" compatibility matrix comparable to the mature OpenShift 4.x release documentation. However, a large part of the future compatibility story can already be anticipated from **upstream Kubernetes version changes**.

In practice, that means two things:

1. **Some future incompatibilities are already predictable** because they are inherited from Kubernetes API deprecations and removals in newer upstream versions.
2. **Some OpenShift-specific changes will remain unclear until Red Hat publishes concrete product documentation**, especially for OpenShift-specific APIs, operators, and cluster configuration resources.

### What is already reasonably predictable

The following areas are primarily driven by upstream Kubernetes evolution and should be expected to continue affecting any future OpenShift major line:

- removal of additional deprecated beta APIs in newer Kubernetes releases
- more pressure to migrate old manifests to stable API versions
- stricter schema expectations for CRDs and admission resources
- continued breakage of manifests that rely on legacy defaults in webhook and policy resources
- more field-level incompatibilities caused by upstream API shape changes rather than by OpenShift itself

Examples of this pattern already visible in newer upstream Kubernetes versions include:

- additional `flowcontrol.apiserver.k8s.io/*` removals and migrations
- continued elimination of deprecated beta APIs in favor of stable `v1` resources
- CRD and admission resources becoming increasingly strict about required fields and schema structure

### What is not yet clear

The following items are much harder to predict until OpenShift 5-specific documentation exists:

- which OpenShift-specific APIs might be deprecated or removed
- whether any `config.openshift.io/*` resources will change compatibility expectations
- future compatibility of resources such as `Route`, `DeploymentConfig`, `BuildConfig`, `ImageStream`, and `SecurityContextConstraints`
- operator ecosystem changes, including version alignment and CRD schema changes shipped with Red Hat operators
- any product-specific migration guarantees or tooling promised for a 4.x to 5.x transition

### Practical implication

For any early planning around a future OpenShift 5 line, the safest assumption is:

- **Kubernetes upstream version changes will remain a major source of incompatibility**, and
- **OpenShift-specific compatibility rules will only become trustworthy once Red Hat publishes concrete release and migration guidance**.

So if you want to future-proof manifests today, the best strategy is to:

1. eliminate deprecated Kubernetes APIs as early as possible
2. move manifests to stable API versions now
3. review CRDs and operator-managed resources separately
4. avoid relying on legacy defaults or cluster-generated fields
5. expect additional OpenShift-specific migration work once an actual OpenShift 5 compatibility story is published
