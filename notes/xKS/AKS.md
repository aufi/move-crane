# AKS to OpenShift migration plan

## Goal and current status

Prepare workload migration from Azure Kubernetes Service to an exact OCP 4 or OCP 5 target profile. Assess manifest portability and persistent data separately, following [provider validation](PROVIDER_VALIDATION.md). A successful Kubernetes API request does not prove that the application works.

This is a research and validation plan. No AKS-to-OCP cluster tests are recorded here. All profiles start as `Unknown`. Documentation and source-code review below establish test requirements, not a support claim. OCP 5 also requires the [target-major enablement gates](OCP_TARGET_VERSIONS.md).

The workflow stays CLI-only and file-based. Discovery reads existing cluster and Azure configuration. Crane does not install operators, CRDs, or cloud integrations. Application owners and platform administrators prepare target prerequisites outside Crane.

## First delivery

The first validation increment covers Linux workloads on AKS Standard, with Azure Disk filesystem PVCs and a single known HTTP ingress implementation. Select one exact OCP 4 target release and record it before testing. Add private-network, identity, RWX, and Gateway API cases as separate increments.

This ordering does not remove the OCP 5, private-topology, or RWX requirements from the overall plan. Support claims must name the completed increment and exact profile.

The first run must produce:

- an inventory of application objects and their Azure dependencies,
- an explicit decision for every non-portable field or resource,
- auditable transformation artifacts and a functional stateless workload,
- a verified Azure Disk to target CSI transfer and application cutover,
- a report using [VALIDATION_REPORT_TEMPLATE.md](VALIDATION_REPORT_TEMPLATE.md), including failures and untested cases.

## Reference profiles

Treat API access, pod egress, application exposure, and storage as independent dimensions. A private AKS API can coexist with pod access to an OCP router. A public AKS API does not prove that pods can reach that router.

| Profile | API and transfer connectivity | Application exposure | Storage and purpose |
| --- | --- | --- | --- |
| AKS-public | CLI reaches both APIs; source mover reaches OCP router | One recorded Ingress implementation | Azure Disk CSI filesystem RWO baseline |
| AKS-private-direct | Private AKS API reachable from CLI; private or permitted public path to OCP router | Private Ingress or LoadBalancer | Azure Disk; prove that private API does not force indirect transfer |
| AKS-private-indirect | CLI reaches both APIs; mover cannot reach OCP router; both clusters reach staging storage | Private endpoint | Azure Disk; validate explicit indirect fallback |
| AKS-RWX-SMB | Use a recorded connectivity profile | Profile-dependent | Azure Files SMB to target RWX filesystem |
| AKS-RWX-NFS | Use a recorded connectivity profile | Profile-dependent | Azure Files NFS, tested separately from SMB |
| AKS-Gateway | Use a recorded connectivity profile | Gateway API with identified controller | Test GatewayClass mapping and route semantics |
| AKS-identity | Use a recorded connectivity profile | Profile-dependent | Application accesses Azure through Entra Workload ID or Key Vault CSI |

For each profile, record AKS Standard or Automatic, exact Kubernetes version, region, node pools, OS and architecture, network plugin and mode, data plane, network policy, outbound type, ingress controller, CSI versions, and source StorageClass definitions. Managed add-ons can change independently of an AKS minor upgrade.

Repeat each claimed profile against each exact target OCP release. Target infrastructure matters too. OCP on Azure may provide Azure CSI or load balancer integrations, but that does not make the source disk, subnet, identity, or private endpoint reusable.

Windows containers, virtual nodes, raw block PVCs, Azure Blob CSI, and Azure Container Storage require separate assessments. The Linux filesystem baseline does not establish their support. Application calls to Blob Storage, Azure SQL, Cosmos DB, or Service Bus are external-service dependencies, not PVC transfers.

## Discovery and retained evidence

