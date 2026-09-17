# Using the rsync-transfer Image with the Integrated OpenShift Registry

**Verification date:** 2026-09-16

**Scope:** Direct `transfer-pvc` between two OpenShift clusters using rsync/stunnel

**Reference image:** `registry.redhat.io/mta/mta-rsync-transfer-rhel9:8.3.0`

## Summary

This procedure stores the transfer image in the integrated image registry of each OpenShift cluster.

The procedure is:

1. Export the image to a file-based mirror on a connected host.
2. Move the mirror into the disconnected environment using approved removable media.
3. Import the image into the integrated registry of both OpenShift clusters.
4. Grant the migration namespaces permission to pull from the image project.
5. Verify the image with a test Pod in both clusters.
6. Pass the cluster-internal pullspec to `transfer-pvc`.

The image is stored under the same project, repository, and tag in both clusters. This gives it the same cluster-internal pullspec in both clusters:

```text
image-registry.openshift-image-registry.svc:5000/mta-images/mta-rsync-transfer-rhel9:8.3.0
```

The hostname resolves to the local integrated registry in each cluster. Each cluster therefore pulls its own local copy of the image.

> `transfer-pvc` creates mover Pods in both clusters. Importing the image only into the destination cluster is not sufficient.

Disconnected in this document means that the clusters cannot access external registries or the internet. A direct rsync/stunnel transfer still requires a network path from the source mover Pod to a passthrough Route or another supported destination endpoint. If no path exists between the clusters, mirroring the image does not make a direct transfer possible.

## Scope Limitation

This integrated-registry-only procedure assumes that both source and destination are OpenShift clusters with the integrated image registry enabled.

The current upstream implementation uses the image options as follows:

| Cluster | Container | Option used |
| --- | --- | --- |
| Source | rsync client | `--source-image` |
| Source | stunnel client | `--destination-image` |
| Destination | rsync server | `--destination-image` |
| Destination | stunnel server | `--destination-image` |

Using the same cluster-internal pullspec in both OpenShift clusters avoids problems caused by the source stunnel sidecar using `--destination-image`.

If the source is not OpenShift, it cannot normally resolve or pull from `image-registry.openshift-image-registry.svc:5000`. That topology requires a registry reachable from both clusters or a downstream `mta-ops` build in which source-side containers consistently use `--source-image`.

Verify the exact downstream behavior with:

```bash
mta-ops transfer-pvc --help
```

## Prerequisites

- Valid entitlement to `registry.redhat.io` and a Red Hat registry authentication file.
- `oc`, `podman`, and optionally `skopeo` on the connected host.
- `oc` on the disconnected import host.
- Cluster administrator access to both OpenShift clusters.
- The integrated image registry enabled and available in both clusters.
- A configured external route to each integrated registry, or permission to enable its default route temporarily.
- Approved removable media with sufficient capacity.
- Existing source and destination migration namespaces.

The examples use:

```bash
export VERSION=8.3.0
export SOURCE_IMAGE="registry.redhat.io/mta/mta-rsync-transfer-rhel9:${VERSION}"
export IMAGE_PROJECT="mta-images"
export IMAGE_NAME="mta-rsync-transfer-rhel9"
export MIRROR_DIR="$PWD/mta-transfer-mirror"
export REDHAT_AUTH_FILE="$HOME/redhat-auth.json"

export SOURCE_CONTEXT="source"
export DESTINATION_CONTEXT="destination"
export SOURCE_NAMESPACE="source-app"
export DESTINATION_NAMESPACE="destination-app"

export TRANSFER_IMAGE="image-registry.openshift-image-registry.svc:5000/${IMAGE_PROJECT}/${IMAGE_NAME}:${VERSION}"
```

## 1. Export the Image on a Connected Host

Log in to the Red Hat registry:

```bash
podman login --authfile "$REDHAT_AUTH_FILE" registry.redhat.io
```

Verify that the image exists and record its digest:

```bash
skopeo inspect --authfile "$REDHAT_AUTH_FILE" \
  --format '{{.Digest}}' "docker://${SOURCE_IMAGE}"
```

Export every platform in the image to a file-based mirror:

```bash
oc image mirror \
  --registry-config="$REDHAT_AUTH_FILE" \
  --keep-manifest-list=true \
  --dir="$MIRROR_DIR" \
  "$SOURCE_IMAGE" \
  "file://mta/${IMAGE_NAME}:${VERSION}"
```

Archive the mirror and create a checksum:

```bash
tar -C "$(dirname "$MIRROR_DIR")" -czf mta-transfer-mirror.tar.gz \
  "$(basename "$MIRROR_DIR")"
sha256sum mta-transfer-mirror.tar.gz > mta-transfer-mirror.tar.gz.sha256
```

Move both files across the air gap. Do not move the Red Hat authentication file unless explicitly required by the approved procedure.

## 2. Prepare the Integrated Registries

Verify that the registry operator is available in both clusters:

