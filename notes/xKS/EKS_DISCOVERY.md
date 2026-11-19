# EKS discovery and first deployment

## Observed cluster, 2026-11-18

This report records Kubernetes API discovery and a live WordPress deployment. Commands used a dedicated kubeconfig at `/tmp/opencode/eks-first-steps.kubeconfig`.

| Item | Observed value |
| --- | --- |
| Cluster name reported by VPC CNI and EBS CSI | `oadp-eks-24-1` |
| Region | `us-east-1` |
| API server | `v1.34.12-eks-91f89a9` |
| Kubelets | `v1.34.12-eks-9adbfea` |
| kubectl | `v1.34.13-gke.100.1+aeb56f38b65297` |
| API readiness | `/readyz` returned `ok` |
| Identity | `system:serviceaccount:default:cluster-admin-sa` |
| Authorization check | `auth can-i '*' '*' --all-namespaces` returned `yes` |
| Initial namespaces | `default`, `kube-node-lease`, `kube-public`, `kube-system` |
| Application namespace created | `wordpress-eks` |

Initial login used the supplied TLS-skip option. After login, the namespace's `kube-root-ca.crt` ConfigMap supplied the CA for the dedicated kubeconfig. TLS skipping was removed, and `/readyz` succeeded with certificate verification enabled. This CA was obtained through the initial authenticated, TLS-unverified connection.

The supplied credential is stored only in that local kubeconfig. It is not included in these documents or manifests.

## Nodes and current health

All three nodes were Ready, Linux/amd64, Amazon Linux 2023.12.20261112, `m5.xlarge`, in node group `linux-nodes`.

| Node | Availability zone |
| --- | --- |
| `ip-192-168-13-170.ec2.internal` | `us-east-1f` |
| `ip-192-168-4-124.ec2.internal` | `us-east-1f` |
| `ip-192-168-46-122.ec2.internal` | `us-east-1b` |

Before application deployment, `kubectl top nodes` reported 38–49m CPU and 514–586Mi memory per node. All listed system Pods were Running with zero restarts.

Historical Warning events included node-startup `InvalidDiskCapacity`, CoreDNS scheduling before nodes became available, and an ECR image-pull timeout for one kube-proxy Pod. That Pod subsequently ran successfully. These events did not prevent the sample deployment.

## API inventory

`api-versions` returned 31 group/version entries. The main workload APIs are `v1`, `apps/v1`, `batch/v1`, `networking.k8s.io/v1`, `policy/v1`, `autoscaling/v1`, and `autoscaling/v2`.

Other served APIs include:

- `admissionregistration.k8s.io/v1`, including ValidatingAdmissionPolicy and bindings.
- `apiextensions.k8s.io/v1` and `apiregistration.k8s.io/v1`.
- Authentication, authorization, RBAC, certificates, coordination, discovery, events, scheduling, node, and API flow-control APIs.
- `resource.k8s.io/v1` and `resource.k8s.io/v1beta1` for dynamic resource allocation.
- `storage.k8s.io/v1` and `storage.k8s.io/v1beta1`.
- `snapshot.storage.k8s.io/v1`.
- `metrics.k8s.io/v1beta1` and `metrics.eks.amazonaws.com/v1`. The latter was advertised by discovery but did not contribute a resource row to `api-resources`.
- The AWS custom APIs listed below.

Ten CRDs were installed:

| API group/version | Kinds |
| --- | --- |
| `crd.k8s.amazonaws.com/v1alpha1` | `ENIConfig` |
| `vpcresources.k8s.aws/v1alpha1` | `CNINode` |
| `vpcresources.k8s.aws/v1beta1` | `SecurityGroupPolicy` |
| `networking.k8s.aws/v1alpha1` | `ApplicationNetworkPolicy`, `ClusterNetworkPolicy`, `ClusterPolicyEndpoint`, `PolicyEndpoint` |
| `snapshot.storage.k8s.io/v1` | `VolumeSnapshot`, `VolumeSnapshotContent`, `VolumeSnapshotClass` |

Three CNINode objects existed. The other six AWS custom resource kinds had no instances at discovery time. Snapshot APIs had one VolumeSnapshotClass. No snapshot creation or restore was tested.

No Gateway API, AWS Load Balancer Controller APIs such as TargetGroupBinding, OpenShift APIs, or OLM APIs appeared in discovery.

For migration, retain application-owned upstream resources, evaluate AWS policies and identities separately, and omit source infrastructure objects such as CNINode. Existing source snapshot objects do not by themselves provide a cross-provider data migration path.

