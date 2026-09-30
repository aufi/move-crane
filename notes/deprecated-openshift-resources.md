# Deprecated and removed OpenShift resources

## Scope

This document inventories OpenShift resources that were deprecated, removed, replaced, or made optional during the OpenShift 4 release line and in the public OpenShift 5.0 draft material.

The goal is to identify candidates for Crane discovery rules, validation, and conversion plugins. The inventory distinguishes:

- OpenShift platform APIs
- upstream Kubernetes APIs used by OpenShift
- APIs supplied by optional Red Hat Operators
- APIs that can be absent because a cluster capability is disabled

Snapshot date: 2026-09-30.

## Main findings

The strongest additional conversion candidates after `DeploymentConfig` and `BuildConfig` are:

1. `ImageContentSourcePolicy` to `ImageDigestMirrorSet` or `ImageTagMirrorSet`
2. MetalLB `AddressPool` to `IPAddressPool`
3. `SiteConfig` to `ClusterInstance`
4. `KubeDescheduler` from `operator.openshift.io/v1beta1` to `operator.openshift.io/v1`
5. historical `OperatorSource` and `CatalogSourceConfig` resources to `CatalogSource`
6. old OpenShift Logging resources to the Logging 6 APIs

Some resources have no safe generic replacement. Crane should report those resources instead of generating an object with different semantics.

## BuildConfig status

`BuildConfig` itself is not marked as deprecated in the reviewed OpenShift 4 or draft OpenShift 5 documentation. The public OpenShift 5 REST API draft still includes `build.openshift.io/v1` `Build` and `BuildConfig` endpoints.

The related deprecations are narrower:

- The `JenkinsPipeline` build strategy has been deprecated since OpenShift 4.3.
- The `lastTriggeredImageID` field has been deprecated since OpenShift 4.8.
- The `Build` cluster capability can be disabled. A cluster without this capability cannot use OpenShift `Build` or `BuildConfig` resources.

Converting `BuildConfig` to a Shipwright `Build` is therefore a modernization and target-capability conversion. It is not currently required by a documented removal of the `BuildConfig` kind.

A Shipwright `Build` is also not a complete behavioral replacement for every `BuildConfig`. Build triggers, image change handling, build history, strategy selection, secrets, and creation of `BuildRun` resources need separate treatment.

## OpenShift platform resources

| Source resource or API | Deprecated | Removed or disabled | Replacement | Crane treatment |
|---|---|---|---|---|
| `DeploymentConfig` `apps.openshift.io/v1` | OpenShift 4.14 | Still present in the 5.0 draft; API can be absent when the `DeploymentConfig` capability is disabled | `Deployment` `apps/v1` | High-priority conversion plugin |
| `ImageContentSourcePolicy` `operator.openshift.io/v1alpha1` | OpenShift 4.13 | Still deprecated in 4.22 and the 5.0 draft | `ImageDigestMirrorSet` or `ImageTagMirrorSet` `config.openshift.io/v1` | Opt-in cluster configuration conversion |
| MetalLB `AddressPool` | API `v1alpha1` deprecated in 4.10; resource deprecated in 4.11 | CRD removed in 4.16 | `IPAddressPool` `metallb.io/v1beta1` | Convert only when the target MetalLB Operator and schema are known |
| `SiteConfig` `ran.openshift.io/v1` | OpenShift 4.18 | Support removed in 4.21 | `ClusterInstance` managed by the SiteConfig Operator | Hub and ZTP conversion, not application migration |
| `KubeDescheduler` `operator.openshift.io/v1beta1` | OpenShift 4.8 | API version removed in 4.9 | Same kind in `operator.openshift.io/v1` | Straight API-version conversion |
| `CatalogSourceConfig` | OpenShift 4.3 and 4.4 | Removed in 4.5 | `CatalogSource` | Historical, cluster-scoped conversion |
| `OperatorSource` `operators.coreos.com/v1` | OpenShift 4.3 through 4.5 | Removed in 4.6 | `CatalogSource` | Historical, cluster-scoped conversion |
| Service Catalog `.servicecatalog.k8s.io/v1beta1` resources | OpenShift 4.2 | Removed in 4.5 | No generic replacement | Report as unsupported and require service redesign |
| `PolicyGenTemplate` | Future deprecation announced in 4.16 through the 5.0 draft | No confirmed removal version in the reviewed material | `PolicyGenerator` | Warning only until deprecation and target schema are final |

