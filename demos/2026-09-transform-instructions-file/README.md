# Transform with an instructions file

This example makes the transform pipeline repeatable and suitable for Git.
`instructions.yaml` defines the stage order for a sample WordPress migration
and a final manual stage for reviewed edits. The source application contains MySQL,
two PVCs, Secret, ConfigMap, Deployments, Services, and an installation Job.

For the complete Crane workflow, see the
[migration tutorial](https://github.com/migtools/crane/blob/main/docs/migration-tutorial.md).

### Prerequisites

- Logged-in `oc` configured for the source test cluster. Set `KUBECONFIG` when
  it is not the current context.
- `mta-ops` available in `PATH`. Set `CRANE_BIN` to use a different binary.
- The WordPress deploy script at
  `../../test-day-august2026/scripts/03-deploy-app-src.sh`. Set
  `WORDPRESS_DEPLOY_SCRIPT` to use a different location.

### Run

```bash
scripts/transform-with-instructions.sh
```

The script deploys the WordPress sample into the `instructions-demo` namespace,
exports all of its resources, runs the declarative transform, and renders the
result to `output/output.yaml`. It does not apply the rendered output to a
target cluster.
The WordPress deploy script creates or reuses its generated credentials in
`test-day-august2026/test-app/wordpress/.env`.

```text
source namespace
  -> export/
  -> transform/10_KubernetesPlugin/
  -> transform/20_CustomEdits/
  -> output/
```

`CustomEdits` is a pass-through stage: use it as the last stage for reviewed
Kustomize patches or other manual changes. Crane assigns the numeric directory
prefixes from the order in `instructions.yaml`; do not supply positional stage
names or `--stage-optionals` together with `--instructions-file`.

`instructions-all-plugins.yaml` lists all built-in plugins. The failing
multi-stage optional-flags reproducer is
`instructions-all-plugins-optionals.yaml`; see

Clean up the source namespace when finished:

```bash
oc delete namespace instructions-demo
```
