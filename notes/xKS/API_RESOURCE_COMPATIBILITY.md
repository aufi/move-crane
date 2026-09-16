# API Resource and Platform Dependency Compatibility

## Principle

Comparing `kind` names alone is insufficient. Compatibility has four layers:

1. The target API server serves the Group/Version/Kind.
2. The schema accepts the specific fields.
3. A required controller or webhook reconciles the object.
4. The resulting semantics match the source.

For example, an accepted `Ingress` without a matching ingress controller is not a functional migration.

## Main Risk Groups

### Managed Kubernetes Resources Requiring an OCP Decision

Migration from managed Kubernetes to OCP 4 or OCP 5 requires explicit decisions for at least these resources and dependencies:

| Resource | Typical target action |
| --- | --- |
| `networking.k8s.io/Ingress` | Transform to an OCP Route when semantics allow, or retain it only when a suitable target ingress controller exists |
| Cloud load balancer annotations | Remove or map to supported OCP exposure settings |
| Cloud workload identity annotations | Report an external identity prerequisite or remove them after credentials are redesigned |
| Provider CSI and StorageClass references | Map to an OCP StorageClass by capabilities |
| Provider-specific CRDs | Require compatible pre-existing target components or mark them non-portable |
| External registry references | Validate target access and credentials or perform image synchronization |
| Pod security assumptions | Validate against OCP SCC and namespace UID/GID behavior |

Transformations must report properties whose semantics cannot be preserved.

### Managed Cloud Integrations

Cloud services commonly add semantics through annotations, CSI drivers, admission webhooks, and optional CRDs. Never assume every cluster from a provider has every add-on.

Typical examples include:

- Service or Ingress annotations configuring cloud load balancers,
- ServiceAccount annotations and pod labels for workload identity,
- cloud resource operator CRDs,
- CSI Secret Store and external secret providers,
- provider-specific snapshot classes and topology parameters,
- autoscaling or node-provisioning CRDs.

Classify cloud IAM and external infrastructure as prerequisites or manual actions rather than copying them blindly into OCP.

### Upstream API Version Skew

For each source `apiVersion`, check against the exact OCP target:

- whether the target serves it,
- whether the storage version is compatible,
- required fields and defaulting changes,
- removed and deprecated APIs between minor versions,
- whether the API server can convert it or Crane must do so.

OCP 4-specific gaps are summarized in [OCP 4.x compatibility gaps](../ocp-4x-compatibility.md). OCP 5 evidence rules and likely impact areas are defined in [OCP_TARGET_VERSIONS.md](OCP_TARGET_VERSIONS.md).

### Existing Application CRDs and Controllers

Crane does not install an operator, CRD, or custom resource. If a source application already depends on custom resources, discovery may inspect the existing CRDs and controllers read-only to determine whether the workload is portable.

An identical existing CRD name is not sufficient. Compare:

- served and storage versions,
- OpenAPI schema and required fields,
- conversion webhook,
- scope and status subresource,
- version and configuration of the managing controller,
- dependent Secrets, ClusterRoles, and webhooks.

If the target does not already provide a compatible CRD and controller, Crane must report an external prerequisite or mark the resource unsupported. Crane must not install the missing components.

## Proposed Crane Discovery Output

A future preflight or discovery step should write a plain local file containing a record for every exported object:

```yaml
formatVersion: 1
findings:
  - resource:
      apiVersion: networking.k8s.io/v1
      kind: Ingress
      namespace: example
      name: frontend
    classification: PlatformReplaceable
    targetCapability: discovered OCP exposure API
    severity: warning
    action: transform
    reason: source Ingress requires conversion for the exact OCP target
```

This is a regular YAML report stored on disk. It is not a Kubernetes manifest and must never be applied to a cluster. JSON and Markdown renderings may be generated from the same in-memory result.

## Transformation Requirements

Transformations must be:

- deterministic and idempotent,
- visible as patches or new manifests,
- driven by source and target capabilities rather than only provider names,
- safe to run repeatedly,
- accompanied by a validation finding when semantics are lost.

Provider-specific logic belongs in a separate CLI plugin only for genuinely provider-specific resources. It must not deploy an operator, CRD, or custom resource. Ingress-to-Route and general API version conversion should remain reusable.

## Minimum Test Catalog

| Area | Source case | Target expectation |
| --- | --- | --- |
| Exposure | Ingress and cloud load balancer annotations | OCP Route equivalent or explicit blocker |
| Rollout | Deployment or StatefulSet | Functional OCP workload with documented admission changes |
| Registry | Cloud registry reference | Reachable image with valid target credentials |
| Security | Source PSA-compatible non-root pod | Valid OCP securityContext and SCC admission |
| Identity | Cloud workload identity | OCP mapping or external prerequisite |
| Storage | Provider StorageClass | Capability-based OCP target class |
| Existing CRD workload | CR, CRD, and webhook | Report compatible pre-existing target components or an external prerequisite |
| Networking | Provider load balancer annotations | Removal, mapping, or warning |

## When to Block Migration

Preflight must fail when:

- the target does not serve an API and no transformation exists,
- the OCP target major has not been validated and a required platform contract is unknown,
- a required CRD or controller is missing,
- security or identity semantics cannot be converted safely,
- target storage does not satisfy access mode, volume mode, or topology requirements,
- API validation would pass but a known data or security property would be lost.
