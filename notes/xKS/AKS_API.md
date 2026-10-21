# AKS cluster API inventory — `crane-test-aks`

Recorded API surface of a live AKS cluster, captured for the discovery step of the
[AKS migration plan](AKS.md) (scenario AKS-01). This is raw evidence, not a support
claim. Classification of individual kinds belongs in
[API_RESOURCE_COMPATIBILITY.md](API_RESOURCE_COMPATIBILITY.md); the matching read-only
command set is in [AKS_DISCOVERY.md](AKS_DISCOVERY.md).

## Capture metadata

| Field | Value |
| --- | --- |
| Capture date | 2026-10-21 |
| Cluster (kubeconfig `clusters[].name`) | `crane-test-aks` |
| Context / user | `kubeadmin` / `kubeadmin` |
| Server version | v1.36.4 (`bb826b1d48562f110659e64e8ec444327433db95`, built 2026-09-09) |
| Server emulation version | major 1, minor 36 |
| Server min compatibility version | 1.35 |
| Client version used | v1.36.5-gke.200 (local binary; unrelated to the cluster) |
| Commands | `kubectl api-versions`, `kubectl api-resources -o wide` |
| Cluster writes | none — both commands are read-only discovery |

Not captured here: AKS SKU (Standard/Automatic), region, node pools, OS/architecture,
network plugin mode, outbound type, CSI driver versions, StorageClass definitions, and
installed ingress controller. Those belong in the profile record required by
[AKS.md](AKS.md) and need separate `kubectl get` / Azure control-plane reads.

## Scope and reading guidance

- `kubectl api-versions` lists group/versions the API server serves. It does not prove
  that a controller behind a CRD is installed, healthy, or authorized.
- The `VERBS` column of `kubectl api-resources` lists the verbs **the resource supports**,
  not the verbs the current subject is allowed to use. Effective permissions require a
  separate `kubectl auth can-i --list` capture. Denied reads must be recorded as
  `unknown`, never as "dependency absent".
- Absence of a group is evidence that the corresponding scenario cannot be exercised on
  this cluster as configured; it is not evidence that the capability is unsupported on AKS
  in general.

## Served group/versions (53)

### Upstream Kubernetes

```
v1
admissionregistration.k8s.io/v1   apiextensions.k8s.io/v1   apiregistration.k8s.io/v1
apps/v1                           authentication.k8s.io/v1  authorization.k8s.io/v1
autoscaling/v1                    autoscaling/v2            batch/v1
certificates.k8s.io/v1            coordination.k8s.io/v1    discovery.k8s.io/v1
events.k8s.io/v1                  flowcontrol.apiserver.k8s.io/v1
networking.k8s.io/v1              node.k8s.io/v1            policy/v1
rbac.authorization.k8s.io/v1      resource.k8s.io/v1        scheduling.k8s.io/v1
storage.k8s.io/v1                 metrics.k8s.io/v1beta1    snapshot.storage.k8s.io/v1
```

### Azure and AKS add-on groups

| Group/version | Kinds | Origin |
| --- | --- | --- |
| `acn.azure.com/v1alpha` | `NodeNetworkConfig` | Azure Container Networking |
| `acn.azure.com/v1alpha1` | `OverlayExtensionConfig` | Azure Container Networking |
| `multitenancy.acn.azure.com/v1alpha1` | `NodeInfo` | Azure Container Networking |
| `aks.clusterconfig.azure.com/v1beta1` | `ExtensionConfig`, `ConfigSyncStatus` | AKS cluster extensions |
| `azurepolicy.azure.com/v1alpha1` | `SyncPolicies` | Azure Policy add-on |
| `azmonitoring.coreos.com/v1` | `PodMonitor`, `ServiceMonitor` | Azure Monitor managed Prometheus |
| `autoscaling.x-k8s.io/v1`, `/v1beta1` | `ProvisioningRequest` | Node autoprovisioning / cluster autoscaler |
| `eraser.sh/v1`, `/v1alpha1` | `ImageJob`, `ImageList` | AKS image cleaner add-on |

### Cilium data plane