Use the read-only commands in [AKS_DISCOVERY.md](AKS_DISCOVERY.md) together with general source/target API discovery. Missing permissions produce `unknown`, not an assumption that the dependency is absent.

Create one dependency register per application:

| Field | Required content |
| --- | --- |
| Object | Group/version/kind, namespace, name, and relevant field path |
| Dependency | Controller, identity, class, node property, Azure service, or network path |
| Source evidence | Inventory file and object reference |
| Target decision | Retain, transform, replace, prerequisite, omit, or unknown |
| Target evidence | Available API/controller, configured identity, storage capability, or runtime check |
| Owner and gate | Who prepares the prerequisite and which test proves it |

Use the classification meanings in [API_RESOURCE_COMPATIBILITY.md](API_RESOURCE_COMPATIBILITY.md). An ordinary Service or Deployment can still contain a non-portable dependency. Classify its affected fields as well as its kind.

### Azure-specific dependency matrix

| Source signal | Migration decision | Evidence needed before cutover |
| --- | --- | --- |
| `service.beta.kubernetes.io/azure-*` annotations | Map individual annotations to target exposure settings; remove only after that decision | Private/public scope, IP allocation, health probes, source-IP behavior, and any Private Link clients |
| `appgw.ingress.kubernetes.io/*`, Azure ingress class, or managed NGINX class | Select target controller or replace supported rules with OCP Routes | Host/path/TLS, rewrites, backend protocol, affinity, auth, WAF, and timeouts |
| Gateway API objects and controller-specific policies | Retain only with a compatible target implementation and mapped parent/class references | Listeners, filters, backend weights, cross-namespace references, and accepted/programmed status |
| `azure.workload.identity/use` pod label and ServiceAccount client/tenant annotations | Target identity prerequisite, or an explicit application authentication change | New target issuer trust, subject, audience, token projection, and a real Azure operation |
| Injected `AZURE_*` environment variables, projected tokens, or identity proxy sidecar | Determine whether source admission injected them; regenerate through the selected target integration | Deployment template and actual Pod comparison; token refresh after restart |
| Legacy pod identity resources or IMDS dependency | Separate authentication migration; do not translate by deleting annotations | Supported target authentication flow and SDK behavior |
| `SecretProviderClass` with `provider: azure`; `secrets-store.csi.k8s.io` volumes | Existing target driver/provider and Azure access are prerequisites, or replace the secret delivery mechanism explicitly | Mount, permissions, secret sync if used, and rotation |
| Azure Service Operator CRs | Check controller, credentials, and existing-resource ownership before any CR deployment | No unintended creation or deletion of Azure resources |
| ACR image without `imagePullSecrets` | Detect implicit AKS kubelet identity access; configure target pull access or synchronize images | Fresh target-node image pull, including init containers |
| `disk.csi.azure.com` or `file.csi.azure.com` volumes | Copy data into newly provisioned target storage; map capabilities | Mode, protocol, capacity, topology, permissions, and application read/write |
| PV Azure resource ID, snapshot handle, or CSI secret reference | Keep as evidence; do not use as a portable target volume definition | Explicit separate backend reuse procedure if requested |
| AKS node pool labels, Azure topology values, taints, or VM-specific requirements | Map scheduling intent to actual target nodes | CPU architecture, OS, zone placement, GPU/device resources, and scheduling |
| Azure Policy/Gatekeeper constraints or admission mutation | Treat source policy as behavior to assess, not target cluster configuration to export | Target SCC/PSA and admission results for workloads and movers |
| DNS, Key Vault, ACR, or external service private endpoints | Prepare target DNS and network access independently | Resolution and authenticated access from target pods or nodes as appropriate |
| KEDA/external metrics or Azure-backed autoscaling triggers | Existing target controller, metrics adapter, and credentials are prerequisites | Scaling behavior, not only CR/HPA creation |

Do not infer Azure role assignments, federated credentials, or registry authorization from Kubernetes RBAC. Azure control-plane evidence and application runtime checks are separate requirements.