```bash
oc --context "$SOURCE_CONTEXT" get clusteroperator image-registry
oc --context "$DESTINATION_CONTEXT" get clusteroperator image-registry
```

Create the same image project and ImageStream in both clusters:

```bash
oc --context "$SOURCE_CONTEXT" new-project "$IMAGE_PROJECT"
oc --context "$SOURCE_CONTEXT" -n "$IMAGE_PROJECT" create imagestream "$IMAGE_NAME"

oc --context "$DESTINATION_CONTEXT" new-project "$IMAGE_PROJECT"
oc --context "$DESTINATION_CONTEXT" -n "$IMAGE_PROJECT" create imagestream "$IMAGE_NAME"
```

If these resources already exist, inspect and reuse them instead of recreating them.

The disconnected import host needs an externally reachable route to each integrated registry. Check whether public registry hostnames already exist:

```bash
oc --context "$SOURCE_CONTEXT" registry info --public --check
oc --context "$DESTINATION_CONTEXT" registry info --public --check
```

If a cluster does not expose the registry and organizational policy permits it, enable the default route:

```bash
oc --context "$CONTEXT" patch configs.imageregistry.operator.openshift.io/cluster \
  --type=merge -p '{"spec":{"defaultRoute":true}}'
oc --context "$CONTEXT" get route default-route -n openshift-image-registry
```

The import host must resolve the route, reach it over HTTPS, and trust its ingress certificate. This affects only the host pushing the image. Pods pulling through the cluster-internal registry service do not require a custom registry CA.

## 3. Import the Image into Both Clusters

Verify and extract the archive on the disconnected import host:

```bash
sha256sum -c mta-transfer-mirror.tar.gz.sha256
tar -xzf mta-transfer-mirror.tar.gz
export MIRROR_DIR="$PWD/mta-transfer-mirror"
```

Import the image into the source cluster:

```bash
export SOURCE_REGISTRY="$(oc --context "$SOURCE_CONTEXT" registry info --public)"
export SOURCE_REGISTRY_AUTH="$HOME/source-registry-auth.json"

oc --context "$SOURCE_CONTEXT" registry login \
  --registry="$SOURCE_REGISTRY" --to="$SOURCE_REGISTRY_AUTH"

oc image mirror \
  --registry-config="$SOURCE_REGISTRY_AUTH" \
  --keep-manifest-list=true \
  --from-dir="$MIRROR_DIR" \
  "file://mta/${IMAGE_NAME}:${VERSION}" \
  "${SOURCE_REGISTRY}/${IMAGE_PROJECT}/${IMAGE_NAME}:${VERSION}"
```

Import the same image into the destination cluster:

```bash
export DESTINATION_REGISTRY="$(oc --context "$DESTINATION_CONTEXT" registry info --public)"
export DESTINATION_REGISTRY_AUTH="$HOME/destination-registry-auth.json"

oc --context "$DESTINATION_CONTEXT" registry login \
  --registry="$DESTINATION_REGISTRY" --to="$DESTINATION_REGISTRY_AUTH"

oc image mirror \
  --registry-config="$DESTINATION_REGISTRY_AUTH" \
  --keep-manifest-list=true \
  --from-dir="$MIRROR_DIR" \
  "file://mta/${IMAGE_NAME}:${VERSION}" \
  "${DESTINATION_REGISTRY}/${IMAGE_PROJECT}/${IMAGE_NAME}:${VERSION}"
```

Remove the temporary registry authentication files after the import according to local credential-handling policy.

If the default registry routes were enabled only for this import, disable them after confirming that no other process uses them:

```bash
oc --context "$CONTEXT" patch configs.imageregistry.operator.openshift.io/cluster \
  --type=merge -p '{"spec":{"defaultRoute":false}}'
```

Disabling the external route does not affect pulls through the cluster-internal registry service.

## 4. Grant Pull Access to the Migration Namespaces

OpenShift automatically provides ServiceAccounts with credentials for its integrated registry.

Because the image is stored in the dedicated `mta-images` project, grant all ServiceAccounts in each migration namespace the `system:image-puller` role in that cluster:

```bash
oc --context "$SOURCE_CONTEXT" policy add-role-to-group system:image-puller \
  "system:serviceaccounts:${SOURCE_NAMESPACE}" \
  --namespace="$IMAGE_PROJECT"

oc --context "$DESTINATION_CONTEXT" policy add-role-to-group system:image-puller \
  "system:serviceaccounts:${DESTINATION_NAMESPACE}" \
  --namespace="$IMAGE_PROJECT"
```

This is the only additional pull authorization required for the integrated registry. If the image is stored directly in each migration namespace instead, this cross-project role grant is unnecessary, but the two clusters will no longer share one uniform pullspec when the namespace names differ.

## 5. Verify the Image in Both Clusters

Run a test Pod in the source namespace:

