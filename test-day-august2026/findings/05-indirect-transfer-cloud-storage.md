# Finding 05 — Indirect PVC transfer via S3 cloud storage

**Scope:** crane `transfer-pvc` indirect mode. Same stateful WordPress migration
as the direct run, but the PV data moves through an S3 bucket instead of a direct
rsync-over-route tunnel between the clusters.

## How it works

Instead of opening a route on the destination and rsyncing directly
(source → target), indirect transfer uses S3 as an intermediary:

```
source cluster  --upload-->  S3 bucket  --download-->  target cluster
```

crane creates temporary Secrets on both clusters from a local `rclone.conf`, runs
an rclone-based copy on the source (upload) and on the target (download), then
cleans up the cloud data.

## Command

Driven by `scripts/11-transfer-pvc-indirect.sh` (a variant of `07`), per PVC:

```bash
crane transfer-pvc \
  --source-context src --destination-context tgt \
  --pvc-name <pvc>:<pvc> --pvc-namespace wordpress:wordpress \
  --cloud-storage remote:<bucket>/wordpress-<pvc> \
  --rclone-config-file ./rclone.conf \
  --dest-storage-class gp3-csi --dest-storage-requests 1Gi \
  --verify
```

Note: **no `--endpoint`** flag — indirect transfer does not use a route/tunnel.

## Setup used

- `rclone.conf` with an `[remote]` S3 profile (AWS, us-east-1) saved locally
  (chmod 600).
- A dedicated bucket created up front with `rclone mkdir remote:<bucket>`
  (`crane-testday-v011-dd133e12` for this run). Each PVC used its own key prefix
  `<bucket>/wordpress-<pvc>` to keep the two transfers isolated.
- Still uses the merged kubeconfig (contexts `src`/`tgt`) — both contexts are
  required exactly as in the direct transfer.

## Result

End-to-end migration succeeded; target serves the source's sample post
`#11428` → data migrated intact (MySQL DB + WordPress files).

After the run the bucket was **empty**: crane cleaned up the cloud data
automatically (no `--keep-cloud-data`). Use `--keep-cloud-data` to retain it, and
`--encrypt` for client-side encryption of the staged data.

Transcript: `runs/migration-indirect-<ts>.log` (raw) and `.clean.log`. The raw
log is large — rclone logs every file copy with progress.

## Client-side encryption (`--encrypt`)

The same indirect run was repeated with `--encrypt` added (crane encrypts the
staged data client-side before uploading, decrypts on download):

```bash
TRANSFER_SCRIPT=11-transfer-pvc-indirect.sh CLOUD_BUCKET=<bucket> ENCRYPT=true \
  scripts/10-run-full-migration.sh
```

Result: **succeeded** — target serves the exact seed `#11428`, data intact,
both pods Running. One nuance worth noting:

- **xattr error on the MySQL socket, self-healed by retry.** With `--encrypt`
  rclone also copies file metadata (xattrs), and fails on the stale MySQL unix
  socket left in the volume (mysql was scaled to 0):

  ```
  ERROR : mysql.sock.rclonelink: Failed to copy: failed to set metadata:
          failed to set xattr key "user.content-type":
          xattr.LSet /data/mysql.sock user.content-type: operation not permitted
  ...
  ERROR : Attempt 1/3 failed with 1 errors ...
  ERROR : Attempt 2/3 succeeded
  ```

  rclone's built-in retry (up to 3 attempts) recovered on the second try, the
  upload completed, and the migration finished cleanly. The error is **non-fatal
  and self-healing** here; it only surfaces with `--encrypt` (the metadata copy),
  and only on special files (a Unix socket) — regular DB/app files are unaffected.
  A truly live socket would not be present anyway, since the source is scaled to 0
  for a consistent copy.

Transcript: `runs/migration-indirect-encrypt-<ts>.log` (raw) / `.clean.log`.

## Considerations

- **Credentials handling.** `rclone.conf` holds long-lived AWS keys in plaintext.
  Keep it out of version control and rotate the keys after the test. crane copies
  it into temporary Secrets on both clusters for the duration of the transfer.
- **Indirect is slower** than direct here (two hops: upload then download) and its
  output is very verbose (per-file rclone progress).
- **Bucket lifecycle.** crane cleaned the data prefix but left the (empty) bucket;
  delete it manually if it was created only for the test.
