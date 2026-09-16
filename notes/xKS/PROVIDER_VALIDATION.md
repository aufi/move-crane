# General Kubernetes Provider Validation Process

## Goal

This process determines whether Crane can migrate workloads between OCP 4 and a specific Kubernetes service profile. The result is not a blanket compatibility label for a provider, but a versioned profile with evidence and documented limitations.

All discovery runs from the Crane CLI and writes results to disk. It must not deploy an operator, install a CRD, or create a Crane-specific custom resource in either cluster. Queries for existing CRDs, controllers, and webhooks are read-only compatibility checks.

## 1. Define the Tested Profile

Record the following before testing:

- provider, region, and service type,
- Kubernetes version and available upgrade targets,
- public or private API server,
- network plugin, network policy, and egress model,
- ingress controller, `IngressClass`, and external DNS/TLS layer,
- available CSI drivers, StorageClasses, and snapshot classes,
- Pod Security Admission, OCP SCC, or other admission policies,
- workload identity and cloud permission integration,
- installed operators, add-ons, and their CRDs,
- Crane and plugin commits or releases.

The same platform with a different ingress controller or CSI driver is a different validation profile.

## 2. API Discovery

Store a machine-readable snapshot from both clusters:

```bash
kubectl --context "$SOURCE" version -o yaml
kubectl --context "$TARGET" version -o yaml
kubectl --context "$SOURCE" api-resources -o wide > source-api-resources.txt
kubectl --context "$TARGET" api-resources -o wide > target-api-resources.txt
kubectl --context "$SOURCE" get crd -o yaml > source-crds.yaml
kubectl --context "$TARGET" get crd -o yaml > target-crds.yaml
kubectl --context "$SOURCE" get storageclass,csidriver,volumesnapshotclass -o yaml > source-storage.yaml
kubectl --context "$TARGET" get storageclass,csidriver,volumesnapshotclass -o yaml > target-storage.yaml
kubectl --context "$SOURCE" get ingressclass -o yaml > source-ingress.yaml
kubectl --context "$TARGET" get ingressclass -o yaml > target-ingress.yaml
```

If the user cannot read cluster-scoped objects, record the capability as `unknown`; do not assume compatibility.

## 3. Application Inventory

Identify hidden dependencies in addition to exported namespaced objects:

- API groups and CRDs used by custom resources,
- operators, controllers, and webhooks,
- `StorageClass`, `IngressClass`, `RuntimeClass`, and `PriorityClass`,
- ServiceAccount identity and cloud IAM bindings,
- node labels, affinity, taints, zones, and CPU architecture,
- external load balancers, DNS, certificates, registries, and secret stores,
- snapshots and storage-backend-specific annotations.

Produce a table in the form `resource -> dependency -> target availability -> action`.

## 4. Classify Each Resource Kind

Assign each resource kind to exactly one category:

| Category | Meaning | Crane action |
| --- | --- | --- |
| Portable | Same supported API and semantics | Transfer after removing server-managed fields |
| Version-convertible | Same concept, different version or schema | Apply a deterministic transformation |
| Platform-replaceable | Platform resource has a target equivalent | Generate a replacement and document semantic loss |
| Prerequisite | Object is not transferred, but the target must provide it | Discovery or validation error with guidance |
| Non-portable | Cluster-managed or without a safe equivalent | Explicitly omit and warn |
| Unknown | Permission, schema, or evidence is missing | Block support claims |

See [API_RESOURCE_COMPATIBILITY.md](API_RESOURCE_COMPATIBILITY.md) for details.

## 5. Manifest Validation Suite

Use at least these workloads:

| Scenario | Concern under test |
| --- | --- |
| Deployment and ClusterIP Service | Basic portability |
| Externally exposed HTTP application | Route/Ingress and ingress class |
| StatefulSet and RWO PVC | Dynamic provisioning and data |
| Application with RWX PVC | Shared filesystem and access modes |
| CronJob | API versions and batch workloads |
| HPA and PDB | Autoscaling, metrics, and policy APIs |
| Non-root workload | SCC/PSA and file ownership |
| Existing application Custom Resource | Detect an external CRD/controller prerequisite without installing it |
| Workload identity | ServiceAccount and cloud IAM dependency |

For every scenario, run `export -> transform -> apply`, server-side dry-run, and a runtime smoke test. Creating an object without reaching a Ready workload is not success.

## 6. Data Validation Suite

Follow [TRANSFER_PVC_VALIDATION.md](TRANSFER_PVC_VALIDATION.md). Required cases include:

- empty and pre-existing target PVCs,
- RWO filesystem PVCs with many small files and one large file,
- content and checksum verification,
- files owned by non-root UID/GID,
- explicit StorageClass mapping,
- direct endpoint and indirect object-storage fallback,
- retry after interruption,
- cleanup of temporary Pods, Services, Secrets, ConfigMaps, and Ingresses/Routes.

Test `volumeMode: Block` separately. File-level rsync/rclone must not be presented as block-volume support.

## 7. Bidirectionality and Network Roles

For direct transfers, Crane creates a public endpoint on the target cluster and runs the client mover on the source. OCP to AKS therefore does not test the same network path as AKS to OCP.

Validate in each direction:

- target ingress/route support for the TCP/TLS passthrough required by stunnel,
- DNS resolution and egress from source nodes and pods,
- firewalls, security groups or NSGs, proxies, and network policies,
- endpoint access from a pod, not only from the user's workstation,
- rotation and cleanup of temporary certificate Secrets.

## 8. Findings and Change Planning

Every finding must include:

- a reproducible scenario and artifacts,
- whether the cause is Crane, cluster configuration, or unsupported semantics,
- the smallest safe change,
- target repository (`crane`, `crane-lib`, plugin, runner, UI, or documentation),
- backward compatibility impact,
- an automated test and acceptance criteria.

Preferred solution order:

1. Precise preflight validation and an actionable error.
2. A configurable option or mapping.
3. A general capability-based transformation.
4. A provider-specific CLI plugin only where a general solution is insufficient; it must not require an in-cluster operator or custom resource.

## 9. Profile Status

| Status | Criteria |
| --- | --- |
| Supported | Required matrix passes, limitations are documented, and regressions are tested |
| Supported with prerequisites | Passes only with clearly verifiable ingress, CSI, or add-on prerequisites |
| Experimental | Main flow works, but bidirectionality, retry, upgrade, or a major scenario is missing |
| Unsupported | Known blocker without a safe procedure |
| Unknown | Test not run or evidence unavailable |

Record the result using [VALIDATION_REPORT_TEMPLATE.md](VALIDATION_REPORT_TEMPLATE.md).