## Application exposure decisions

Inventory the installed implementation instead of assuming every AKS application uses Ingress. Possible sources include self-managed controllers, the application routing add-on, Application Gateway Ingress Controller, Application Gateway for Containers, and Gateway API implementations.

Microsoft's [managed NGINX documentation](https://learn.microsoft.com/en-us/azure/aks/app-routing) states that its critical security patch support ends in November 2026. Its [Gateway API documentation](https://learn.microsoft.com/en-us/azure/aks/app-routing-gateway-api) describes the replacement path. Keep controller/version evidence with the profile rather than making NGINX a permanent AKS baseline.

For each exposed application:

1. Record client-visible hostname, DNS ownership, public/private scope, ports, and protocol.
2. Record every match rule and controller-specific behavior. Include `Exact`, `Prefix`, regex, rewrites, redirects, headers, and authentication.
3. Select retained Ingress, retained Gateway API, or generated OCP Route resources based on available target capabilities.
4. Verify TLS termination location, certificate delivery and renewal, backend TLS trust, and any mTLS requirement.
5. Test permitted traffic and requests that must not match or must remain inaccessible.

One Ingress can need several Routes. A Route path does not automatically preserve every Ingress `pathType` or regex rule. Gateway filters, policy attachments, and listener rules also have no universal one-to-one Route mapping. Unrepresentable behavior is a prerequisite or blocker, not a dropped annotation.

Do not deploy both the original and replacement exposure objects by default. Record which source objects the replacement supersedes. Keep service names, ports, namespace references, and generated resource names deterministic.

Removing `azure-load-balancer-internal` while retaining `type: LoadBalancer` can change private exposure into public exposure. Likewise, a replacement Route on the default router may expose a previously private application. Require an explicit target exposure decision before either transformation. Non-HTTP TCP/UDP services need a separate target load balancer or other suitable endpoint; a normal HTTP Route is not a general replacement.

Source application ingress is independent of the `transfer-pvc` endpoint. The AKS mover initiates the data connection to the OCP target, so no source ingress controller is required for PVC transfer.

## Workload runtime and OpenShift admission

Validate workload Pods and mover Pods independently. A source application accepted by AKS admission can still fail the target SCC, and a successful mover does not prove that the application image supports the target UID.

- Inspect pod-level and container-level `runAsUser`, `runAsGroup`, `fsGroup`, supplemental groups, and init-container behavior. Fixed source IDs can fall outside target namespace ranges. Select a tested target ownership strategy before changing them.
- Verify that the application image works with the target-assigned UID and can write its required directories. Removing `runAsUser` is insufficient if the image requires a fixed user, root-owned files, or privileged startup scripts.
- Check dropped capabilities, privilege escalation, seccomp, privileged/host access, and ports. Report incompatible application requirements instead of relying on a broad SCC grant as a default migration transformation.
- Map node affinity, selectors, tolerations, and topology spread to actual target labels. Preserve placement intent without copying AKS pool names or source zone values.
- Review NetworkPolicy selectors, CIDRs, DNS egress, and access to external Azure services. Portable policy syntax can still refer to source-specific addresses or block target movers.
- Recheck injected sidecars, service mesh dependencies, resource requests, HPA metrics, and PDB availability requirements against target controllers and capacity.

Server-side dry-run of a Deployment or StatefulSet does not exercise Pod admission by its controller. Keep actual Pod creation, admission events, process identity, readiness, and application read/write checks in the runtime evidence.

## Identity, secrets, and images

### Retaining access to Azure services

Moving the application does not require moving its Azure service. It does require a target authentication and network design.

For Entra Workload ID, record the source issuer, ServiceAccount subject, audience, client identity, Azure permissions, and injection mechanism. Reusing the same namespace and ServiceAccount name does not preserve trust because the target token issuer differs. Namespace mapping also changes the subject.

