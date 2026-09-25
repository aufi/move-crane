# Kustomize security considerations

Crane uses the Kustomize Go API to materialize transform stages and render final
manifests. This avoids a dependency on `kubectl kustomize`, but it does not make
a Kustomize build a sandboxed operation.

A Kustomization can read files, fetch remote content, invoke Helm, and load
locally installed Kustomize plugins. Treat an instructions file, a
`--stage-kustomize` value, and every `kustomization.yaml` under `transform/` as
code that runs with the filesystem, network, environment, and user permissions
of the Crane process.

This document describes Crane's current behavior. It is not a general
Kustomize security guide.

## Where Kustomize runs

Kustomize can run during both `crane transform` and `crane apply`:

1. `crane transform` writes each stage and runs Kustomize to materialize the
   stage output for the next stage.
2. `crane apply` runs Kustomize on the final selected stage and writes the
   rendered manifests under `output/`.

The final stage can therefore be built twice in a normal workflow. Remote
content may be downloaded twice, Helm may run twice, and Kustomize plugins may
run twice. A mutable remote dependency can produce different results between
the transform and apply commands.

`crane apply` does not submit resources to a Kubernetes API server. It writes
manifest files. A later command such as `kubectl apply` creates the cluster-side
security boundary.

## Responsibilities of crane and crane-lib

The two repositories have different roles:

- `crane-lib/transform/kustomize` serializes Crane transform results. It creates
  a `kustomization.yaml` with `apiVersion`, `kind`, sorted `resources`, and
  sorted `patches` with target selectors. It does not execute Kustomize.
- `crane/internal/kustomize` configures and executes the embedded Kustomize API
  against the real host filesystem.
- `crane/internal/transform` merges user-provided Kustomize fragments into the
  generated file and runs a build after each stage.
- `crane/internal/apply` runs a build for the selected final stage and writes
  the result.

Crane transform plugins are separate from Kustomize plugins. A binary Crane
plugin processes Kubernetes resources before Kustomize runs. A Kustomize plugin
is loaded by Kustomize through fields such as `generators` or `transformers`.
Both types of plugin execute code and require an explicit trust decision.

## Effective embedded Kustomize options

Crane starts with `krusty.MakeDefaultOptions()` and changes these values:

| Option | Effective value | Consequence |
|--------|-----------------|-------------|
| Resource ordering | `legacy` | Output uses Kustomize's legacy fixed ordering rather than input order. |
| Managed-by label | disabled | Crane does not ask Kustomize to add its managed-by label. |
| Load restrictions | `LoadRestrictionsNone` | Kustomizations may load absolute paths and paths outside their root directory. |
| Plugin restrictions | `PluginRestrictionsNone` | Non-builtin exec and Go plugins may be loaded from the local Kustomize plugin home. |
| Builtin plugins | statically linked | Builtin generators and transformers run inside the Crane process. |
| Function exec | disabled by default | KRM functions that request a host executable are rejected. |
| Function containers | enabled by default | A KRM function may start a container through the available container runtime. |
| Function container network | disabled by default | The function container receives no network access, although the runtime may still pull its image. |
| Helm | disabled by default | A permitted CLI argument can enable it and select the Helm executable. |

The two `None` values are more permissive than Kustomize's defaults.
`MakeDefaultOptions()` normally uses root-only file loading and builtin-only
plugins. Crane overrides both settings for every embedded build. Users cannot
restore the root-only loader with `--kustomize-args` because Crane does not
allow the `--load-restrictor` argument.

## User-controlled inputs

Kustomize behavior can be influenced through several surfaces.

### Generated stage content

Crane and crane-lib generate:

- resource files under a stage's `input/` and `new/` directories;
- JSON or strategic patches under `patches/`;
- `resources` and `patches` entries in `kustomization.yaml`;
- patch target selectors derived from resource group, version, kind, name, and
  namespace.

Exported Kubernetes resources are data, but they can still affect the rendered
result. Review unexpected API kinds, container images, RBAC, admission
configuration, and privileged workload settings before deployment.

### Instructions files and `--stage-kustomize`

An instructions stage may contain a generic `kustomize` mapping. The same
mapping can be supplied as YAML or JSON with `--stage-kustomize`.

Crane applies only these merge rules:

| Field | Crane behavior |
|-------|----------------|
| `resources` | Append to generated resources and remove duplicate string values. |
| `patches` | Append to generated patches. |
| `apiVersion`, `kind` | Ignore the user value and retain Crane's value. |
| Every other field | Replace or add the top-level field without a Crane allowlist. |

Kustomize performs schema validation later. As a result, the fragment can use
more than namespace, labels, images, and inline patches. It can also request
components, generators, transformers, validators, CRDs, OpenAPI configuration,
Helm charts, remote bases, and other fields supported by the embedded Kustomize
version.

### Existing transform directories

`crane apply` trusts the `kustomization.yaml` already present in the selected
stage. The fragment path validation used while generating a stage does not run
when an existing transform directory is applied. A downloaded transform
directory or one modified by another process must therefore be reviewed as
executable build input.

### `--kustomize-args`

