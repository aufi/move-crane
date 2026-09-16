# Azure Kubernetes Service Support Plan

## First-Phase Goal

Validate and prepare bidirectional OCP 4 to AKS workload migration support. AKS is the first managed Kubernetes provider used to stabilize the general methodology.

## Reference Profiles

Do not define one ambiguous "AKS cluster." Validate at least:

| Profile | Network | Exposure | Storage |
| --- | --- | --- | --- |
| AKS-public | Public API and ingress | Reachable DNS with a NGINX-compatible ingress | Azure Disk CSI (RWO) |
| AKS-private | Private cluster | Private ingress or no direct path | Azure Disk CSI and indirect object-storage transfer |
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

## OCP to AKS Risks

### APIs and Workloads

- `Route` requires conversion to Ingress or Gateway API and new DNS.
- `DeploymentConfig`, `BuildConfig`, `ImageStream`, and `Template` require transformation or an external prerequisite.
- SCC cannot be transferred; pod security contexts must pass AKS admission policy.
- OCP image pull and internal registry references must be replaced with reachable registry endpoints.
- OCP-specific operators and CRDs require individual assessment.

### Data

- Map OCP storage by access mode and volume mode to Azure Disk or Azure Files, not by name.
- Provision zone-bound disks so that mover and target workload pods can be scheduled.
- Validate UID/GID and mount permission differences, especially for Azure Files.
- Ensure the target ingress supports stunnel passthrough; ordinary HTTP routing is insufficient.

## AKS to OCP Risks

- Do not copy Azure Load Balancer or Application Gateway annotations without warning.
- Microsoft Entra workload identity bindings require replacement or manual target integration.
- Azure Service Operator and other cloud CRDs are prerequisites or non-portable resources.
- Map Azure Disk and Azure Files StorageClasses to OCP CSI by capability.
- Convert Ingress to Route only when host, path, and TLS semantics can be preserved; otherwise retain Ingress with a suitable controller.

## Test Backlog

| Priority | Test | Expected result |
| --- | --- | --- |
| P0 | OCP Route to AKS Ingress with HTTP/TLS | Functional endpoint and recorded transformation |
| P0 | OCP RWO PVC to Azure Disk CSI | Transfer, checksum, and cutover |
| P0 | AKS Azure Disk PVC to OCP RWO CSI | Reverse direction over its independent network path |
| P0 | Public AKS as `nginx-ingress` target | stunnel connectivity from an OCP pod |
| P0 | Private AKS through indirect object storage | Functional fallback without public ingress |
| P1 | OCP RWX storage and Azure Files | Access mode, permissions, and performance |
| P1 | Non-root StatefulSet | PSA/SCC and UID/GID preservation |
| P1 | Azure-annotated Service to OCP | Removal or mapping with warning |
| P1 | Workload Identity application | Precisely reported prerequisite or blocker |
| P2 | Operator-managed CR | CRD, schema, and controller discovery |
| P2 | AKS minor-version upgrade | API, CSI, and ingress regression coverage |

## Potential Crane Changes

Findings should determine whether these changes are necessary; do not assume them before testing:

1. Capability discovery for ingress passthrough and StorageClasses.
2. Preflight validation of pod-to-endpoint connectivity.
3. StorageClass mapping files containing access mode, volume mode, and topology constraints.
4. General Route/Ingress transformations and provider annotation removal.
5. An AKS CLI plugin only for Azure CRDs or annotations that cannot be handled generally; no in-cluster operator or Crane CRD.
6. Explicit direct and indirect transport selection with private-topology diagnostics.

## Definition of Done

- P0 scenarios pass in both directions on recorded versions.
- Private AKS has a validated indirect procedure.
- Missing add-ons or incompatible storage produce actionable preflight findings.
- Transformations are auditable and idempotent.
- Results use the [validation report template](VALIDATION_REPORT_TEMPLATE.md).
- Findings reusable for EKS move into the general methodology rather than Azure-only logic.