A target integration must provide a trusted issuer and keys, the intended projected token audience, SDK configuration, and token renewal. Azure administrators prepare federation and permissions, while target administrators prepare any required integration. Crane records these prerequisites and the test result. It does not install a webhook or create Azure role assignments.

Do not strip workload identity metadata and call the workload portable. Test an application-level operation against the intended resource, then restart the Pod and test again. A copied access token or a working source Pod does not prove target federation.

### Key Vault and secret lifecycle

`SecretProviderClass` is a Secrets Store CSI API, while its Azure provider parameters and identity are environment-specific. The CRD alone does not prove that the provider is installed or authorized.

Choose either an already prepared compatible target integration or an explicit replacement for secret delivery. A synchronized Kubernetes Secret can be stale or controller-owned; copying it does not preserve rotation. Record mount paths, object versions, sync consumers, restart behavior, and certificate renewal where applicable. Keep secret values and rclone configuration out of compatibility reports.

### ACR image access

AKS can pull from ACR through its kubelet identity, with no pull Secret in the application namespace. Exporting ServiceAccounts therefore may export no usable registry credential.

Choose target registry authentication or image synchronization, preserve image digests, and account for ACR private endpoint DNS and data endpoints. Verify an uncached pull from a target node for application, init, sidecar, and mover images. Workload identity used inside a container does not by itself grant the kubelet image-pull access.

## Storage and data transfer

### Mapping Azure storage

Use the capability fields in [TRANSFER_PVC_VALIDATION.md](TRANSFER_PVC_VALIDATION.md), not a fixed Azure-to-ODF name table. The target can use any validated CSI implementation.

| Source storage | Baseline target requirement | Specific checks |
| --- | --- | --- |
| Azure Disk filesystem RWO | Filesystem PVC with adequate capacity and application-compatible performance | Zone/node affinity, attach limits, detach after quiescing, filesystem, and mover scheduling |
| Azure Files SMB RWX | Shared filesystem accessible to the intended target replicas | SMB mount UID/GID and modes may be synthesized; compare application-visible permissions rather than assuming POSIX ownership preservation |
| Azure Files NFS RWX | Shared filesystem with the required POSIX behavior | Root squash, numeric ownership, symlinks, locking, and concurrent writers |
| In-tree Azure volume migrated through CSI | Discover actual PV and CSI behavior | Legacy annotations/provisioner names must not become target provisioning instructions |
| Raw block PVC | Separate block-aware procedure | rsync/rclone filesystem copy is not raw block support |
| Blob CSI or Azure Container Storage | Separate profile and data semantics assessment | A filesystem mount or a PVC alone does not establish equivalence to Azure Disk/Files |

Map `StatefulSet.spec.volumeClaimTemplates` as well as standalone PVCs. Use consistent names between transformed workloads and transferred claims. Exclude source binding, selected-node, snapshot, and backend identifiers from target provisioning instructions. An Azure snapshot is not a cross-provider portable data artifact.

With `WaitForFirstConsumer`, a target PVC can remain `Pending` until the mover Pod schedules. Test provisioning and scheduling together. A test that waits for `Bound` before allowing any consumer can report a false failure.

For Azure Disk RWO, record the current consumer node and any source mover placement. RWO allows multiple Pods on one node; it does not guarantee multi-node attachment or application-consistent concurrent access. Test the final copy after source writers stop and the disk detaches when required.

### Transport selection

| Condition | Planned path |
| --- | --- |
| AKS mover resolves and reaches target OCP TLS passthrough Route | Direct `transfer-pvc --endpoint=route` |
| Private connectivity provides the same Route contract | Direct transfer using the validated private path |
| No direct path; both mover environments reach a validated S3-compatible endpoint | Explicit indirect transfer through staging storage |
| CLI cannot reach one API | Block orchestration until API access is available; indirect storage does not remove this requirement |
| Neither direct path nor staging access works | Block with the missing DNS/network prerequisites |

