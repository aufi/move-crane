# Test Day — crane v0.11 (August 2026)

Test day for the [migtools/crane](https://github.com/migtools/crane) migration
tool. Crane sources are available locally via the `./crane-sources` symlink.

## Objectives

1. **Stateful application migration** (primary) — migrate a stateful WordPress
   app between two OpenShift clusters, including persistent volume data.
2. **BuildConfig → Shipwright conversion** (secondary, **done**) — via
   [crane-plugin-buildconfig-to-shipwright](https://github.com/migtools/crane-plugin-buildconfig-to-shipwright).
   A source BuildConfig was converted and its BuildRun built + pushed an image on
   the target (see findings 06–07).

## Process

- Claude-assisted setup, documentation and help.
- Manual interaction with the `crane` CLI must remain possible and be tested
  (scripts document the exact commands, they don't hide them).

## Tested crane build (alpha, from `$PATH`)

| Component | Version |
| :-- | :-- |
| Binary | `/home/XXX/.local/bin/crane` |
| crane | `v0.11.0-alpha.1` (SHA `fe0fa07f3391ddec7a076527f727f5e2a6f853ff`) |
| crane-lib | `v0.0.10` |
| kustomize | `v5.8.1` |

## Clusters

| Role | API server | Login |
| :-- | :-- | :-- |
| Source | `https://api.octl-mman-fdfa814-220.mg.XXXX:6443` | `oc login --server=<src> -u kubeadmin -p XXXX --insecure-skip-tls-verify=true` |
| Target | `https://api.octl-mman-4dfb891-219.mg.XXXX:6443` | `oc login --server=<tgt> -u kubeadmin -p XXXX --insecure-skip-tls-verify=true` |

Sessions are stored in separate kubeconfigs by `scripts/02-login-clusters.sh`:
`kubeconfig-src` and `kubeconfig-tgt`.

## Test application

Stateful WordPress (MySQL + WordPress/NGINX, two PVCs, Secret, ConfigMap, install
Job) from
[aufi/kubectl-migrate](https://github.com/aufi/kubectl-migrate/tree/main/sample-resources/wordpress).
Manifests are saved locally under `test-app/wordpress/` (with an OpenShift
compatibility fix — see findings).

## Layout

```
scripts/     numbered, idempotent verification scripts (run in order)
test-app/    locally saved test application manifests (wordpress + buildconfig)
findings/    documented issues discovered during the test day
shipwright/  vendored ClusterBuildStrategies for the target (objective 2)
export/       crane export output               (generated)
transform/    crane transform output            (generated)
output/       crane apply output                (generated)
export-bc/    crane export (BuildConfig)        (generated)
transform-bc/ crane transform (plugin)          (generated)
output-bc/    crane apply (Shipwright Build)     (generated)
plugins/      built crane plugin binary          (generated)
```

## Scripts

| # | Script | Purpose |
| :-- | :-- | :-- |
| 01 | `scripts/01-check-versions.sh` | Verify crane build and companion tools |
| 02 | `scripts/02-login-clusters.sh` | Log in to both clusters (separate kubeconfigs) |
| 03 | `scripts/03-deploy-app-src.sh` | Deploy WordPress to the source cluster |
| 04 | `scripts/04-validate-app.sh` | Validate a WordPress instance (HTTP 200 + seed id) |
| 05 | `scripts/05-crane-export-transform-apply.sh` | Non-destructive crane pipeline (export → transform → apply) |
| 06 | `scripts/06-merge-kubeconfig.sh` | Merge src+tgt into one kubeconfig (contexts `src`/`tgt`) for `transfer-pvc` |
| 07 | `scripts/07-transfer-pvc.sh` | Scale down source, transfer both PVCs to target (`RUNS=2` times + compares each run) |
| 08 | `scripts/08-apply-target.sh` | Apply crane output to the target cluster |
| 09 | `scripts/09-cleanup-target.sh` | Delete the app namespace on the target (clean slate) |
| 10 | `scripts/10-run-full-migration.sh` | Orchestrate the whole migration end to end (steps 0→5) with a full transcript |
| 11 | `scripts/11-transfer-pvc-indirect.sh` | PVC transfer via S3 cloud storage (indirect); drop-in for step 07 (`RUNS`, `KEEP_CLOUD_DATA` for incremental re-run timing) |
| — | *BuildConfig → Shipwright (objective 2)* | |
| 20 | `scripts/20-install-openshift-builds-operator.sh` | Install OpenShift Pipelines + Builds operators (Shipwright) + ClusterBuildStrategies on the target |
| 21 | `scripts/21-deploy-buildconfig-src.sh` | Deploy the sample S2I BuildConfig to the source |
| 22 | `scripts/22-crane-buildconfig-convert.sh` | `crane export --include-gk` → `transform BuildConfigPlugin` → `apply` |
| 23 | `scripts/23-apply-shipwright-target.sh` | Apply the converted Build to the target, run a BuildRun, verify the pushed image |
| — | *Downstream binary (mta-ops)* | |
| 30 | `scripts/30-check-downstream-binary.sh` | Assert the downstream binary contract: command surface, embedded plugins (Kubernetes/OpenShift/Builds-Shipwright), non-quay.io transfer image (`CRANE_BIN=<bin>`) |

## Findings

| # | Finding |
| :-- | :-- |
| 01 | [`findings/01-nginx-scc-openshift.md`](findings/01-nginx-scc-openshift.md) — nginx sidecar crashes under OpenShift restricted SCC; fixed in the manifests (Option 2) |
| 02 | [`findings/02-pvc-whiteout-transfer-pvc.md`](findings/02-pvc-whiteout-transfer-pvc.md) — PVCs are whiteouted by transform; state migrates via `transfer-pvc`, with ordering/consistency implications |
| 03 | [`findings/03-transform-observations.md`](findings/03-transform-observations.md) — Jobs suspended in output (good); OpenShift-managed objects included (harmless noise); end-to-end result |
| 04 | [`findings/04-minor-considerations.md`](findings/04-minor-considerations.md) — nice-to-have (non-blocking): noisy controller-runtime stack trace; `transfer-pvc` needs a merged kubeconfig |
| 05 | [`findings/05-indirect-transfer-cloud-storage.md`](findings/05-indirect-transfer-cloud-storage.md) — indirect PVC transfer via S3 cloud storage (incl. `--encrypt`): setup, result, credentials/cleanup considerations |
| 06 | [`findings/06-openshift-builds-operator-setup.md`](findings/06-openshift-builds-operator-setup.md) — preparing the OpenShift target for Shipwright: Tekton prerequisite + install order, downstream operator ships no ClusterBuildStrategies |
| 07 | [`findings/07-buildconfig-to-shipwright-conversion.md`](findings/07-buildconfig-to-shipwright-conversion.md) — BuildConfig → Shipwright end to end: crane v0.11 alpha drives the plugin, `--include-gk` scoping, BuildRun builds + pushes (S2I **and** Docker/buildah), `oc get build` naming clash |
| 08 | [`findings/08-transfer-pvc-incremental-timing.md`](findings/08-transfer-pvc-incremental-timing.md) — `transfer-pvc` re-run is incremental: second run is faster (direct + indirect); `--keep-cloud-data` makes the indirect upload incremental too (~2×) |
| 09 | [`findings/09-downstream-binary-check.md`](findings/09-downstream-binary-check.md) — run the same flow against a downstream binary via `CRANE_BIN`; separate contract check (commands, embedded plugins, non-quay.io transfer image) — validated against crane as the documented upstream/downstream diff |

## Result

End-to-end stateful WordPress migration **succeeded** (v0.11.0-alpha.1). The exact
sample-post seed `#11428` created on the source is served by the target after
migration, confirming both the MySQL database and WordPress files transferred
intact. Verified with all three PVC-transfer paths — **direct** (rsync over
route), **indirect** (S3 cloud storage), and **indirect + `--encrypt`**
(client-side encryption) — each ending with the same `#11428` on the target.

**BuildConfig → Shipwright (objective 2) also succeeded.** Source `BuildConfig`s
were converted with `crane transform BuildConfigPlugin` (driven by the same
v0.11.0-alpha.1 build), applied to the target, and their BuildRuns built and
pushed images whose digests matched the resulting ImageStreamTags. Verified for
**both** strategies — **S2I** (nodejs → source-to-image) and **Docker/buildah**
(ruby-hello-world → buildah-shipwright-managed-push, needing a privileged SCC and
an annotated internal-registry push secret) — see findings 06–07.

## Reproducing the migration (full transcript)

`scripts/10-run-full-migration.sh` runs the whole flow (ensure/validate source →
export/transform/apply → merge kubeconfig → transfer-pvc → apply target →
validate target) and echoes every command it runs. To capture a verbatim
terminal transcript:

```bash
# clean slate on the target first
scripts/09-cleanup-target.sh

# with the `script` utility (true typescript), if installed:
script -q -e -c scripts/10-run-full-migration.sh runs/migration-$(date +%Y%m%d-%H%M%S).log

# or plain tee (this repo's fallback — script utility not present here):
set -o pipefail
scripts/10-run-full-migration.sh 2>&1 | tee runs/migration-$(date +%Y%m%d-%H%M%S).log
```

To run the same migration with **indirect transfer via S3 cloud storage**, point
the orchestrator at the indirect transfer step and provide a bucket (needs a
local `rclone.conf` with an `[remote]` S3 profile — keep it out of version
control):

```bash
scripts/09-cleanup-target.sh
rclone --config rclone.conf mkdir remote:<bucket>   # once
set -o pipefail
TRANSFER_SCRIPT=11-transfer-pvc-indirect.sh CLOUD_BUCKET=<bucket> \
  scripts/10-run-full-migration.sh 2>&1 | tee runs/migration-indirect-$(date +%Y%m%d-%H%M%S).log
```

Add `ENCRYPT=true` for client-side encryption of the staged data (crane's
`--encrypt`):

```bash
TRANSFER_SCRIPT=11-transfer-pvc-indirect.sh CLOUD_BUCKET=<bucket> ENCRYPT=true \
  scripts/10-run-full-migration.sh 2>&1 | tee runs/migration-indirect-encrypt-$(date +%Y%m%d-%H%M%S).log
```

Transcripts are stored under `runs/`:

- `runs/migration-<ts>.log` — raw transcript (includes the rsync progress bar's
  ANSI control codes).
- `runs/migration-<ts>.clean.log` — same run with ANSI codes and repeated
  progress lines stripped, for readable review.

## Downstream binary (mta-ops)

The same flow can run against a downstream build instead of upstream `crane`. Every
crane-invoking script honors `CRANE_BIN` (default `crane`):

```bash
CRANE_BIN=mta-ops scripts/10-run-full-migration.sh   # whole migration, downstream binary
```

A **separate** check, `scripts/30-check-downstream-binary.sh`, asserts the
downstream-specific contract (it does not migrate data): only
`export/transform/apply/validate/transfer-pvc` commands (no
`plugin-manager/convert/skopeo-sync-gen/tunnel-api`); embedded transform plugins
`Kubernetes` + `OpenShift` + `Builds/Shipwright` (Shipwright embedded, not added
externally); and a `transfer-pvc` default image **not** on `quay.io` (echoed to the
log). Run against crane it reports `RESULT: FAIL`, spelling out the exact
upstream/downstream diff mta-ops must close — see finding 09.

## Migration workflow (crane)

1. `crane export -n wordpress` (source) → `export/`
2. `crane transform` → `transform/`
3. `crane apply` → `output/output.yaml`
4. Deploy `output/output.yaml` to the target cluster
5. `crane transfer-pvc` — migrate both PVCs (mysql + wordpress) source → target
6. Validate the app on the target (sample post seed id must match the source)
