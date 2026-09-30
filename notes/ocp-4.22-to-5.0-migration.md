# OpenShift 4.22 to 5.0 migration compatibility

## Status and scope

This is a pre-release planning snapshot based on public development branches. It is not a support statement for OpenShift 5.0.

Snapshot date: 2026-09-30.

The public `enterprise-5.0` documentation branch and `release-5.0` API branch provide useful evidence, but they can change before release. At the time of this review:

- the draft 5.0 release notes list no new removed features
- the notable technical changes section is empty
- the draft maps both OpenShift 4.22 and 5.0 to Kubernetes 1.35
- the OpenShift API source contains the same top-level API group/version packages in `release-4.22` and `release-5.0`

These findings reduce the expected API-version gap, but they do not prove that every manifest accepted by 4.22 will be admitted or work on 5.0.

## Two different migration operations

### In-place cluster update

The draft OpenShift 5.0 documentation describes the 4.x to 5.0 transition as an in-place cluster update. It says the process should work like a regular minor update without rebuilding the cluster or manually migrating data.

Do not assume that a specific 4.22 patch has an update edge to 5.0 until the official update graph and `oc adm upgrade` show it. Installed Operators must also declare support for the target release.

### Workload migration with Crane

Crane moves workload manifests and persistent data between clusters. It does not update the source cluster. For a migration from an OpenShift 4.22 cluster to a separate OpenShift 5.0 cluster, Crane still needs to verify:

1. the target serves each Group/Version/Kind
2. the target schema accepts each manifest
3. required controllers, CRDs, and admission webhooks exist
4. SCC, storage, networking, and image access preserve the required behavior

## Kubernetes API baseline

The public documentation branches currently map both releases to Kubernetes 1.35:

| OpenShift release | Kubernetes baseline | New upstream removal boundary |
|---|---:|---|
| 4.22 | 1.35 | Baseline |
| 5.0 draft | 1.35 | None identified between these two releases |

This means the major-version number alone does not currently introduce a Kubernetes API removal boundary. Stable APIs expected to remain available include:

| Area | API versions and common resources |
|---|---|
| Core | `v1` Pod, Service, ConfigMap, Secret, ServiceAccount, PVC, PV, Namespace |
| Workloads | `apps/v1` Deployment, StatefulSet, DaemonSet, ReplicaSet |
| Batch | `batch/v1` Job and CronJob |
| Networking | `networking.k8s.io/v1` Ingress, IngressClass, NetworkPolicy |
| Autoscaling | `autoscaling/v1` and `autoscaling/v2` HorizontalPodAutoscaler |
| Policy | `policy/v1` PodDisruptionBudget |
| RBAC | `rbac.authorization.k8s.io/v1` roles and bindings |
| Admission | `admissionregistration.k8s.io/v1` webhook and validating admission policy resources |
| Extensions | `apiextensions.k8s.io/v1` CustomResourceDefinition |
| Storage | `storage.k8s.io/v1` StorageClass and CSI resources |

This table does not cover CRDs installed by Operators. Those APIs depend on the exact Operator version installed on the target cluster.

## OpenShift API evidence

### Important workload-facing APIs

The following types are present in the public `openshift/api` `release-5.0` branch:

| API | Resources found in the 5.0 source | Current conclusion |
|---|---|---|
| `route.openshift.io/v1` | Route | Present in source; verify that the target serves it and admits the generated Route |
| `apps.openshift.io/v1` | DeploymentConfig | Present but still deprecated; prefer conversion to `apps/v1` Deployment |
| `build.openshift.io/v1` | Build, BuildConfig | Present in source; controller availability and supported build strategy still require validation |
| `image.openshift.io/v1` | Image, ImageStream, ImageStreamTag, ImageStreamImage | Present in source; registry and import behavior require validation |
| `security.openshift.io/v1` | SecurityContextConstraints | Present in source; SCC admission behavior must be tested |
| `project.openshift.io/v1` | Project, ProjectRequest | Present in source |
| `template.openshift.io/v1` | Template, TemplateInstance | Present in source |

Source presence is weaker evidence than API discovery from a running release. A type can remain in a Go module for compatibility or internal use even when a product configuration does not serve it.

### OpenShift API packages found in the 5.0 branch

The following top-level packages exist in both the 4.22 and 5.0 API branches:

```text
apps/v1
authorization/v1
build/v1
cloudnetwork/v1
config/v1
console/v1
image/v1
imageregistry/v1
kubecontrolplane/v1
legacyconfig/v1
machineconfiguration/v1
machineconfiguration/v1alpha1
monitoring/v1
network/v1
oauth/v1
openshiftcontrolplane/v1
operator/v1
operator/v1alpha1
operatoringress/v1
osin/v1
platform/v1alpha1
project/v1
quota/v1
route/v1
security/v1
securityinternal/v1
servicecertsigner/v1alpha1
template/v1
unidling/v1alpha1
user/v1
```

Internal and alpha packages in this list are not portability guarantees. Crane should not copy cluster-managed configuration merely because its Go type still exists.

## API changes currently visible

The public API comparison shows additive and deprecation changes in `machineconfiguration.openshift.io/v1`:

- `ControllerConfigSpec` gains an optional `bgpVIPPeersJSON` field behind the `BGPBasedVIPManagement` feature gate.
- `KubeletConfig` status gains the `Accepted` condition.
- The `Success` and `Failure` condition names are deprecated in favor of `Accepted=True` and `Accepted=False`.

These changes should not block ordinary application manifests. They can affect automation that reads `KubeletConfig.status`. `ControllerConfig` is cluster-managed configuration and should not be migrated as an application resource.

## Deprecations carried into the 5.0 draft

The current draft keeps these items deprecated rather than newly removing them:

