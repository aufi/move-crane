# Offline test record

Date: 2026-11-10.

## Environment

- Official `migtools/crane` release `v0.11.0`, Linux amd64.
- Crane reports SHA `8844161b3e5a9df01886f5c07e48668ff06fe8c7`.
- crane-lib reports version `v0.0.10`; the release source pins commit `f8e16a055cd666b01c5fca484fa58d6c3238651b`.
- Embedded Kustomize reports version `v5.8.1`.
- Binary SHA-256 `3ab010981c47523c46092a836cedecfcbd596881542695ac9ea4a76a76552469`, verified against the release's `checksums.txt`.
- Python 3 with PyYAML `6.0.3`.

The installed development binary and local modified Crane source were not used for this run.

## Command

Run from the planning repository root:

```bash
python3 playground/argocd-migration/test_offline.py \
  --crane /tmp/opencode/argocd-crane-v0.11.0/crane_linux_amd64 \
  --work-dir /tmp/opencode/argocd-release-test-final
```

Result: **14 tests passed**, no failures or errors.

## Cases checked

1. Generic cleanup preserves custom-resource specifications while removing status and server metadata. Top-level Application operations and lifecycle finalizers survive the baseline.
2. Default ownership filtering drops the ApplicationSet child, operator-owned RBAC ConfigMap, and operator-owned server Deployment.
3. Ownership retention keeps the generated objects and their original owner references.
4. Namespace-only transformation leaves Argo destinations and decoded cluster registration data pointing to the source.
5. Local and explicit Application destinations and source overlay/revision mappings are correct.
6. Named destinations and multi-source Helm value-file mappings are correct; unrelated chart/ref settings remain intact.
7. ApplicationSet list inputs, Git inputs, main templates, and generator-level destination overrides contain target values.
8. Automated sync is absent in standalone Applications and all fixture ApplicationSet templates, including generator-level overrides.
9. The copied Application operation and stale source tracking metadata are removed; the lifecycle finalizer and unrelated label remain.
10. AppProject destination permissions, additional Application namespace, repository allowlist, and namespace-dependent role policy match the target scenario.
11. Cluster credentials and generator-selection labels are replaced, while repository credentials and Argo secret-type labels remain correct.
12. The owned ConfigMap's user RBAC configuration is recovered through the ArgoCD CR. Generated children and source owner references are absent from the target bundle.
13. Object namespaces, additional Application namespace settings, workload namespace label, and cross-namespace RoleBinding subjects are mapped; the unrelated SA namespace remains intact.
14. A second full build produces the same parsed resource set, and input fixture/export hashes remain unchanged.

## Resource counts

| Pipeline | Resource count | Explanation |
| --- | --- | --- |
| Synthetic source | 13 | Instance, project, 4 Applications, 2 ApplicationSets, 2 Secrets, owned ConfigMap, owned Deployment, RoleBinding |
| Default Kubernetes stage | 10 | Three owned resources omitted |
| Ownership retention experiment | 13 | All source objects retained, including generated children and source owner references |
| Target stage | 13 | Ten surviving source resources transformed, three target Namespaces added |

## Local artifacts

The recorded run retained its artifacts under `/tmp/opencode/argocd-release-test-final/`:

- `command-*.log` records the CLI arguments and output, including `version`.
- `default-transform/10_KubernetesPlugin/` contains Crane's generated cleanup patches and commented ownership exclusions.
- `default-output/output.yaml` is the generic baseline.
- `retain-owned-output/output.yaml` demonstrates retained source ownership.
- `namespace-only-output/output.yaml` demonstrates incomplete namespace-only migration.
- `target-output/output.yaml` is the transformed target bundle.
- `replay-target-output/output.yaml` is the independent repeatability build.

These temporary paths are local run artifacts. The fixtures, stage, and runner reproduce them in any new work directory.

No live export, API/schema validation, operator reconciliation, ApplicationSet generation, repository authentication, or workload synchronization was performed.
