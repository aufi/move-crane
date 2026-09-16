# Amazon Elastic Kubernetes Service Support Plan

## Second-Phase Goal

After stabilizing the process on AKS, validate OCP 4 to EKS migrations in both directions. EKS validation must prove that the resulting solution is capability-based and not implicitly tied to Azure.

## Reference Profiles

| Profile | Network | Exposure | Storage |
| --- | --- | --- | --- |
| EKS-public | Publicly reachable endpoint | NGINX-compatible ingress | EBS CSI (RWO) |
| EKS-private | Private endpoint/VPC | Private ingress or no direct path | EBS CSI and indirect S3-compatible transfer |
| EKS-RWX | Public or private | Profile-dependent | EFS CSI (RWX) |

AWS Load Balancer Controller and NGINX ingress controller are different implementations. The former alone does not prove compatibility with Crane's `nginx-ingress` endpoint.

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

## OCP to EKS Risks

- OpenShift resources require the same classification process as for AKS.
- Route-to-Ingress conversion must not assume a specific AWS load balancer controller without discovery.
- Map OCP RWO storage to EBS CSI by topology and performance requirements.
- Map OCP RWX storage to EFS or another target filesystem only after checking POSIX and permission behavior.
- The source OCP pod must reach the endpoint in the target VPC; otherwise use indirect transfer.

## EKS to OCP Risks

- AWS-specific Service and Ingress annotations require removal or transformation.
- `TargetGroupBinding` and other controller CRDs are not portable without their target controller.
- IRSA and Pod Identity bindings do not become functional cloud identities on OCP.
- Map EBS/EFS StorageClasses to OCP storage by capability.
- ECR image references require network access and credentials or image synchronization.

## Test Backlog

| Priority | Test | Expected result |
| --- | --- | --- |
| P0 | OCP Route to EKS exposure | Functional, explicitly selected controller |
| P0 | OCP RWO PVC to EBS CSI | Transfer, checksum, topology, and cutover |
| P0 | EKS EBS PVC to OCP RWO CSI | Reverse direction over its independent network path |
| P0 | NGINX endpoint on public EKS | stunnel connectivity from an OCP pod |
| P0 | Private EKS through S3-compatible storage | Functional fallback |
| P1 | OCP RWX storage and EFS CSI | Permissions, symlinks, and performance |
| P1 | AWS load balancer annotations to OCP | Safe removal or mapping |
| P1 | IRSA or Pod Identity workload | Actionable prerequisite or blocker |
| P1 | Non-root StatefulSet | PSA/SCC and file ownership |
| P2 | TargetGroupBinding or ACK CR | CRD and controller discovery |
| P2 | EKS minor/add-on upgrade | API, EBS/EFS, and ingress regression coverage |

## Generalization Check After AKS

Before adding EKS-specific code, determine:

- whether the issue is a general OCP-to-upstream difference,
- whether capability discovery (`IngressClass`, CSI, served APIs) can solve it,
- whether StorageClass mapping incorrectly uses Azure names as logic,
- whether indirect transport uses a general S3-compatible contract,
- whether the CLI plugin contains only AWS CRDs and annotations rather than general transformations, and does not install in-cluster components.

## Definition of Done

- P0 scenarios pass in both directions on recorded versions.
- Public and private profiles have validated data transfer paths.
- The AWS Load Balancer Controller versus NGINX endpoint difference is detected before transfer.
- EBS/EFS mapping is capability-based.
- AWS identities and CRDs are not silently transferred as apparently functional resources.
- Results use the same [validation report template](VALIDATION_REPORT_TEMPLATE.md) as AKS.
