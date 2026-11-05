# Adding xKS-to-OpenShift migration support

## Goal

Use this workflow to add and verify Crane support for public cloud Kubernetes services (xKS).

The deliverable is a tested source-to-OpenShift migration procedure, supported by reproducible applications, E2E results, manifest transformations, and user documentation. Record separate results for manifests and persistent data, and for every claimed source/target version and topology.

This document describes the delivery sequence. Use [provider validation](PROVIDER_VALIDATION.md) for detailed checks and the [report template](VALIDATION_REPORT_TEMPLATE.md) for evidence. Implementation belongs in the Crane ecosystem repositories.

## 1. Obtain infrastructure access and prepare clusters

Arrange an infrastructure owner, account access, quota, and a test environment for each provider. Examples:

| Source | Infrastructure access | Initial profile and follow-up variants |
| --- | --- | --- |
| AKS | Azure tenant/subscription, resource group, Azure RBAC, and permission to inspect networking, identities, registries, and storage | Linux AKS with Azure Disk RWO; then private networking, Azure Files SMB/NFS RWX, workload identity, and alternate ingress implementations |
| EKS | AWS account, region, IAM role, EKS access, and visibility into VPC, load balancers, IAM, ECR, and storage | Linux EKS with EBS RWO; then private networking, EFS RWX, IRSA/Pod Identity, and AWS Load Balancer Controller |
| Tanzu | Access to the selected Tanzu platform and workload cluster; for vSphere-backed deployments, the relevant vCenter, Supervisor or management cluster, resource pool, datastore/storage policies, and network administration | Name the exact product, release, and cluster type. Start with its actual CSI RWO and exposure implementation; add RWX and private topology where available |

Obtain source and target kubeconfigs, working credential helpers, and access from the test runner to both APIs. Kubernetes RBAC and cloud/vSphere permissions are separate. Record unavailable reads as unknown dependencies.

Prepare an exact OpenShift target release, test namespaces, target storage, registry access, DNS, and either a direct transfer path or object-storage staging. Record versions of Crane, plugins, mover images, and test tooling. Agree on environment lifetime and cleanup of test-created load balancers, volumes, and staging data.

**Output:** a versioned source/target profile, usable credentials, and a repeatable cluster setup procedure. Keep credentials outside the published artifacts.

## 2. Analyze APIs, CRDs, networking, and storage

