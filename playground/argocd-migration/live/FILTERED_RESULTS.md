# Filtered migration into an existing Argo CD instance

Date: 2026-11-10.

**Result: passed.** The migration reused the existing Argo CD instance in kind's `crane-gitops-target` namespace. No `ArgoCD` CR, Secret, ConfigMap, operator resource, or workload object entered the migration bundle.

## Target preparation

The original test instance was already available. Its Git server, public repository configuration, `kind-workloads` cluster registration, and operator permissions were already configured.

The preparation phase removed only the previous experiment's `fleet` ApplicationSet, four sample Applications, and `crane-sample` project. Application finalizers cleaned up their previous sample workloads. The target's default project and Argo CD installation remained in place. Four empty workload namespaces were prepared with the target instance's managed-namespace label:

- `crane-payments-filtered`
- `crane-ledger-filtered`
- `crane-fleet-filtered-blue`
- `crane-fleet-filtered-green`

An initial attempt to prepare an additional instance hit the host's inotify instance limit, reported by the repo server as `failed to create fsnotify Watcher: too many open files`. That incomplete instance namespace was removed. The successful test reused the original running instance and required no host sysctl changes.

## Filtered export

The runner invoked the official Crane v0.11.0 release with this scope:

```bash
crane export --context minikube -n crane-gitops-source \
  --include-gk argoproj.io/Application \
  --include-gk argoproj.io/ApplicationSet \
  --include-gk argoproj.io/AppProject \
  --crd-skip-group argoproj.io \
  --export-dir export
```

| Phase | Resource count | Contents |
| --- | --- | --- |
| Filtered export | 7 | Four Applications, one ApplicationSet, two projects |
| Default KubernetesPlugin output | 5 | Two standalone Applications, one ApplicationSet, two projects |
| Final target bundle | 4 | Two standalone Applications, one ApplicationSet, sample project |

There were no export failure files. The filter and CRD skip option excluded instance configuration, Secrets, ConfigMaps, CRDs, and cluster RBAC. Default cleanup omitted the two owned ApplicationSet children. The custom stage excluded the source `default` project to preserve the existing target project.

## Transformations still needed

Default cleanup did not perform the target mappings. The custom `50_FilteredTarget` stage changed:

- Definition namespace to the existing `crane-gitops-target` namespace.
- Git URLs to the existing target Git service.
- Source paths from `overlays/source` to `overlays/target`.
- Explicit minikube API destination to the local kind API URL.
- ApplicationSet destination name from `minikube-workloads` to the preconfigured `kind-workloads`.
- Workload destinations and generator namespace inputs to the four `*-filtered*` namespaces.
- Project repository and destination permissions.
- Automated sync settings, which were removed for initial restore.

No source credentials were copied and no new target credentials were issued during this replay. The public repository and target cluster registration were prerequisites supplied by the existing installation.

## Validation

- Target server-side dry run passed for all four definitions.
- All four Applications rendered as `OutOfSync` with sync paused and no workload Deployments present before manual sync.
- Manual sync produced four `Synced` and `Healthy` Applications.
- Every workload returned `crane-argocd-live-test environment=target cluster=kind` over HTTP.
- Hard refreshes and another ApplicationSet reconciliation completed successfully.
- ApplicationSet children referenced their new target parent UID; automated sync remained disabled.
- The existing `ArgoCD` CR's UID, generation, and complete `spec` matched the snapshot taken before resetting the demo definitions.
- The default project's UID and spec, credential Secret UIDs, and control-plane Deployment UIDs matched that same snapshot.
- Source Deployment UIDs, ready replica counts, and source-specific HTTP responses remained unchanged.

In this replay, target Applications `local-web`, `explicit-web`, `fleet-blue`, and `fleet-green` deployed into the filtered workload namespaces listed above. The later [same-namespace replay](same-namespaces/README.md) reset these demo definitions again and records the current target layout.

## Reproduce

Use [run_filtered.py](run_filtered.py) after the initial live environment has been installed. Run the phases in order from the planning repository root:

```bash
python3 playground/argocd-migration/live/run_filtered.py prepare \
  --target-kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --work-dir /tmp/opencode/argocd-live/filtered \
  --crane /tmp/opencode/argocd-crane-v0.11.0/crane_linux_amd64
```

Then run the same command with phase `migrate`, followed by `verify`. The preparation phase explicitly resets the known demo definitions. The migration phase expects new Crane output directories; choose a fresh work directory for another complete replay.

Artifacts for the recorded run are in `/tmp/opencode/argocd-live/filtered/`:

- `instance-before.json` records installation identities and instance/project configuration without Secret values.
- `source-before.json` records source workload identities and HTTP responses.
- `commands.log` records the Crane commands and their output.
- `export/`, `baseline/`, and `transform/50_FilteredTarget/` record the filtered pipeline.
- `target-output/output.yaml` contains the four-resource bundle.
- `inventory.json` records identities, export failures, and the paused checkpoint.
- `filtered-results.json` records the completed checks and target application states.
