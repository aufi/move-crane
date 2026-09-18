# transfer-pvc: Support Authenticated Downstream Transfer Images on External Kubernetes Clusters

## Problem

The downstream `mta-ops transfer-pvc` default image is:

```text
registry.redhat.io/mta/mta-rsync-transfer-rhel9:8.3.0
```

Unlike the upstream public `quay.io/konveyor/rsync-transfer` image, this image
requires Red Hat registry authentication and an entitlement for the MTA
repository.

This adds a prerequisite for migrations where either endpoint is an external
Kubernetes cluster, for example Minikube, EKS, GKE, or AKS. Such clusters do not
normally inherit an OpenShift global pull secret.

## Observed Behavior

During an indirect PVC transfer from Minikube to CRC, the temporary inspect and
rclone upload pods failed with:

```text
Failed to pull image "registry.redhat.io/mta/mta-rsync-transfer-rhel9:8.3.0":
unauthorized: Please login to the Red Hat Registry using your Customer Portal credentials
```

Adding a pull secret copied from the available CRC cluster did not resolve the
issue because those credentials were not entitled to the MTA repository.

The transfer succeeded only after explicitly overriding both runtime images with
the public upstream image:

```text
--source-image quay.io/konveyor/rsync-transfer:latest
--destination-image quay.io/konveyor/rsync-transfer:latest
```

This validates the transfer workflow but does not validate that the downstream
default image is usable from an external cluster.

## Expected Behavior

Users need a documented and supported path to run `transfer-pvc` with the
downstream default image when source and/or destination clusters are not
OpenShift clusters.

At minimum, the documentation should explain:

- the required `registry.redhat.io` entitlement;
- how to create a namespaced `docker-registry` pull secret;
- which ServiceAccount is used by temporary transfer pods;
- that credentials are required on both source and destination clusters;
- how to verify image access before a migration starts;
- how to diagnose `ErrImagePull` and `ImagePullBackOff`.

## Proposed Enhancements

1. Add official documentation for authenticated transfer-image pulls on
   external Kubernetes clusters.
2. Add a `transfer-pvc` option to select the ServiceAccount used by temporary
   transfer pods.
3. Add a `transfer-pvc` option to reference one or more image pull secrets
   explicitly.
4. Fail early with an actionable message when the transfer image cannot be
   pulled, instead of timing out while waiting for temporary pods to start.
5. Consider a preflight command or image-access validation before starting a
   transfer.

## Scope Notes

- The downstream image choice is intentional and is correctly reported by
  `mta-ops transfer-pvc --help`.
- This is not a request to revert the downstream default to Quay.
- Runtime image overrides are useful for diagnostics and functional tests but
  should not be the standard downstream deployment path.

## Supporting Material

- [External registry access setup](REGISTRY_REDHAT_IO_EXTERNAL_CLUSTER_SETUP.md)
- [Minikube to CRC migration finding](findings/10-mta-ops-minikube-crc.md)
- [Test report](TEST_REPORT_2026-09-18.md)