```bash
oc --context "$SOURCE_CONTEXT" -n "$SOURCE_NAMESPACE" run mta-transfer-image-check \
  --image="$TRANSFER_IMAGE" --restart=Never --command -- /bin/bash -c \
  'test -x /usr/bin/rsync && test -x /bin/stunnel && command -v nc >/dev/null && /usr/bin/rsync --version'
oc --context "$SOURCE_CONTEXT" -n "$SOURCE_NAMESPACE" wait \
  --for=jsonpath='{.status.phase}'=Succeeded pod/mta-transfer-image-check --timeout=2m
oc --context "$SOURCE_CONTEXT" -n "$SOURCE_NAMESPACE" logs mta-transfer-image-check
oc --context "$SOURCE_CONTEXT" -n "$SOURCE_NAMESPACE" delete pod mta-transfer-image-check
```

Repeat the test in the destination namespace:

```bash
oc --context "$DESTINATION_CONTEXT" -n "$DESTINATION_NAMESPACE" run mta-transfer-image-check \
  --image="$TRANSFER_IMAGE" --restart=Never --command -- /bin/bash -c \
  'test -x /usr/bin/rsync && test -x /bin/stunnel && command -v nc >/dev/null && /usr/bin/rsync --version'
oc --context "$DESTINATION_CONTEXT" -n "$DESTINATION_NAMESPACE" wait \
  --for=jsonpath='{.status.phase}'=Succeeded pod/mta-transfer-image-check --timeout=2m
oc --context "$DESTINATION_CONTEXT" -n "$DESTINATION_NAMESPACE" logs mta-transfer-image-check
oc --context "$DESTINATION_CONTEXT" -n "$DESTINATION_NAMESPACE" delete pod mta-transfer-image-check
```

If a test fails, inspect the Pod with `oc describe pod mta-transfer-image-check`. Common causes are missing `system:image-puller` authorization, an unavailable registry operator, or a missing manifest for the node architecture.

## 6. Run the Direct Migration

Use the same cluster-internal pullspec for both image options:

```bash
mta-ops transfer-pvc \
  --source-context="$SOURCE_CONTEXT" \
  --destination-context="$DESTINATION_CONTEXT" \
  --pvc-name="$SOURCE_PVC:$DESTINATION_PVC" \
  --pvc-namespace="$SOURCE_NAMESPACE:$DESTINATION_NAMESPACE" \
  --dest-storage-class="$DESTINATION_STORAGE_CLASS" \
  --endpoint=route \
  --source-image="$TRANSFER_IMAGE" \
  --destination-image="$TRANSFER_IMAGE" \
  --verify
```

Stop or correctly quiesce the source workload before the final transfer. rsync alone does not guarantee application consistency for a database.

While the transfer runs, confirm that all mover containers use the expected image digest:

```bash
oc --context "$SOURCE_CONTEXT" -n "$SOURCE_NAMESPACE" get pods \
  -l app.kubernetes.io/component=transfer-pvc \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.containerStatuses[*]}  {.name}{" => "}{.imageID}{"\n"}{end}{end}'

oc --context "$DESTINATION_CONTEXT" -n "$DESTINATION_NAMESPACE" get pods \
  -l app.kubernetes.io/component=transfer-pvc \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.containerStatuses[*]}  {.name}{" => "}{.imageID}{"\n"}{end}{end}'
```

## Acceptance Checklist

- [ ] The archive passed `sha256sum -c` validation.
- [ ] The integrated registry operator is available in both clusters.
- [ ] The image was imported into the same project and repository in both clusters.
- [ ] The mirror contains a manifest for every planned node architecture.
- [ ] Both migration namespaces have `system:image-puller` access to `mta-images`.
- [ ] The test Pod succeeded in both migration namespaces.
- [ ] `mta-ops transfer-pvc --help` confirms both image options.
- [ ] Source and destination mover containers used the expected `imageID`.
- [ ] The source workload was consistently stopped before the final transfer.
- [ ] `--verify` completed data verification successfully.
- [ ] Temporary mover Pods, Secrets, Services, and Routes were removed after migration.
- [ ] Temporary registry authentication files were removed securely.

## Sources and Verification Status

- OpenShift integrated registry access: <https://docs.redhat.com/en/documentation/openshift_container_platform/latest/html/registry/accessing-the-registry>
- Upstream Crane image options: <https://github.com/migtools/crane/blob/7f87cc2641ccd1e249d387402a35c35cdb4e6b4b/cmd/transfer-pvc/transfer-pvc.go#L185-L186>
- Upstream direct transfer image wiring: <https://github.com/migtools/crane/blob/7f87cc2641ccd1e249d387402a35c35cdb4e6b4b/cmd/transfer-pvc/transfer-pvc.go#L467-L652>
- rsync-transfer image source: <https://github.com/migtools/rsync-transfer>

The image pull from `registry.redhat.io` could not be completed during this analysis without Red Hat credentials. An authorized user must verify the availability, digest, architectures, and signature of tag `8.3.0` before transfer.
