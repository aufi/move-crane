# Live Argo CD migration from minikube to kind

The live test passed on 2026-11-10. Four Applications became `Synced` and `Healthy` on kind, including two recreated by an ApplicationSet. Their HTTP responses contained target-specific content. The source Deployments retained their UIDs, readiness, and source-specific content.

See [RESULTS.md](RESULTS.md) for the observed transformations and limitations.

## Running environment

| Component | Source | Target |
| --- | --- | --- |
| Kubernetes | Existing minikube, v1.35.1 | New kind cluster, v1.35.0 |
| Context | `minikube` | `kind-crane-argocd-target` |
| Argo CD namespace | `crane-gitops-source` | `crane-gitops-target` |
| Argo CD instance | `crane` | `crane` |
| Operator | argocd-operator v0.18.0 | Same |
| Argo CD | v3.3.10 | Same |
| Git fixture namespace | `crane-git-source` | `crane-git-target` |

The target uses rootless Podman and kind v0.31.0. Its kubeconfig is separate from the user's default kubeconfig:

```text
/tmp/opencode/argocd-live/kind.kubeconfig
```

Both operators run in `argocd-operator-system`. The operator is cluster-scoped for the test instance namespaces through `ARGOCD_CLUSTER_CONFIG_NAMESPACES`. Workload namespaces have the corresponding `argocd.argoproj.io/managed-by` label.

## Sample application

The sample is a stateless BusyBox HTTP server, a Service, and a ConfigMap. Git contains `overlays/source` and `overlays/target`, with different HTTP response content.

| Application | Source destination | Target destination |
| --- | --- | --- |
| `local-web` | Local API, `crane-payments-source` | Local API, `crane-payments-target` |
| `explicit-web` | Minikube API URL, `crane-ledger-source` | Local kind API, `crane-ledger-target` |
| `fleet-blue` | Registered cluster `minikube-workloads`, `crane-fleet-source-blue` | `kind-workloads`, `crane-fleet-target-blue` |
| `fleet-green` | Registered cluster `minikube-workloads`, `crane-fleet-source-green` | `kind-workloads`, `crane-fleet-target-green` |

The last two Applications come from the `fleet` ApplicationSet. They are excluded by Crane's default ownership filter and recreated by the target ApplicationSet controller.

The repository fixture is a read-only Git daemon inside each cluster. The repository URL therefore changes during migration. There is no external Git hosting account or published repository. Both fixtures initialize the same deterministic commit from [git-fixture.yaml](git-fixture.yaml), then Argo CD renders the selected environment overlay.

## Reproduce in a fresh test environment

Requirements are `kubectl`, minikube, kind, a working container runtime, Python 3 with PyYAML, and the official Crane v0.11.0 binary. The clusters need image-registry access. The disposable Git container installs Alpine's separate `git-daemon` package on startup and needs Alpine package-repository access.

Run commands from the planning repository root. The commands below show the paths used in the recorded run. Choose a fresh artifact directory and fresh target test namespaces for a new migration run. The migration phase intentionally does not overwrite existing Crane output directories.

### 1. Create the target cluster

```bash
mkdir -p /tmp/opencode/argocd-live
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster \
  --name crane-argocd-target \
  --image kindest/node:v1.35.0 \
  --kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --wait 180s
```

### 2. Install the operator on both clusters

[operator/kustomization.yaml](operator/kustomization.yaml) uses the upstream v0.18.0 manual installation and its pinned operator image digest. It enables cluster-scoped instance configuration for the two test namespaces. No OLM or conversion webhook is required for the v1beta1 instance CR used here.

```bash
kubectl --context minikube apply --server-side \
  -k playground/argocd-migration/live/operator
kubectl --context minikube -n argocd-operator-system rollout status \
  deployment/argocd-operator-controller-manager --timeout=180s

kubectl --kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --context kind-crane-argocd-target apply --server-side \
  -k playground/argocd-migration/live/operator
kubectl --kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --context kind-crane-argocd-target -n argocd-operator-system rollout status \
  deployment/argocd-operator-controller-manager --timeout=180s
```

### 3. Create and validate the source

```bash
python3 playground/argocd-migration/live/run_live.py source \
  --target-kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --work-dir /tmp/opencode/argocd-live/run \
  --crane /tmp/opencode/argocd-crane-v0.11.0/crane_linux_amd64
```

This installs the Git fixture, creates the operator-managed instance and workload namespaces, registers the explicit minikube destination, and creates a repository Secret, project, two standalone Applications, and an ApplicationSet. It waits for four healthy/synced Applications and checks HTTP responses. It saves source Deployment identities for the later comparison.

### 4. Export, transform, and restore with sync paused

```bash
python3 playground/argocd-migration/live/run_live.py migrate \
  --target-kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --work-dir /tmp/opencode/argocd-live/run \
  --crane /tmp/opencode/argocd-crane-v0.11.0/crane_linux_amd64
```