| Item | Migration impact | Recommended preparation |
|---|---|---|
| DeploymentConfig | Still present, but long-term availability is not guaranteed | Convert to `apps/v1` Deployment where semantics allow |
| ImageContentSourcePolicy | Cluster image configuration remains deprecated | Use ImageDigestMirrorSet or ImageTagMirrorSet |
| `failure-domain.beta.kubernetes.io/*` labels | Scheduling rules can depend on deprecated labels | Use `topology.kubernetes.io/zone` and `topology.kubernetes.io/region` |
| SQLite Operator catalogs | Catalog format remains deprecated | Move catalogs to file-based catalog format |
| `oc-mirror` v1 and Docker v2 registry workflows | Disconnected migration tooling can stop working in a later release | Test `oc-mirror` v2 and an OCI-compatible registry |
| runC runtime | Deprecated in 4.22 and still deprecated in the 5.0 draft | Test workloads with the target default runtime |
| Fujitsu iRMC BMC URI | Affected BareMetalHost resources can become unmanageable after removal | Replace `irmc://` with a supported BMC scheme |

Dynamic Accelerator Slicer and Red Hat Marketplace were already removed in OpenShift 4.22. Their resources should not be treated as new 5.0 regressions, but they remain non-portable to a fresh target.

## What remains unknown

The following questions need release documentation or a real target cluster:

- the final list of removed OpenShift APIs and fields
- the exact 4.22 to 5.0 update graph and required source patch level
- final SCC defaults, namespace UID ranges, and Pod Security Admission interaction
- bundled CSI drivers, default StorageClasses, and snapshot support by platform
- Route admission, ingress defaults, and external certificate behavior
- supported Operator catalog content and Operator upgrade paths
- CRD schema and conversion-webhook compatibility for installed Operators
- final container runtime and node operating system requirements
- whether deprecated APIs remain served in every supported 5.0 installation profile

## Required validation against a target cluster

When a candidate or released target is available, record the exact release image digest and run these checks before declaring compatibility.

### API discovery

```bash
oc version
oc api-resources -o wide
oc get --raw /openapi/v3
```

Confirm at least:

```bash
oc api-resources --api-group=route.openshift.io
oc api-resources --api-group=apps.openshift.io
oc api-resources --api-group=build.openshift.io
oc api-resources --api-group=image.openshift.io
oc api-resources --api-group=security.openshift.io
```

### Manifest validation

Run server-side dry-run against the target for every transformed resource:

```bash
oc apply --dry-run=server -f output/resources/
```

An accepted object is not enough. Verify that its controller reconciles it and that admission did not change required behavior.

### Platform validation

Test at least:

1. Route creation, admission, TLS mode, and reachable hostname
2. a restricted non-root workload under the selected SCC
3. RWO and RWX PVC provisioning and mounting where claimed
4. image pulls from every required registry
5. existing application CRDs, webhooks, and Operators
6. direct and indirect Crane PVC transfer, checksum, and cleanup

## Preliminary compatibility assessment

| Area | Preliminary status | Reason |
|---|---|---|
| Stable Kubernetes 1.35 workload APIs | Likely compatible | Both public release branches currently use Kubernetes 1.35 |
| Main OpenShift workload APIs | Provisionally present | The 5.0 API branch still contains Route, DC, BuildConfig, ImageStream, SCC, Project, and Template types |
| Deprecated OpenShift APIs | High risk | Presence in the draft does not guarantee future support |
| Operator CRDs and custom resources | Unknown | Compatibility depends on the exact Operator and CRD versions |
| Admission and security semantics | Unknown | Source comparison cannot prove runtime admission behavior |
| Storage and PVC migration | Unknown by platform | CSI drivers and StorageClasses are installation-specific |
| Crane direct transfer through Route | Experimental until tested | Requires Route, ingress, SCC, service, and network behavior on the target |

## Crane implications

Crane should not add an `ocp5` special case based on these pre-release findings. It should:

1. discover the target APIs and OpenAPI schemas
2. validate transformed resources with server-side dry-run
3. check Route, SCC, storage, registry, and controller capabilities
4. report missing or deprecated APIs before apply
5. keep every transformation visible as patches or generated manifests
6. treat an untested OpenShift 5 profile as `Unknown` or `Experimental`

## Sources and evidence snapshot

- [Draft OpenShift 5.0 release notes](https://github.com/openshift/openshift-docs/blob/enterprise-5.0/release_notes/ocp-5-0-release-notes.adoc)
- [Draft OpenShift 5.0 update procedure](https://github.com/openshift/openshift-docs/blob/enterprise-5.0/updating/updating_a_cluster/update-ocp-5.adoc)
- [Draft 5.0 deprecated and removed feature table](https://github.com/openshift/openshift-docs/blob/enterprise-5.0/modules/rn-ocp-release-notes-deprecated-removed-tables.adoc)
- [OpenShift API comparison: release-4.22 to release-5.0](https://github.com/openshift/api/compare/release-4.22...release-5.0)
- [OpenShift API release-5.0 branch](https://github.com/openshift/api/tree/release-5.0)
- [Kubernetes 1.35 API reference](https://v1-35.docs.kubernetes.io/docs/reference/kubernetes-api/)
- [Kubernetes deprecated API migration guide](https://v1-35.docs.kubernetes.io/docs/reference/using-api/deprecation-guide/)

Evidence used for the API comparison:

- `openshift/api` `release-4.22`: `231177cd43bccd49bad2bfb4c3cd4cc8153288fb`
- `openshift/api` `release-5.0`: `c1bf12f5d04823f92c88af6c9835890de13b3474`
- `openshift/openshift-docs` `enterprise-5.0`: `2a3864e257493b1edf8bdf7ba850241251eb9291`
