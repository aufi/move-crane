# Same namespaces on source and target

Live test date: 2026-11-10. **Result: passed.** Four Applications synchronized automatically on kind with only four destination-related JSON Patch operations.

A later [minimal replay](minimal/README.md) also passed with **two operations**. Its source fleet already uses the local API URL and a matching project rule, so only the explicit Application's API URL and its project permission need transformation. That replay records the current target configuration; the four-operation case below remains reproducible without `--portable-fleet`.

This example removes namespace and Git-environment differences from the previous experiments. It demonstrates which custom transformations remain necessary when application namespaces and Git configuration are already portable.

## Settings kept identical

| Setting | Value on both clusters |
| --- | --- |
| Argo CD definition namespace | `crane-gitops-target` |
| Local Application workload namespace | `crane-payments-shared` |
| Explicit Application workload namespace | `crane-ledger-shared` |
| ApplicationSet workload namespaces | `crane-fleet-shared-blue`, `crane-fleet-shared-green` |
| Git URL | `git://git-fixture.crane-git-shared.svc.cluster.local:9418/apps.git` |
| Git revision | `main` |
| Git path | `overlays/source` |
| Automated sync | Enabled, including prune and self-heal |
| Application names | `local-web`, `explicit-web`, `fleet-blue`, `fleet-green` |

The namespace name `crane-gitops-target` is intentionally used on minikube as well as kind. The kubeconfig context determines which cluster receives each operation.

A separate source instance was provisioned on minikube in that namespace before export. Kind reused the existing instance from the earlier tests. The earlier minikube example in `crane-gitops-source` remained running.

Both clusters host the same deterministic, public, read-only Git fixture under the same Service DNS name. The runner verified matching Git commit revisions. This stands in for a repository URL accessible unchanged from both clusters; it does not test migration of a Git hosting service.

All sample endpoints return the same application content:

```text
crane-argocd-live-test same-namespaces shared-content
```

## The complete custom stage

[kustomization.yaml](kustomization.yaml) contains the actual, readable stage copied into this live run. It has no `namespace:` setting and does not patch repository fields, paths, revisions, or sync policies.

| Resource | JSON Patch path | Change | Why needed |
| --- | --- | --- | --- |
| Application `explicit-web` | `/spec/destination/server` | Minikube API URL to `https://kubernetes.default.svc` | Deploy to kind instead of retaining an explicit reference to minikube. |
| ApplicationSet `fleet` | `/spec/template/spec/destination/name` | `minikube-workloads` to `kind-workloads` | Use the target's existing cluster registration. |
| AppProject `crane-sample` | `/spec/destinations/1/server` | Minikube API URL to the local API URL | Permit the remapped explicit Application destination. |
| AppProject `crane-sample` | `/spec/destinations/2/server` | Minikube API URL to the local API URL | Permit the remapped ApplicationSet destinations. |

The local Application's existing `https://kubernetes.default.svc` destination already means the cluster where Argo CD runs. **`local-web` required no custom spec changes.** Its namespace, Git references, project reference, and sync policy remained unchanged.

For example, the entire explicit-Application patch is:

```yaml
- target:
    group: argoproj.io
    kind: Application
    name: explicit-web
  patch: |-
    - op: replace
      path: /spec/destination/server
      value: https://kubernetes.default.svc
```

These changes are required for this scenario's explicit endpoint and registered-name differences. An installation whose Applications already use only the local API URL and whose project rules remain valid may need no custom destination patches.

## Export and generic cleanup

The migration exports application definitions only. The target Argo CD instance and its cluster registration already exist:

```bash
crane export --context minikube -n crane-gitops-target \
  --include-gk argoproj.io/Application \
  --include-gk argoproj.io/ApplicationSet \
  --include-gk argoproj.io/AppProject \
  --crd-skip-group argoproj.io \
  --export-dir export

crane transform KubernetesPlugin --export-dir export --transform-dir transform
```

No optional KubernetesPlugin flags were used. Default cleanup strips server metadata/status and omits the two ApplicationSet-owned children. The custom stage uses materialized baseline output for the sample project, two standalone Applications, and ApplicationSet.

The source `default` project is excluded by resource selection to preserve the existing target project. That exclusion is not one of the four patch operations. No ArgoCD instance, Secrets, ConfigMaps, CRDs, or cluster RBAC are exported.

After preparing the stage, the final build is:

```bash
crane apply 50_SameNamespaces \
  --transform-dir transform \
  --output-dir target-output
```

## Recorded live results

- Official Crane v0.11.0 with embedded Kustomize v5.8.1, argocd-operator v0.18.0, and Argo CD v3.3.10.
- Minikube v1.35.1 to kind v1.35.0, using the existing kind cluster.
- Seven filtered exported objects, five after generic cleanup, four in the final bundle. No export failure files.
- The runner compared the default-cleaned and final `spec` trees and asserted exactly the four changed paths listed above. All definition and destination namespace names stayed the same.
- Target server-side dry run passed for all four resources.
- All four Applications became `Synced` and `Healthy` through their preserved automated sync policies. No manual sync operation or temporary sync-policy patch was used.
- Source and target Applications referenced the same Git commit and served the expected identical HTTP content.
- Target hard refreshes and another ApplicationSet reconciliation completed. Generated children referenced the target ApplicationSet UID.
- The existing target instance UID, generation, and spec, default project, credential Secret UIDs, and control-plane Deployment UIDs matched the pre-migration snapshot.
- The new source workloads retained their UIDs, readiness, and content. The original minikube experiment's workloads also matched their snapshot.

The kind Applications deploy into the four `*-shared*` workload namespaces above, with automated sync enabled. The later minimal replay uses the same layout with a portable fleet destination. Earlier filtered experiments are historical runs; their demo definitions were reset before these replays.

## Reproduce

Use [run_same_namespaces.py](../run_same_namespaces.py) after the initial operator and kind setup described in the [live guide](../README.md). From the planning repository root:

```bash
python3 playground/argocd-migration/live/run_same_namespaces.py prepare \
  --target-kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --work-dir /tmp/opencode/argocd-live/same-namespaces \
  --crane /tmp/opencode/argocd-crane-v0.11.0/crane_linux_amd64
```

Then use the same arguments with phase `migrate`, followed by `verify`. Choose a new work directory for another complete replay because the migration phase preserves existing Crane artifacts.

`prepare` provisions the matching source instance and shared Git fixtures, resets only the known target demo definitions, prepares empty matching workload namespaces, and snapshots the running target installation. Target namespace labels, permissions, and the `kind-workloads` registration are prerequisites, not custom transformations of the exported definitions.

The runner reuses shared helpers from the earlier live experiments. Its `migrate` phase copies this directory's static Kustomization into `50_SameNamespaces`, so the checked-in patches are the patches exercised by the live test.

## Artifacts

Recorded run directory: `/tmp/opencode/argocd-live/same-namespaces/`.

- `export/` and `baseline/output.yaml` contain the filtered source and default-cleaned output.
- `transform/50_SameNamespaces/` contains the static stage and four selected baseline manifests.
- `target-output/output.yaml` is the final transformed bundle.
- `spec-differences.json` lists the exact custom changes, including an empty list for `Application/local-web`.
- `instance-before.json`, `source-before.json`, and `original-source-before.json` capture pre-migration checks without Secret values.
- `same-namespace-results.json` records the successful checks, Application states, revisions, and HTTP results.
- `commands.log` records the Crane commands and their output.
