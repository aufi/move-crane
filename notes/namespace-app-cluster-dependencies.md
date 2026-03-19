# Namespace-Scoped Applications with Hidden Cluster-Level Dependencies

This note lists common cases where an application appears to live entirely within a single Kubernetes namespace, and can be managed by a namespace-scoped user, but still depends on cluster-scoped components or cluster-wide configuration that the user typically cannot read or modify.

## Why this matters

For migration, backup/restore, or portability analysis, a namespace alone is often not the full unit of deployment. A workload may restore successfully at the YAML level, yet still fail to function because required cluster-level components are missing, incompatible, or configured differently on the target cluster.

## Executive summary

- A namespace often contains only the tenant-visible part of an application.
- The real runtime contract may also include cluster-scoped APIs, controllers, webhooks, RBAC, security policy, ingress/storage classes, and platform infrastructure.
- Namespace-only migration works reliably only when those cluster-level prerequisites already exist and are compatible on the destination cluster.
- Operator-managed applications are a particularly common trap: the CRs may be namespaced, but the CRDs, controllers, webhooks, and lifecycle management are not.
- A successful restore of YAML does not guarantee a functional application.

## Quick risk table

| Dependency type | Namespace-scoped symptom | Hidden cluster dependency | Migration implication |
| --- | --- | --- | --- |
| Operator-managed CRs | App uses CRs in one namespace | CRDs + operator/controller + webhook | Install operator stack first, then migrate CRs |
| PVCs | App creates PVCs normally | StorageClass + CSI + snapshot stack | Storage behavior may differ or provisioning may fail |
| Ingress | Ingress object restores cleanly | IngressClass + ingress controller | Traffic may never reach the app |
| Certificates | `Certificate` exists in namespace | cert-manager + `ClusterIssuer` | Cert issuance fails after restore |
| ServiceAccount | Pod runs with namespace SA | `ClusterRoleBinding` / cluster RBAC | App loses cluster-wide permissions |
| Security settings | Pod spec looks valid | SCC / PSA / admission policy | Pods may be rejected or stuck Pending |
| Scheduling | Pod has selectors/tolerations | node labels, taints, runtime classes, priority classes | Workload schedules differently or not at all |
| Service mesh | Namespace labels trigger injection | mesh control plane + webhook | Traffic behavior and sidecars differ |
| External secrets | Secret request object exists | cluster controller + secret store | Secrets never materialize |
| Gateway / Route | Route objects are namespaced | router, `GatewayClass`, shared gateways | Exposure path is missing |

## Common dependency patterns

### 1. CRDs and operators
- The application uses namespaced Custom Resources (CRs).
- Those CRs only work if the corresponding cluster-level `CustomResourceDefinition` exists.
- In many cases, a running operator/controller is also required to reconcile the CRs.
- Namespace users may be allowed to create CRs, but not install CRDs or operators.

Examples:
- cert-manager `Certificate`
- Argo CD `Application`
- External Secrets `ExternalSecret`
- many vendor-specific database, messaging, and storage operators

### 2. Admission webhooks
- The application creates ordinary namespaced resources.
- Their acceptance or mutation depends on cluster-wide `ValidatingWebhookConfiguration` or `MutatingWebhookConfiguration`.
- Without the webhook, the same manifest may be rejected, accepted incorrectly, or behave differently.

Examples:
- sidecar injection
- policy enforcement
- defaulting and mutation done by operators

### 3. Aggregated APIs (`APIService`)
- The application or operator depends on an aggregated Kubernetes API.
- The API is registered cluster-wide through `APIService`.
- Namespaced objects may exist, but the backing API must be present and healthy.

### 4. Cluster-wide RBAC bound to a namespaced ServiceAccount
- Pods run using a ServiceAccount in the namespace.
- That ServiceAccount may receive permissions via `ClusterRoleBinding` to act outside the namespace.
- The workload looks namespaced, but its effective permissions are not.

Examples:
- reading cluster nodes
- watching resources in all namespaces
- accessing non-namespaced APIs

### 5. SecurityContextConstraints / Pod Security / security admission
- Pods are namespaced objects.
- Their ability to start may depend on cluster-level security controls.

