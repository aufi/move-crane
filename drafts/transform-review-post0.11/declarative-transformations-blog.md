# Declarative Kubernetes transformations with Crane instructions files

Most migration pipelines start with a simple sequence: export resources from a
source cluster, transform them, and render the manifests that will be applied to
the target cluster. The difficult part is making the transformation repeatable.
Command-line options tend to grow over time, while edits made directly under
`transform/` are generated artifacts that can be lost on the next run.

Crane's transform instructions file moves the transformation policy into one
YAML document. It can define:

- which transform stages run;
- the order in which they run;
- plugin-specific options for each stage;
- Kustomize settings and inline patches for each stage.

This article uses the same three Crane commands for every example. Only the
contents of `instructions.yaml` change. No generated file under `export/`,
`transform/`, or `output/` needs to be edited.

## One workflow, different instructions

The examples assume:

- the source kubeconfig has a context named `source`;
- the namespace to migrate is `my-app`;
- the built-in `KubernetesPlugin` is available;
- the exported application has a Deployment named `web` that uses an `nginx`
  image.

Every example runs this exact workflow:

```sh
crane export \
  --context source \
  --namespace my-app \
  --overwrite

crane transform \
  --instructions-file instructions.yaml \
  --overwrite

crane apply --overwrite
```

The commands use Crane's default `export/`, `transform/`, and `output/`
directories.

`crane export` reads the source cluster. `crane transform` creates and executes
the stages declared in `instructions.yaml`. `crane apply` runs embedded
Kustomize and writes the final manifests to `output/output.yaml` and
`output/resources/`. Despite its name, `crane apply` renders files; it does not
connect to the target cluster.

The `--overwrite` flags make the workflow repeatable. Crane regenerates the
export, transform, and output directories from the source cluster and the
instructions file on every run.

## Instructions file structure

An instructions file is a single YAML document with one top-level field,
`stages`:

```yaml
stages:
  - KubernetesPlugin
  - name: ApplicationSettings
    optionals: {}
    kustomize: {}
```

A stage can use either of two forms:

| Form | Use |
|------|-----|
| A string such as `KubernetesPlugin` | Run a stage with its default behavior. |
| A mapping with `name` | Add `optionals`, `kustomize`, or both. |

The list order is the execution order. Crane generates directory names with
10-step prefixes:

```text
transform/
|-- 10_KubernetesPlugin/
`-- 20_ApplicationSettings/
```

A name ending in `Plugin` requires a plugin with that name. A different name,
such as `ApplicationSettings`, creates a pass-through stage. A pass-through
stage does not run a plugin, but it can still apply a `kustomize` block.

## Example 1: minimal instructions

The smallest useful instructions file runs the built-in Kubernetes cleanup
plugin:

```yaml
# instructions.yaml
stages:
  - KubernetesPlugin
```

The plugin removes server-managed fields such as resource versions, UIDs,
timestamps, managed fields, and status. Crane creates one stage named
`10_KubernetesPlugin`.

Run the standard workflow without adding any stage arguments or transformation
flags:

```sh
crane export \
  --context source \
  --namespace my-app \
  --overwrite

crane transform \
  --instructions-file instructions.yaml \
  --overwrite

crane apply --overwrite
```

The result is a cleaned set of Kubernetes manifests produced entirely from the
export and the one-line stage declaration.

## Example 2: configure a plugin with optionals

The mapping form adds plugin-specific `optionals`:

```yaml
# instructions.yaml
stages:
  - name: KubernetesPlugin
    optionals:
      registry-replacement: "docker.io=quay.io/example"
      add-annotations: "migrated-by=crane"
```

This stage still performs the default Kubernetes cleanup. It also rewrites
container image registry prefixes and adds an annotation to transformed
resources.

Run the same commands:

```sh
crane export \
  --context source \
  --namespace my-app \
  --overwrite

crane transform \
  --instructions-file instructions.yaml \
  --overwrite