The direct check must run from a source pod under the relevant policy and network conditions. Workstation reachability and an admitted Route are insufficient. Record router hostname, TCP port, TLS passthrough, NSG/firewall rules, NetworkPolicy, proxy behavior, and mover image access. An HTTP-only proxy is not proof of stunnel connectivity.

The existing indirect contract is S3-compatible staging storage. Azure Blob Storage is not an S3 endpoint. rclone's support for an Azure Blob backend does not establish that the Crane indirect workflow supports it. Validate it as a separate change if required.

### Verified CLI baseline

The following direct invocation uses options present in the reviewed Crane baseline. Set the variables to the recorded profile and prepare namespaces first. This command creates temporary cluster resources and copies data; it is a validation step, not discovery.

```bash
crane transfer-pvc \
  --source-context "$SOURCE" \
  --destination-context "$TARGET" \
  --pvc-namespace "$SOURCE_NAMESPACE:$TARGET_NAMESPACE" \
  --pvc-name "$SOURCE_PVC:$TARGET_PVC" \
  --dest-storage-class "$TARGET_STORAGE_CLASS" \
  --endpoint route \
  --verify
```

For indirect testing, use the same context, namespace, PVC, and StorageClass mapping with `--cloud-storage` and either `--rclone-config-file` or `--rclone-config-secret`. Record exact options from the tested build. Transport selection and fallback are explicit; do not assume automatic retry through staging storage.