Both `crane transform` and `crane apply` accept `--kustomize-args`. The argument
is parsed by Crane, not by a shell. The current allowlist is:

| Argument | Behavior |
|----------|----------|
| `--enable-helm` | Enables the builtin Helm chart inflator. |
| `--helm-command NAME_OR_PATH` | Enables Helm and selects the executable invoked by Kustomize. The `--helm-command=...` form is also supported. |
| `--env KEY=VALUE` | Sets a process environment variable for the complete Kustomize build. |
| `-e KEY=VALUE` | Short form of `--env`. |

Crane rejects other flags and rejects `;`, `|`, `&`, backticks, and `$` anywhere
in the argument string. This reduces shell-injection mistakes, but it is not a
sandbox:

- Kustomize invokes the Helm command directly with `exec.Command`.
- The Helm command may be any executable name or path allowed by the operating
  system.
- Environment values affect Kustomize and subprocesses started during the
  build.
- Variables such as `PATH`, `HOME`, `XDG_CONFIG_HOME`,
  `KUSTOMIZE_PLUGIN_HOME`, Git variables, proxy variables, and credential
  variables can change executable lookup, plugin lookup, network behavior, and
  credential use.

Use the space-separated `--env KEY=VALUE` form. Although the argument parser
accepts `--env=KEY=VALUE`, the embedded runner currently handles only the
space-separated form.

Kustomize arguments are not stored in the generated stage. A Helm-based stage
must receive the required arguments during every command that builds it. In a
typical workflow that means both `crane transform` and `crane apply`.

## Filesystem access

Crane calls Kustomize with the real on-disk filesystem and
`LoadRestrictionsNone`. There is no chroot, container boundary, or root-only
loader restriction.

A Kustomization can load files outside its stage through fields including:

- `resources`, `components`, `crds`, and deprecated `bases`;
- `patches.path`, deprecated patch fields, and transformer configurations;
- `configMapGenerator.files` and `configMapGenerator.envs`;
- `secretGenerator.files` and `secretGenerator.envs`;
- `generators`, `transformers`, and `validators`;
- Helm chart homes, values files, and additional values files;
- other file-bearing fields supported by the embedded Kustomize version.

This has two security effects:

1. A build can disclose readable host files by placing their content in a
   generated ConfigMap, Secret, or rendered resource.
2. A build can consume configuration and credentials that were not intended to
   be migration inputs.

The transform fragment validator checks only local entries in `resources` and
`patches.path`. It rejects paths that resolve lexically inside the generated
stage because `--overwrite` removes that directory. Paths outside the stage are
allowed. This is a data-preservation check, not a security boundary.

The check does not cover other file-bearing Kustomize fields, does not confine
paths to the migration workspace, and does not resolve symlinks. URL-like and
Git-style references are delegated to Kustomize. Direct edits to an existing
`kustomization.yaml` also bypass the fragment check.

Run Crane in a dedicated working directory and under an account that cannot
read unrelated secrets. For stronger isolation, run it in a container or CI job
with a minimal read-only filesystem and mount only the migration inputs that the
build needs.

## Network and remote content

Kustomize can fetch remote resources, components, and Git repositories. With
Helm enabled, it can also download charts from a user-specified repository.
Crane does not apply a host allowlist, protocol allowlist, checksum policy, or
network sandbox to these requests.

Risks include:

- server-side request forgery against services reachable from the Crane host;
- use of Git, proxy, SSH, cloud, or registry credentials inherited from the
  environment;
- mutable branches, tags, charts, and URLs changing between runs;
- dependency substitution if a repository or registry is compromised;
- unexpectedly large downloads or long-running network operations;
- different content being fetched when transform and apply rebuild a stage.

Pin remote Git references to immutable commit IDs. Pin Helm chart versions and
verify the repository separately. In higher-risk environments, deny network
access during the build and mirror approved dependencies into a controlled,
read-only workspace.

## Helm execution

Helm support requires an installed executable and a `helmCharts` or equivalent
Kustomize field. `--helm-command` both enables Helm and selects the executable.
`--enable-helm` alone enables the feature but does not supply a command, so a
Helm chart build still needs `--helm-command` in the current Crane runner.

Kustomize invokes Helm as a subprocess and passes it the inherited process
environment plus Helm config, cache, and data directories. Depending on the
Kustomization, Helm may read local charts and values files or fetch a chart from
a remote repository.

Security guidance:

- use an absolute path to a trusted, version-pinned Helm binary;
- do not set `--helm-command` from an untrusted configuration source;
- review chart templates and values as executable build input;
- avoid passing secrets through `--env` or Helm values when they can appear in
  rendered output or error messages;
- pass identical Helm settings to transform and apply.

Helm chart hooks are rendered according to Helm/Kustomize behavior; Crane does
not install a release or execute hooks against a cluster. Rendered hook objects
can still be deployed later if the output is submitted to a cluster.

## Kustomize plugins

Crane sets `PluginRestrictionsNone` even though `--enable-alpha-plugins` is not
accepted by `--kustomize-args`. If a Kustomization references a non-builtin
generator or transformer, Kustomize searches its plugin home and may load an
executable or Go plugin.

