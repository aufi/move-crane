# Argo CD migration transformations, offline experiment

This experiment runs the real Crane CLI against synthetic exported manifests and tests an explicit target Kustomize stage. It identifies which Argo CD migration changes Crane's generic cleanup performs and which changes need a custom stage.

**Result: all 14 offline tests passed with the official Crane v0.11.0 Linux amd64 release.** See [the test record](RESULTS.md).

A subsequent [live minikube-to-kind migration](live/README.md) also passed. Four target Applications synchronized and served target-specific HTTP content; source workload identities and responses remained unchanged. See [the live results](live/RESULTS.md).

For the smallest tested custom stage, see the [minimal same-namespace live example](live/same-namespaces/minimal/README.md). It keeps namespaces, Git references, the portable fleet destination, and automated sync unchanged. Only the explicit Application's API URL and its project destination permission need JSON Patch operations.

## Files

- [fixtures/source.yaml](fixtures/source.yaml) contains 13 synthetic resources across three namespaces. The test runner splits them into an export-shaped directory.
- [target-stage/kustomization.yaml](target-stage/kustomization.yaml) contains the target-specific RFC 6902 patches.
- [target-stage/namespaces.yaml](target-stage/namespaces.yaml) supplies namespaces that normal Crane namespace export does not capture.
- [test_offline.py](test_offline.py) invokes Crane and checks both incomplete recipes and the target stage.

All credentials and certificates are dummy values. The fixtures and output are not deployable examples.

## Tested migration scenario

| Source | Target |
| --- | --- |
| Argo CD instance namespace `gitops-source` | `gitops-target` |
| Workload namespace `payments-source` | `payments-target` |
| Additional Application namespace `team-apps-source` | `team-apps-target` |
| Explicit API URL `https://api.source.example.test:6443` | `https://api.target.example.test:6443` |
| Registered destination name `source-workloads` | `target-workloads` |
| Local destination `https://kubernetes.default.svc` | Unchanged |
| Git revision `main` | `migration-target` |
| Git paths containing the source environment | Corresponding target environment paths |
| Instance hostname `argocd.source.example.test` | `argocd.target.example.test` |

The scenario uses an OpenShift-style operator-managed instance with Route configuration. The additional Application namespace requires the target operator's cluster-scoped configuration and apps-in-any-namespace support. The test checks the manifests for that setup, but does not run the operator.

## Run

