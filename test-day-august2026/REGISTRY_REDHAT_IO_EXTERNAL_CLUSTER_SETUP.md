# Accessing registry.redhat.io from External Kubernetes Clusters

`mta-ops transfer-pvc` uses the downstream transfer image by default:

```text
registry.redhat.io/mta/mta-rsync-transfer-rhel9:<version>
```

An OpenShift cluster often has registry credentials in its global pull secret.
An external Kubernetes cluster, including Minikube, does not. Configure an image
pull secret in the migration namespace on **both** the source and destination
clusters before running a PVC transfer.

## Prerequisites

- Network access from every cluster node to `registry.redhat.io:443`.
- Red Hat registry credentials with an entitlement to the MTA transfer image.
  Obtain a registry service-account username and token from the Red Hat Hybrid
  Cloud Console or Customer Portal. A pull secret from an unrelated OpenShift
  cluster may not have this entitlement.
- `kubectl` access to the migration namespace on each cluster.

Never commit the service-account token or a generated `dockerconfigjson` secret.

## Configure Each Cluster

Set these values in a local shell. Do not save the token in this repository.

```bash
NAMESPACE=wordpress
RH_REGISTRY_USERNAME='<registry-service-account-username>'
RH_REGISTRY_TOKEN='<registry-service-account-token>'
```

Run the following on the source cluster, then run it again with `kubectl`
pointing at the destination cluster:

```bash
kubectl -n "${NAMESPACE}" create secret docker-registry mta-registry-pull \
  --docker-server=registry.redhat.io \
  --docker-username="${RH_REGISTRY_USERNAME}" \
  --docker-password="${RH_REGISTRY_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" patch serviceaccount default --type=strategic \
  -p '{"imagePullSecrets":[{"name":"mta-registry-pull"}]}'
```

The transfer utility creates its temporary inspect, upload, download, and rsync
pods in the migration namespace. Attaching the pull secret to its `default`
ServiceAccount lets those pods pull the downstream image.

For separate source and destination kubeconfigs, use the explicit environment
variable for each invocation:

```bash
KUBECONFIG=kubeconfig-src kubectl -n "${NAMESPACE}" create secret docker-registry mta-registry-pull \
  --docker-server=registry.redhat.io \
  --docker-username="${RH_REGISTRY_USERNAME}" \
  --docker-password="${RH_REGISTRY_TOKEN}" \
  --dry-run=client -o yaml | KUBECONFIG=kubeconfig-src kubectl apply -f -

KUBECONFIG=kubeconfig-src kubectl -n "${NAMESPACE}" patch serviceaccount default --type=strategic \
  -p '{"imagePullSecrets":[{"name":"mta-registry-pull"}]}'
```

Repeat the same two commands with `kubeconfig-tgt`.

## Verify the Pull

Before starting a migration, create a short-lived pod on each cluster:

```bash
IMAGE=registry.redhat.io/mta/mta-rsync-transfer-rhel9:8.3.0
kubectl -n "${NAMESPACE}" run mta-registry-check \
  --image="${IMAGE}" --restart=Never --command -- sleep 5

kubectl -n "${NAMESPACE}" wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/mta-registry-check --timeout=120s
kubectl -n "${NAMESPACE}" delete pod mta-registry-check --ignore-not-found
```

Use the exact image tag reported by `mta-ops transfer-pvc --help` when testing a
different MTA version.

## Run the Migration

No image override is needed once both clusters can pull the default image:

```bash
mta-ops transfer-pvc \
  --source-context src \
  --destination-context tgt \
  --pvc-name mysql-pv-claim:mysql-pv-claim \
  --pvc-namespace wordpress:wordpress \
  --cloud-storage remote:<bucket>/wordpress-mysql-pv-claim \
  --rclone-config-file rclone.conf \
  --dest-storage-class <target-storage-class> \
  --verify
```

The same pull-secret requirement applies to direct transfer: temporary transfer
pods are still created on both clusters.

## Troubleshooting

`ErrImagePull` or `ImagePullBackOff` with `unauthorized` means that the node
reached the registry but its credentials were rejected. Confirm all of the
following:

- The `mta-registry-pull` secret exists in the exact migration namespace.
- The relevant ServiceAccount lists the secret under `imagePullSecrets`.
- The registry service account is entitled to the `mta-rsync-transfer-rhel9`
  repository and the requested tag.
- The pod is using the expected ServiceAccount.

Useful diagnostics:

```bash
kubectl -n "${NAMESPACE}" get serviceaccount default \
  -o jsonpath='{.imagePullSecrets[*].name}{"\n"}'
kubectl -n "${NAMESPACE}" get events --sort-by=.lastTimestamp
kubectl -n "${NAMESPACE}" describe pod <transfer-pod-name>
```

As a temporary functional-test workaround, `transfer-pvc` accepts
`--source-image` and `--destination-image`. Do not use an alternate image to
claim that the downstream registry image has been validated; the explicit pull
check above is the required validation for that image.