Collect source and target evidence using [general discovery](PROVIDER_VALIDATION.md#2-api-discovery) and, for AKS, [AKS discovery](AKS_DISCOVERY.md).

- Compare served APIs, schemas, CRD versions, conversion webhooks, controllers, and admission policies. Separate application resources from generated runtime state and infrastructure-management objects.
- Inventory application exposure, ingress/Gateway controllers, public/private scope, DNS, TLS, load balancer annotations, NetworkPolicy, proxies, and pod egress.
- Inspect CSI drivers, StorageClasses, filesystem/block mode, access modes, binding/topology constraints, capacity, permissions, snapshots, and existing PVC consumers.
- Identify cloud identity, registry authentication, external services, secret delivery, scheduling constraints, and target SCC/UID requirements.

Pay particular attention to these provider dependencies:

| Provider | Examples to inspect |
| --- | --- |
| AKS | Azure load balancer and application gateway settings, Cilium-generated resources, Entra Workload ID, Key Vault CSI, ACR, Azure Disk/Files |
| EKS | AWS load balancer annotations, `TargetGroupBinding`, IRSA/Pod Identity, ECR, EBS/EFS, optional ACK or secret controllers |
| Tanzu | Installed Antrea or other CNI, NSX/NSX ALB or other load balancer, Contour or other ingress, vSphere CSI/storage policies, registry and identity integrations. Discover these instead of assuming they exist |

Do not migrate Tanzu Supervisor, management-cluster, Cluster API, or machine-lifecycle objects as application configuration. Existing application CRDs need their own portability assessment.

Create a dependency table with `resource/field -> source behavior -> target decision -> owner -> verification`. Classify each item as portable, transformable, replaceable, prerequisite, non-portable, or unknown using [API resource compatibility](API_RESOURCE_COMPATIBILITY.md).

Check transfer connectivity separately from application ingress. Direct transfer requires the source mover to reach the target OpenShift TLS passthrough Route. Indirect transfer requires the relevant movers to reach the configured staging backend. API access from a workstation proves neither path.

**Output:** an API/dependency comparison, explicit storage and exposure mappings, and an initial list of blockers and transformation rules.

## 3. Run the standard Crane E2E suite

Use the standard [Crane E2E suite](https://github.com/migtools/crane/tree/main/e2e-tests), with the xKS cluster as source and OpenShift as target. Pin the test checkout and CLI build. Prepare Ginkgo/Gomega, `kubectl`/`oc`, `k8sdeploy` and its dependencies, mover images, and admin/non-admin contexts required by the selected tests.


For indirect scenarios, supply the suite's `--cloud-storage` and `--rclone-config-file` or `--rclone-config-secret` options. Record which tests actually exercised each transport. A direct-only run is not indirect-transfer evidence.

Review scenario applicability before interpreting results. Some tests require OpenShift source APIs, particular add-ons, storage, or endpoint assumptions. Record passed, failed, skipped, and not-applicable cases with reasons. Adapt reusable helpers where needed and keep existing OpenShift coverage; an xKS support claim cannot rely on silently skipping applicable failures.

Separate environment failures, test-harness assumptions, and Crane defects. Run a baseline before provider-specific changes and repeat affected tests afterward. A compile check is not an E2E run.

**Output:** tier0/tier1 reports, logs, test applicability, and issues for reproduced gaps.

## 4. Build provider-specific demonstration applications

Standard E2E coverage must be supplemented with applications that actually use the provider integrations. Give each sample deploy, seed, source-validation, migration, target-validation, and cleanup instructions. Pin images and retain sanitized export fixtures.

| Sample | Source behavior to demonstrate | Target evidence |
| --- | --- | --- |
| Shared baseline | Deployment, ConfigMap/Secret, internal Service, and non-root runtime | Ready Pods, correct configuration, internal connectivity, and application read/write |
| AKS | HTTP application with the selected Azure ingress or load balancer; database on Azure Disk | Preserved exposure scope/TLS, target storage mapping, database data and new writes. Add Azure Files, workload identity, Key Vault, and ACR samples for those claims |
| EKS | HTTP application using AWS Load Balancer Controller; database on EBS | Correct exposure replacement and EBS-to-target data transfer. Add EFS and an IRSA/Pod Identity external-service operation for those claims |
| Tanzu | HTTP application using the installed exposure stack; database on the selected vSphere CSI storage policy | Correct target exposure, new target PVC provisioning, and application data. Add installed CNI policy, RWX, or secret integrations for those claims |

For identity or secret-provider samples, demonstrate a real external operation or secret refresh after migration. For networking, test both allowed traffic and traffic that must remain inaccessible. Shared baseline applications alone do not verify Azure, AWS, or Tanzu dependencies.


**Output:** runnable samples, source manifests and data, expected target behavior, and regression fixtures.

## 5. Implement and integrate manifest transformations

Use [migtools/crane-plugin-xks-to-ocp](https://github.com/migtools/crane-plugin-xks-to-ocp) for xKS-to-OpenShift manifest rules. Keep general export, cleanup, and data-transfer fixes in `crane` or `crane-lib` as appropriate.

### Establish plugin execution first

At the reviewed commit, the plugin is a pass-through skeleton. It produces no patches, whiteouts, or new resources and declares no optional flags. Its metadata name is `xKStoOCP`, while the reviewed Crane stage-creation code requires plugin names ending in `Plugin`. Resolve and test that integration before publishing runnable transform instructions. Renaming the binary alone does not change its metadata name.

Build and test in the plugin repository with `make build` and `make test`. Put the executable in a dedicated plugin directory, inspect `crane transform list-plugins --plugin-dir "$PLUGIN_DIR"`, and verify that a real transform stage invokes it. Record the final metadata name and supported CLI/plugin versions.

### Add rules from the dependency analysis

- Reuse `KubernetesPlugin` for common cleanup. Add focused handlers and configuration to the xKS plugin for provider fields and target mappings.
- Generate deterministic JSON patches, whiteouts, and replacement resources. Preserve export evidence and unrelated resources. Test the pinned CLI/library support for new-resource generation.
- Map HTTP exposure using explicit target host, TLS, backend, and public/private decisions. Do not turn internal services public or silently discard unsupported ingress/Gateway behavior.
- Map standalone PVCs and StatefulSet claim templates consistently with `transfer-pvc`. Do not reuse source PV handles, cloud disk IDs, or source storage-policy references as target provisioning instructions.
- Report cloud identity, external secret providers, and unavailable controllers as prerequisites. Removing their metadata does not reproduce their behavior on OpenShift.
- Exclude generated state by a justified kind/ownership rule. Do not drop an entire provider API group or its network policies.

Keep transformation offline and file-based. The plugin does not provision cloud infrastructure, install operators/CRDs, copy PVC data, or apply output to a live cluster.

The intended pipeline is `export -> KubernetesPlugin -> xKS plugin -> reviewed local edits -> crane apply`. `crane apply` renders files; deployment remains a separate operator action. Publish an instructions file with the tested stage names, order, and options once plugin integration is verified.

Add fixture tests for each supported rule, unsupported input, missing fields, replacement/whiteout behavior, and deterministic reruns. In E2E tests, set `TransformOptions.PluginDir` and explicitly select the plugin stage or `InstructionsFile`. Passing the suite's `--plugin-dir` only makes plugins available; it does not prove a test invoked this plugin. Assert a known transformation in the output and then verify application behavior.

**Output:** plugin implementation and tests, versioned configuration examples, and auditable before/after manifests.

## 6. Verify the complete migration and persistent data

Run each provider sample through the final plugin pipeline. Inspect patches and replacements, run server-side dry-run against the target, then deploy and check actual Pods. A dry-run of a Deployment does not exercise admission of its future Pods.

For stateful samples, follow [PVC transfer validation](TRANSFER_PVC_VALIDATION.md):

1. Prepare target dependencies and storage mapping. Keep target application consumers stopped during transfer.
2. Quiesce source writers using the application's consistency procedure, then perform the final direct or indirect copy.
3. Compare contents and required ownership, modes, links, and xattrs independently. Record the tested meaning of `--verify` for each transport.
4. Start the target application and verify reads, new writes, exposure, identity, and external dependencies.
5. Test interruption, retry/repeat-run behavior, failed-copy reporting, and temporary-resource/staging cleanup. Retain application PVCs.
6. Rehearse traffic cutover and rollback. After target writes, rollback needs a data reconciliation plan.

Test RWO first, then RWX and private-network variants as separate profiles. Filesystem copy does not establish raw-block support. Account for `WaitForFirstConsumer` when checking target provisioning.

Track the known [CiliumEndpoint finding](todo/001-ciliumendpoint.md) and [indirect-transfer findings](todo/003-indirect-transfer-validation.md), also tracked in [#1111](https://github.com/migtools/crane/issues/1111) and [#1112](https://github.com/migtools/crane/issues/1112). A successful demonstration does not close unrelated metadata, verification, or mover-admission questions.

**Output:** separate manifest, direct-transfer, and indirect-transfer results, plus application-level verification for each claimed profile.

## 7. Add regression coverage and record support scope

Automate the provider samples in the standard E2E framework and plugin fixture tests. Reuse source/target context handling and lifecycle helpers rather than maintaining a separate migration harness. Arrange periodic provider-backed runs and reruns after relevant CLI, plugin, CSI, ingress, source Kubernetes, or target OpenShift changes.

Retest at least one source and target minor-version upgrade before claiming upgrade coverage. Validate OpenShift major versions independently using [target version gates](OCP_TARGET_VERSIONS.md).

Publish a matrix with exact source product/version, add-ons, topology, storage, target release, CLI/plugin versions, test results, and limitations. Use `Unknown`, `Experimental`, `Supported with prerequisites`, or `Supported` according to the evidence. An AKS result does not establish EKS or Tanzu support.

**Output:** automated regression cases, a reproducible validation report, and a narrowly stated support matrix.

## 8. Publish the user migration procedure

Provide a runnable guide for each validated provider profile, with shared steps linked where possible. Include:

- Infrastructure and Kubernetes access, required permissions, target prerequisites, and tested versions.
- Read-only discovery and how to resolve API, CRD/controller, identity, networking, and storage findings.
- CLI/plugin installation, exact transform instructions/options, expected patches/replacements, and any remaining manual edits.
- Explicit direct/indirect transfer selection, storage/namespace/PVC mapping, quiesce steps, and content/metadata verification.
- Target deployment, application checks, traffic cutover, rollback boundary, cleanup, and troubleshooting.
- A worked provider-specific sample and the tested limitations, including unsupported or untested integrations.

Run the guide from a clean working directory using its documented credentials and prerequisites. Publish CLI workflow documentation with Crane, transformation/configuration reference with the plugin, and samples with the maintained test assets. Link all three from the provider guide.

**Output:** user documentation that reproduces a verified migration from the named xKS profile to OpenShift.

## Source review baseline

Reviewed on 2026-11-05. These references establish current interfaces and implementation gaps, not cluster-test results:

- [Crane E2E suite and invocation](https://github.com/migtools/crane/blob/79198fe66eed282bb6d4d8fb156e8ac0ffac5549/e2e-tests/README.md)
- [E2E flags](https://github.com/migtools/crane/blob/79198fe66eed282bb6d4d8fb156e8ac0ffac5549/e2e-tests/tests/tier0/e2e_suite_test.go) and [transform runner options](https://github.com/migtools/crane/blob/79198fe66eed282bb6d4d8fb156e8ac0ffac5549/e2e-tests/framework/crane.go)
- [Crane plugin stage creation](https://github.com/migtools/crane/blob/79198fe66eed282bb6d4d8fb156e8ac0ffac5549/cmd/transform/transform.go)
- [xKS plugin skeleton and metadata](https://github.com/migtools/crane-plugin-xks-to-ocp/blob/5d707152872d1e9c5d15f5cb3e317e3b1640ee7b/xks-to-ocp/plugin.go) and [build/use instructions](https://github.com/migtools/crane-plugin-xks-to-ocp/blob/5d707152872d1e9c5d15f5cb3e317e3b1640ee7b/README.md)
