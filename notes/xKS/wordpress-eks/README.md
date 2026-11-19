# WordPress on EKS

This overlay deploys the [June test-day sample](../../../test-day-june2026/sample-apps/wordpress) into `wordpress-eks`. It reuses the sample's existing `.env` file to generate a Kubernetes Secret. Keep that file and rendered Secret contents out of version control.

The overlay selects EBS CSI StorageClass `gp3` for both 1Gi RWO PVCs and changes the frontend Service to `ClusterIP`. The installation Job shares the frontend PVC and has required Pod affinity to the frontend's node.

## Access the running application

The dedicated kubeconfig created during the first deployment is temporary local state:

```bash
export KUBECONFIG=/tmp/opencode/eks-first-steps.kubeconfig
kubectl -n wordpress-eks get pods,pvc,svc
kubectl -n wordpress-eks port-forward service/wordpress 8080:80
```

Open <http://127.0.0.1:8080/> or <http://127.0.0.1:8080/wp-admin/> while port-forward is running.

The administrator username is `admin`. Its password is `WORDPRESS_ADMIN_PASSWORD` in `test-day-june2026/sample-apps/wordpress/.env`. MySQL and WordPress credentials match that existing sample configuration.

## Deploy again

Run from `notes/xKS`, using a kubeconfig authenticated to the intended EKS cluster:

```bash
kubectl apply --dry-run=client -k wordpress-eks
kubectl apply -k wordpress-eks
kubectl -n wordpress-eks wait --for=condition=available deployment --all --timeout=300s
kubectl -n wordpress-eks wait --for=condition=complete job/wordpress-install --timeout=300s
kubectl -n wordpress-eks logs job/wordpress-install
kubectl -n wordpress-eks get pods,pvc,svc -o wide
```

If the sample's `.env` is absent in a fresh checkout, prepare it using the base sample's instructions before rendering the overlay. Reapplying unchanged manifests retains existing data and the completed Job. Changes to the Job's immutable Pod template require recreating that Job explicitly.

## Validate

The shared validation script uses the kubeconfig's current namespace. The following uses a subshell to leave the caller's `KUBECONFIG` environment unchanged:

```bash
(
  export KUBECONFIG=/tmp/opencode/eks-first-steps.kubeconfig
  kubectl config set-context --current --namespace=wordpress-eks
  PORT=18081 WORDPRESS_SEED_ID=1819 bash ../../test-day-june2026/sample-apps/wordpress/validate.sh
)
```

Run from `notes/xKS`. For a fresh installation, replace `1819` with the value in the installation Job's logs. The script starts and stops its own port-forward.

## Initial validation, 2026-11-18

- EKS `oadp-eks-24-1`, Kubernetes `v1.34.12-eks-91f89a9`.
- Client-side dry run, deployment, and both availability waits passed.
- A subsequent server-side dry run accepted every overlay resource as unchanged.
- WordPress frontend had `2/2` containers Ready; MySQL had `1/1`, with zero restarts.
- Installation Job completed with zero restarts and created WordPress post ID `4`, titled `Sample post #1819`.
- Both PVCs were Bound, 1Gi RWO, `gp3`, filesystem `ext4`, driver `ebs.csi.aws.com`, zone `us-east-1f`.
- WordPress and the installation Job ran on `ip-192-168-13-170.ec2.internal`. MySQL ran on `ip-192-168-4-124.ec2.internal`.
- The validation script exited successfully. HTTP returned `200`, and HTML contained `Hello from k8s`, `Sample post #`, and the exact seed `#1819`.
- No Warning events were present in `wordpress-eks` after installation.
- Both Services remained ClusterIP; no AWS load balancer was requested.

Resolved image digests from this run:

| Container | Base sample tag | Digest |
| --- | --- | --- |
| WordPress FPM | `wordpress:6-fpm-alpine` | `sha256:b0062e171b9c8a24e28acdd25cb8ea67e95e60ca0b3c982f88faf93217b0e1a9` |
| NGINX | `nginx:alpine` | `sha256:fed7e14be83cbd2661a75cdc5b872d936cf155d46c327084d30b8df19ae88d72` |
| MySQL | `mysql:8.0` | `sha256:7dcddc01f13bab2f15cde676d44d01f61fc9f99fe7785e86196dfc07d358ae2b` |
| Installation CLI | `wordpress:cli-2` | `sha256:e4980e3ef763ce7535049c05a54e906d95b16370f28ca02fa329a079eebf3f65` |

The base sample uses mutable tags, so future runs can resolve different images. The base Deployments do not define readiness probes; the separate HTTP/content validation confirms application behavior for this run.

## Cleanup

The deployment remains running for further experiments. To remove the entire sample, including its database and WordPress data:

```bash
kubectl delete -k wordpress-eks
```

The overlay includes the namespace. Both PVCs use a StorageClass with reclaim policy `Delete`, so cleanup also requests deletion of the backing EBS volumes.

See [EKS discovery](../EKS_DISCOVERY.md) for the cluster inventory and remaining validation work.
