# 001: Exclude CiliumEndpoint from application migration output

## Status and proposed decision

The explicit whiteout workaround passed in the [AKS WordPress run](../wordpress-aks/migration-2026-10-21/README.md) on 2026-10-21. Investigate whether Crane should exclude this kind by default or already has an ownership-based rule that should cover it. No implementation change has been made.

Classify `cilium.io/v2, Kind=CiliumEndpoint` as generated source-network state. Preserve it in export evidence, exclude it from deployable output, and do not convert it to an OpenShift Route.

## What CiliumEndpoint describes

Cilium is a Kubernetes network plugin. Its agent manages network connectivity and policy enforcement for Pods. A namespaced `CiliumEndpoint` records a Pod's Cilium endpoint state, including network addresses, Cilium identity, node information, named ports, and lifecycle state. It is not an application exposure request or a network policy definition.

The exported frontend object provides direct evidence:

```yaml
apiVersion: cilium.io/v2
kind: CiliumEndpoint
metadata:
  name: wordpress-749f4d9ff9-hcxsl
  namespace: marek-test
  ownerReferences:
    - apiVersion: v1
      kind: Pod
      name: wordpress-749f4d9ff9-hcxsl
      uid: 8ed13514-00f8-40a2-b5f9-b472aa5e289d
status:
  id: 992
  networking:
    addressing:
      - ipv4: 10.244.3.103
    node: 10.224.0.7
  state: ready
```

This is an excerpt, not a manifest for deployment. The original object's `managedFields` identifies `cilium-agent` as the manager. Its owner reference has no `controller: true` field. That distinction may matter if a generic ownership filter only recognizes controller references; inspect the implementation before drawing a conclusion.

The run exported two instances, for WordPress and MySQL, plus the `ciliumendpoints.cilium.io` CRD.

## Why whiteout is needed

- Pod names and UIDs, container attachment IDs, IP addresses, node addresses, and Cilium identity IDs refer to the source environment. Target Pods receive new runtime state.
- On a target without the Cilium API, applying this CR fails because its kind is unavailable. Copying the CRD does not install Cilium or make the source endpoint usable.
- On a target running Cilium, its agent must manage endpoint state for the new Pods. Replaying the source record is unnecessary and can introduce stale references or conflict with controller-managed state.
- Removing metadata or `status` alone does not turn the object into portable application intent. There is no application configuration here that needs redeployment.

Whiteout means excluding the object from active transformed resources. It does not delete the live source object, remove it from export evidence, or disable source networking.

Do not generalize this decision to all `cilium.io` resources. `CiliumNetworkPolicy` and `CiliumClusterwideNetworkPolicy` express policy intent and need separate compatibility assessment. Dropping them silently could change permitted application traffic.

## Verified workaround

The run used Crane `v0.11.0-alpha.1`, commit `fe0fa07f3391ddec7a076527f727f5e2a6f853ff`, and KubernetesPlugin `v0.0.10`:

```bash
crane transform KubernetesPlugin \
  --export-dir export \
  --transform-dir transform \
  --stage-optionals 'KubernetesPlugin={"extra-whiteouts":"CiliumEndpoint.cilium.io"}'

crane apply \
  --transform-dir transform \
  --output-dir output \
  --skip-cluster-scoped
```

`KubernetesPlugin` explicitly whiteouted both endpoint instances. `crane apply --skip-cluster-scoped` excluded their CRD from final output. The CRD remained in the transform stage's output before apply.

This run does not establish what would happen without `extra-whiteouts`. It also does not establish that `--skip-cluster-scoped` is appropriate for every application. Other applications may require reviewed cluster-scoped dependencies.

## Should this CR become an OpenShift Route?

No. The two APIs represent different information and have different owners.

| Aspect | CiliumEndpoint | OpenShift Route |
| --- | --- | --- |
| Purpose | Record a Pod's network endpoint state | Describe external HTTP/TLS access to a Service |
| Managed by | Cilium agent | Application configuration and the OpenShift ingress controller |
| References | Pod identity, network addresses, node and Cilium identity | Backend Service and port, with optional host, path and TLS settings |
| Lifetime | Associated with a particular Pod endpoint | Can remain stable across replacement Pods |
| Migration action | Exclude source-generated state | Retain, generate or transform according to exposure requirements |

A `CiliumEndpoint` does not specify a client-facing hostname, URL path, public/private exposure requirement, TLS termination mode, certificate, or intended backend Service. Its named ports do not establish which ports should be externally reachable. Generating Routes from these records would infer application intent from runtime state and could expose internal services, including MySQL.

In this WordPress sample, the relevant exposure source is `Service/wordpress`, which has `type: LoadBalancer` and port 80. A future OpenShift exposure decision can choose a Route targeting that Service and assess whether the Service should become `ClusterIP`. The MySQL Service should remain internal. This decision must preserve the intended exposure scope and account for hostname, TLS, and the selected target router.

Ingress or Gateway API resources, when present, are other possible sources of exposure intent. They require their own mapping analysis. None of these transformations should use `CiliumEndpoint` as the exposure source.

## Required changes and checks

- [ ] Reproduce transformation without `extra-whiteouts` using a separate copy of this export. Record whether both endpoint instances survive and whether the CRD reaches final output.
- [ ] Inspect KubernetesPlugin's existing whiteout and ownership rules in `migtools/crane-lib`. Check the handling of a Pod owner reference without `controller: true`.
- [ ] Decide whether to add a kind-specific default whiteout or extend an existing generated-resource rule. Preserve explicit user configuration and existing plugin compatibility. Do not apply a group-wide Cilium exclusion.
- [ ] If a change is needed, add regression coverage in the implementation repository for this owner-reference shape and for endpoints whose owner Pod is absent from export.
- [ ] Verify that excluding CiliumEndpoint leaves application Deployments, Services, ConfigMaps, Secrets, and policy resources intact.
- [ ] Review CRD collection/output behavior in `migtools/crane`. Confirm how an automatically collected CRD is handled when all its instances are whiteouted, without discarding unrelated application CRDs.
- [ ] Record a precise target OpenShift profile and decide WordPress Service-to-Route exposure separately. Verify that no Route is generated for MySQL or from CiliumEndpoint.
- [ ] During later runtime validation, verify target Pod networking and application connectivity. If the target uses Cilium with endpoint CRs enabled, confirm that its agents create fresh endpoint records.

## References

- [Local run and exact commands](../wordpress-aks/migration-2026-10-21/README.md)
- Local evidence: `../wordpress-aks/migration-2026-10-21/export/resources/marek-test/CiliumEndpoint_cilium.io_v2_marek-test_wordpress-749f4d9ff9-hcxsl.yaml`, retained locally and ignored by Git with other export artifacts.
- [Cilium Kubernetes networking concepts](https://docs.cilium.io/en/stable/network/kubernetes/concepts/)
- [Cilium policy resource distinctions](https://docs.cilium.io/en/stable/network/kubernetes/policy/)
- [OpenShift Route API types](https://github.com/openshift/api/blob/master/route/v1/types.go)
- [AKS exposure decisions](../AKS.md#application-exposure-decisions)