This phase performs a real namespace export and runs Crane's KubernetesPlugin and apply commands. It records the complete export and baseline inventories, then builds `50_ArgoTarget` from six selected, materialized baseline objects:

- The `ArgoCD` CR.
- The sample `AppProject`.
- Two standalone Applications.
- The `ApplicationSet`.
- The repository Secret.

It generates explicit JSON Patch operations for the repository URL, Git overlay path, application destinations, project permissions, ApplicationSet inputs, and sync policy. It rebuilds cluster registration with target-issued credentials instead of copying the source token and CA.

The target operator and namespaces exist before restore. The runner validates the instance and definition phases with server-side dry runs, waits for instance readiness, restores definitions, and confirms that four Applications exist with sync paused and no workload Deployments have started.

Only the six selected objects enter the final Crane bundle. The manually installed target operator supplies its CRDs and RBAC. The test creates target cluster registration separately with a token issued by the target API.

### 5. Sync and verify

```bash
python3 playground/argocd-migration/live/run_live.py verify \
  --target-kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --work-dir /tmp/opencode/argocd-live/run \
  --crane /tmp/opencode/argocd-crane-v0.11.0/crane_linux_amd64
```

The runner requests a manual sync through each Application's Kubernetes API object. It checks all target HTTP responses, requests hard refreshes, waits for controller acknowledgement, and requests another ApplicationSet reconciliation. It verifies that sync remains disabled, generated Applications point to the new target parent UID, and source workload identities and responses match the saved baseline.

The test leaves automated sync disabled on the target. Further manual syncs can use the same `verify` phase.

## Inspect the running test

### Export only Argo CD custom resources

This filtered export was also executed against the live source with Crane v0.11.0:

```bash
crane export --context minikube -n crane-gitops-source \
  --include-gk argoproj.io/ArgoCD \
  --include-gk argoproj.io/Application \
  --include-gk argoproj.io/ApplicationSet \
  --include-gk argoproj.io/AppProject \
  --crd-skip-group argoproj.io \
  --export-dir export-argocd-only
```

`--include-gk` selects object kinds. `--crd-skip-group argoproj.io` separately suppresses related CRD collection because the target operator already supplies those definitions.

The filtered source contained eight CRs. Default KubernetesPlugin cleanup produced six: the instance CR, two standalone Applications, the ApplicationSet, and two projects, including `default`. The two owned ApplicationSet children were omitted.

The output still contained the source namespace, source Git URL and overlay paths, explicit minikube API URL, registered cluster name, project permissions, ApplicationSet namespace inputs, and enabled automated sync. Therefore default cleanup alone did not produce the working target configuration. The instance CR's `spec` needed no additional changes in this sample; the application definitions did.

The four-kind filter excludes Secrets and ConfigMaps. Configure required repository credentials, cluster registrations, and trust separately on the target, or export selected configuration through an additional reviewed step. Adding `--include-gk Secret` exports all Secrets in the namespace, including operator-generated credentials; the kind filter cannot select only Argo repository/cluster Secret subtypes. The sample repository is public, but its named destination still requires target cluster registration.

Filtered artifacts are under `/tmp/opencode/argocd-live/include-gk/`. This follow-up generated and inspected default output; the already running target retained the successfully transformed configuration.

### Check Applications

```bash
kubectl --context minikube -n crane-gitops-source get applications,argocd
kubectl --kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --context kind-crane-argocd-target -n crane-gitops-target get applications,argocd
```

For the target UI:

```bash
kubectl --kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --context kind-crane-argocd-target -n crane-gitops-target \
  port-forward service/crane-server 8082:80
```

The test instance uses HTTP, so open `http://localhost:8082`. The login is `admin`. Retrieve the target-generated initial password locally when needed:

```bash
kubectl --kubeconfig /tmp/opencode/argocd-live/kind.kubeconfig \
  --context kind-crane-argocd-target -n crane-gitops-target \
  get secret crane-cluster -o jsonpath='{.data.admin\.password}' | base64 -d
```

Cluster registration uses disposable ServiceAccount tokens requested for four hours. To renew them for further testing, run the same runner with phase `refresh-credentials` and the arguments above.

## Artifacts

The recorded run is under `/tmp/opencode/argocd-live/run/`:

- `export/` contains the complete live export and its failure directory.
- `baseline/` contains output from the default Kubernetes stage.
- `transform/50_ArgoTarget/` contains the selected baseline manifests and generated patches.
- `target-output/output.yaml` contains the six-resource target bundle.
- `inventory.json` lists exported and baseline identities and export failure filenames.
- `source-snapshot.json` and `live-results.json` record workload identities, HTTP responses, and controller results without Secret values.
- `target-cluster-secret.yaml` contains the separately generated target registration.

The work directory has mode 0700. Raw export/baseline artifacts contain real local credentials and operator keys, so keep them outside version control. The checked-in files contain no live credentials.
