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

The script deploys the WordPress sample into the
`wordpress-instructions-demo` namespace, exports all of its resources, runs the
declarative transform, and would render the result to `output/output.yaml`.
With the current `mta-ops` binary, the KubernetesPlugin optionals in
`instructions.yaml` intentionally reproduce the known multi-stage failure, so
the script stops before rendering. It does not apply output to a target cluster.
The WordPress deploy script creates or reuses its generated credentials in
`test-day-august2026/test-app/wordpress/.env`.

### Demo Commands

Run these commands from this directory. Each transform command overwrites
`transform/`; run one transform variant at a time before rendering it.

```bash
NAMESPACE=wordpress-instructions-demo

# 1. Export the WordPress source namespace.
mta-ops export -n "${NAMESPACE}" --export-dir export --overwrite

# 2. Transform with mta-ops defaults and no instructions file.
mta-ops transform --export-dir export --transform-dir transform --overwrite

# 3. Transform with an instructions file that explicitly runs every built-in plugin.
mta-ops transform \
  --export-dir export \
  --transform-dir transform \
  --instructions-file instructions-all-plugins.yaml \
  --overwrite

# 4. Run KubernetesPlugin optionals from instructions.yaml.
#    This currently reproduces the known mta-ops multi-stage optionals failure.
mta-ops transform \
  --export-dir export \
  --transform-dir transform \
  --instructions-file instructions.yaml \
  --overwrite

# 5. Render the latest successful transform (step 2 or 3).
mta-ops apply \
  --transform-dir transform \
  --output-dir output \
  --overwrite
```

To add custom labels, place a Kustomize patch in `transform/20_CustomEdits/`
after a successful transform. `mta-ops` exposes `add-annotations`, but not an
`add-labels` optional, so labels belong in this manual stage.

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
oc delete namespace wordpress-instructions-demo
```
