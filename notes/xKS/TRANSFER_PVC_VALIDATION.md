# Validating transfer-pvc Across Platforms

## Current Flow

For a direct transfer, Crane:

1. Reads the source PVC.
2. Creates or validates the target PVC.
3. Creates a `route` or `nginx-ingress` endpoint on the target.
4. Creates the target stunnel/rsync server.
5. Copies the mTLS Secret to the source.
6. Starts the source client and copies data.
7. Removes temporary resources.

The source pod therefore initiates the connection to the target cluster endpoint. The reverse migration direction must be tested separately.

Current Crane also provides indirect transfer through S3-compatible object storage. This is the fallback for private clusters, incompatible ingress, or clusters without mutual connectivity.

## Direct Transfer Network Prerequisites

Validate on the target:

- an installed and functional ingress controller or OCP router,
- a compatible `IngressClass`,
- TCP/TLS passthrough support for stunnel, not only HTTP termination,
- creation of a publicly or privately reachable hostname,
- correct DNS and certificate passthrough behavior,
- permitted inbound traffic to the load balancer or router.

Validate on the source:

- target hostname resolution from the mover pod,
- egress from the pod or node network to the target port,
- proxy, firewall, network policy, and cloud egress rules,
- access to the registry containing the mover image.

Crane preflight should validate these conditions before creating the target PVC, or at least before starting a long-running transfer.

## Endpoint Matrix

| Target | Preferred endpoint | Notes |
| --- | --- | --- |
| OCP 4 | `route` | Validate passthrough Route and router domain |
| AKS | `nginx-ingress` | A compatible controller is not guaranteed; requires a specific ingress class and subdomain |
| EKS | `nginx-ingress` | AWS Load Balancer Controller alone may not satisfy NGINX annotations or passthrough behavior |
| kind/minikube | `nginx-ingress` | Control baseline; ingress must be reachable from the other cluster |

When a platform uses another ingress implementation, validate behavior rather than only checking for an `IngressClass`.

## StorageClass Mapping

Mapping must be more than a `source name -> target name` string. Record for every pair:

- CSI provisioner,
- `volumeBindingMode`,
- `allowVolumeExpansion`,
- `reclaimPolicy`,
- supported access modes (`RWO`, `RWOP`, `RWX`, `ROX`),
- `volumeMode` (`Filesystem` or `Block`),
- topology and zone constraints,
- mount options and filesystem,
- encryption and performance tier,
- minimum or rounded capacity,
- snapshot and clone capabilities.

Example mapping profile:

```yaml
source:
  name: ocs-storagecluster-ceph-rbd
  accessModes: [ReadWriteOnce]
  volumeMode: Filesystem
target:
  name: managed-csi-premium
requiredCapabilities:
  accessModes: [ReadWriteOnce]
  volumeMode: Filesystem
decision: compatible-with-validation
```

Exact class names depend on cluster configuration and must not be hardcoded as universal defaults.

## Required Tests

### T1: Dynamic Provisioning

- The source PVC is `Bound`.
- Crane creates the target PVC with explicit `--dest-storage-class`.
- The target PVC becomes `Bound` in the correct zone.
- The mover pod mounts the PVC and writes data.

### T2: Existing Target PVC

- The target PVC has the correct name, namespace, capacity, and StorageClass.
- No active workload uses it.
- Crane does not reprovision it or change its storage properties.

### T3: Data Integrity and File Metadata

- Include small files, one large file, a sparse file, and a deep directory tree.
- Compare checksums before and after transfer.
- Evaluate UID/GID, modes, symlinks, and timestamps against declared mover capabilities.
- Record non-root transfer limitations explicitly.

### T4: Interruption

- Delete a mover pod or temporarily block networking during the copy.
- Record retry/resume behavior and repeat-run safety.
- Ensure partial data is not reported as success.

### T5: Cleanup

- After success and failure, inspect temporary Pods, Services, Ingresses/Routes, Secrets, and ConfigMaps.
- Preserve the target PVC and transferred data.

### T6: Indirect Transfer

- Validate an S3-compatible endpoint reachable from both clusters.
- Use separate credentials with minimum permissions.
- Validate checksum, encryption, cleanup, and `--keep-cloud-data`.
- Record egress cost and object-size or object-count limitations.

### T7: Cutover

- An initial copy may run with the source workload active only when application consistency is addressed.
- Quiesce or scale down the workload before the final copy.
- Start the target workload only after successful verification.
- Database workloads require an application-consistent procedure; file copy alone does not guarantee consistency.

## Security Validation

- Mover pods run without privilege escalation and with minimum capabilities.
- OCP SCC and Kubernetes Pod Security Admission accept them.
- Temporary certificates are not logged and are removed after transfer.
- RBAC permits only required resources in migration namespaces.
- The mover image is reachable and trusted on both platforms.
- Object-storage credentials do not appear in reports or persistent artifacts.

## Acceptance Criteria

A direct direction is supported when:

- preflight identifies missing ingress, passthrough, and storage prerequisites,
- 10 GiB of reference data transfers without corruption,
- checksum validation succeeds,
- the workload passes a functional smoke test after cutover,
- repeated execution has defined and safe behavior,
- no temporary resources remain after success or a handled failure.

If topology prevents direct transfer, a profile may be supported only through indirect transfer when this restriction is clearly detected and documented.
