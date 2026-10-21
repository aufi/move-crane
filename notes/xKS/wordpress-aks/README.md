# WordPress on AKS

The complete validated migration procedure is recorded in [WordPress migration from AKS to CRC](migration-2026-10-21/MIGRATION_AKS_TO_CRC.md), including export, transformation, indirect S3 transfer, target deployment, and application checks.

This overlay deploys [the June test-day sample](../../../test-day-june2026/sample-apps/wordpress) into `marek-test`. It uses the sample's existing `.env` file for generated Kubernetes Secrets. Do not commit that file or rendered Secret manifests.

The installation Job shares the WordPress RWO PVC. Pod affinity places it on the same node as the frontend so both can mount the Azure Disk.

## Deploy

Run from `notes/xKS`:

```bash
export KUBECONFIG="$HOME/mig/kubeadmin-kubeconfig-az.txt"
kubectl get namespace marek-test || kubectl create namespace marek-test
kubectl apply -k wordpress-aks
kubectl -n marek-test wait --for=condition=available --timeout=300s deployment --all
kubectl -n marek-test wait --for=condition=complete --timeout=300s job/wordpress-install
kubectl -n marek-test get pods,pvc,svc
```

The WordPress Service is a public `LoadBalancer`. The two 1 GiB PVCs use the cluster's default StorageClass.

## Access

Get the current public IP:

```bash
kubectl -n marek-test get service wordpress
```

Open `http://<EXTERNAL-IP>/` or `/wp-admin/`. The administrator username is `admin`. Its password is `WORDPRESS_ADMIN_PASSWORD` in `test-day-june2026/sample-apps/wordpress/.env`.

For local access:

```bash
kubectl -n marek-test port-forward service/wordpress 8080:80
```

Then open `http://127.0.0.1:8080/`.

## Initial validation, 2026-10-21

- Context `kubeadmin`, AKS API `crane-test-aks-dns-qclb06l3.hcp.eastus.azmk8s.io`.
- Kubernetes `v1.36.4`, four Ready Linux nodes.
- WordPress `2/2` containers Ready and MySQL `1/1`, with zero restarts.
- Installation Job completed and created sample post `#11079`.
- Both PVCs Bound, each 1 GiB RWO, StorageClass `default`, provisioner `disk.csi.azure.com`.
- Public endpoint `http://48.206.162.144/` returned HTTP 200 with `Sample post #11079` and `Hello from k8s`.
- The sample validation script passed all application checks through port-forward. Its shell invocation timed out after printing successful results and cleanup. A separate request to the public endpoint passed.
- No Warning events in `marek-test` at the end of deployment.

This run validates sample deployment on AKS. It does not validate Crane export, transformation, or PVC transfer.
