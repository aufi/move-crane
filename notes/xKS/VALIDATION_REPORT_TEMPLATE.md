# Validation Report: <Provider and Profile>

## Metadata

| Field | Value |
| --- | --- |
| Date | |
| Author | |
| Migration direction | xKS to OCP 4 / xKS to OCP 5 |
| Source platform/version | |
| Source Kubernetes version | |
| Target platform/version | |
| Target Kubernetes version | |
| Target profile evidence level | Documented OCP 4 / provisional OCP 5 / validated OCP 5 |
| Crane release/commit | |
| Plugin releases/commits | |
| Region/zones | |
| Public/private profile | |

## Cluster Capabilities

| Area | Source | Target | Notes |
| --- | --- | --- | --- |
| API endpoint | | | |
| Network plugin | | | |
| Egress | | | |
| Ingress controller/class | | | |
| TLS passthrough | | | |
| Pod security | | | |
| CSI drivers | | | |
| StorageClasses | | | |
| Snapshot classes | | | |
| Workload identity | | | |
| Relevant add-ons/CRDs | | | |
| OpenShift Route API/router | | | |
| SCC and namespace UID/GID contract | | | |

## Workload Inventory

| Resource/dependency | Classification | Target capability | Action | Result |
| --- | --- | --- | --- | --- |
| | Portable/Convertible/Replaceable/Prerequisite/Non-portable/Unknown | | | |

## Storage Mapping

| Source StorageClass | Target StorageClass | Access mode | Volume mode | Topology | Result |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## Test Results

| ID | Scenario | Status | Duration | Artifact/finding |
| --- | --- | --- | --- | --- |
| M1 | Export/transform/apply basic workload | | | |
| M2 | Route/Ingress exposure | | | |
| M3 | Non-root security | | | |
| M4 | Existing application CRD/controller prerequisite | | | |
| M5 | Exact OCP target API discovery and server-side dry-run | | | |
| D1 | Dynamic target PVC provisioning | | | |
| D2 | Direct transfer-pvc | | | |
| D3 | Checksum/integrity | | | |
| D4 | Interruption/retry | | | |
| D5 | Cleanup | | | |
| D6 | Indirect object-storage transfer | | | |
| D7 | Target Route/config API and router contract | | | |
| C1 | Cutover and functional smoke test | | | |

Allowed statuses: `pass`, `pass-with-prerequisite`, `fail`, `blocked`, `not-run`.

## Findings

### <ID and Title>

- Severity:
- Reproduction:
- Expected behavior:
- Actual behavior:
- Layer: Crane / plugin / cluster configuration / provider limitation / documentation
- Proposed solution:
- Target repository:
- Acceptance criteria:
- Artifact or issue link:

## Limitations and Untested Areas

- None recorded.

## Conclusion

| Area | Status |
| --- | --- |
| Manifests xKS to OCP | |
| Direct PVC transfer xKS to OCP | |
| Indirect PVC transfer | |
| OCP target-major validation gates | |
| Overall profile | Supported / Supported with prerequisites / Experimental / Unsupported / Unknown |

The final conclusion must list exact prerequisites and must not generalize results to other versions, add-ons, or network profiles.

Passing OCP 4 does not imply OCP 5 support. For OCP 5, record which gates from [OCP_TARGET_VERSIONS.md](OCP_TARGET_VERSIONS.md) passed and keep the profile `Unknown` or `Experimental` until its promotion criteria are satisfied.