crane apply --overwrite
```

Optional names and values belong to the selected plugin. The built-in
`KubernetesPlugin` currently accepts these options:

| Optional | Purpose | Example value |
|----------|---------|---------------|
| `add-annotations` | Add annotations to resources. | `team=migration,source=cluster-a` |
| `remove-annotations` | Remove annotations. | `kubectl.kubernetes.io/last-applied-configuration` |
| `registry-replacement` | Replace image registry or path prefixes. | `docker.io=quay.io/example` |
| `extra-whiteouts` | Exclude additional GroupKinds. | `Event,Route.route.openshift.io` |
| `include-only` | Keep only listed GroupKinds. | `Deployment.apps,Service` |
| `disable-whiteout-owned` | Keep owned Pods and template resources. | `true` |
| `strip-default-rbac` | Remove default RBAC resources. | `true` |
| `strip-default-cabundle` | Remove default CA bundle resources. | `true` |
| `pvc-rename-map` | Rename PVCs. | `old-data:new-data` |
| `pvc-storage-class-map` | Replace PVC and template storage classes. | `standard:fast` |
| `whiteout-pvc` | Exclude PVCs without owner references. | `true` |
| `downscale-workloads` | Scale PVC-consuming workloads to zero. | `true` |

Option values are strings. Quote boolean-looking values such as `"true"` to
make that explicit. Installed plugins may expose different options. Run
`crane transform optionals` to inspect the options available in the current
installation.

## Example 3: stages, optionals, and Kustomize in one file

The full form combines plugin behavior with Kustomize configuration and an
additional pass-through stage:

```yaml
# instructions.yaml
stages:
  - name: KubernetesPlugin
    optionals:
      registry-replacement: "docker.io=quay.io"
    kustomize:
      namespace: destination
      labels:
        - pairs:
            migration.konveyor.io/managed-by: crane
      images:
        - name: nginx
          newName: quay.io/example/nginx
          newTag: "1.27"
  - name: ApplicationSettings
    kustomize:
      patches:
        - target:
            group: apps
            version: v1
            kind: Deployment
            name: web
          patch: |-
            - op: replace
              path: /spec/replicas
              value: 3
```

The first stage performs plugin cleanup and registry replacement, then applies
Kustomize namespace, label, and image transformations. The second stage receives
the materialized output of the first stage and changes the replica count with
an inline JSON patch. No patch file needs to be created.

Run the same workflow again:

```sh
crane export \
  --context source \
  --namespace my-app \
  --overwrite

crane transform \
  --instructions-file instructions.yaml \
  --overwrite

crane apply --overwrite
```

The commands did not change between the minimal and full examples. The
instructions file alone changed the stage graph and transformation policy.

## What can go in `kustomize`

The `kustomize` value is an inline Kustomization fragment. It can contain normal
Kustomize fields such as:

- `namespace`;
- `namePrefix` and `nameSuffix`;
- `labels` and `commonAnnotations`;
- `images`;
- `patches` with inline patch content;
- `resources`, including remote Kustomize bases.

Crane merges the fragment into the generated `kustomization.yaml` for that
stage:

| Field | Merge behavior |
|-------|----------------|
| `resources` | Append fragment entries and remove duplicate string values. |
| `patches` | Append fragment entries after Crane-generated patches. |
| `apiVersion`, `kind` | Keep Crane-generated values. Fragment values are ignored. |
| Any other field | Use the fragment value. |

For a self-contained instructions-only workflow, prefer inline patches and
fields whose values are present directly in the YAML. A local `resources` or
`patches.path` entry introduces another input file. Crane permits such a path
only when it resolves outside the generated stage directory, because
`--overwrite` replaces the stage directory. Remote resources are also external
dependencies and should be pinned to an immutable revision.

## Validation and command boundaries

Crane validates the instructions file before running the pipeline:

- `stages` must contain at least one item;
- stage names must be unique;
- names may contain letters, digits, underscores, and hyphens;
- a stage mapping supports only `name`, `optionals`, and `kustomize`;
- the file must contain one YAML document;
- `resources` and `patches` must be lists;
- local resource and patch paths must resolve outside the generated stage.

When `--instructions-file` is used, do not add positional stage arguments,
`--stage-optionals`, or `--stage-kustomize`. Those inputs would create a second
source of transformation policy, so Crane rejects the combination.

## Why this is declarative

The instructions file describes the desired transformation pipeline rather
than a sequence of edits to generated files. Given the same exported resources,
plugin versions, remote dependencies, and instructions file, Crane can rebuild
the same stage structure and final manifests.

That makes the transformation policy suitable for code review and version
control. A change from one example to another is a YAML diff in
`instructions.yaml`, while the operational workflow remains:

```text
export -> transform --instructions-file -> apply
```

The generated directories remain inspectable artifacts, but they are no longer
the place where the migration policy has to live.
