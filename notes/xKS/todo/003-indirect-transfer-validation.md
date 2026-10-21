# 003: Findings from the successful indirect AKS to CRC transfer

## Status

Both PVC transfers and independent file-content comparisons passed on 2026-10-21. See the [run report](../wordpress-aks/migration-2026-10-21/TRANSFER_PVC_CRC_INDIRECT.md) for exact commands and scope.

## MySQL symlink metadata retry

The MySQL download logged:

```text
failed to set metadata: failed to set xattr key "user.content-type":
xattr.LSet /data/mysql.sock user.content-type: operation not permitted
```

The first rclone attempt failed; the second succeeded. Independent verification confirmed all 180 regular files and the `mysql.sock` symlink matched the source. This was a recoverable error in this run, not an established guarantee for other metadata failures.

- [ ] Investigate metadata handling for symlink objects, including rclone's `.rclonelink` representation and S3 content-type metadata.
- [ ] Verify behavior when retry cannot recover. A successful summary must not hide missing application files.
- [ ] Test required ownership, permissions, and xattrs separately from file-content checks before target application startup.

## PodSecurity warning

Target download setup reported that the rclone container would violate `restricted:latest` because `allowPrivilegeEscalation=false`, dropped capabilities, and seccomp settings were missing. The transfer still completed on this CRC profile.

- [ ] Inspect generated indirect download Pod security settings in `crane-lib` and the CLI's security-context propagation.
- [ ] Reproduce under enforced restricted Pod Security and the exact intended OpenShift SCC profile. Do not infer strict-admission compatibility from this warning-only result.

## Meaning of --verify in indirect mode

The full indirect path in the installed CLI's reviewed `cmd/transfer-pvc/indirect.go` does not consult `t.Verify`. This run passed the flag but relied on a separate SHA-256 and symlink comparison for end-to-end content evidence.

- [ ] Confirm this behavior against an exact recorded source commit for the executable.
- [ ] Define and implement explicit indirect verification semantics, or document/reject the flag when it has no effect. Preserve compatibility deliberately.

## CRC capacity reporting

Both target PVCs request 1 GiB but report 59 GiB on the default CRC hostpath provisioner.

- [ ] Confirm provisioner capacity/quota semantics before using reported capacity as evidence of allocation, isolation, or performance. Do not interpret two such claims as independently reserved 59 GiB disks.

## Target runtime verified for this CRC profile

- [x] Deploy the transformed sample after resolving OpenShift UID/write access and frontend exposure. The manual `50_CRC` stage uses non-root runtime paths and an HTTP Route.
- [x] Verify MySQL startup, WordPress sample post `#11079`, and an application read/write after migration. Admin login, a temporary draft, and a temporary PVC upload passed, and the test data was removed.

See the [CRC deployment report](../wordpress-aks/migration-2026-10-21/DEPLOYMENT_CRC.md). Both application Pods run under `restricted-v2` with container UID `1000650000`; no extra SCC grant was required. This application result does not resolve the separate indirect mover PodSecurity warning above.