Requirements are Python 3, PyYAML, and a Crane CLI with multi-stage Kustomize support. Use the [official v0.11.0 release](https://github.com/migtools/crane/releases/tag/v0.11.0) to reproduce the recorded result.

From this directory:

```bash
python3 test_offline.py --crane /path/to/crane
```

To choose where artifacts are retained, pass a new directory:

```bash
python3 test_offline.py --crane /path/to/crane \
  --work-dir /tmp/argocd-migration-experiment
```

The runner prints the artifact path and preserves command logs, Crane patches, baseline output, incomplete-recipe output, and the transformed target bundle. It uses an isolated home directory and no kubeconfig. It does not invoke `crane export` or contact a Kubernetes cluster.

The tested pipeline is:

1. Split the fixture into an export-shaped resource tree.
2. Run `crane transform KubernetesPlugin` and `crane apply` to observe the default behavior.
3. Test `disable-whiteout-owned=true` separately.
4. Build a namespace-only stage separately to demonstrate its missing mappings.
5. Copy `target-stage/` to `transform/50_ArgoTarget/` and run `crane apply 50_ArgoTarget`. That stage references `../10_KubernetesPlugin`, so the generic patches remain part of the build.
6. Rebuild the successful pipeline from the same source in a second directory and compare parsed output and input hashes.

The fixture's source namespaces are supplied together to the transformation stage. In a live migration, export each namespace separately, check the failures, and assemble the reviewed resources before using this pattern.

## Transformation findings

These changes reflect the scenario's migration decisions. A real instance needs its own mappings and ownership decisions.

| Area | What the experiment established | Example transformation |
| --- | --- | --- |
| Generic cleanup | Crane strips `status`, UID, and resource version from surviving custom resources. | Use the built-in Kubernetes stage first. |
| Owned objects | Crane omits the generated Application, server Deployment, and owned RBAC ConfigMap. | Keep parent CRs; recover needed configuration through the operator CR. |
| Ownership retention | Disabling ownership exclusion keeps generated objects and source owner UIDs. | Selective retention requires separate owner-reference cleanup. This experiment keeps default exclusion. |
| Object namespaces | A global `namespace:` does not update custom destination fields or encoded Secrets. It also collapses the distinct namespace layout. | Patch object namespaces with explicit source-to-target maps. |
| Local Application destination | The local Kubernetes API URL remains correct after moving the controller. | Keep the URL; change the workload namespace. |
| Explicit/named destinations | Neither an API URL nor a registered cluster name changes automatically. | Map the URL or name and the destination namespace. |
| Source definitions | Git revisions, overlay paths, and multi-source Helm values still reference the source environment. | Patch the selected source fields; preserve the chart version and `$values` reference identity. |
| ApplicationSets | Updating the main template alone leaves generator inputs and overrides unchanged. | Map list elements, Git directory/revision inputs, generator templates, and the main template. |
| Initial sync | Both standalone and generated Applications can retain automated sync settings. | Remove `automated` from standalone Applications, main templates, and generator-level overrides. |
| In-flight operation | `status` cleanup leaves the Application's top-level `operation`. | Remove the copied operation. |
| Tracking metadata | A source app-of-apps tracking annotation and instance label survive generic cleanup. | Remove them for an Application intentionally becoming standalone. Keep unrelated labels. |
| Lifecycle finalizers | Argo's resource-deletion finalizer survives cleanup. | Preserve it in this scenario. Removing all finalizers is not a required migration transformation. |
| Projects | Destination allowlists and additional Application namespaces must match the remapped Applications. | Map project destinations, `sourceNamespaces`, and namespace-dependent role policies. |
| Cluster credentials | Base64-encoded endpoint, token, CA, and namespace restrictions remain source-specific. | Replace the complete Secret payload with target credentials; preserve the `cluster` label and update generator-selection labels. |
| Repository credentials | The same Git repository needs no payload change in this scenario. | Preserve the encoded data and `repository` label; move the Secret to the target instance namespace. |
| Operator configuration | Default ownership filtering loses the user RBAC setting in the ConfigMap. | Copy its `policy.csv` and scopes into `ArgoCD.spec.rbac`; let the operator generate the ConfigMap. |
| Additional Application namespace | An Application outside the instance namespace needs matching operator and project settings. | Map both `ArgoCD.spec.sourceNamespaces` and `AppProject.spec.sourceNamespaces`. |
| Namespace permissions | Namespace labels and cross-namespace RBAC references are outside generic CR cleanup. | Add the workload's `managed-by` label and map the controller SA subject; preserve an unrelated SA namespace. |

The `team-apps-target` Namespace deliberately has no workload `managed-by` label. The operator's apps-in-any-namespace feature uses its own configuration and labeling for Application namespaces. See the [operator documentation](https://github.com/redhat-developer/gitops-operator/blob/f55d6713c0154ee02b73cb7d09d30c7a63a081b5/docs/usage/apps-in-any-namespace.md). Workload namespaces and Application-definition namespaces have different roles.

The namespace-dependent project role policy applies to the Application in `team-apps-target`. Applications in the Argo CD control-plane namespace use the usual two-component `<project>/<application>` policy form. Do not insert the control-plane namespace into those policies.

## How to adapt the stage

The patch targets and array indexes refer to these fixtures. JSON Patch `remove` and `replace` require the selected paths to exist. Inspect actual resources before adapting the patches. Do not run this fixture-specific stage against an arbitrary export unchanged.

The example uses explicit patches rather than a new plugin. It is a working experiment, not production migration automation. It demonstrates that standard Kustomize patches can express these transformations within Crane's output-generation workflow.

Repeatability here means rebuilding from the same immutable source produces the same parsed manifests. It does not mean applying a JSON Patch twice to an already transformed document; patches that remove fields are not generally valid a second time.

For a real deployment, apply the reviewed namespaces and instance configuration first, wait for the operator, then restore projects and GitOps definitions with sync paused. The generated bundle's document order is not an operator-readiness mechanism.

## Remaining validation

The tests inspect actual Crane/Kustomize output. They do not validate CRD schemas, start an operator, execute ApplicationSet generators, authenticate to repositories, or perform a sync.

Before relying on the recipe with real resources:

- Validate each deployment phase against the installed target CRDs and admission rules.
- Verify operator reconciliation, Route/SSO/certificates, namespace permissions, and needed instance identity data.
- Check generated Applications and rendered workloads against the intended destination.
- Make corresponding Git changes so reconciliation preserves the target settings.

Other generator types, Go templates and `templatePatch`, repository URL changes, `repo-creds` templates, external secret controllers, SSO migration, and existing target-instance conflicts need case-specific experiments.

Background research and source references are in [notes/gitops-resources/README.md](../../notes/gitops-resources/README.md).