### ImageContentSourcePolicy conversion

OpenShift documents the following mechanical mapping:

```text
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
spec.repositoryDigestMirrors
```

becomes:

```text
apiVersion: config.openshift.io/v1
kind: ImageDigestMirrorSet
spec.imageDigestMirrors
```

The `oc adm migrate icsp` command performs this conversion. `ImageTagMirrorSet` is required when mirroring by tag rather than digest.

These objects are cluster-scoped configuration. Crane should not include them in a normal namespace application migration without an explicit cluster-configuration mode.

### MetalLB AddressPool conversion

The old and new objects are not distinguished only by API version:

```text
AddressPool -> IPAddressPool
```

The target configuration can also require `L2Advertisement` or `BGPAdvertisement` resources. A converter must preserve address ranges, automatic assignment behavior, namespace and service selectors, and advertisement semantics.

### Service Catalog resources

The removed Service Catalog API included resources such as:

- `ServiceInstance`
- `ServiceBinding`
- `ServiceBroker`
- `ServiceClass`
- `ServicePlan`
- their cluster-scoped variants

These objects described broker-managed external services. Converting them to a Kubernetes `Service` or Secret would lose lifecycle and credential semantics. Crane should classify them as external prerequisites.

## Upstream API-version conversions

These resources are not OpenShift-specific, but they commonly occur in exported OpenShift manifests.

| Resource | Removed API | First affected OCP target | Replacement |
|---|---|---:|---|
| Ingress | `extensions/v1beta1`, `networking.k8s.io/v1beta1` | 4.9 | `networking.k8s.io/v1` plus schema conversion |
| CustomResourceDefinition | `apiextensions.k8s.io/v1beta1` | 4.9 | `apiextensions.k8s.io/v1` plus structural schema conversion |
| Admission webhook configurations | `admissionregistration.k8s.io/v1beta1` | 4.9, temporarily restored in 4.17 and removed again in 4.20 | `admissionregistration.k8s.io/v1` |
| CronJob | `batch/v1beta1` | 4.12 | `batch/v1` |
| PodDisruptionBudget | `policy/v1beta1` | 4.12 | `policy/v1` with selector semantic review |
| HorizontalPodAutoscaler | `autoscaling/v2beta1` | 4.12 | `autoscaling/v2` plus metric schema conversion |
| HorizontalPodAutoscaler | `autoscaling/v2beta2` | 4.13 | `autoscaling/v2` |
| PodSecurityPolicy | `policy/v1beta1` | 4.12 | No object conversion; redesign for SCC or Pod Security Admission |
| VolumeSnapshot, VolumeSnapshotClass, VolumeSnapshotContent | `snapshot.storage.k8s.io/v1alpha1` or `v1beta1` | Alpha CRDs blocked earlier upgrades; `v1beta1` endpoint removed in 4.11 | `snapshot.storage.k8s.io/v1` |
| FlowSchema, PriorityLevelConfiguration | `flowcontrol.apiserver.k8s.io/v1beta1` | 4.13 | Newer flow-control API, ultimately `v1` |
| FlowSchema, PriorityLevelConfiguration | `flowcontrol.apiserver.k8s.io/v1beta2` | 4.16 | `flowcontrol.apiserver.k8s.io/v1` |
| FlowSchema, PriorityLevelConfiguration | `flowcontrol.apiserver.k8s.io/v1beta3` | 4.19 | `flowcontrol.apiserver.k8s.io/v1` |
| ValidatingAdmissionPolicy and binding | `admissionregistration.k8s.io/v1beta1` | 4.20 | `admissionregistration.k8s.io/v1` |