`cilium.io/v2` and `cilium.io/v2alpha1` serve `CiliumNetworkPolicy`,
`CiliumClusterwideNetworkPolicy`, `CiliumEndpoint`, `CiliumEndpointSlice`,
`CiliumIdentity`, `CiliumNode`, `CiliumNodeConfig`, `CiliumCIDRGroup`,
`CiliumLoadBalancerIPPool`, `CiliumPodIPPool`, `CiliumL2AnnouncementPolicy`, and
`CiliumLocalRedirectPolicy`.

### Gatekeeper / Azure Policy

Nine groups, seventeen group/versions: `templates.gatekeeper.sh` (`v1`, `v1alpha1`, `v1beta1`),
`constraints.gatekeeper.sh` (`v1alpha1`, `v1beta1`), `mutations.gatekeeper.sh`
(`v1`, `v1alpha1`, `v1beta1`), `expansion.gatekeeper.sh` (`v1alpha1`, `v1beta1`),
`externaldata.gatekeeper.sh` (`v1alpha1`, `v1beta1`), `status.gatekeeper.sh`
(`v1alpha1`, `v1beta1`), `config.gatekeeper.sh/v1alpha1`,
`connection.gatekeeper.sh/v1alpha1`, and `syncset.gatekeeper.sh/v1alpha1`.

Sixteen Azure Policy constraint kinds are registered under
`constraints.gatekeeper.sh/v1beta1`:

```
K8sAzureV1BlockDefault              K8sAzureV1IngressHttpsOnly
K8sAzureV1ServiceAllowedPorts       K8sAzureV2BlockAutomountToken
K8sAzureV2BlockHostNamespace        K8sAzureV2ContainerAllowedImages
K8sAzureV2NoPrivilege               K8sAzureV3AllowedCapabilities
K8sAzureV3AllowedUsersGroups        K8sAzureV3ContainerLimits
K8sAzureV3DisallowedCapabilities    K8sAzureV3EnforceAppArmor
K8sAzureV3HostNetworkingPorts       K8sAzureV3NoPrivilegeEscalation
K8sAzureV3ReadOnlyRootFilesystem    K8sAzureV5HostFilesystem
```

The registered constraint *kinds* come from the Azure Policy add-on's ConstraintTemplates.
They do not indicate which constraints are instantiated, nor whether enforcement is
`deny` or `dryrun`. Capture the actual constraint objects separately.

Mutation kinds `Assign`, `AssignMetadata`, `AssignImage`, and `ModifySet` are also
served.

## Groups absent from this cluster

| Expected group | Affected AKS.md scenario | Consequence |
| --- | --- | --- |
| `gateway.networking.k8s.io` | AKS-18 (Gateway API) | Not exercisable here; exposure testing must use `networking.k8s.io/v1 Ingress` |
| `secrets-store.csi.x-k8s.io` | AKS-16 (Key Vault CSI) | No `SecretProviderClass`; the Secrets Store CSI driver is not installed |
| Azure Service Operator groups | AKS-20 | No ASO CRs to assess on this cluster |
| `keda.sh` | AKS-20 | Azure-backed KEDA triggers not exercisable |

Absence of the application routing add-on CRDs does not by itself determine the installed
ingress controller. Record the actual `IngressClass` objects and controller
Deployments separately before making any AKS-03 claim.

## Migration-relevant observations

These map onto the Azure-specific dependency matrix in [AKS.md](AKS.md). Each is a
discovery signal requiring a target decision, not a finished classification.

- **Gatekeeper with Azure Policy is active.** The constraint set (`K8sAzureV3AllowedUsersGroups`,
  `K8sAzureV3NoPrivilegeEscalation`, `K8sAzureV3ReadOnlyRootFilesystem`,
  `K8sAzureV2NoPrivilege`, `K8sAzureV5HostFilesystem`, and others) is the source-side
  admission behavior that must be compared against the target SCC/PSA outcome for both
  workload and mover Pods (AKS-05). Source policy is behavior to assess, not target
  configuration to export.
