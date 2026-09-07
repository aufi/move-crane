# Demo: BuildConfig -> Shipwright on OpenShift Local

This directory contains repeatable material for a local demonstration of
[crane-plugin-buildconfig-to-shipwright](https://github.com/migtools/crane-plugin-buildconfig-to-shipwright)
on a single OpenShift Local (`crc`) cluster. The demo creates three OpenShift
`BuildConfig` resources, exports them with Crane, converts them offline into
Shipwright `Build` resources, and manually starts a `BuildRun` for each that
builds and pushes an image to the cluster's internal registry.

It uses two S2I Node.js examples and one Docker Ruby example. All outputs use
the cluster's internal registry, so the same generated push secret works for
each BuildRun. The three inputs and BuildRuns were verified on OpenShift Local
4.22.7.

## Prerequisites

- A working OpenShift Local and a logged-in `oc` client. Before first use:

  ```bash
  crc setup
  crc config set disk-size 60
  crc start
  eval "$(crc oc-env)"
  crc console --credentials
  ```

  The last command prints the credentials and the exact `oc login` command for
  your cluster; copy that command into the terminal.

  The default 31GB CRC disk is too small for the operator catalogs, OpenShift
  Builds, and the demo images. Configure 60GB before the first `crc start`.
  Changing the disk size of an existing instance requires `crc delete` followed
  by `crc start`.
- A Red Hat pull secret configured for CRC. An interactive `crc start` prompts
  for it. To start CRC non-interactively, download the secret from
  [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret)
  and configure its local path before starting the instance:

  ```bash
  crc config set pull-secret-file /path/to/pull-secret.txt
  crc start
  ```
- The `mta-ops` binary on `PATH`. It embeds `BuildConfigPlugin`; no external
  plugin binary or `--plugin-dir` is used in this demo.

The OpenShift Builds operator is available only when the local cluster can reach
the operator catalog. The first operator installation and image pulls may take several minutes.

## Running the Demo

Run the scripts from this directory in order:

```bash
scripts/01-check-prerequisites.sh
scripts/02-install-openshift-builds.sh
scripts/03-convert-buildconfig.sh
scripts/04-run-build.sh
```

`02-install-openshift-builds.sh` installs OpenShift Pipelines before OpenShift
Builds. This installs the downstream OpenShift Builds operator, not upstream
Shipwright. OpenShift Builds provides the Shipwright API and requires Tekton.
The downstream operator does not provide any `ClusterBuildStrategy`, so the
script applies the versioned `source-to-image` strategy included here.

The local strategy uses Kaniko and therefore requires the `privileged` SCC for
the demo namespace's `pipeline` ServiceAccount. Script 04 grants this exception
only to that account. Do not apply this permission model to production workloads.
It also turns the account's internal-registry token into a Tekton-annotated
`dockerconfigjson` push secret, which Shipwright needs to push the output image.

After successful runs, the final script prints each BuildRun output digest and
the matching ImageStreamTag. The demonstration proves the entire flow:

```text
BuildConfig -> mta-ops export -> mta-ops transform -> Shipwright Build -> BuildRun -> ImageStreamTag
```

To repeat the demo, delete only the demo namespace:

```bash
scripts/05-cleanup.sh
```

## Demo Talking Points

1. `manifests/buildconfig.yaml` and `manifests/buildconfig-nodejs-webhook.yaml`:
   S2I Node.js BuildConfigs using an `openshift/nodejs:18-ubi8` ImageStreamTag.
   Their ImageChange trigger is paused so CRC does not try to run the original
   BuildConfig with an unavailable source ImageStream; the second also has a
   GitHub webhook trigger.
2. `manifests/buildconfig-ruby-docker.yaml`: a Docker-strategy BuildConfig for
   the `openshift/ruby-hello-world` repository.
3. `scripts/03-convert-buildconfig.sh`: the embedded plugin runs offline. The
   `imagestream-mapping` parameter replaces the source ImageStream with a
   concrete publicly pullable UBI image; the output ImageStreamTag remains in
   the target OpenShift internal registry.
4. `output/resources/demo-buildconfig/`: the generated `shipwright.io/v1beta1`
   Build. Read the `crane.konveyor.io/conversion-warnings` annotation: triggers
   and `runPolicy` have no Shipwright equivalent and are recorded transparently.
5. `scripts/04-run-build.sh`: Shipwright has no OpenShift triggers, so each
   build is started with an explicit `BuildRun`.

On OpenShift, the `build` name is ambiguous because both OpenShift and Shipwright
provide a `Build` resource. Always use the fully qualified resource
`builds.shipwright.io` and `buildruns.shipwright.io`.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `NAMESPACE` | `demo-buildconfig` | Namespace for demo resources |
| `CRANE_BIN` | `mta-ops` | Crane-compatible binary path or name |
| `BUILD_TIMEOUT` | `900s` | Maximum BuildRun wait time |

The scripts change only local working directories and the demo namespace, except
for OpenShift Builds operator and cluster strategy installation in step 02.