Source review at [`7f87cc2641ccd1e249d387402a35c35cdb4e6b4b`](https://github.com/migtools/crane/blob/7f87cc2641ccd1e249d387402a35c35cdb4e6b4b/cmd/transfer-pvc/transfer-pvc.go) identifies these validation concerns:

- `--verify` adds rsync's `--checksum` option. Keep a separate post-transfer content comparison and application check in the evidence.
- Restricted rsync options disable owner and group preservation. Exact source UID/GID preservation is not an existing guarantee. Test intentional target ownership and application access.
- Destination PVC construction clears `volumeName` and `volumeMode`, but copies other source spec fields. Test rejection of block mode and removal of incompatible selectors or data-source references before creating a claim.
- Existing destination PVC handling checks active consumers and an explicitly requested StorageClass. Tests must additionally establish capacity, access modes, and volume mode compatibility.
- UID/GID discovery can create a temporary inspection Pod. Discovery documented here remains read-only; transfer setup is a separate phase with cluster writes and policy checks.

These are source-review observations at the pinned baseline. Recheck them for the build used in each run and reproduce failures before filing implementation work.

### Consistency and cutover

1. Record source replica counts, scheduled writers, PVC consumers, DNS, and a rollback boundary.
2. Prepare target namespaces and dependencies. Keep target application consumers stopped during transfer.
3. Run an initial copy only if the application supports it. A database needs a documented quiesce, backup/restore, or replication procedure.
4. Stop source writers, including Jobs and external clients. Perform the final copy using the validated repeat-run behavior.
5. Compare file contents and required metadata, then start target consumers. Verify application-level reads and writes.
6. Switch client traffic only after target validation. Keep the source stopped while the target accepts writes.
7. Before target writes, rollback can restart the source and restore traffic. After target writes, rollback needs a data reconciliation procedure; restarting the stale source is not sufficient.

Scaling, DNS changes, deployment, and rollback are operator-run steps recorded in the report. They are not automatic Crane actions. Retain the source PVC and data until the migration owner closes the rollback window.

## Validation backlog

All scenarios initially have status `not-run`. Every test records an exact source/target profile, commands, events, logs, transformation artifacts, and a functional result. Use the report's standard M/D/C test rows and include the AKS IDs below as additional rows or finding references.

| ID | Priority | Scenario | Acceptance evidence |
| --- | --- | --- | --- |
| AKS-01 | P0 | Discovery, including denied cluster/Azure reads | Inventory and dependency register; denied reads remain unknown; no discovery-created resources |
| AKS-02 | P0 | Deployment, ClusterIP Service, ConfigMap, ServiceAccount, CronJob, HPA, and PDB | Export/transform/apply artifacts, server dry-run, Ready workload, batch execution, and available metrics where required |
| AKS-03 | P0 | HTTP/TLS Ingress on the chosen baseline controller | Correct host/path/backend and TLS; unmatched paths fail as expected; replacement excludes original exposure |
| AKS-04 | P0 | Azure-specific internal LoadBalancer settings | Target retains private scope; no accidental public exposure; unsupported fields produce findings |
| AKS-05 | P0 | Non-root application and mover under source admission and target SCC | Pods admitted without ad hoc security relaxation; target process can read/write copied data |
| AKS-06 | P0 | Azure Disk filesystem RWO, empty target, explicit class mapping | Provisioning and mover scheduling pass; at least 10 GiB copied; content comparison and application cutover pass |
| AKS-07 | P0 | Direct AKS mover to target passthrough Route | Pod-side DNS/TLS/network evidence; source ingress is not a prerequisite |
| AKS-08 | P0 | Private AKS with unreachable router, explicit indirect transfer | S3 staging works from both clusters; content verification, credential handling, and staging cleanup pass |
| AKS-09 | P0 | Existing target claim and repeated/interrupted copy | Compatible claim succeeds; active consumer and incompatible class/capacity/modes are rejected; partial copy is not success |
| AKS-10 | P0 | Failure paths and cleanup | No orphaned transfer or inspection resources after handled failures; source/target data claims retained |
| AKS-11 | P0 | Exact OCP 5 target-major validation | Independent target API, security, CSI, endpoint/client evidence; status follows target-major gates |
| AKS-12 | P1 | Private API with working direct data path | Direct transfer succeeds without making either cluster API public |
| AKS-13 | P1 | Azure Files SMB to target RWX | Two target replicas share data; contents, mount permissions, and supported metadata behavior documented |
| AKS-14 | P1 | Azure Files NFS to target RWX | Ownership, root squash, links, locking, and concurrent access tested separately from SMB |
| AKS-15 | P1 | Entra Workload ID and changed namespace | Correct target issuer/subject/audience; Azure operation works after restart; absent federation yields a prerequisite finding |
| AKS-16 | P1 | Key Vault CSI and secret rotation | Target mount and optional sync work; rotated value reaches the intended consumer; missing provider is detected |
| AKS-17 | P1 | ACR with implicit source kubelet access | Uncached target pull works through configured auth or synchronized digest; missing auth is identified |
| AKS-18 | P1 | Gateway API and alternate application gateway controller | Retained API/class mapping or explicit replacement; filters and policies checked; unsupported semantics block the exposure claim |
| AKS-19 | P1 | Source/target minor or add-on upgrade | Repeat API, ingress, admission, storage, transfer interruption, and smoke tests; retain before/after versions |
| AKS-20 | P2 | Azure Service Operator CR or Azure-backed KEDA trigger | Controller/identity prerequisites identified; no unintended cloud reconciliation; scaling tested if claimed |
| AKS-21 | P2 | Block mode, Blob CSI, Windows, or other excluded baseline | Explicit unsupported/unknown result or a separately validated procedure; no silent filesystem-copy claim |

P0 is the complete AKS planning requirement, including private indirect transfer and the OCP 5 investigation. An OCP 4-only result can be published with its narrower scope while AKS-11 remains `not-run`; it cannot imply OCP 5 support. P1 tests become required when the corresponding capability is claimed. Run the general data integrity, interruption, cleanup, and cutover suite for every claimed transport/storage combination.

## Work packages for Crane changes

Create implementation issues only from reproduced findings. The plan must preserve existing CLI behavior and plugin compatibility.

| Package | Responsibility and likely repository | Acceptance criteria |
| --- | --- | --- |
| AKS-W1: local discovery findings | General capability/dependency discovery in `migtools/crane`; Azure detection rules where needed | Local findings identify object and field, evidence, target prerequisite, and unknown permissions; no cluster-installed component |
| AKS-W2: target transformations | General resource transformations in `migtools/crane-lib`; Azure-specific annotation/CR logic in a CLI plugin only if needed | Deterministic patches and replacement resources; explicit exposure mapping; no silent semantic loss; repeat transform produces the same output |
| AKS-W3: storage validation | `migtools/crane` `transfer-pvc`, with `migtools/pvc-transfer` changes only for reproduced library behavior | Explicit class/capability mapping; incompatible existing claims and block mode fail before copy; StatefulSet claim names agree with data mapping |
| AKS-W4: transport diagnostics | `migtools/crane` preflight and endpoint handling | Distinguish API access, pod DNS, TCP/TLS, and staging failures; direct/indirect path is explicit; errors identify the failed prerequisite |
| AKS-W5: ownership and lifecycle | `migtools/crane` and affected mover library/image | Documented UID/GID behavior, application access checks, interruption result, cleanup, and retained PVCs |
| AKS-W6: regression fixtures and runbook | Tests in the affected implementation repositories; reports and planning notes here | Fixtures cover Azure fields and rejected semantics; exact-profile integration results accompany any support statement |

Before AKS-W2, check whether the pinned plugin API can emit new resource kinds and explicitly supersede source objects. Ingress-to-Route replacement cannot be assumed to fit a patch-only response. Track any missing library/CLI capability as a separate backward-compatible change.

Move reusable findings into the general xKS documents and tests before starting the EKS increment. Storage, SCC, API compatibility, and endpoint behavior should depend on discovered capabilities, not an `aks` switch.

## Definition of done

- Each claimed profile has an exact versioned report and separate manifest/direct/indirect results.
- Baseline P0 scenarios pass for the claimed OCP release; narrower intermediate results state their scope.
- Private AKS has a verified indirect procedure, and direct eligibility depends on the actual network path.
- Azure Files, identity, Key Vault, ACR, and Gateway API claims have the corresponding P1 runtime evidence.
- Every transformed or omitted Azure dependency has an explicit target decision and owner.
- Transformations are auditable and idempotent; new resource generation is supported by the tested plugin/CLI build.
- Content verification, usable target permissions, interruption behavior, cleanup, cutover, and rollback boundaries are recorded.
- OCP 5 remains `Unknown` or `Experimental` until its independent promotion criteria pass.

## References and evidence date

Documentation and the pinned Crane source were reviewed on 2026-10-20. Recheck release-specific behavior before each cluster run.

- [Crane transfer CLI at the initial baseline](https://github.com/migtools/crane/blob/7f87cc2641ccd1e249d387402a35c35cdb4e6b4b/cmd/transfer-pvc/transfer-pvc.go)
- [Crane transfer usage at the initial baseline](https://github.com/migtools/crane/blob/7f87cc2641ccd1e249d387402a35c35cdb4e6b4b/cmd/transfer-pvc/README.md)
- [AKS CSI storage drivers](https://learn.microsoft.com/en-us/azure/aks/csi-storage-drivers)
- [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Azure Key Vault provider for Secrets Store CSI](https://learn.microsoft.com/en-us/azure/aks/csi-secrets-store-driver)
- [AKS managed NGINX application routing](https://learn.microsoft.com/en-us/azure/aks/app-routing)
- [AKS application routing with Gateway API](https://learn.microsoft.com/en-us/azure/aks/app-routing-gateway-api)
- [AKS internal load balancer and Private Link settings](https://learn.microsoft.com/en-us/azure/aks/internal-lb)
- [AKS integration with ACR](https://learn.microsoft.com/en-us/azure/aks/cluster-container-registry-integration)