- **Admission mutation is available.** With `Assign`, `AssignMetadata`, `AssignImage`, and
  `ModifySet` served, exported objects can contain fields written by admission rather than
  by the application owner. Compare Deployment templates against actual Pods before
  treating any field as authored intent.
- **Cilium is the network policy engine.** `CiliumNetworkPolicy` and
  `CiliumClusterwideNetworkPolicy` carry semantics that upstream `NetworkPolicy` does not
  express. They need their own dependency-register rows with an explicit target decision;
  they are not portable to an OCP target without an equivalent implementation. Cluster-wide
  policies also sit outside a namespace-scoped export.
- **No Gateway API served.** AKS-18 cannot run on this cluster in its current state.
- **No Secrets Store CSI driver.** AKS-16 cannot run here; any application depending on
  Key Vault CSI would already be broken on this source cluster.
- **`snapshot.storage.k8s.io/v1` is served.** Snapshot APIs exist, but an Azure snapshot
  remains a non-portable, backend-specific artifact per [AKS.md](AKS.md). API availability
  does not change the transfer procedure.
- **`storage.k8s.io/v1` includes `VolumeAttributesClass`.** Storage mapping still requires a
  separate capture of `StorageClass`, `CSIDriver`, and `CSINode` objects; `api-resources`
  shows only that the kinds are served.
- **`resource.k8s.io/v1` (DRA) is served.** Relevant only if workloads use
  `ResourceClaim`/`DeviceClass`; check actual objects before assuming device scheduling is
  out of scope.
- **Azure Monitor managed Prometheus CRDs** (`PodMonitor`, `ServiceMonitor`) are
  application-adjacent objects that may appear in a namespace export and require a target
  monitoring decision.

## Follow-up captures needed for AKS-01

1. `kubectl auth can-i --list` — effective permissions, so denied reads are recorded as
   `unknown` rather than inferred absence.
2. `kubectl get storageclass,csidrivers,csinodes -o yaml` — storage capability mapping.
3. `kubectl get ingressclass -o yaml` plus controller Deployments — exposure baseline.
4. `kubectl get constrainttemplates,constraints` and the Azure Policy assignment list —
   enforced vs. audit-only policy.
5. `kubectl get ciliumnetworkpolicies,ciliumclusterwidenetworkpolicies -A` — non-portable
   policy inventory.
6. Node inventory with labels, taints, topology, OS, and architecture.

## Appendix: raw `kubectl api-resources -o wide`

Verbatim command output, retained as evidence. Remember that `VERBS` describes
resource-supported verbs, not subject permissions.