See [OpenShift 4.x compatibility gaps](ocp-4x-compatibility.md) for the complete Kubernetes removal matrix.

## Network resources after OpenShift SDN

OpenShift SDN was deprecated in 4.15 and 4.16 and removed in 4.17. This does not prove that every resource historically associated with OpenShift SDN disappeared.

Do not unconditionally convert or remove the following based only on the OCP version:

- `EgressNetworkPolicy`
- `NetNamespace`
- `HostSubnet`
- multicast annotations
- egress IP configuration

The target network plugin and API discovery are authoritative. A safe conversion needs to compare OpenShift SDN behavior with OVN-Kubernetes resources such as `EgressFirewall`, `EgressIP`, Kubernetes `NetworkPolicy`, and namespace annotations. Some mappings are semantic redesigns rather than field renames.

## Optional Red Hat Operator resources

The following APIs belong to Operators that release independently from OpenShift. Their compatibility is determined by the installed Operator version, not only by the OCP minor version.

| Product | Source | Replacement or current API | Notes |
|---|---|---|---|
| OpenShift Logging 6 | `ClusterLogging.logging.openshift.io` | No direct replacement; storage commonly moves to `LokiStack` | Old API removed in Logging 6 |
| OpenShift Logging 6 | `ClusterLogForwarder.logging.openshift.io` | `ClusterLogForwarder.observability.openshift.io` | Requires schema conversion; no automatic migration is supplied |
| Network Observability | `FlowCollector` `v1alpha1` | `FlowCollector` `v1beta1`, then `v1beta2` | `v1alpha1` removed in 1.6; `v1beta1` removed in 1.10 |
| OpenShift Service Mesh | `ServiceMeshExtension` | `WasmPlugin` | Deprecated in Service Mesh 2.2 and removed in 2.3 |
| Power Monitoring | `Kepler` | `PowerMonitor` | Deprecated in the 0.5 Technology Preview material |
| OpenShift Pipelines | `Condition` | `when` expressions | Resource removed |
| OpenShift Pipelines | `PipelineResource` | Tasks, workspaces, parameters, and explicit resources | No single generic replacement |
| OpenShift Pipelines | `v1alpha1 Run` | `v1beta1 CustomRun` | Removed in Pipelines 1.11 |
| OpenShift Pipelines | `v1alpha1` Pipeline, PipelineRun, Task, ClusterTask, TaskRun | supported `v1beta1` or `v1` APIs for the installed release | Old APIs removed in later Pipelines releases |
| OpenShift Serverless | `KafkaChannel` `v1alpha1` | `v1beta1` | Old API removed |
| OpenShift Serverless | `KafkaSource` `v1alpha1` | `v1beta1` | Old API deprecated |
| OpenShift Serverless | `KafkaBinding` | No direct generic replacement identified | API deprecated in Serverless 1.19 |
| OpenShift Serverless | old `KnativeServing` and `KnativeEventing` `v1alpha1` APIs | `operator.knative.dev/v1beta1` | Operator upgrades can convert stored objects |
| OpenShift Kueue | Kueue API `v1beta1` | `v1beta2` | Operator-specific API migration |
| OpenShift Dev Spaces or Che | `Workspace` | `DevWorkspace` | Operator-specific replacement |

Crane should not apply these conversions unless discovery confirms that the target Operator, replacement CRD, and controller are installed and compatible.

## Disabled cluster capabilities

Since OpenShift 4.11, installations can disable optional cluster capabilities. OpenShift 4.14 added `Build`, `ImageRegistry`, and `DeploymentConfig` to the capability sets. Later releases added other capabilities such as OLM v1 and cloud controller management.

The most direct API effects for workload migration are:

| Disabled capability | Migration effect |
|---|---|
| `Build` | OpenShift `Build`, `BuildConfig`, and the `builder` service account are unavailable |
| `DeploymentConfig` | `DeploymentConfig` and the `deployer` service account are unavailable |
| `CSISnapshot` | Snapshot APIs or their controller behavior cannot be assumed |
| `OperatorLifecycleManager` | OLM resources and installed Operator prerequisites cannot be assumed |
| `ImageRegistry` | The integrated registry and its controller behavior cannot be assumed |
| `Storage` | Platform storage Operators and default storage behavior cannot be assumed |
| `Marketplace` | Default Operator catalog sources cannot be assumed |

An API can therefore be absent even when the OCP release normally supports it. Static version tables are insufficient.

Check the target cluster before transformation:

```bash
oc get clusterversion version \
  -o jsonpath='{.status.capabilities.enabledCapabilities}'

oc api-resources -o wide
```

For deprecated or removed APIs used on a source cluster, inspect `APIRequestCount`:

```bash
oc get apirequestcounts \
  -o jsonpath='{range .items[?(@.status.removedInRelease!="")]}{.status.removedInRelease}{"\t"}{.metadata.name}{"\n"}{end}'
```

## Recommended Crane classification

### Built-in or generally reusable conversion

- `DeploymentConfig` to `Deployment`
- removed Kubernetes beta APIs to their stable versions where semantics are deterministic
- same-kind API-version upgrades such as `KubeDescheduler` `v1beta1` to `v1`

### Opt-in platform conversion

- `BuildConfig` to Shipwright resources
- `ImageContentSourcePolicy` to IDMS or ITMS
- MetalLB `AddressPool` to `IPAddressPool` and advertisement resources
- `SiteConfig` to `ClusterInstance`
- `OperatorSource` or `CatalogSourceConfig` to `CatalogSource`

These conversions require target capability or controller discovery and often operate on cluster-scoped resources.

### Operator-specific plugin

- OpenShift Logging API migration
- Service Mesh extension migration
- OpenShift Pipelines resource migration
- Serverless API migration
- Network Observability API migration
- Power Monitoring migration

### Report only

- Service Catalog resources
- PodSecurityPolicy
- unknown CRDs without a compatible target controller
- resources whose behavior depends on an unavailable external service

## OpenShift 5 status

The public OpenShift 5.0 draft does not currently declare additional removed OpenShift resource kinds beyond removals inherited from OpenShift 4 and optional Operators. It still documents `BuildConfig`, `DeploymentConfig`, `ImageStream`, `Route`, SCC, and the same top-level OpenShift API packages found in the 4.22 API branch.

This is pre-release evidence. Final release notes and API discovery against a real target cluster remain authoritative.

## Sources

- [OpenShift 4.5 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.5/html/release_notes/ocp-4-5-release-notes)
- [OpenShift 4.6 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.6/html/release_notes/ocp-4-6-release-notes)
- [OpenShift 4.8 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.8/html/release_notes/ocp-4-8-release-notes)
- [OpenShift 4.9 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.9/html/release_notes/ocp-4-9-release-notes)
- [OpenShift 4.10 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.10/html/release_notes/ocp-4-10-release-notes)
- [OpenShift 4.11 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.11/html/release_notes/ocp-4-11-release-notes)
- [OpenShift 4.13 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.13/html/release_notes/ocp-4-13-release-notes)
- [OpenShift 4.14 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.14/html/release_notes/ocp-4-14-release-notes)
- [OpenShift 4.16 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/release_notes/ocp-4-16-release-notes)
- [OpenShift 4.17 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.17/html/release_notes/ocp-4-17-release-notes)
- [OpenShift 4.18 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/release_notes/ocp-4-18-release-notes)
- [OpenShift 4.21 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/release_notes/ocp-4-21-release-notes)
- [OpenShift 4.22 cluster capabilities](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_overview/cluster-capabilities)
- [Draft OpenShift 5.0 documentation branch](https://github.com/openshift/openshift-docs/tree/enterprise-5.0)
- [OpenShift 4.22 to 5.0 migration compatibility](ocp-4.22-to-5.0-migration.md)
