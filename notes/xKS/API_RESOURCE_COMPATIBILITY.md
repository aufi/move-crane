# API Resource and Platform Dependency Compatibility

## Principle

Comparing `kind` names alone is insufficient. Compatibility has four layers:

1. The target API server serves the Group/Version/Kind.
2. The schema accepts the specific fields.
3. A required controller or webhook reconciles the object.
4. The resulting semantics match the source.

For example, an accepted `Ingress` without a matching ingress controller is not a functional migration.

## Main Risk Groups

### OpenShift-Specific Resources

Migration from OCP to upstream or managed Kubernetes requires explicit decisions for at least these resources:

| Resource | Typical target action |
| --- | --- |
| `route.openshift.io/Route` | Transform to `networking.k8s.io/Ingress` or Gateway API; assess TLS and passthrough manually |
| `apps.openshift.io/DeploymentConfig` | Transform to `apps/v1/Deployment`; assess triggers and rollout semantics |
| `build.openshift.io/BuildConfig` | Replace with external CI or a target build platform such as Shipwright |
| `image.openshift.io/ImageStream` | Rewrite image references and provide image transfer or registry credentials |
| `security.openshift.io/SecurityContextConstraints` | Do not transfer as an application resource; convert requirements to pod security context and target policy |
| `template.openshift.io/Template` | Render before migration or replace with a Helm/Kustomize workflow |
| `config.openshift.io/*` | Treat as cluster-managed and do not transfer with the application |

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

When migrating to OCP, classify cloud IAM and external infrastructure as prerequisites or manual actions rather than copying them blindly.

### Upstream API Version Skew

For each source `apiVersion`, check:

- whether the target serves it,
- whether the storage version is compatible,
- required fields and defaulting changes,
- removed and deprecated APIs between minor versions,
- whether the API server can convert it or Crane must do so.

OCP-specific gaps are summarized in [OCP 4.x compatibility gaps](../ocp-4x-compatibility.md).

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
      apiVersion: route.openshift.io/v1
      kind: Route
      namespace: example
      name: frontend
    classification: PlatformReplaceable
    targetCapability: networking.k8s.io/v1/Ingress
    severity: warning
    action: transform
    reason: target cluster does not serve route.openshift.io/v1
```

This is a regular YAML report stored on disk. It is not a Kubernetes manifest and must never be applied to a cluster. JSON and Markdown renderings may be generated from the same in-memory result.

## Transformation Requirements

Transformations must be:

- deterministic and idempotent,
- visible as patches or new manifests,
- driven by source and target capabilities rather than only provider names,
- safe to run repeatedly,
- accompanied by a validation finding when semantics are lost.

Provider-specific logic belongs in a separate CLI plugin only for genuinely provider-specific resources. It must not deploy an operator, CRD, or custom resource. Route-to-Ingress and general API version conversion should remain reusable.

## Minimum Test Catalog

| Area | Source case | Target expectation |
| --- | --- | --- |
| Exposure | Route with edge, reencrypt, or passthrough TLS | Equivalent or explicit blocker |
| Rollout | DeploymentConfig triggers and hooks | Deployment with documented differences |
| Build | BuildConfig and ImageStream | External prerequisite or generated replacement |
| Security | SCC-dependent non-root pod | Valid securityContext/PSA profile |
| Identity | Cloud workload identity | Mapping or prerequisite |
| Storage | Provider StorageClass | Capability-based target class |
| Existing CRD workload | CR, CRD, and webhook | Report compatible pre-existing target components or an external prerequisite |
| Networking | Provider load balancer annotations | Removal, mapping, or warning |

## When to Block Migration

Preflight must fail when:

- the target does not serve an API and no transformation exists,
- a required CRD or controller is missing,
- security or identity semantics cannot be converted safely,
- target storage does not satisfy access mode, volume mode, or topology requirements,
- API validation would pass but a known data or security property would be lost.
