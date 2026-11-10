# CRC source deletion and fresh-target restore results

Date: 2026-11-10. **Result: passed with zero custom patch operations.**

## Execution

1. Started the existing CRC OpenShift 4.22.7 instance and installed argocd-operator v0.18.0 manually.
2. Provisioned Argo CD v3.3.10 and prepared the same namespace/connection layout planned for the target.
3. Created two standalone Applications and an ApplicationSet generating two more. All four synchronized and served the expected content through OpenShift Routes.
4. Exported seven CRs with Crane v0.11.0 and `--include-gk` restricted to Applications, ApplicationSets, and AppProjects. There were no export failure files.
5. Default KubernetesPlugin cleanup retained five objects. A resource-selection stage excluded the source default project, leaving four definitions with no additional changes.
6. Preserved Git, export, kubeconfig, and evidence on the host, then executed `crc stop` and `crc delete --force`.
7. Started a fresh CRC VM from the cached bundle. None of the test namespaces existed before bootstrap.
8. Independently installed the same operator and Argo CD before importing. Recreated namespace permissions and registered the new local cluster as `workloads` using a newly issued token.
9. Target server-side validation accepted all four definitions. Their automated sync created the application workloads.
10. All four Applications became `Synced` and `Healthy`, and all four Routes returned the same body and hostnames as the source.
11. Hard refresh and ApplicationSet reconciliation completed. Application specs and Git revisions matched the saved source values exactly.
12. Target namespace, Deployment, Route, Pod, Application, and Argo CD instance UIDs differed from the source. Import preserved the independently provisioned target instance and default project.

## Versions and resources

- CRC 2.63.0+3a67a3.
- OpenShift 4.22.7, Kubernetes v1.35.6, CRI-O 1.35.5.
- Six vCPUs, 14336 MiB RAM, 60 GiB configured disk.
- Community argocd-operator v0.18.0 via the same pinned image/configuration used in the minikube/kind experiments.
- Argo CD v3.3.10.
- Official Crane v0.11.0, embedded Kustomize v5.8.1.
- Host Git commit `37a2b1a9b1d95e1f2c52155e1827f05f3092438d`.

## Restored application checks

| Application | Target namespace | Destination | Sync | Health |
| --- | --- | --- | --- | --- |
| `local-web` | `crane-payments-crc` | Local API | Synced | Healthy |
| `explicit-web` | `crane-ledger-crc` | Registered local alias `workloads` | Synced | Healthy |
| `fleet-blue` | `crane-fleet-crc-blue` | Local API | Synced | Healthy |
| `fleet-green` | `crane-fleet-crc-green` | Local API | Synced | Healthy |

Every namespace has a `sample-web` Deployment, Service, ConfigMap, and admitted Route. Every Route returned:

```text
crane-crc-gitops restored-shared-content
```

The Route hosts were unchanged after reset. For example, `sample-web-crane-payments-crc.apps-crc.testing` worked on the fresh target.

## OpenShift-specific validation

All workload Pods ran under `restricted-v2`. The target assigned fresh namespace UID ranges rather than copying source Pod security identities:

| Workload namespace | Source container UID | Target container UID |
| --- | --- | --- |
| `crane-payments-crc` | 1000680000 | 1000670000 |
| `crane-ledger-crc` | 1000700000 | 1000680000 |
| `crane-fleet-crc-blue` | 1000710000 | 1000690000 |
| `crane-fleet-crc-green` | 1000720000 | 1000700000 |

Namespaces and workload objects were created anew through target setup and Argo CD reconciliation. The export contained only the GitOps definitions, so it did not carry source namespace UID-range annotations or admission-generated Pod fields.

## Why zero custom patches worked

- All definition and workload namespace names stayed the same.
- The host-retained Git repository kept the same reachable URL, revision, and manifest path across CRC deletion.
- Local destinations used `https://kubernetes.default.svc`.
- The named destination used the same alias `workloads` on both clusters. Its target credentials were provisioned outside the export.
- Project permissions already matched those portable destinations.
- Automated sync was intentionally preserved, allowing startup immediately after import.

The selection stage removed only the source default project from the bundle. No namespace, Git, destination, project-policy, or sync-policy fields were patched.

## Freshness evidence

`crc stop` and `crc delete --force` completed successfully, and the target started without any test namespaces. The recorded cluster IDs also changed:

- Source: `ac0fdab4-5952-4a3e-a206-12b7059c21c8`.
- Target: `1966e161-e0f8-4555-b6af-2ff976d365c6`.

CRC's cached bundle retained the same `kube-system` and Node UIDs and their original creation timestamps. Those values alone are therefore unsuitable for proving a reset. The runner checked absence of all test namespaces before bootstrap and fresh UIDs for all restored test objects instead.

## Fixture networking finding

`host.crc.testing` resolved to `192.168.127.254` but Git connections timed out. Using the host LAN address `192.168.8.125` succeeded from the repo server after publishing the read-only host Git service on port 9418. Both source and target used that same URL. The server and repository remained running throughout CRC stop/delete/start.

## Evidence location

The complete host-side record is `/tmp/opencode/argocd-crc/`, particularly:

- `crc-results.json`, with specs/revision checks, source/target UIDs, SCCs, and HTTP responses.
- `reset-complete.json` and private CRC stop/delete/start logs.
- `target-cluster.json`, recording absent test namespaces before target bootstrap.
- `target-output/output.yaml`, the restored four-resource bundle.
- `transform/50_SelectedDefinitions/kustomization.yaml`, containing only a resource list.

The recreated CRC cluster and host Git container remain running for inspection. This was a stateless, public-repository restore; it does not establish PVC data migration, private credential migration, SSO, or Red Hat OpenShift GitOps Operator lifecycle support.
