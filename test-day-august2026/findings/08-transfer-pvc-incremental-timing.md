# Finding 08 — transfer-pvc re-run is incremental (timing)

**Scope:** confirm that `crane transfer-pvc` can be run repeatedly against the same
destination and that a second run only moves the delta, so it is faster. Measured
for both transfer paths — **direct** (rsync over route) and **indirect** (S3 cloud
storage) — via `RUNS=2` in `scripts/07` and `scripts/11`.

## Re-run is safe (idempotent destination)

`transfer-pvc` creates the destination PVC with `Create(...)` and tolerates an
existing one:

```go
// cmd/transfer-pvc/transfer-pvc.go
err = destClient.Create(context.TODO(), destPVC, &client.CreateOptions{})
if err != nil && !errors.IsAlreadyExists(err) {
    return phases.Fail(err, "unable to create destination PVC")
}
```

So a second run reuses the destination PVC and rsync copies only what changed.
Both scripts gained a `RUNS` env (default 1); `RUNS=2` repeats the transfer after
the first pass and times each run.

## Results (WordPress: mysql-pv-claim + wordpress-pv-claim, 1Gi each)

| Transfer path | Run 1 | Run 2 | Second run |
| :-- | --: | --: | :-- |
| **Direct** (rsync over route) | 83.8s | 72.9s | faster |
| **Indirect** (cloud storage, default) | 149.9s | 125.8s | faster |
| **Indirect** + `--keep-cloud-data` | 132.8s | **65.6s** | ~2× faster |

(Per-PVC crane timings for the direct run: mysql 41s→40s, wordpress 43s→33s.)

## Reading the numbers

- **Direct** — the second run is only modestly faster. Each PVC pays a large fixed
  cost every run regardless of data volume: schedule the rsync pods, create the
  route endpoint, wait for it healthy, set up the TLS tunnel, run the `--verify`
  checksum pass, then tear it all down. rsync's incremental skip only saves time
  in the copy phase, which for this small dataset is a small slice of the total.
  On large PVCs the incremental saving would dominate instead.

- **Indirect, default** — the second run is faster (the destination PVC persists,
  so the bucket→destination download is incremental), **but** crane purges the
  cloud staging after every transfer:

  ```
  [5/6] Cleaning up cloud storage ... ok
  ```

  so the source→bucket **upload** re-stages the full dataset every run — no
  incremental benefit on the upload side.

- **Indirect + `--keep-cloud-data`** — the flag skips that cleanup:

  ```
  [5/6] Cleaning up cloud storage ... skipped (--keep-cloud-data)
  ```

  The staged objects stay in the bucket, so on the second run rclone's upload is
  incremental too (it skips unchanged objects), not just the download. Here that
  roughly **halved** the second run (132.8s → 65.6s). This is the setting to use
  when you expect to re-sync the same PVC to the same bucket (e.g. a staged
  cutover: pre-seed most of the data ahead of time, then a short final delta sync
  during the maintenance window).

## Caveats

- `--keep-cloud-data` leaves PVC data sitting in the bucket after the transfer —
  clean it up (`rclone purge remote:<bucket>/<path>`) once the migration is done,
  especially without `--encrypt`.
- These are wall-clock numbers on shared, ephemeral test clusters; treat the
  ratios (run 2 vs run 1), not the absolute seconds, as the signal.
- Environment note: partway through this test the source cluster's backing EBS
  volume for an existing PVC vanished (`AttachVolume ... InvalidVolume.NotFound`),
  which hangs the rsync client pod in `ContainerCreating`. That is ephemeral-infra
  churn, not a crane bug; a fresh redeploy (new PVCs/volumes, namespace
  `wp-timing`) produced the numbers above.

## Reproduce

```bash
# direct rsync, timed, two runs
NAMESPACE=wp-timing RUNS=2 scripts/07-transfer-pvc.sh

# indirect via cloud storage, timed, two runs (default: staging purged each run)
NAMESPACE=wp-timing RUNS=2 CLOUD_BUCKET=<bucket> scripts/11-transfer-pvc-indirect.sh

# indirect, keep the staged data so the 2nd run's upload is incremental too
NAMESPACE=wp-timing RUNS=2 KEEP_CLOUD_DATA=true CLOUD_BUCKET=<bucket> \
  scripts/11-transfer-pvc-indirect.sh
```

For a clean first-run baseline, delete the destination PVCs (and, for indirect,
`rclone purge` the bucket paths) before the run — otherwise "run 1" is itself
already incremental.
