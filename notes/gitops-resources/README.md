# Migrating an operator-managed Argo CD instance with Crane

Research date: 2026-11-10.

## Conclusion

Crane can export Argo CD's namespaced custom resources, apply generic Kubernetes cleanup, and generate manifests for a target cluster. With a compatible Argo CD operator already installed, this provides the building blocks to recreate an Argo CD instance and its GitOps configuration.

**This is a conditional, operator-assisted migration, not an out-of-the-box Argo CD migration workflow.** Crane does not supply Argo CD-specific destination mapping, configuration recovery, reconciliation sequencing, or functional validation.

Also, `crane apply` applies transformations to files. It does not deploy to the target API server. Deployment requires `kubectl apply`, `oc apply`, or another deployment mechanism.

The practical migration unit is the `ArgoCD` instance CR, user-maintained GitOps definitions, and required configuration and credentials. The target operator should recreate the instance's generated Deployments, Services, and other managed resources.

## Evidence and version scope

The assessment uses upstream source rather than local working-tree changes:

- Crane `main` at [`203065a3a3cd`](https://github.com/migtools/crane/tree/203065a3a3cd9979a245a80b1472346d61c564af).
- Its [pinned crane-lib dependency](https://github.com/migtools/crane/blob/203065a3a3cd9979a245a80b1472346d61c564af/go.mod), `926a5ffd044f510bb8175ed8ed4b07e052057b16`.
- Latest published Crane release found during research, [v0.11.0](https://github.com/migtools/crane/releases/tag/v0.11.0). It pins crane-lib `f8e16a055cd666b01c5fca484fa58d6c3238651b`. The ownership filtering and generic discovery behavior discussed below also exist in that release.
- Argo CD's upstream documentation and the GitOps operator's documentation. Operator behavior must be checked against the actual distribution and version in use.

The initial assessment was source-based. Follow-up offline and live experiments are described below. The tested scenario does not establish a vendor support commitment or a general compatibility matrix.

### Offline transformation experiment

A follow-up [synthetic experiment](../../playground/argocd-migration/README.md) now exercises the real Crane v0.11.0 release and an explicit target Kustomize stage. [All 14 offline tests passed](../../playground/argocd-migration/RESULTS.md).

The experiment covers destination and namespace maps, multi-source Helm values, ApplicationSet generator inputs and template overrides, initial sync control, project permissions, encoded cluster credentials, owned configuration recovery, stale tracking and operations, and cross-namespace RBAC. It also proves that namespace-only remapping and global ownership retention are incomplete recipes. The [patch examples](../../playground/argocd-migration/target-stage/kustomization.yaml) are fixture-specific and need adaptation to real exports.

The offline result validates manifest transformation and repeatability.

### Live minikube-to-kind experiment

A subsequent [live experiment](../../playground/argocd-migration/live/README.md) passed with Crane v0.11.0, argocd-operator v0.18.0, and Argo CD v3.3.10. The operator ran on both source minikube and target kind before migration. Four target Applications, including two ApplicationSet-generated children, became healthy/synced and served target-specific HTTP content. Source workload UIDs and HTTP responses remained unchanged.

The live run exported 88 resources, retained 18 after generic cleanup, and migrated six selected desired-state resources. It tested target server-side dry runs, operator readiness, repository/destination mappings, target-issued credentials, paused restore, manual sync, and subsequent controller reconciliation. [Full live results](../../playground/argocd-migration/live/RESULTS.md) document the versions and remaining coverage gaps.

One observed limit matters for the migration recipe. The manually installed operator's four CRDs and six cluster RBAC resources survived the generic baseline. The experiment explicitly excluded them and let the target operator supply those resources.

## What Crane does today

### Export

Crane discovers server-preferred API resources and uses a dynamic client to list objects. It admits namespaced resource types without requiring an Argo-specific implementation. Discovery requires the API type to advertise `list`, `create`, `get`, and `delete` verbs. The exporting identity must have permission to list the objects.

For an operator-managed Argo CD migration, use `--include-gk` to export the desired-state custom resources. This avoids collecting the instance's generated Deployments, Services, and other runtime objects. Start with these kinds, where present:

| Group/Kind | Needed resource |
| --- | --- |
| `argoproj.io/ArgoCD` | The instance definition for the target operator, unless the target instance is configured separately. |
| `argoproj.io/Application` | Standalone application definitions. ApplicationSet-generated children may be exported but default cleanup omits them. |
| `argoproj.io/ApplicationSet` | Parent definitions needed to regenerate their Applications on the target. |
| `argoproj.io/AppProject` | Projects referenced by the Applications and ApplicationSets, including their repository and destination permissions. |

```bash
crane export --context source -n argocd \
  --include-gk argoproj.io/ArgoCD \
  --include-gk argoproj.io/Application \
  --include-gk argoproj.io/ApplicationSet \
  --include-gk argoproj.io/AppProject \
  --crd-skip-group argoproj.io \
  --export-dir export-argocd
```

Use `--crd-skip-group argoproj.io` when the preinstalled target operator supplies the Argo CD CRDs. Related CRD collection is separate from the `--include-gk` filter. Kind filtering selects all objects of each listed kind, so review which projects and Applications belong in the migration, including any exported `default` project.

The four-kind export does not include configuration stored in Secrets or ConfigMaps. Inventory these dependencies and either recreate them on the target or export the selected configuration separately:

| Resource | When needed |
| --- | --- |
| Repository and `repo-creds` Secrets | Authentication to private Git, Helm, or OCI repositories. Preserve the `argocd.argoproj.io/secret-type` labels. |
| Cluster registration Secrets | Applications use a registered destination name or an external cluster. Reissue credentials and map endpoints/CA data when the destination changes. |
| Trust and configuration ConfigMaps | Custom repository CA certificates, SSH known hosts, RBAC, notifications, or other settings not fully represented in the instance CR. Use the operator's supported configuration mechanism. |
| Referenced Secrets | SSO, webhooks, TLS, or other enabled integrations depend on them. Check whether the target operator or another controller should recreate them. |

Adding `--include-gk Secret` or `--include-gk ConfigMap` exports every object of that kind in the namespace, including generated configuration and credentials. The kind filter cannot select only repository or cluster Secret subtypes. A separate label-filtered export can select a known Secret subtype, but it does not collect that resource's dependencies.

Create target Namespaces, managed-namespace labels, and required permissions separately. Filtering the export does not replace the Argo-specific transformations described below.

Secrets, ConfigMaps, and other namespaced resources are also eligible. Export does not use `ownerReferences` to exclude them.

Export covers one namespace per invocation. Applications in other namespaces require additional exports. A label selector is not a dependency collector and can omit a required project, credential, or parent resource.

Crane also collects selected related cluster-scoped RBAC/SCC resources and attempts to collect CRDs backing exported custom resources. When its metadata heuristic identifies an operator-managed CRD, it skips that CRD and tells the user to install the operator on the target. This heuristic is not proof that every operator-managed CRD will be recognized.

Per-resource list failures can appear under `export/failures/<namespace>/` without making the whole export fail. A successful command exit alone does not prove that all GitOps resources and credentials were captured.

Sources: [discovery and dynamic listing][crane-discovery], [export orchestration and flags][crane-export], [related CRD handling][crane-crd], [cluster resource filtering][crane-cluster].

### Transform

The embedded Kubernetes plugin handles unstructured objects. It removes common server-managed metadata and `status` from surviving custom resources. It does not need a special Argo CD implementation to perform that cleanup.

The most important default is broader than the option's help text suggests:

> Any object with at least one `ownerReference` is omitted from the transformed output.

This affects operator-generated resources and Applications owned by an ApplicationSet. The filter checks for any owner reference, not just controller references or workload kinds.

For an ApplicationSet, preserving the parent and letting the target ApplicationSet controller regenerate its Applications is normally appropriate. However, the parent's generators must still work on the target. Cluster generators depend on registered clusters, labels, and credentials; Git generators depend on repository access. Live edits to generated Applications are not necessarily represented in the parent definition.

The same ownership rule can lose configuration that is not fully recoverable from the parent CR. An operator-owned ConfigMap or Secret may contain user changes or instance identity data that the target operator will not reproduce. Its omission must be evaluated by content and configuration ownership, not assumed harmless.

`--optional-flags '{"disable-whiteout-owned":"true"}'` disables the ownership exclusion. It is not a complete migration recipe. It retains generated resources and source owner UIDs, and other exclusion rules still apply. Any selected resource retained this way needs an explicit ownership decision and cleanup before deployment.

Crane's built-in plugin does not remap Argo CD destinations, Git references, project policies, SSO settings, or encoded cluster credential data. It does not generally remove Argo finalizers or the Application's top-level `operation` field. An exported in-flight operation therefore needs explicit review and removal for a clean bootstrap.

Sources: [ownership filtering][lib-whiteouts], [generic fields stripped][lib-fields], [embedded plugin registration][crane-plugins].

### Apply

`crane apply` builds the final transformation stage with embedded Kustomize and writes an output bundle and individual manifests. It does not contact the target cluster, wait for an operator, or check whether Git repositories and destination clusters are reachable.

`--skip-cluster-scoped` can omit cluster-scoped output when the target platform already provides it. It also omits any required custom cluster RBAC, so it is not a substitute for deciding which prerequisites the target needs.

Sources: [apply command][crane-apply], [manifest generation][crane-kustomize].

## Resource-by-resource assessment

| Resource or configuration | Export and default transform | Target migration action |
| --- | --- | --- |
| `ArgoCD` instance CR | Exportable; survives if it has no owner references | Adjust target-specific CR settings and create it under the target operator. Check whether the operator already created a default instance with the same identity. |
| Standalone `Application` | Exportable; survives if it has no owner references | Map destinations and Git references; initially disable automated sync. |
| `ApplicationSet` | Exportable; survives if it has no owner references | Adapt templates, generator inputs, credentials, and cluster selectors; regenerate child Applications on the target. |
| ApplicationSet-generated `Application` | Exportable; omitted because it has an owner reference | Migrate the parent definition. Check whether live-only overrides need to become part of that definition. |
| `AppProject` | Exportable; survives if it has no owner references | Adapt allowed destinations, source repositories, source namespaces, and role policies. Reconcile with any target-created `default` project. |
| Repository and `repo-creds` Secrets | Exportable; survive unless ownership or another exclusion rule applies | Preserve the Argo secret-type labels. Verify the credentials still work from the target. |
| Cluster registration Secrets | Exportable; survive unless ownership or another exclusion rule applies | Decide whether each registration remains external or must point to the new local cluster. Update endpoint, CA, authentication, and namespace restrictions as needed. |
| Operator-managed ConfigMaps and Secrets | Exportable; omitted if owned | Recover desired settings through the operator CR or the operator's supported configuration mechanism. Handle needed identity data explicitly. |
| Operator-generated Deployments, Services, and RBAC | Exportable within Crane's scope; owned objects are omitted | Let the target operator regenerate them. Review unowned generated objects separately. |
| Namespace objects and their labels | Not exported by the normal namespace discovery path | Create target namespaces and required labels separately. This includes operator-specific managed-namespace labels. |
| Git repositories, Helm/OCI content, external identity providers | References may be exported; external content/services are not | Keep them accessible or migrate them separately and update references. |

An `app.kubernetes.io/managed-by` label or an Argo tracking annotation is not an `ownerReference`. Crane's ownership exclusion will not remove an object merely because it has such a label or annotation. Inspect the actual metadata.

## Required Argo CD-specific transformations

At minimum, inspect these fields and configuration areas:

- `Application.spec.destination.server`, `.name`, and `.namespace`.
- `Application.spec.source` and `.sources`, including repository URL, revision, path, Helm values, and Kustomize settings.
- ApplicationSet templates, generator-specific templates, `templatePatch`, and generator inputs. Destination information may be generated rather than written directly in the main template.
- `AppProject.spec.destinations`, `.sourceRepos`, `.sourceNamespaces`, and any namespace-dependent role policies.
- Cluster registration Secret data, particularly `server`, `config`, and namespace restrictions. Exported `data` values are base64 encoded; a text substitution on a plain URL will not update them.
- `ArgoCD.spec` hostnames, ingress/Route configuration, SSO/OIDC redirect URLs, certificate references, repository trust settings, node placement, and external service references as applicable.
- Object namespaces and references to the Argo CD namespace in RBAC, operator settings, and managed-namespace labels.
- Finalizers and any top-level Application `operation`. Generic status removal does not address these fields.

`https://kubernetes.default.svc` normally means the cluster where the Argo CD controller runs. An Application using that local destination can keep the same URL and deploy to the target after migration. An explicit source API URL or a registered cluster name does not automatically change meaning when copied.

Changing `metadata.namespace` alone does not rewrite all of these custom-resource fields.

Sources: [declarative setup][argo-declarative], [ApplicationSet resource handling][argo-appset], [applications in other namespaces][argo-any-namespace], [operator instance setup][operator-basics], [operator namespace permissions][operator-namespaces].

## Suggested migration procedure

1. Install the compatible operator and CRDs on the target. Configure its watched namespaces and required cluster permissions. Determine whether it also creates a default Argo CD instance, since installing an operator and creating an instance are separate concerns.
2. Inventory the source instance CR, projects, Applications, ApplicationSets, configuration, and credentials. Include Applications in additional namespaces and configuration managed by other operators, such as external secret controllers.
3. Export each relevant namespace to its own directory. Inspect the failure files and compare the exported GitOps resource names with the live inventory.
4. Run the Kubernetes cleanup stage. Compare export and output inventories, with particular attention to owned objects that disappeared.
5. Add a manual Kustomize stage or a custom transformation for the Argo-specific mappings above. Recover needed configuration that the generic ownership filter omitted. Do not enable ownership retention globally without reviewing the additional objects it keeps.
6. Generate manifests with `crane apply`. Divide the reviewed result into an instance/configuration phase and a GitOps-definition phase for deployment.
7. Create the target namespaces and apply the `ArgoCD` CR and required configuration through the operator's supported mechanisms. Wait for the instance to become ready. Verify repository authentication, trust, and destination-cluster access.
8. Apply projects, then standalone Applications and ApplicationSets. Initially remove `spec.syncPolicy.automated` from standalone Applications and from the effective ApplicationSet templates, including overrides. On versions supporting it, `automated.enabled: false` is another explicit way to disable auto-sync.
9. Check the generated Applications and rendered desired manifests. Update the Git source or select a target-specific overlay so Argo CD will maintain the migrated configuration. Then enable synchronization as part of cutover.

App-of-apps and self-managed Argo CD installations require the same changes in their Git definitions. Patching only the exported live resources allows the parent Application or ApplicationSet to restore the old settings.

Copying an Application with automated sync enabled can immediately deploy resources. Copying an external cluster registration can also leave the new controller managing the original source cluster. Initial sync control and explicit destination mapping are part of making this migration work correctly.

### Example export and generic cleanup

These commands illustrate the file-processing phase for one instance namespace. They do not include the required Argo-specific stage or deploy anything to a cluster.

```bash
crane export --context source -n argocd \
  --include-gk argoproj.io/ArgoCD \
  --include-gk argoproj.io/Application \
  --include-gk argoproj.io/ApplicationSet \
  --include-gk argoproj.io/AppProject \
  --crd-skip-group argoproj.io \
  --export-dir export-argocd
crane transform KubernetesPlugin \
  --export-dir export-argocd \
  --transform-dir transform-argocd

# Add and review Argo-specific transformations before generating final output.
crane apply --transform-dir transform-argocd --output-dir output-argocd
```

Retaining the source namespace name reduces remapping work, but target destinations and operator configuration still require review.

## Validation for broader end-to-end coverage

A useful test should include:

- An operator-managed `ArgoCD` CR and a separately maintained `AppProject`.
- A standalone Application using the local Kubernetes API destination.
- An ApplicationSet with generated Applications, including a generator that depends on cluster registrations or private Git access.
- A private repository credential Secret and custom repository trust configuration.
- An operator-owned configuration object containing a user setting, to verify that the setting reaches the target despite ownership filtering.
- An explicit source-cluster destination and cluster credential Secret, to verify mapping rather than accidental reconnection to the source.
- A second Application namespace if the source uses that feature.

Success means the target operator creates a healthy instance, all intended projects and Applications appear, ApplicationSet children regenerate, private repositories authenticate, and a controlled sync creates the expected workload on the intended target. It also means Argo CD keeps the target settings after another reconciliation.

Run server-side dry-run validation on each deployment phase once its namespaces and API prerequisites exist. This catches API/schema/admission issues, but does not prove successful operator reconciliation, repository authentication, generator output, or GitOps behavior.

The defensible current capability statement is:

> Crane can migrate Argo CD resource manifests using its generic Kubernetes workflow. A live operator-assisted minikube-to-kind scenario passed with explicit resource selection, target mappings, credential setup, and staged deployment. Broader Argo CD migration support still requires configuration-specific validation; Crane does not provide this complete recipe as a built-in workflow.

## References

[crane-discovery]: https://github.com/migtools/crane/blob/203065a3a3cd9979a245a80b1472346d61c564af/cmd/export/discover.go
[crane-export]: https://github.com/migtools/crane/blob/203065a3a3cd9979a245a80b1472346d61c564af/cmd/export/export.go
[crane-crd]: https://github.com/migtools/crane/blob/203065a3a3cd9979a245a80b1472346d61c564af/cmd/export/crd.go
[crane-cluster]: https://github.com/migtools/crane/blob/203065a3a3cd9979a245a80b1472346d61c564af/cmd/export/cluster.go
[lib-whiteouts]: https://github.com/migtools/crane-lib/blob/926a5ffd044f510bb8175ed8ed4b07e052057b16/transform/kubernetes/kubernetes.go#L340-L397
[lib-fields]: https://github.com/migtools/crane-lib/blob/926a5ffd044f510bb8175ed8ed4b07e052057b16/transform/kubernetes/kubernetes.go#L79-L92
[crane-plugins]: https://github.com/migtools/crane/blob/203065a3a3cd9979a245a80b1472346d61c564af/internal/plugin/plugin_helper.go#L41-L45
[crane-apply]: https://github.com/migtools/crane/blob/203065a3a3cd9979a245a80b1472346d61c564af/cmd/apply/apply.go
[crane-kustomize]: https://github.com/migtools/crane/blob/203065a3a3cd9979a245a80b1472346d61c564af/internal/apply/kustomize.go
[argo-declarative]: https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/
[argo-appset]: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Controlling-Resource-Modification/
[argo-any-namespace]: https://argo-cd.readthedocs.io/en/stable/operator-manual/app-any-namespace/
[operator-basics]: https://github.com/redhat-developer/gitops-operator/blob/f55d6713c0154ee02b73cb7d09d30c7a63a081b5/docs/usage/basics.md
[operator-namespaces]: https://github.com/redhat-developer/gitops-operator/blob/f55d6713c0154ee02b73cb7d09d30c7a63a081b5/docs/usage/deploy-to-different-namespaces.md

- [Argo CD automated sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/).
- [Argo CD disaster recovery](https://argo-cd.readthedocs.io/en/stable/operator-manual/disaster_recovery/) documents Argo's own admin export/import workflow. Crane does not invoke that workflow.

Other GitOps controllers, such as Flux, need a separate resource and reconciliation assessment. Generic CR export alone does not establish that their configuration will function on the target.