```
$ kubectl api-resources -o wide
NAME                                SHORTNAMES                          APIVERSION                            NAMESPACED   KIND                               VERBS                                                        CATEGORIES
bindings                                                                v1                                    true         Binding                            create                                                       
componentstatuses                   cs                                  v1                                    false        ComponentStatus                    get,list                                                     
configmaps                          cm                                  v1                                    true         ConfigMap                          create,delete,deletecollection,get,list,patch,update,watch   
endpoints                           ep                                  v1                                    true         Endpoints                          create,delete,deletecollection,get,list,patch,update,watch   
events                              ev                                  v1                                    true         Event                              create,delete,deletecollection,get,list,patch,update,watch   
limitranges                         limits                              v1                                    true         LimitRange                         create,delete,deletecollection,get,list,patch,update,watch   
namespaces                          ns                                  v1                                    false        Namespace                          create,delete,get,list,patch,update,watch                    
nodes                               no                                  v1                                    false        Node                               create,delete,deletecollection,get,list,patch,update,watch   
persistentvolumeclaims              pvc                                 v1                                    true         PersistentVolumeClaim              create,delete,deletecollection,get,list,patch,update,watch   
persistentvolumes                   pv                                  v1                                    false        PersistentVolume                   create,delete,deletecollection,get,list,patch,update,watch   
pods                                po                                  v1                                    true         Pod                                create,delete,deletecollection,get,list,patch,update,watch   all
podtemplates                                                            v1                                    true         PodTemplate                        create,delete,deletecollection,get,list,patch,update,watch   
replicationcontrollers              rc                                  v1                                    true         ReplicationController              create,delete,deletecollection,get,list,patch,update,watch   all
resourcequotas                      quota                               v1                                    true         ResourceQuota                      create,delete,deletecollection,get,list,patch,update,watch   
secrets                                                                 v1                                    true         Secret                             create,delete,deletecollection,get,list,patch,update,watch   
serviceaccounts                     sa                                  v1                                    true         ServiceAccount                     create,delete,deletecollection,get,list,patch,update,watch   
services                            svc                                 v1                                    true         Service                            create,delete,deletecollection,get,list,patch,update,watch   all
nodenetworkconfigs                  nnc                                 acn.azure.com/v1alpha                 true         NodeNetworkConfig                  delete,deletecollection,get,list,patch,create,update,watch   
overlayextensionconfigs             oec                                 acn.azure.com/v1alpha1                true         OverlayExtensionConfig             delete,deletecollection,get,list,patch,create,update,watch   
mutatingadmissionpolicies                                               admissionregistration.k8s.io/v1       false        MutatingAdmissionPolicy            create,delete,deletecollection,get,list,patch,update,watch   api-extensions
mutatingadmissionpolicybindings                                         admissionregistration.k8s.io/v1       false        MutatingAdmissionPolicyBinding     create,delete,deletecollection,get,list,patch,update,watch   api-extensions
mutatingwebhookconfigurations                                           admissionregistration.k8s.io/v1       false        MutatingWebhookConfiguration       create,delete,deletecollection,get,list,patch,update,watch   api-extensions
validatingadmissionpolicies                                             admissionregistration.k8s.io/v1       false        ValidatingAdmissionPolicy          create,delete,deletecollection,get,list,patch,update,watch   api-extensions
validatingadmissionpolicybindings                                       admissionregistration.k8s.io/v1       false        ValidatingAdmissionPolicyBinding   create,delete,deletecollection,get,list,patch,update,watch   api-extensions
validatingwebhookconfigurations                                         admissionregistration.k8s.io/v1       false        ValidatingWebhookConfiguration     create,delete,deletecollection,get,list,patch,update,watch   api-extensions
configsyncstatuses                  akscss                              aks.clusterconfig.azure.com/v1beta1   true         ConfigSyncStatus                   delete,deletecollection,get,list,patch,create,update,watch   
extensionconfigs                    aksec                               aks.clusterconfig.azure.com/v1beta1   true         ExtensionConfig                    delete,deletecollection,get,list,patch,create,update,watch   
customresourcedefinitions           crd,crds                            apiextensions.k8s.io/v1               false        CustomResourceDefinition           create,delete,deletecollection,get,list,patch,update,watch   api-extensions
apiservices                                                             apiregistration.k8s.io/v1             false        APIService                         create,delete,deletecollection,get,list,patch,update,watch   api-extensions
controllerrevisions                                                     apps/v1                               true         ControllerRevision                 create,delete,deletecollection,get,list,patch,update,watch   
daemonsets                          ds                                  apps/v1                               true         DaemonSet                          create,delete,deletecollection,get,list,patch,update,watch   all
deployments                         deploy                              apps/v1                               true         Deployment                         create,delete,deletecollection,get,list,patch,update,watch   all
replicasets                         rs                                  apps/v1                               true         ReplicaSet                         create,delete,deletecollection,get,list,patch,update,watch   all
statefulsets                        sts                                 apps/v1                               true         StatefulSet                        create,delete,deletecollection,get,list,patch,update,watch   all
selfsubjectreviews                                                      authentication.k8s.io/v1              false        SelfSubjectReview                  create                                                       
tokenreviews                                                            authentication.k8s.io/v1              false        TokenReview                        create                                                       
localsubjectaccessreviews                                               authorization.k8s.io/v1               true         LocalSubjectAccessReview           create                                                       
selfsubjectaccessreviews                                                authorization.k8s.io/v1               false        SelfSubjectAccessReview            create                                                       
selfsubjectrulesreviews                                                 authorization.k8s.io/v1               false        SelfSubjectRulesReview             create                                                       
subjectaccessreviews                                                    authorization.k8s.io/v1               false        SubjectAccessReview                create                                                       
horizontalpodautoscalers            hpa                                 autoscaling/v2                        true         HorizontalPodAutoscaler            create,delete,deletecollection,get,list,patch,update,watch   all
provisioningrequests                provreq,provreqs                    autoscaling.x-k8s.io/v1               true         ProvisioningRequest                delete,deletecollection,get,list,patch,create,update,watch   
podmonitors                         pmon                                azmonitoring.coreos.com/v1            true         PodMonitor                         delete,deletecollection,get,list,patch,create,update,watch   prometheus-operator
servicemonitors                     smon                                azmonitoring.coreos.com/v1            true         ServiceMonitor                     delete,deletecollection,get,list,patch,create,update,watch   prometheus-operator
syncpolicies                                                            azurepolicy.azure.com/v1alpha1        false        SyncPolicies                       delete,deletecollection,get,list,patch,create,update,watch   
cronjobs                            cj                                  batch/v1                              true         CronJob                            create,delete,deletecollection,get,list,patch,update,watch   all
jobs                                                                    batch/v1                              true         Job                                create,delete,deletecollection,get,list,patch,update,watch   all
certificatesigningrequests          csr                                 certificates.k8s.io/v1                false        CertificateSigningRequest          create,delete,deletecollection,get,list,patch,update,watch   
ciliumcidrgroups                    ccg                                 cilium.io/v2                          false        CiliumCIDRGroup                    delete,deletecollection,get,list,patch,create,update,watch   cilium
ciliumclusterwidenetworkpolicies    ccnp                                cilium.io/v2                          false        CiliumClusterwideNetworkPolicy     delete,deletecollection,get,list,patch,create,update,watch   cilium,ciliumpolicy
ciliumendpoints                     cep,ciliumep                        cilium.io/v2                          true         CiliumEndpoint                     delete,deletecollection,get,list,patch,create,update,watch   cilium
ciliumendpointslices                ces                                 cilium.io/v2alpha1                    false        CiliumEndpointSlice                delete,deletecollection,get,list,patch,create,update,watch   cilium
ciliumidentities                    ciliumid                            cilium.io/v2                          false        CiliumIdentity                     delete,deletecollection,get,list,patch,create,update,watch   cilium
ciliuml2announcementpolicies        l2announcement                      cilium.io/v2alpha1                    false        CiliumL2AnnouncementPolicy         delete,deletecollection,get,list,patch,create,update,watch   cilium
ciliumloadbalancerippools           ippools,ippool,lbippool,lbippools   cilium.io/v2                          false        CiliumLoadBalancerIPPool           delete,deletecollection,get,list,patch,create,update,watch   cilium
ciliumlocalredirectpolicies         clrp                                cilium.io/v2                          true         CiliumLocalRedirectPolicy          delete,deletecollection,get,list,patch,create,update,watch   cilium,ciliumpolicy
ciliumnetworkpolicies               cnp,ciliumnp                        cilium.io/v2                          true         CiliumNetworkPolicy                delete,deletecollection,get,list,patch,create,update,watch   cilium,ciliumpolicy
ciliumnodeconfigs                                                       cilium.io/v2                          true         CiliumNodeConfig                   delete,deletecollection,get,list,patch,create,update,watch   cilium
ciliumnodes                         cn,ciliumn                          cilium.io/v2                          false        CiliumNode                         delete,deletecollection,get,list,patch,create,update,watch   cilium
ciliumpodippools                    cpip                                cilium.io/v2alpha1                    false        CiliumPodIPPool                    delete,deletecollection,get,list,patch,create,update,watch   cilium
configs                             config                              config.gatekeeper.sh/v1alpha1         true         Config                             delete,deletecollection,get,list,patch,create,update,watch   
connections                                                             connection.gatekeeper.sh/v1alpha1     true         Connection                         delete,deletecollection,get,list,patch,create,update,watch   
k8sazurev1blockdefault                                                  constraints.gatekeeper.sh/v1beta1     false        K8sAzureV1BlockDefault             delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev1ingresshttpsonly                                              constraints.gatekeeper.sh/v1beta1     false        K8sAzureV1IngressHttpsOnly         delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev1serviceallowedports                                           constraints.gatekeeper.sh/v1beta1     false        K8sAzureV1ServiceAllowedPorts      delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev2blockautomounttoken                                           constraints.gatekeeper.sh/v1beta1     false        K8sAzureV2BlockAutomountToken      delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev2blockhostnamespace                                            constraints.gatekeeper.sh/v1beta1     false        K8sAzureV2BlockHostNamespace       delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev2containerallowedimages                                        constraints.gatekeeper.sh/v1beta1     false        K8sAzureV2ContainerAllowedImages   delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev2noprivilege                                                   constraints.gatekeeper.sh/v1beta1     false        K8sAzureV2NoPrivilege              delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev3allowedcapabilities                                           constraints.gatekeeper.sh/v1beta1     false        K8sAzureV3AllowedCapabilities      delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev3allowedusersgroups                                            constraints.gatekeeper.sh/v1beta1     false        K8sAzureV3AllowedUsersGroups       delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev3containerlimits                                               constraints.gatekeeper.sh/v1beta1     false        K8sAzureV3ContainerLimits          delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev3disallowedcapabilities                                        constraints.gatekeeper.sh/v1beta1     false        K8sAzureV3DisallowedCapabilities   delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev3enforceapparmor                                               constraints.gatekeeper.sh/v1beta1     false        K8sAzureV3EnforceAppArmor          delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev3hostnetworkingports                                           constraints.gatekeeper.sh/v1beta1     false        K8sAzureV3HostNetworkingPorts      delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev3noprivilegeescalation                                         constraints.gatekeeper.sh/v1beta1     false        K8sAzureV3NoPrivilegeEscalation    delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev3readonlyrootfilesystem                                        constraints.gatekeeper.sh/v1beta1     false        K8sAzureV3ReadOnlyRootFilesystem   delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
k8sazurev5hostfilesystem                                                constraints.gatekeeper.sh/v1beta1     false        K8sAzureV5HostFilesystem           delete,deletecollection,get,list,patch,create,update,watch   constraint,constraints
leases                                                                  coordination.k8s.io/v1                true         Lease                              create,delete,deletecollection,get,list,patch,update,watch   
endpointslices                                                          discovery.k8s.io/v1                   true         EndpointSlice                      create,delete,deletecollection,get,list,patch,update,watch   
imagejobs                                                               eraser.sh/v1                          false        ImageJob                           delete,deletecollection,get,list,patch,create,update,watch   
imagelists                                                              eraser.sh/v1                          false        ImageList                          delete,deletecollection,get,list,patch,create,update,watch   
events                              ev                                  events.k8s.io/v1                      true         Event                              create,delete,deletecollection,get,list,patch,update,watch   
expansiontemplate                                                       expansion.gatekeeper.sh/v1beta1       false        ExpansionTemplate                  delete,deletecollection,get,list,patch,create,update,watch   
providers                                                               externaldata.gatekeeper.sh/v1beta1    false        Provider                           delete,deletecollection,get,list,patch,create,update,watch   
flowschemas                                                             flowcontrol.apiserver.k8s.io/v1       false        FlowSchema                         create,delete,deletecollection,get,list,patch,update,watch   
prioritylevelconfigurations                                             flowcontrol.apiserver.k8s.io/v1       false        PriorityLevelConfiguration         create,delete,deletecollection,get,list,patch,update,watch   
nodes                                                                   metrics.k8s.io/v1beta1                false        NodeMetrics                        get,list                                                     
pods                                                                    metrics.k8s.io/v1beta1                true         PodMetrics                         get,list                                                     
nodeinfo                            ni                                  multitenancy.acn.azure.com/v1alpha1   false        NodeInfo                           delete,deletecollection,get,list,patch,create,update,watch   
assign                                                                  mutations.gatekeeper.sh/v1            false        Assign                             delete,deletecollection,get,list,patch,create,update,watch   
assignimage                                                             mutations.gatekeeper.sh/v1alpha1      false        AssignImage                        delete,deletecollection,get,list,patch,create,update,watch   
assignmetadata                                                          mutations.gatekeeper.sh/v1            false        AssignMetadata                     delete,deletecollection,get,list,patch,create,update,watch   
modifyset                                                               mutations.gatekeeper.sh/v1            false        ModifySet                          delete,deletecollection,get,list,patch,create,update,watch   
ingressclasses                                                          networking.k8s.io/v1                  false        IngressClass                       create,delete,deletecollection,get,list,patch,update,watch   
ingresses                           ing                                 networking.k8s.io/v1                  true         Ingress                            create,delete,deletecollection,get,list,patch,update,watch   
ipaddresses                         ip                                  networking.k8s.io/v1                  false        IPAddress                          create,delete,deletecollection,get,list,patch,update,watch   
networkpolicies                     netpol                              networking.k8s.io/v1                  true         NetworkPolicy                      create,delete,deletecollection,get,list,patch,update,watch   
servicecidrs                                                            networking.k8s.io/v1                  false        ServiceCIDR                        create,delete,deletecollection,get,list,patch,update,watch   
runtimeclasses                                                          node.k8s.io/v1                        false        RuntimeClass                       create,delete,deletecollection,get,list,patch,update,watch   
poddisruptionbudgets                pdb                                 policy/v1                             true         PodDisruptionBudget                create,delete,deletecollection,get,list,patch,update,watch   
clusterrolebindings                                                     rbac.authorization.k8s.io/v1          false        ClusterRoleBinding                 create,delete,deletecollection,get,list,patch,update,watch   
clusterroles                                                            rbac.authorization.k8s.io/v1          false        ClusterRole                        create,delete,deletecollection,get,list,patch,update,watch   
rolebindings                                                            rbac.authorization.k8s.io/v1          true         RoleBinding                        create,delete,deletecollection,get,list,patch,update,watch   
roles                                                                   rbac.authorization.k8s.io/v1          true         Role                               create,delete,deletecollection,get,list,patch,update,watch   
deviceclasses                                                           resource.k8s.io/v1                    false        DeviceClass                        create,delete,deletecollection,get,list,patch,update,watch   
resourceclaims                                                          resource.k8s.io/v1                    true         ResourceClaim                      create,delete,deletecollection,get,list,patch,update,watch   
resourceclaimtemplates                                                  resource.k8s.io/v1                    true         ResourceClaimTemplate              create,delete,deletecollection,get,list,patch,update,watch   
resourceslices                                                          resource.k8s.io/v1                    false        ResourceSlice                      create,delete,deletecollection,get,list,patch,update,watch   
priorityclasses                     pc                                  scheduling.k8s.io/v1                  false        PriorityClass                      create,delete,deletecollection,get,list,patch,update,watch   
volumesnapshotclasses               vsclass,vsclasses                   snapshot.storage.k8s.io/v1            false        VolumeSnapshotClass                delete,deletecollection,get,list,patch,create,update,watch   
volumesnapshotcontents              vsc,vscs                            snapshot.storage.k8s.io/v1            false        VolumeSnapshotContent              delete,deletecollection,get,list,patch,create,update,watch   
volumesnapshots                     vs                                  snapshot.storage.k8s.io/v1            true         VolumeSnapshot                     delete,deletecollection,get,list,patch,create,update,watch   
configpodstatuses                                                       status.gatekeeper.sh/v1beta1          true         ConfigPodStatus                    delete,deletecollection,get,list,patch,create,update,watch   
connectionpodstatuses                                                   status.gatekeeper.sh/v1alpha1         true         ConnectionPodStatus                delete,deletecollection,get,list,patch,create,update,watch   
constraintpodstatuses                                                   status.gatekeeper.sh/v1beta1          true         ConstraintPodStatus                delete,deletecollection,get,list,patch,create,update,watch   
constrainttemplatepodstatuses                                           status.gatekeeper.sh/v1beta1          true         ConstraintTemplatePodStatus        delete,deletecollection,get,list,patch,create,update,watch   
expansiontemplatepodstatuses                                            status.gatekeeper.sh/v1beta1          true         ExpansionTemplatePodStatus         delete,deletecollection,get,list,patch,create,update,watch   
mutatorpodstatuses                                                      status.gatekeeper.sh/v1beta1          true         MutatorPodStatus                   delete,deletecollection,get,list,patch,create,update,watch   
providerpodstatuses                                                     status.gatekeeper.sh/v1beta1          true         ProviderPodStatus                  delete,deletecollection,get,list,patch,create,update,watch   
csidrivers                                                              storage.k8s.io/v1                     false        CSIDriver                          create,delete,deletecollection,get,list,patch,update,watch   
csinodes                                                                storage.k8s.io/v1                     false        CSINode                            create,delete,deletecollection,get,list,patch,update,watch   
csistoragecapacities                                                    storage.k8s.io/v1                     true         CSIStorageCapacity                 create,delete,deletecollection,get,list,patch,update,watch   
storageclasses                      sc                                  storage.k8s.io/v1                     false        StorageClass                       create,delete,deletecollection,get,list,patch,update,watch   
volumeattachments                                                       storage.k8s.io/v1                     false        VolumeAttachment                   create,delete,deletecollection,get,list,patch,update,watch   
volumeattributesclasses             vac                                 storage.k8s.io/v1                     false        VolumeAttributesClass              create,delete,deletecollection,get,list,patch,update,watch   
syncsets                                                                syncset.gatekeeper.sh/v1alpha1        false        SyncSet                            delete,deletecollection,get,list,patch,create,update,watch   
constrainttemplates                 constraints                         templates.gatekeeper.sh/v1            false        ConstraintTemplate                 delete,deletecollection,get,list,patch,create,update,watch   
```