## Storage

| StorageClass | Provisioner | Binding | Expansion | Reclaim |
| --- | --- | --- | --- | --- |
| `gp3`, default | `ebs.csi.aws.com` | `WaitForFirstConsumer` | Enabled | `Delete` |
| `gp2` | `kubernetes.io/aws-ebs` | `WaitForFirstConsumer` | Disabled | `Delete` |

Both classes specify `ext4`. The sample explicitly selects `gp3`.

- EBS CSI driver image version is `v1.68.0`. Two controller replicas and three Linux node Pods were healthy.
- Every CSINode registered `ebs.csi.aws.com`.
- `efs.csi.aws.com` exists as a CSIDriver object, but there were no EFS controller/node Pods, EFS entries in CSINode, or EFS StorageClasses. Working EFS/RWX provisioning remains unverified.
- `ebs-csi-snapclass` uses `ebs.csi.aws.com` and deletion policy `Delete`.
- Two snapshot-controller replicas use `v8.6.0`; the EBS controller's CSI snapshotter uses `v8.7.0-eksbuild.4`.

WordPress successfully provisioned two 1Gi RWO EBS volumes, mounted them, and wrote application data. Both volumes are in `us-east-1f`. This validates the basic CSI provisioning path, not resize, snapshot restore, or cross-zone recovery.

For an OCP migration, map `gp3` to a target filesystem/RWO StorageClass, transfer data separately, and let the target provision new PVs with its own topology. The source EBS volume identifiers and zone affinity are not portable.

## Networking and identity

- VPC CNI is `v1.22.4-eksbuild.14`, with network-policy agent `v1.4.0-eksbuild.4`.
- CoreDNS is `v1.12.4-eksbuild.82`; kube-proxy is `v1.34.6-eksbuild.69`.
- Metrics Server is `v0.9.1-eksbuild.2`; node metrics worked.
- No IngressClass, Ingress, application LoadBalancer Service, or ingress-controller Deployment was present.
- No Kubernetes NetworkPolicy existed at initial discovery. The agent was present, but policy enforcement was not tested.
- VPC CNI settings included IPv4 enabled, IPv6 disabled, Pod ENI disabled, prefix delegation disabled, and network-policy enforcing mode `standard`.
- The `aws-node` and `ebs-csi-controller-sa` ServiceAccounts had `eks.amazonaws.com/role-arn` annotations. Running EBS controller Pods and successful provisioning provide evidence that the storage path works.
- A `pod-identity-webhook` and VPC-resource mutating/validating webhooks were installed. A webhook name alone does not establish that EKS Pod Identity associations are configured. No Pod Identity agent DaemonSet was listed.

The API endpoint was reachable from this workstation, and nodes reported public IPs. AWS-side public/private endpoint settings, security groups, subnet routes, NAT configuration, IAM policies, and Pod Identity associations were not queried. Kubernetes credentials alone do not establish AWS account access.

The sample Job resolved `wordpress-mysql` and connected to MySQL. Image pulls from Docker Hub succeeded. No public application endpoint was created; HTTP validation used Kubernetes port-forwarding.

## Repeat discovery

Use an authenticated kubeconfig, then run:

```bash
export KUBECONFIG=/tmp/opencode/eks-first-steps.kubeconfig
kubectl version -o yaml
kubectl get --raw=/readyz
kubectl api-versions
kubectl api-resources -o wide
kubectl get crd
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type,eks.amazonaws.com/nodegroup
kubectl top nodes
kubectl get pods,deployments,daemonsets,services,pvc,ingress -A -o wide
kubectl get storageclass,csidriver,csinode,volumesnapshotclass,ingressclass
kubectl get networkpolicy -A
kubectl get events -A --field-selector=type=Warning
```

`kubectl get all` is only a subset of the inventory. Use `api-resources` to discover kinds, `kubectl explain deployment.spec` to inspect a schema, and explicit `get` commands to inspect objects. Avoid exporting Secret contents into shareable evidence.

## Validated sample and next checks

See [WordPress on EKS](wordpress-eks/README.md) for deployment, access, validation results, and cleanup.

Useful next experiments are EBS snapshot/restore, PVC expansion, Pod replacement with data verification, and choosing an external exposure controller if public ingress is needed. EKS-to-OCP migration still requires a specific target cluster, SCC checks for the sample's container users, storage mapping, data transfer, and application validation after cutover. This run establishes the EKS source baseline only.
