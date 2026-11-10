# Minimal required destination changes

Live test date: 2026-11-10. **Result: passed with two JSON Patch operations.** All four Applications started through automated sync and became `Synced` and `Healthy` on kind.

This replay makes the fleet configuration portable before migration. Unlike the earlier named-destination example, the source ApplicationSet already uses:

```yaml
destination:
  server: https://kubernetes.default.svc
  namespace: "{{namespace}}"
```

The source AppProject already permits that local API destination for `crane-fleet-shared-*`. Neither field needs a target patch. This is source application configuration, rather than an additional transformation hidden in the migration stage.

## The two remaining operations

Only `explicit-web` retains a source-specific API URL, together with its project permission. The complete tested [Kustomization](kustomization.yaml) changes:

| Resource | JSON Patch path | Source | Target |
| --- | --- | --- | --- |
| Application `explicit-web` | `/spec/destination/server` | `https://192.168.39.12:8443` | `https://kubernetes.default.svc` |
| AppProject `crane-sample` | `/spec/destinations/1/server` | `https://192.168.39.12:8443` | `https://kubernetes.default.svc` |

The Application patch directs deployment to kind. The project patch permits that destination in `crane-ledger-shared`; its source rule permits only the minikube API for that namespace.

There are no custom patches for:

- `local-web`.
- The `fleet` ApplicationSet or its generated Applications.
- Definition or workload namespaces.
- Git URL, revision, or path.
- Automated sync, prune, self-heal, or application content.

If `explicit-web` and its project rule also used a portable destination on the source, these remaining operations could be omitted as well. That further zero-patch configuration was not the case exercised in this replay.

## Scope and prerequisites

The [same-namespace setup](../README.md) is reused. Argo CD definitions use `crane-gitops-target` on both minikube and kind. Workloads use the same four `*-shared*` namespaces. Both clusters resolve the same Git Service URL and serve the same repository content at revision `main`, path `overlays/source`.

The target Argo CD instance, operator, namespace permissions, and connections already exist. Preparation clears only the previous demo definitions and their workloads. No `ArgoCD` CR, Secret, ConfigMap, CRD, or cluster RBAC enters the migration bundle.

The source `default` project is excluded from the final stage to preserve the existing target project. That is resource selection, not another transformation patch.

## Run

Use the existing runner's `--portable-fleet` option in all three phases. From the planning repository root:

```bash
python3 playground/argocd-migration/live/run_same_namespaces.py prepare \
  --portable-fleet \
  --target-kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --work-dir /tmp/opencode/argocd-live/minimal-destinations \
  --crane /tmp/opencode/argocd-crane-v0.11.0/crane_linux_amd64
```

Then run the same arguments with phase `migrate`, followed by `verify`. Choose a fresh work directory for another complete replay. The preparation phase updates the source fleet to its portable local destination and prepares a clean target application space while preserving the running instance.

The migration phase runs filtered export of `Application`, `ApplicationSet`, and `AppProject` with `--crd-skip-group argoproj.io`, followed by the default KubernetesPlugin. It copies this static Kustomization into `50_MinimalDestinations` and builds it with `crane apply`. There are no special plugin optional flags.

## Recorded verification

- Seven filtered source CRs, five after default cleanup, four in the final bundle. No export failure files.
- Default cleanup omitted the two ApplicationSet-owned children, which the target controller regenerated.
- Exact comparison of baseline and final spec trees found only the two paths listed above. Both `Application/local-web` and `ApplicationSet/fleet` had empty custom diff lists.
- Target server-side validation passed.
- `local-web`, `explicit-web`, `fleet-blue`, and `fleet-green` all became `Synced` and `Healthy` through automated sync. No manual sync request was issued.
- The complete `spec` of `local-web`, `fleet-blue`, and `fleet-green` matched their source counterparts after target controller reconciliation.
- All Applications used the same Git commit on source and target and served `crane-argocd-live-test same-namespaces shared-content` over HTTP.
- Target hard refreshes and another ApplicationSet reconciliation completed, with correct target ownership.
- Target instance configuration and identities, default project, credential Secret identities, and control-plane Deployment identities were preserved.
- Source workload identities, readiness, and HTTP content remained unchanged during migration, including the original source experiment.

The test used the official Crane v0.11.0, argocd-operator v0.18.0, and Argo CD v3.3.10, on minikube v1.35.1 and kind v1.35.0.

## Artifacts

Recorded run directory: `/tmp/opencode/argocd-live/minimal-destinations/`.

- `baseline/output.yaml` contains the default-cleaned source resources.
- `transform/50_MinimalDestinations/kustomization.yaml` is the copied two-operation recipe.
- `target-output/output.yaml` contains the final transformed definitions.
- `spec-differences.json` records the exact two custom spec changes.
- `same-namespace-results.json` records the successful checks and application results, including `portable_fleet: true`.
- `commands.log` records the Crane commands and output.

The current target fleet uses the local API URL and automated sync remains enabled.
