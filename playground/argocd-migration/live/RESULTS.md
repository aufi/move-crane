# Live test results

Date: 2026-11-10.

**Result: operator-assisted Argo CD migration from minikube to kind passed for the stateless sample.**

## Versions

- Source Kubernetes v1.35.1, existing minikube profile `minikube` with kvm2/Docker.
- Target Kubernetes v1.35.0, kind v0.31.0, rootless Podman.
- argocd-operator v0.18.0 installed manually on both clusters.
- Operator image `quay.io/argoprojlabs/argocd-operator@sha256:a09814522a72864cc10ec1be2834db63593427a9ab4779d97687a73dd30272f4`.
- Argo CD v3.3.10, commit `4e8d8b5d05451d76412b36122d6803a90b4f406e`.
- Argo CD image `quay.io/argoproj/argocd@sha256:05d68bf224df7cd39713012c19226a33c374f2f3bd65df7b9088349e4ac3e6a2`.
- Official Crane v0.11.0, SHA `8844161b3e5a9df01886f5c07e48668ff06fe8c7`, embedded Kustomize v5.8.1. The binary checksum was verified during the offline experiment.
- Instance CR API `argoproj.io/v1beta1`; Application, ApplicationSet, and AppProject APIs `argoproj.io/v1alpha1`.

## Observed pipeline

1. The source operator created a healthy Argo CD instance.
2. Source Argo CD synchronized four Applications, including two ApplicationSet children.
3. All four source web endpoints returned `crane-argocd-live-test environment=source cluster=minikube`.
4. A real Crane namespace export captured **88 resources**, with **no export failure files**.
5. The default Kubernetes stage retained **18 resources**.
6. Six desired-state resources were selected from that baseline, patched, and materialized through another `crane apply`.
7. Target server-side dry runs passed for the instance CR and the GitOps definitions.
8. The target operator created its own healthy instance and generated configuration.
9. Target definitions produced four Applications with sync disabled. No sample workload Deployment existed during the paused checkpoint.
10. Explicit manual sync created four healthy target workloads.
11. All target web endpoints returned `crane-argocd-live-test environment=target cluster=kind`.
12. Hard-refresh annotations were acknowledged by both Application controllers. The target ApplicationSet acknowledged another reconciliation, and all Applications remained healthy/synced with automated sync disabled.
13. The generated target Applications referenced the target ApplicationSet UID, which differed from the source UID.
14. All four source Deployment UIDs, ready replica counts, and HTTP responses matched the pre-export snapshot.

## Target application results

| Application | Destination namespace | Sync | Health | HTTP content |
| --- | --- | --- | --- | --- |
| `local-web` | `crane-payments-target` | Synced | Healthy | target/kind |
| `explicit-web` | `crane-ledger-target` | Synced | Healthy | target/kind |
| `fleet-blue` | `crane-fleet-target-blue` | Synced | Healthy | target/kind |
| `fleet-green` | `crane-fleet-target-green` | Synced | Healthy | target/kind |

## Required transformations in this run

A subsequent live export with `--include-gk` restricted to `ArgoCD`, `Application`, `ApplicationSet`, and `AppProject`, plus `--crd-skip-group argoproj.io`, captured eight CRs. Default cleanup retained six and omitted the two owned ApplicationSet children. Inspection confirmed that all source-specific Git/destination settings and automated sync policies remained. Filtering reduces export scope; it does not supply the target mappings described below. The generated follow-up output is under `/tmp/opencode/argocd-live/include-gk/`.

- Map the instance/definition namespace from `crane-gitops-source` to `crane-gitops-target`.
- Replace source Git service URLs in the repository Secret, project allowlist, Applications, and ApplicationSet template.
- Select `overlays/target` instead of `overlays/source` in Applications and the ApplicationSet template.
- Preserve the local destination URL and map the workload namespace for `local-web`.
- Replace the explicit minikube API destination with the target-local API URL for `explicit-web`.
- Map ApplicationSet destination name `minikube-workloads` to `kind-workloads` and update its generated namespace parameters.
- Replace project destination permissions with the four intended target namespaces and target API URL.
- Remove automated sync from standalone Applications and the ApplicationSet template during restore.
- Reissue cluster registration credentials from the target cluster and use its CA. The source registration Secret was deliberately excluded from the migration bundle.
- Create workload namespaces with labels referring to the target instance namespace.

The exported ArgoCD CR already contained the desired RBAC configuration. Its `spec` transferred without an ArgoCD-specific spec patch. An operator-owned configuration setting outside the CR was covered by the earlier offline recovery experiment, rather than manufactured as an additional live change here.

## Important live finding about generated cluster resources

The default baseline retained all four referenced Argo CD CRDs and six cluster-scoped RBAC resources, despite the operator already being installed on the target. Manual installation did not provide metadata sufficient for Crane's operator-manager heuristic to skip these CRDs. Cluster-scoped operator RBAC also survived generic ownership filtering.

The baseline contained:

- Four CRDs.
- Three ClusterRoles and three ClusterRoleBindings.
- Two Secrets, including source cluster registration.
- Two AppProjects, including the generated/default project.
- Two standalone Applications.
- One ApplicationSet.
- One ArgoCD instance CR.

Applying the entire baseline would therefore reapply source platform resources and source registration. The explicit desired-state selection was part of the successful migration recipe. The target operator supplied its CRDs, generated RBAC, default project, instance credentials, and runtime components.

Crane correctly omitted both generated Applications and the owned namespaced runtime/configuration objects. The target controller regenerated children with fresh ownership.

## Test-harness fixes during setup

The initial static HTTP repository fixture returned `unexpected EOF` during Argo CD Git reference discovery. A real Git daemon resolved this. Alpine's Git image did not include the separate `git-daemon` package, so the disposable fixture installs it on startup. These were fixture setup issues; they occurred before the successful source baseline and migration.

## Scope

This demonstrates a live, scripted, operator-assisted resource migration with public Git, local and named destinations, ApplicationSet regeneration, actual target schema/admission checks, and working stateless HTTP workloads.

Private repository authentication, SSO, externally managed secrets, additional Application namespaces, multi-source Helm, generator template overrides, persistent data, and upgrades between Argo/operator versions were not exercised in this live run. Some manifest transformations for these cases have separate offline coverage.

This remains a custom migration recipe. Crane supplies export and generic transformation/output generation; the experiment supplies resource selection, target mappings, credential setup, deployment ordering, and validation.

The source and target test installations are running for further inspection. Target automated sync remains disabled. The target has a separate kubeconfig, and the default current context remains `minikube`.
