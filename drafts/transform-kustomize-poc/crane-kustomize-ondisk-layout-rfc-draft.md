# RFC Draft: On-Disk Layout Contract for `crane transform` Kustomize Output

## Status

Draft

## Purpose

Define the exact filesystem contract produced by `crane transform` and consumed by `crane apply` in the new Kustomize-only workflow.

---

## Scope

This RFC specifies:

- directory and file layout under `--transform-dir`
- naming rules for patch files
- `kustomization.yaml` structure
- whiteout and ignored-patch reporting files

This RFC does **not** redefine plugin patch semantics.

---

## Normative Layout

Given:
- `--export-dir=<EXPORT_DIR>`
- `--transform-dir=<TRANSFORM_DIR>`

`crane transform` MUST produce:

```text
<TRANSFORM_DIR>/
  kustomization.yaml
  patches/
    <patch-file>.patch.yaml
    ...
  reports/
    ignored-patches.json        # optional (present when non-empty)
  whiteouts/
    whiteouts.json              # optional (present when non-empty)
```

No `transform-*` JSONPatch files are generated.

---

## `kustomization.yaml` contract

`kustomization.yaml` MUST include:

- `resources`: list of relative paths to exported resource files that are not whiteouted
- `patches`: list of patch references with explicit `target`

Example:

```yaml
resources:
  - ../export/ns1/apps_v1_deployment_myapp.yaml
  - ../export/ns1/v1_service_myapp.yaml

patches:
  - path: patches/ns1--apps-v1--Deployment--myapp.patch.yaml
    target:
      group: apps
      version: v1
      kind: Deployment
      name: myapp
      namespace: ns1
```

For core-group resources, `group` SHOULD be omitted or set consistently according to implementation policy (must be documented and tested).

---

## Patch file content contract

Each patch file MUST contain a JSON6902 op array serialized as YAML.

Example:

```yaml
- op: remove
  path: /spec/clusterIP
- op: replace
  path: /spec/type
  value: NodePort
```

The operation sequence MUST preserve post-sanitization order from runner output.

---

## Patch target derivation

Patch target fields are derived from original resource identity:

- `group` from `apiVersion` prefix (empty for core)
- `version` from `apiVersion`
- `kind` from object kind
- `name` from metadata.name
- `namespace` from metadata.namespace (if set)

If name or kind is missing, transform MUST fail with validation error.

---

## Patch file naming

Patch file names MUST be deterministic and collision-safe.

Recommended canonical pattern:

```text
<namespace-or-_cluster>--<group-or-core>-<version>--<kind>--<name>.patch.yaml
```

Examples:

- `ns1--apps-v1--Deployment--myapp.patch.yaml`
- `_cluster--core-v1--Namespace--myns.patch.yaml`

Sanitization rules:
- non filename-safe chars converted to `-`
- repeated separators collapsed
- max length handling must be deterministic (e.g., suffix hash)

---

## Whiteout contract

Whiteouted resources MUST be excluded from `resources`.

If at least one whiteout exists, create:

`whiteouts/whiteouts.json`

Example:

```json
[
  {
    "apiVersion": "route.openshift.io/v1",
    "kind": "Route",
    "name": "frontend",
    "namespace": "ns1",
    "requestedBy": ["OpenShiftPlugin"]
  }
]
```

`requestedBy` is recommended when available.

---

## Ignored patches report contract

If conflict resolution discards any patch operation, create:

`reports/ignored-patches.json`

Example:

```json
[
  {
    "resource": {
      "apiVersion": "apps/v1",
      "kind": "Deployment",
      "name": "myapp",
      "namespace": "ns1"
    },
    "path": "/spec/template/spec/containers/0/image",
    "selectedPlugin": "OpenShiftPlugin",
    "ignoredPlugin": "ImageStreamPlugin",
    "reason": "path-conflict-priority"
  }
]
```

---

## `crane apply` input contract

`crane apply` MUST require `<TRANSFORM_DIR>/kustomization.yaml`.

It MUST execute:

```bash
kubectl kustomize <TRANSFORM_DIR>
```

and return rendered manifests (stdout or output file, per CLI behavior).

---

## Validation Rules

`crane transform` MUST fail when:

- target identity cannot be derived (`apiVersion`/`kind`/`name` missing)
- patch serialization fails
- `kustomization.yaml` cannot be written

`crane apply` MUST fail when:

- `kubectl` is missing
- `kustomization.yaml` missing
- `kubectl kustomize` exits non-zero

---

## Determinism Requirements

For reproducible Git diffs, transform output MUST be stable:

- stable sort for `resources`
- stable sort for `patches`
- stable sort for report entries
- deterministic patch file naming

---

## Backward Compatibility

This RFC defines Kustomize-only behavior.

- Legacy `transform-*` JSONPatch file contract is removed.
- Existing plugins remain compatible if they output standard JSONPatch ops.

---

## Open Questions

1. Should `resources` reference export files directly or copies/symlinks under transform root?
2. Should we enforce one patch file per resource or allow multiple grouped by plugin?
3. Do we need a formal schema file for reports (`ignored-patches.json`, `whiteouts.json`)?
4. Should `crane apply` support `kubectl kustomize --enable-helm` style passthrough flags?

---

## Acceptance Criteria

- [ ] Generated directory tree matches this RFC.
- [ ] `kubectl kustomize <transform-dir>` succeeds on generated outputs in CI fixtures.
- [ ] Whiteouts and ignored patches are represented in machine-readable reports.
- [ ] Output is deterministic across repeated runs with identical input.
