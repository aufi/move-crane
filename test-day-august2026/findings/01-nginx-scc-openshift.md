# Finding 01 — WordPress nginx sidecar crashes on OpenShift (restricted SCC)

**Scope:** test application, not crane itself. Blocks getting the app healthy on
the source cluster before migration.

## Symptom

The `wordpress` deployment pod is `1/2` in `CrashLoopBackOff`. The `wordpress`
(php-fpm) and `wordpress-mysql` containers run fine; the `nginx` sidecar crashes:

```
[emerg] mkdir() "/var/cache/nginx/client_temp" failed (13: Permission denied)
nginx: [emerg] mkdir() "/var/cache/nginx/client_temp" failed (13: Permission denied)
```

## Root cause

The test app (from `aufi/kubectl-migrate/sample-resources/wordpress`) was written
for minikube/kind, where containers run as root. It uses the stock `nginx:alpine`
image, which at startup writes to `/var/cache/nginx` and `/run`.

OpenShift's default `restricted-v2` SCC runs pods under an **arbitrary non-root
UID**. That UID cannot write to `/var/cache/nginx` (owned by root, not
group-writable), so nginx aborts.

- Deployment: `wordpress` (namespace `wordpress`)
- Service account: `default` (none set explicitly)
- Containers: `wordpress=wordpress:6-fpm-alpine`, `nginx=nginx:alpine`

## Remediation options

Two viable options. They differ in what we change and in migration fidelity.

---

### Option 1 — Grant `anyuid` SCC (change the cluster, keep the app as-is)

Allow the pods' service account to run as root, matching the minikube/kind
behavior the app was written for.

```bash
# Source cluster (repeat on target after migration)
oc adm policy add-scc-to-user anyuid -z default -n wordpress
oc rollout restart deployment/wordpress -n wordpress
```

**Pros**
- App manifests stay **byte-for-byte upstream** → crane migrates the *real*,
  unmodified application. Highest test fidelity.
- One command, immediately reversible
  (`oc adm policy remove-scc-from-user anyuid -z default -n wordpress`).

**Cons**
- Cluster-level privilege change; the workaround lives **outside** the migrated
  manifests, so it must be **re-applied on the target cluster** — and it is not
  something crane carries across. Easy to forget during the migration test.
- Running as root is not representative of a hardened production posture.

**Migration impact:** files on the PVCs are written as UID 0. The target
namespace needs the same `anyuid` grant before the migrated app will start.

---

### Option 2 — Make the manifest OpenShift-compatible (change the app, keep the cluster default)

Let nginx run under an arbitrary UID by giving it writable scratch space and a
non-privileged config. Edit `test-app/wordpress/wordpress-deployment.yaml`.

Minimal change — add emptyDir volumes for the paths nginx writes to:

```yaml
# in the nginx container:
        volumeMounts:
        - name: nginx-cache
          mountPath: /var/cache/nginx
        - name: nginx-run
          mountPath: /run
        # (existing wordpress-persistent-storage + nginx-config mounts stay)
# in the pod volumes:
      - name: nginx-cache
        emptyDir: {}
      - name: nginx-run
        emptyDir: {}
```

Alternative to the emptyDir approach: switch the image to
`nginxinc/nginx-unprivileged:alpine` (listens on 8080, writes to writable paths
by default) and update the container port + nginx config `listen` directive
accordingly.

**Pros**
- The fix travels **with the manifests**, so the migrated app is portable and
  starts on the target without any extra cluster configuration.
- No elevated cluster privileges; works under the default `restricted-v2` SCC —
  representative of a real hardened deployment.

**Cons**
- We are testing a **modified** version of the sample app, not the upstream one.
- Slightly larger manifest change (emptyDir mounts, or image + port + config
  changes for the unprivileged image).

**Migration impact:** none beyond the manifest edit — the change is part of the
resources crane exports/transforms/applies.

---

## Applied (Option 2)

Chosen for this test day. Changes made to the local manifests:

- `nginx-config.yaml`: `listen 80;` → `listen 8080;`
- `wordpress-deployment.yaml` Service: added `targetPort: 8080` (service port
  stays 80).
- `wordpress-deployment.yaml` nginx container: `containerPort` 80 → 8080; added
  `emptyDir` volumes mounted at `/var/cache/nginx` and `/run`.

Note the port change from 80 → 8080: `restricted-v2` lists `NET_BIND_SERVICE` in
`allowedCapabilities` but does **not** add it by default (`defaultAddCapabilities`
is null, `requiredDropCapabilities` is `ALL`), so a non-root nginx cannot bind
port 80 without an extra `securityContext.capabilities.add`. Using 8080 avoids
depending on that capability and is fully portable.

Result: `wordpress` pod reaches `2/2 Running` under the default SCC and passes
`validate.sh` (HTTP 200, sample post seed id matches).

## Recommendation

For a crane migration test where we want the workload itself to migrate cleanly
onto a default-configured target, **Option 2** keeps the fix inside the manifests
and avoids a separate manual step on the target. **Option 1** is preferable when
the goal is to migrate the *unmodified* upstream app and we accept re-granting the
SCC on the target as part of the runbook.
