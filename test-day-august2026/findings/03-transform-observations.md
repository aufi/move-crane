# Finding 03 — Transform/apply observations (Jobs suspended, OpenShift-managed objects)

**Scope:** crane transform/apply behavior observed during the WordPress
migration. Not blockers — all outcomes were correct — but worth noting.

## 3a. Jobs are suspended in the output (good)

The `KubernetesPlugin` patches the `wordpress-install` Job with:

```yaml
- op: add
  path: /spec/suspend
  value: true
```

and strips the immutable/runtime fields (`spec.selector`,
`batch.kubernetes.io/controller-uid` labels, `status`, `uid`, etc.).

**Effect:** on the target the Job is created `Suspended` (0/1) and never runs.
This is the desired behavior for a migration — the install/seed Job must not
re-execute against the already-migrated database and mutate it.

**Consequence for validation:** because the Job never runs on the target, its
logs are absent, so the seed id cannot be re-extracted there. The exact-instance
check must **carry the seed id from the source** across the migration. Verified
manually: `WORDPRESS_SEED_ID=11428` is present in the target homepage, confirming
the data (MySQL rows + WordPress files) migrated intact.

## 3b. OpenShift-managed objects are included in the output

`crane export`/`transform` keep some namespace objects that OpenShift creates
automatically in every project:

- ServiceAccounts `builder`, `deployer`
- RoleBindings `system:deployers`, `system:image-builders`, `system:image-pullers`
- ConfigMap `openshift-service-ca.crt`

(The `default` SA and the `*-dockercfg` / `kube-root-ca.crt` objects *are*
whiteouted.)

On apply to the target these already exist (the target project recreates them),
so `oc apply` emits:

```
Warning: resource serviceaccounts/builder is missing the
kubectl.kubernetes.io/last-applied-configuration annotation ...
```

**Effect:** harmless — the objects are patched/reconciled. But they add noise and
are not part of the application. For a cleaner migration one could exclude them
at export time, e.g.:

```
crane export ... \
  --exclude-gk ServiceAccount \
  --exclude-gk rbac.authorization.k8s.io/RoleBinding \
  --exclude-gk authorization.openshift.io/RoleBinding
```

(…then re-add only the app-specific SAs/RoleBindings if any — this app has none.)
Left as-is for this test day since it did not affect the result.

## Result

End-to-end stateful migration succeeded:

| Check | Source | Target |
| :-- | :-- | :-- |
| HTTP 200 | ✓ | ✓ |
| "Hello from k8s" | ✓ | ✓ |
| Sample post present | ✓ | ✓ |
| Exact seed `#11428` | ✓ | ✓ (migrated) |