## Appendix: raw `kubectl api-versions`

```
$ kubectl api-versions
acn.azure.com/v1alpha
acn.azure.com/v1alpha1
admissionregistration.k8s.io/v1
aks.clusterconfig.azure.com/v1beta1
apiextensions.k8s.io/v1
apiregistration.k8s.io/v1
apps/v1
authentication.k8s.io/v1
authorization.k8s.io/v1
autoscaling.x-k8s.io/v1
autoscaling.x-k8s.io/v1beta1
autoscaling/v1
autoscaling/v2
azmonitoring.coreos.com/v1
azurepolicy.azure.com/v1alpha1
batch/v1
certificates.k8s.io/v1
cilium.io/v2
cilium.io/v2alpha1
config.gatekeeper.sh/v1alpha1
connection.gatekeeper.sh/v1alpha1
constraints.gatekeeper.sh/v1alpha1
constraints.gatekeeper.sh/v1beta1
coordination.k8s.io/v1
discovery.k8s.io/v1
eraser.sh/v1
eraser.sh/v1alpha1
events.k8s.io/v1
expansion.gatekeeper.sh/v1alpha1
expansion.gatekeeper.sh/v1beta1
externaldata.gatekeeper.sh/v1alpha1
externaldata.gatekeeper.sh/v1beta1
flowcontrol.apiserver.k8s.io/v1
metrics.k8s.io/v1beta1
multitenancy.acn.azure.com/v1alpha1
mutations.gatekeeper.sh/v1
mutations.gatekeeper.sh/v1alpha1
mutations.gatekeeper.sh/v1beta1
networking.k8s.io/v1
node.k8s.io/v1
policy/v1
rbac.authorization.k8s.io/v1
resource.k8s.io/v1
scheduling.k8s.io/v1
snapshot.storage.k8s.io/v1
status.gatekeeper.sh/v1alpha1
status.gatekeeper.sh/v1beta1
storage.k8s.io/v1
syncset.gatekeeper.sh/v1alpha1
templates.gatekeeper.sh/v1
templates.gatekeeper.sh/v1alpha1
templates.gatekeeper.sh/v1beta1
v1
```
