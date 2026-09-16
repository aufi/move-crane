# Amazon Elastic Kubernetes Service Support Plan

## Second-Phase Goal

After stabilizing the process on AKS, validate migrations from EKS into OCP 4 or OCP 5. EKS validation must prove that the resulting solution is capability-based and not implicitly tied to Azure. Each OCP major and minor is a separate target profile.

## Reference Profiles

| Source profile | Network | Workload exposure | Source storage |
| --- | --- | --- | --- |
| EKS-public | Public API and egress | Public Ingress or LoadBalancer resources | EBS CSI (RWO) |
| EKS-private | Private endpoint/VPC with controlled egress | Private Ingress or LoadBalancer resources | EBS CSI and indirect S3-compatible fallback |
| EKS-RWX | Public or private | Profile-dependent | EFS CSI (RWX) |

AWS Load Balancer Controller and NGINX ingress controller are different implementations. Their resources and annotations require different transformations when producing an OCP Route. Neither controller is used as the `transfer-pvc` target endpoint because OCP is always the target.

## EKS Discovery

In addition to the general process, determine:

- public/private API endpoints and VPC connectivity,
- security groups, network ACLs, NAT/egress, and network policies,
- ingress controller, `IngressClass`, load balancer scheme, and TLS passthrough,
- EBS CSI and EFS CSI add-ons, versions, and StorageClasses,
- availability zones, node groups, and `WaitForFirstConsumer`,
- IRSA or EKS Pod Identity bindings for ServiceAccounts and workloads,
- AWS Load Balancer Controller resources and annotations,
- optional CRDs such as `TargetGroupBinding`, ACK controllers, External Secrets, or autoscaling add-ons,
- ECR access and AWS IAM dependencies.

## EKS to OCP Risks

- AWS-specific Service and Ingress annotations require removal or transformation.
- `TargetGroupBinding` and other controller CRDs are not portable without their target controller.
- IRSA and Pod Identity bindings do not become functional cloud identities on OCP.
- Map EBS/EFS StorageClasses to OCP storage by capability.
- ECR image references require network access and credentials or image synchronization.
- Validate EKS Pod Security assumptions against OCP SCC and namespace-assigned UID/GID ranges.
- Ensure the EKS mover pod can resolve and reach the target OCP passthrough Route.
- Do not assume OCP 5 retains the OCP 4 Route, SCC, namespace UID/GID, or CSI contracts; run the target-major gates first.

## Test Backlog

| Priority | Test | Expected result |
| --- | --- | --- |
| P0 | EKS Ingress to OCP Route | Functional exposure with recorded transformation |
| P0 | EKS EBS PVC to OCP RWO CSI | Transfer, checksum, topology, and cutover |
| P0 | Public EKS source to OCP Route | stunnel connectivity from an EKS mover pod |
| P0 | Private EKS through S3-compatible storage | Functional fallback when OCP Route is unreachable |
| P0 | EKS to OCP 5 target-major gate | API discovery, security, Route, CSI, and Crane client compatibility |
| P1 | EFS CSI to OCP RWX storage | Permissions, symlinks, and performance |
| P1 | AWS load balancer annotations to OCP | Safe removal or mapping |
| P1 | IRSA or Pod Identity workload | Actionable prerequisite or blocker |
| P1 | Non-root StatefulSet | PSA/SCC and file ownership |
| P2 | TargetGroupBinding or ACK CR | CRD and controller discovery |
| P2 | EKS minor/add-on upgrade | API, EBS/EFS, and ingress regression coverage |

## Generalization Check After AKS

Before adding EKS-specific code, determine:

- whether the issue is a general upstream-to-OCP difference,
- whether capability discovery (`IngressClass`, CSI, served APIs) can solve it,
- whether StorageClass mapping incorrectly uses Azure names as logic,
- whether indirect transport uses a general S3-compatible contract,
- whether the CLI plugin contains only AWS CRDs and annotations rather than general transformations, and does not install in-cluster components.

## Definition of Done

- P0 EKS-to-OCP scenarios pass separately on every claimed OCP 4 or OCP 5 target profile.
- Public and private profiles have validated data transfer paths.
- AWS Load Balancer Controller and NGINX workload exposure differences are detected before manifest transformation.
- EBS/EFS mapping is capability-based.
- AWS identities and CRDs are not silently transferred as apparently functional resources.
- Results use the same [validation report template](VALIDATION_REPORT_TEMPLATE.md) as AKS.
- OCP 5 remains `Unknown` or `Experimental` until [target-major enablement gates](OCP_TARGET_VERSIONS.md) pass.
