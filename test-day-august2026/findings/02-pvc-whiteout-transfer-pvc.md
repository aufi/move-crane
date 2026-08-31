# Finding 02 — PVCs are whiteouted by transform; state moves via `transfer-pvc`

**Scope:** crane behavior / stateful migration workflow. Not a bug — documenting
the intended design and its consequences for ordering.

## Observation

`crane export` captured both PVCs (`mysql-pv-claim`, `wordpress-pv-claim`), but
after `crane transform` they are **excluded from the active resource list** and
therefore **absent from `output/output.yaml`**.

The generated `transform/10_KubernetesPlugin/kustomization.yaml` lists them under:

```
# Whiteout resources are written to resources/ for complete snapshot
# but excluded from active resources list above:
# - input/PersistentVolumeClaim__v1_wordpress_mysql-pv-claim.yaml
# - input/PersistentVolumeClaim__v1_wordpress_wordpress-pv-claim.yaml
```

Other whiteouted resources: Pods, ReplicaSets, Endpoints/EndpointSlices,
`*-dockercfg` Secrets, the `default` ServiceAccount, and `kube-root-ca.crt`
(all runtime/server-managed).

## Why

Persistent volume state is not migrated as a manifest — it is migrated by
`crane transfer-pvc`, which **creates the destination PVC** and copies the data
over the network (rsync). Emitting the source PVC manifest into `output.yaml`
would conflict with the PVC that `transfer-pvc` provisions on the target.

## Consequences for the migration workflow

1. **`output.yaml` alone is not deployable for a stateful app.** It contains the
   Deployments that mount `mysql-pv-claim` / `wordpress-pv-claim`, but not the
   PVCs themselves. Applying it to a fresh target namespace leaves pods `Pending`
   ("persistentvolumeclaim not found") until the PVCs exist.

2. **`transfer-pvc` needs a single kubeconfig with BOTH contexts.** It takes
   `--source-context` and `--destination-context` from the *current* kubeconfig.
   Our two separate files (`kubeconfig-src`, `kubeconfig-tgt`) must be merged
   (e.g. `KUBECONFIG=kubeconfig-src:kubeconfig-tgt oc config view --flatten`).

3. **Ordering.** Provision + populate the PVCs on the target *before* (or
   concurrently with) applying `output.yaml`, so the Deployments can bind them.
   Practically: run `transfer-pvc` for each PVC, then apply `output.yaml`.

4. **Data consistency.** The source PVCs are RWO and currently mounted by running
   pods. For a consistent copy — especially MySQL, where copying live datafiles
   can corrupt the DB — **scale down the source Deployments first**
   (`strategy: Recreate` already releases the volume on scale-to-zero), then run
   the transfer.

## Planned approach for this test day

- Merge kubeconfigs into one file with `src` + `tgt` contexts.
- Create the target namespace and apply the SCC/app prerequisites.
- Scale down the source app (mysql + wordpress) to release the RWO volumes.
- `crane transfer-pvc` for `mysql-pv-claim` and `wordpress-pv-claim`
  (`--endpoint route`, matching `--dest-storage-class gp3-csi`).
- Apply `output/output.yaml` to the target.
- Validate on the target (sample post seed id must match the source: `11428`).