Examples:
- OpenShift `SecurityContextConstraints`
- Pod Security Admission configuration
- cluster-level admission policies restricting privileged pods, hostPath, capabilities, or UID ranges

### 6. Storage classes and CSI infrastructure
- PVCs are namespaced.
- Their provisioning depends on cluster-scoped storage objects and controllers.

Examples:
- `StorageClass`
- `VolumeSnapshotClass`
- CSI drivers
- storage backends and topology settings

The namespace owner may create a PVC, but cannot guarantee that the referenced storage class exists or behaves the same on another cluster.

### 7. Ingress classes and ingress controllers
- `Ingress` is namespaced.
- Its behavior depends on cluster-level `IngressClass` definitions and an installed ingress controller.

Without the same ingress class and controller implementation, traffic routing may not work after migration.

### 8. Gateway API shared infrastructure
- `HTTPRoute` and similar route resources may be namespaced.
- They often depend on cluster-scoped `GatewayClass` and centrally managed `Gateway` resources.

This creates a split responsibility model: the app team owns routes, while platform admins own the gateway layer.

### 9. Cert-manager and cluster issuers
- `Certificate` resources are often namespaced.
- Their issuance may depend on:
  - cert-manager CRDs
  - cert-manager controllers
  - admission webhooks
  - cluster-scoped `ClusterIssuer`

A namespace restore is insufficient if the target cluster lacks the issuer and controller stack.

### 10. Policy engines (Gatekeeper, Kyverno, custom admission)
- The application resources are namespaced.
- Their creation and runtime shape are constrained by cluster-wide policy engines.

Examples:
- required labels/annotations
- blocked container images
- forbidden volume types
- mandatory security settings

The same namespace content may be valid on one cluster and invalid on another.

### 11. Priority classes
- Pods may reference a cluster-scoped `PriorityClass`.
- If the class is missing on the target cluster, scheduling behavior changes or pod creation fails.

### 12. Runtime classes
- Pods may reference a cluster-scoped `RuntimeClass`.
- This is common when workloads rely on alternative runtimes such as Kata Containers or gVisor.

### 13. Node labels, taints, and topology assumptions
- Workloads are namespaced.
- Scheduling may depend on cluster/node-level properties.

Examples:
- `nodeSelector`
- node affinity
- tolerations for taints
- zone / region topology constraints
- GPU or special hardware labels

These dependencies are often invisible if one only inspects namespace-local objects.

### 14. Image trust, registry policy, and mirrors
- Deployments and Pods are namespaced.
- Actual image pull behavior may depend on cluster-level registry configuration.

Examples:
- image content source policies / mirrors
- allowed registries
- trusted CA bundles
- cluster pull secret conventions

### 15. Service mesh control plane
- Application resources live in a namespace.
- Their actual behavior may depend on a cluster- or platform-managed service mesh control plane.

Examples:
- automatic sidecar injection
- mesh CRDs
- mesh webhooks
- global traffic and security policy

### 16. OpenShift Routes and router infrastructure
- `Route` is namespaced.
- It still depends on cluster-level router/ingress infrastructure and related platform configuration.

### 17. External secret backends and cluster secret stores
- The application may use namespaced secret request objects.
- Resolution of those objects depends on cluster-installed controllers and sometimes cluster-scoped secret store definitions.

Examples:
- `ClusterSecretStore`
- Vault / cloud secret manager integrations

### 18. Snapshot and backup ecosystem dependencies
- Namespace-scoped backup-related CRs may exist.
- Their functionality depends on cluster-level snapshot CRDs, drivers, and controllers.

Examples:
- CSI snapshot controller
- `VolumeSnapshotClass`
- backup operator infrastructure

## Typical migration risk

A common failure mode is:

> The application namespace is restored successfully, but the application still does not work because the target cluster is missing required cluster-scoped APIs, controllers, webhooks, RBAC bindings, or platform configuration.

This is especially common for operator-managed applications.

## Practical heuristics for detecting hidden cluster dependencies

When reviewing a namespace, pay special attention to objects that reference or imply external cluster-level dependencies, such as:

- `storageClassName`
- `ingressClassName`
- `runtimeClassName`
- `priorityClassName`
- `issuerRef.kind=ClusterIssuer`
- Custom Resources from non-core API groups
- ServiceAccounts that may be referenced by `ClusterRoleBinding`
- annotations that trigger injection, mutation, or external controllers
- node affinity, `nodeSelector`, tolerations, topology constraints
- snapshot-related resources
- route or gateway resources
- PVCs relying on CSI-specific behavior

## How to detect these dependencies

The safest approach is to combine manifest inspection, API discovery, and runtime observation.

### 1. Inspect namespace manifests for explicit references

Search exported YAML or live resources for fields that point to cluster-scoped infrastructure:

- `storageClassName`
- `ingressClassName`
- `runtimeClassName`
- `priorityClassName`
- `issuerRef.kind: ClusterIssuer`
- `serviceAccountName`
- `nodeSelector`
- affinity / anti-affinity
- tolerations
- topology spread constraints

Also look for API groups outside the Kubernetes core APIs, because these often indicate operator-managed resources.

### 2. Identify Custom Resources

If a namespace contains resources from non-core API groups, verify:

- the corresponding CRDs exist on the destination cluster
- the same operator/controller is installed
- any required webhook is present
- API versions are compatible between source and destination

A namespaced CR without its CRD and controller is usually just inert YAML.

### 3. Inspect ServiceAccounts and effective privileges

A workload may appear namespace-scoped but rely on cluster-wide RBAC.

Check:
- which `ServiceAccount` each workload uses
- whether that ServiceAccount is referenced by any `ClusterRoleBinding`
- whether the application needs to list/watch cluster-wide objects

This is a common hidden dependency for operators, backup agents, observability components, and security tooling.

### 4. Look for admission-driven behavior

Check whether the application depends on mutation or validation performed outside the namespace.

Typical indicators:
- sidecars appear even though they are not in the original Pod spec
- labels/annotations trigger injection
- resources are rejected unless they contain platform-specific fields
- defaults are added by a webhook rather than by the manifest itself

### 5. Validate storage assumptions

For every PVC or snapshot-related resource, verify:

- referenced `StorageClass` exists on the target cluster
- provisioner/CSI driver is available
- access modes are supported
- expansion and snapshot features exist if the application relies on them
- performance/topology assumptions still hold

### 6. Validate traffic exposure assumptions

For every `Ingress`, `Route`, `HTTPRoute`, or TLS-related object, verify:

- referenced `IngressClass`, `GatewayClass`, or router infrastructure exists
- DNS / hostname ownership assumptions are valid
- certificate issuance infrastructure exists
- target cluster exposes equivalent networking features

### 7. Check cluster policy compatibility

Review whether the workload depends on cluster security and policy posture.

Examples:
- OpenShift SCC assignment
- Pod Security Admission mode
- Gatekeeper / Kyverno constraints
- image policy / trusted registries
- forbidden capabilities, host mounts, or privileged mode

A namespace migration may fail even when all YAML restores cleanly, simply because the target policy is stricter.

### 8. Check scheduling assumptions

Inspect whether workloads require cluster/node characteristics that are not visible from namespace ownership alone:

- specific node labels
- taints that must be tolerated
- GPUs or special hardware
- NUMA / topology expectations
- custom runtime classes
- priority classes

### 9. Compare source and destination API surface

Before migration, compare source and destination for:

- available API groups and versions
- CRDs
- storage classes
- ingress/gateway classes
- cluster issuers
- runtime classes
- priority classes
- policy engines and relevant constraints

This is especially important for operator-managed applications and platform-integrated workloads.

### 10. Observe runtime behavior, not just manifests

Some dependencies are only obvious at runtime.

Check:
- Pod events
- admission rejections
- mount/provisioning failures
- image pull failures
- certificate issuance status
- CR reconciliation status
- missing sidecars or injected config

If possible, compare a working source deployment with a restored destination deployment and inspect differences in generated resources and events.

## Short conclusion

A namespace is often not a sufficient migration boundary.

If an application is namespace-scoped only from the tenant perspective, but depends on cluster-scoped APIs, controllers, classes, policies, or RBAC, then a successful migration requires those cluster-level prerequisites to be recreated or validated on the destination cluster first.
