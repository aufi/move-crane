# Azure Kubernetes Service Support Plan

## First-Phase Goal

Validate and prepare workload migration support from AKS into OCP 4 or OCP 5. AKS is the first managed Kubernetes source platform used to stabilize the general methodology. Each OCP major and minor is a separate target profile.

## Reference Profiles

Do not define one ambiguous "AKS cluster." Validate at least:

| Source profile | Network | Workload exposure | Source storage |
| --- | --- | --- | --- |
| AKS-public | Public API and egress | Public Ingress or LoadBalancer resources | Azure Disk CSI (RWO) |
| AKS-private | Private API with controlled egress | Private Ingress or LoadBalancer resources | Azure Disk CSI and indirect object-storage fallback |
| AKS-RWX | Same as public/private profile | Profile-dependent | Azure Files CSI (RWX) |

Record the exact network plugin, ingress controller, CSI driver versions, and StorageClass names for every run.

## AKS Discovery

In addition to the general process, determine:

- whether the cluster is private and where its API server is reachable,
- egress mode and NSG or firewall restrictions,
- installed ingress classes and TLS passthrough support,
- Azure Disk and Azure Files CSI drivers and their StorageClasses,
- node pool zones and `WaitForFirstConsumer` behavior,
- Pod Security Admission configuration,
- Microsoft Entra Workload ID labels, annotations, and federated identity prerequisites,
- optional CRDs such as Azure Service Operator or Secrets Store CSI provider resources,
- Service and Ingress annotations tied to Azure Load Balancer or Application Gateway.

These integrations are not automatically present on every AKS cluster.

## AKS to OCP Risks

- Do not copy Azure Load Balancer or Application Gateway annotations without warning.
- Microsoft Entra workload identity bindings require replacement or manual target integration.
- Azure Service Operator and other cloud CRDs are prerequisites or non-portable resources.
- Map Azure Disk and Azure Files StorageClasses to OCP CSI by capability.
- Convert Ingress to Route only when host, path, and TLS semantics can be preserved; otherwise retain Ingress with a suitable controller.
- Validate AKS Pod Security assumptions against OCP SCC and namespace-assigned UID/GID ranges.
- Ensure ACR and other image references are reachable from OCP, with target pull credentials or image synchronization.
- Ensure the AKS mover pod can resolve and reach the target OCP passthrough Route.
- Do not assume OCP 5 retains the OCP 4 Route, SCC, namespace UID/GID, or CSI contracts; run the target-major gates first.

## Test Backlog

| Priority | Test | Expected result |
| --- | --- | --- |
| P0 | AKS Ingress to OCP Route with HTTP/TLS | Functional endpoint and recorded transformation |
| P0 | AKS Azure Disk PVC to OCP RWO CSI | Transfer, checksum, and cutover |
| P0 | Public AKS source to OCP Route | stunnel connectivity from an AKS mover pod |
| P0 | Private AKS through indirect object storage | Functional fallback when OCP Route is unreachable |
| P0 | AKS to OCP 5 target-major gate | API discovery, security, Route, CSI, and Crane client compatibility |
| P1 | Azure Files to OCP RWX storage | Access mode, permissions, and performance |
| P1 | Non-root StatefulSet | PSA/SCC and UID/GID preservation |
| P1 | Azure-annotated Service to OCP | Removal or mapping with warning |
| P1 | Workload Identity application | Precisely reported prerequisite or blocker |
| P2 | Operator-managed CR | CRD, schema, and controller discovery |
| P2 | AKS minor-version upgrade | API, CSI, and ingress regression coverage |

## Potential Crane Changes

Findings should determine whether these changes are necessary; do not assume them before testing:

1. Capability discovery for source Ingress resources and source/target StorageClasses.
2. Preflight validation of pod-to-endpoint connectivity.
3. StorageClass mapping files containing access mode, volume mode, and topology constraints.
4. General Ingress-to-Route transformations and provider annotation removal.
5. An AKS CLI plugin only for Azure CRDs or annotations that cannot be handled generally; no in-cluster operator or Crane CRD.
6. Explicit direct and indirect transport selection with private-topology diagnostics.

## Definition of Done

- P0 AKS-to-OCP scenarios pass separately on every claimed OCP 4 or OCP 5 target profile.
- Private AKS has a validated indirect procedure.
- Missing add-ons or incompatible storage produce actionable preflight findings.
- Transformations are auditable and idempotent.
- Results use the [validation report template](VALIDATION_REPORT_TEMPLATE.md).
- Findings reusable for EKS move into the general methodology rather than Azure-only logic.
- OCP 5 remains `Unknown` or `Experimental` until [target-major enablement gates](OCP_TARGET_VERSIONS.md) pass.