Plugin home lookup can use:

- `KUSTOMIZE_PLUGIN_HOME`;
- `XDG_CONFIG_HOME/kustomize/plugin`;
- the default config directory under the current user's home;
- `kustomize/plugin` under the current user's home.

An exec plugin runs with the same user, environment, filesystem access, and
network access as Crane. A Go plugin is loaded into the Crane process. Both are
arbitrary code execution, not data-only transformation.

KRM function-style plugins are a separate path. Host exec functions are
disabled by the current default function options, but container functions are
not disabled. If a compatible container runtime is available, a referenced
function image may be pulled and executed. Its network is disabled by default,
and requested storage mounts must stay under the current Kustomization
directory, but the function still processes migration resources and executes
code from an image selected by the Kustomization.

Do not run an untrusted Kustomization on a host that has a populated Kustomize
plugin directory. Clear `KUSTOMIZE_PLUGIN_HOME`, use an isolated `HOME` and
`XDG_CONFIG_HOME`, and remove unneeded plugins from the execution environment.
Setting these variables with `--env` is itself trusted code configuration, not a
safe way to accept untrusted input. Do not expose a host container runtime to an
untrusted build.

## Generated secrets and output files

Kustomize `secretGenerator` can read literals, files, and env files and emit a
Kubernetes Secret. Kubernetes Secret values are base64-encoded, not encrypted.
The same applies to Secrets exported from the source cluster.

Crane writes transform and output manifests to disk. These directories may be
copied, archived, uploaded as CI artifacts, or committed to Git. Treat them as
sensitive even when the final target cluster has not been contacted.

Review CI artifact collection, workspace retention, backup software, and Git
ignore rules. Do not assume that a successful render is safe to publish.

## Rendered Kubernetes resources are not policy-checked

Kustomize can produce any Kubernetes object represented in YAML. Crane does not
act as an admission controller or policy engine. A fragment, remote base, chart,
or plugin can introduce:

- cluster-wide RBAC and impersonation permissions;
- privileged Pods, host mounts, host networking, or dangerous capabilities;
- admission webhooks and API services;
- CRDs and operator resources;
- workloads with untrusted images;
- namespace changes and cross-resource reference changes.

`crane apply --skip-cluster-scoped` filters objects without a namespace after
rendering. It does not make namespaced workloads safe, validate RBAC intent, or
replace target-cluster admission policy.

Validate the rendered output with the target cluster, a policy engine, and a
human review before deployment.

## Recommended trust model

Use these rules when deciding whether a Crane transform is safe to run:

1. Treat instructions files, stage Kustomizations, remote bases, Helm charts,
   values files, and Kustomize plugins as executable build inputs.
2. Run untrusted migrations in an ephemeral container or VM with no host
   credentials and no access to unrelated files.
3. Mount only the export directory, instructions file, approved shared inputs,
   and output locations.
4. Use a dedicated `HOME`, empty Kustomize plugin home, minimal `PATH`, and
   scrubbed environment.
5. Disable network access unless the build requires reviewed and pinned remote
   dependencies.
6. Use immutable Git commits, chart versions, container digests, and tool
   versions.
7. Avoid `--enable-helm`, `--helm-command`, and `--env` unless the workflow
   explicitly needs them.
8. Review all rendered manifests, including generated Secrets and resources
   introduced by remote dependencies.
9. Apply target-cluster policy and admission controls independently of Crane.

## Current argument summary

The following examples summarize accepted and rejected CLI configuration:

```sh
# No extra Kustomize capability.
crane transform --instructions-file instructions.yaml

# Enable Helm using a trusted executable.
crane transform \
  --instructions-file instructions.yaml \
  --kustomize-args '--helm-command /usr/local/bin/helm'

# Set an environment variable for the complete embedded build.
crane apply --kustomize-args '--env HTTPS_PROXY=http://proxy.example.test:8080'
```

Crane rejects arguments such as `--load-restrictor` and
`--enable-alpha-plugins`, but the embedded runner already hardcodes permissive
load and plugin restrictions. The CLI allowlist should not be interpreted as a
complete statement of the Kustomize runtime's authority.

## Version and implementation references

Kustomize fields, plugin behavior, Helm integration, and remote loading can
change between embedded Kustomize versions. Use `crane version` to record the
Crane, crane-lib, and Kustomize versions used for a migration.

The behavior described here is implemented in:

- `internal/kustomize/runner.go` for embedded options, environment changes, and
  Kustomize execution;
- `internal/kustomize/args.go` for the `--kustomize-args` allowlist;
- `internal/kustomize/merge.go` for fragment merge and path checks;
- `internal/transform/writer.go` and `internal/transform/orchestrator.go` for
  stage generation and materialization;
- `internal/apply/kustomize.go` for final rendering;
- `crane-lib/transform/kustomize/kustomization.go` for generated resources and
  patch entries.

## Related documentation

- [Declarative transformations with an instructions file](./kustomize-fragments.md)
- [`crane transform`](./commands/transform.md)
- [`crane apply`](./commands/apply.md)
- [Multi-stage Kustomize transform pipeline](./multistage-pipeline.md)
