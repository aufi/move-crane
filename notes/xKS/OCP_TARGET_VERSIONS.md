# OCP 4 and OCP 5 Target Impact Analysis

## Scope and Evidence Level

The migration direction remains xKS to OCP. The target can be either OCP 4 or OCP 5, but each exact target release is a separate compatibility profile.

At the time of this analysis, the public Red Hat OpenShift lifecycle page describes OCP 4 as the current major line, and this repository's existing compatibility research does not identify a stable public OCP 5 API-removal matrix. OCP 5 support is therefore a planned capability, not an inferred compatibility claim.

Until Red Hat publishes release-specific OCP 5 API, security, networking, storage, and upgrade documentation and a real cluster profile passes validation:

- OCP 5 profiles default to `Unknown` before testing.
- A partially tested OCP 5 profile can be at most `Experimental`.
- OCP 4 results must not be reused as OCP 5 evidence.
- No guessed OCP 5 API or behavior may be hardcoded into Crane.

References:

- [Red Hat OpenShift Container Platform life cycle](https://access.redhat.com/support/policy/updates/openshift)
- [Existing OCP 4.x and future OCP 5 compatibility notes](../ocp-4x-compatibility.md)

## Compatibility Dimensions Affected by the Target Major

### Kubernetes API Baseline

OCP minor releases embed different Kubernetes minor versions. A future OCP 5 release will likely move the baseline further and can remove APIs still accepted by some xKS source versions.

For the exact target cluster, discovery must verify:

- every exported Group/Version/Kind through API discovery,
- schema compatibility through server-side dry-run,
- removed beta APIs and required field changes,
- CRD served/storage versions and conversion webhooks,
- target admission defaulting and validation behavior.

Static major-version tables are guidance only. Live target discovery is authoritative.

### OpenShift APIs and Route Conversion

Ingress-to-Route conversion and direct `transfer-pvc` currently depend on OpenShift APIs and router behavior. For each OCP 4 or OCP 5 target, preflight must verify:

- `route.openshift.io/v1` is served,
- a cluster ingress/router is available,
- passthrough Routes are admitted and receive a reachable hostname,
- `config.openshift.io/v1` ingress configuration remains available when Crane needs the cluster domain,
- generated Route fields remain schema-compatible.

If an OCP 5 target changes these contracts, direct transfer must fail before data copy with an actionable message. Indirect object-storage transfer remains the fallback until Crane gains a validated endpoint implementation for the new contract.

### Security and UID/GID Handling

Current Crane behavior accounts for OCP SCC and OpenShift namespace UID and supplemental-group annotations. A target-major change can affect pod admission or file ownership.

Validate on every target profile:

- SCC availability and selection for mover and migrated workload pods,
- Pod Security Admission interaction,
- namespace UID range and supplemental group annotations,
- `runAsUser`, `runAsGroup`, `fsGroup`, and seccomp requirements,
- restricted container capabilities and privilege-escalation settings,
- preservation or intentional remapping of PVC file ownership.

Crane must not assume that OCP 5 retains every OCP 4 security API or annotation. Missing capabilities require explicit discovery and a safe failure.

### Storage and CSI

StorageClass names are never portable across target clusters, even within the same OCP major. OCP 5 can also change bundled CSI versions, defaults, topology behavior, or deprecated in-tree integrations.

Validate separately:

- CSI driver and provisioner identity,
- default and selected StorageClass behavior,
- `RWO`, `RWOP`, and `RWX` support,
- Filesystem versus Block mode,
- `WaitForFirstConsumer`, zones, and scheduling,
- volume expansion, snapshots, mount options, and permissions,
- target PVC creation and mover pod mounting.

Storage mapping must remain capability-based and versioned by target profile.

### Crane Client and Dependency Compatibility

Crane uses Kubernetes and OpenShift Go API dependencies and typed clients for parts of `transfer-pvc`. A new target major can expose client/server compatibility gaps even when common manifests remain valid.

For each OCP target major, test:

- authentication and API discovery,
- typed Route and OpenShift config API operations,
- creation, watch, log streaming, and deletion of temporary resources,
- error decoding for unknown or changed schemas,
- compatibility of the pinned `client-go`, OpenShift API, and `pvc-transfer` dependencies,
- mover image execution on supported node architectures and container runtimes.

Prefer dynamic discovery and unstructured reads for compatibility checks. Keep typed clients only where their contract is validated against both target majors.

### Existing Application Controllers and CRDs

Application CRDs or controllers may support only selected OCP releases. Crane only inspects them read-only and never installs them.

The report must distinguish:

- API schema compatibility,
- controller certification or documented support for the exact OCP target,
- admission webhook compatibility,
- unsupported or unknown external prerequisites.

## Required Target Matrix

For every xKS source profile, record separate rows:

| Source profile | Target profile | Manifest status | Direct PVC status | Indirect PVC status |
| --- | --- | --- | --- | --- |
| `<xKS/version/add-ons>` | `<OCP 4.minor.patch>` | | | |
| `<xKS/version/add-ons>` | `<OCP 5.minor.patch>` | | | |

Do not summarize these rows into a single "OCP supported" result unless every listed profile has passed.

## OCP 5 Enablement Gates

An OCP 5 profile can move from `Unknown` to `Experimental` only after:

1. Exact OCP and Kubernetes versions are recorded.
2. API discovery and server-side dry-run complete.
3. Ingress-to-Route conversion is validated.
4. A non-root workload passes the target security model.
5. RWO PVC provisioning, direct or indirect transfer, checksum, and cutover pass.
6. Temporary resources are cleaned up after success and failure.

It can move to `Supported` or `Supported with prerequisites` only after:

1. Official release-specific behavior is available and reviewed.
2. The complete required suite passes, including RWX and interruption tests where claimed.
3. Crane dependency compatibility is covered by automated tests.
4. Limitations and prerequisites are documented for the exact target release.
5. At least one target minor or patch upgrade regression has been exercised.

## Implementation Consequences

The initial implementation should add no OCP 5 special-case transformations without evidence. It should instead:

1. Require the exact target server version in the local compatibility report.
2. Discover required APIs, Route admission, security behavior, and StorageClasses before transformation or transfer.
3. Select transformations from capabilities rather than an `ocp4` or `ocp5` boolean.
4. Emit a local blocking finding for unknown target contracts.
5. Preserve indirect transfer as a fallback when direct Route-based transfer is unavailable.

These changes remain CLI-only and file-based. They require no operator, CRD, or Crane-specific custom resource in the cluster.
