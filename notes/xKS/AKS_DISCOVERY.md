# Read-only AKS discovery runbook

## Purpose

Collect evidence for the [AKS migration plan](AKS.md) before choosing transformations or copying data. These commands read cluster and Azure configuration and write local artifacts. They do not export secret values or create cluster resources.

Use a separate local directory per source/target profile. The filenames below are relative to that directory. Run the general API discovery in [PROVIDER_VALIDATION.md](PROVIDER_VALIDATION.md) there as well. Record each command's success, denial, or missing API in the report; an empty or failed output is not evidence that a feature is absent.

## Inputs and tools

Set these values for the selected run:

```bash
SOURCE='aks-source-context'
TARGET='ocp-target-context'
SOURCE_NAMESPACE='application-source'
TARGET_NAMESPACE='application-target'
AZURE_SUBSCRIPTION='subscription-id'
AKS_RESOURCE_GROUP='aks-resource-group'
AKS_CLUSTER='aks-cluster-name'
```

Use an existing kubeconfig for both contexts. For Microsoft Entra-authenticated AKS access, ensure the kubeconfig exec authentication helper works with the Crane build as well as with kubectl. Kubernetes read permissions and Azure read permissions are independent. Azure CLI access is optional evidence collection, not a requirement for every Crane invocation.

Record local CLI versions and actual server versions:

```bash
az version > azure-cli-version.json
kubectl --context "$SOURCE" version -o yaml > source-version.yaml
kubectl --context "$TARGET" version -o yaml > target-version.yaml
kubectl --context "$TARGET" get clusterversion version -o yaml > target-clusterversion.yaml
crane version > crane-version.txt
```

Also record plugin commits, mover image digests, and the target infrastructure in the report.

## Azure cluster configuration

The selected query avoids retrieving kubeconfig credentials. It includes resource and identity identifiers needed for dependency analysis.

```bash
az aks show \
  --subscription "$AZURE_SUBSCRIPTION" \
  --resource-group "$AKS_RESOURCE_GROUP" \
  --name "$AKS_CLUSTER" \
  --query '{id:id,kind:kind,location:location,kubernetesVersion:kubernetesVersion,currentKubernetesVersion:currentKubernetesVersion,sku:sku,nodeResourceGroup:nodeResourceGroup,apiServerAccessProfile:apiServerAccessProfile,networkProfile:networkProfile,storageProfile:storageProfile,oidcIssuerProfile:oidcIssuerProfile,securityProfile:securityProfile,addonProfiles:addonProfiles,ingressProfile:ingressProfile,identity:identity,identityProfile:identityProfile}' \
  -o json > source-azure-profile.json

az aks nodepool list \
  --subscription "$AZURE_SUBSCRIPTION" \
  --resource-group "$AKS_RESOURCE_GROUP" \
  --cluster-name "$AKS_CLUSTER" \
  --query '[].{name:name,osType:osType,osSKU:osSKU,vmSize:vmSize,mode:mode,orchestratorVersion:orchestratorVersion,zones:availabilityZones,labels:nodeLabels,taints:nodeTaints,vnetSubnetID:vnetSubnetID,podSubnetID:podSubnetID}' \
  -o json > source-nodepools.json
```

These values do not prove effective egress. Obtain the relevant route table, NSG, Azure Firewall/NAT, proxy, private DNS, and peering details from the network owner. Record only the paths used by the application and mover. For identity-enabled workloads, request the relevant federated credential and Azure role assignment metadata from the identity owner. A cluster OIDC issuer setting alone does not prove application trust or authorization.

## Kubernetes application and scheduling evidence

The general inventory should retain relevant workload specs through the established export process. Supplement it with metadata and scheduling evidence:

```bash
kubectl --context "$SOURCE" get namespace "$SOURCE_NAMESPACE" -o yaml > source-namespace.yaml
kubectl --context "$TARGET" get namespace "$TARGET_NAMESPACE" -o yaml > target-namespace.yaml
kubectl --context "$SOURCE" get nodes \
  -L kubernetes.io/os,kubernetes.io/arch,kubernetes.azure.com/agentpool,topology.kubernetes.io/zone \
  -o wide > source-nodes.txt
kubectl --context "$SOURCE" -n "$SOURCE_NAMESPACE" get serviceaccount -o yaml > source-serviceaccounts.yaml
kubectl --context "$SOURCE" -n "$SOURCE_NAMESPACE" get networkpolicy -o yaml > source-networkpolicies.yaml
kubectl --context "$SOURCE" -n "$SOURCE_NAMESPACE" get pods \
  -o 'custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,SERVICEACCOUNT:.spec.serviceAccountName,IMAGES:.spec.containers[*].image,INIT_IMAGES:.spec.initContainers[*].image,PVC:.spec.volumes[*].persistentVolumeClaim.claimName' \
  > source-pod-dependencies.txt
```

Inspect Deployment, StatefulSet, Job, and CronJob pod templates for fixed UID/GID, `fsGroup`, capabilities, seccomp, volume mounts, init containers, node selectors, affinity, tolerations, and identity metadata. Compare a running Pod with its owning template to identify admission-injected tokens, environment variables, and sidecars. A controller-managed child is evidence, not automatically an independent workload to redeploy.

Do not put full Secret, token, kubeconfig, or rclone configuration contents in the evidence directory. Full application exports can contain credentials in Secrets, environment variables, or custom resources; keep those working artifacts separate from shareable reports.

## Exposure inventory

```bash
kubectl --context "$SOURCE" get ingressclass -o yaml > source-ingressclasses.yaml
kubectl --context "$SOURCE" -n "$SOURCE_NAMESPACE" get ingress,service -o yaml > source-exposure.yaml
```

After API discovery confirms Gateway API resources are served, query them separately. Use the fully qualified Gateway API name to avoid confusion with Istio's `Gateway` kind:

```bash
kubectl --context "$SOURCE" get gatewayclasses.gateway.networking.k8s.io -o yaml > source-gatewayclasses.yaml
kubectl --context "$SOURCE" -n "$SOURCE_NAMESPACE" get gateways.gateway.networking.k8s.io -o yaml > source-gateways.yaml
kubectl --context "$SOURCE" -n "$SOURCE_NAMESPACE" get httproutes.gateway.networking.k8s.io -o yaml > source-httproutes.yaml
kubectl --context "$SOURCE" -n "$SOURCE_NAMESPACE" get referencegrants.gateway.networking.k8s.io -o yaml > source-referencegrants.yaml
```

Inspect other served route kinds and controller-specific policies if the application uses them. Follow cross-namespace `parentRefs`, backend references, certificate references, and ReferenceGrants beyond the exported namespace. For every class, identify the actual controller deployment/version or obtain managed add-on evidence. Record controller-managed DNS and Key Vault certificate dependencies outside the namespace.

## Storage and secret-provider inventory

```bash
kubectl --context "$SOURCE" -n "$SOURCE_NAMESPACE" get pvc -o yaml > source-pvcs.yaml
kubectl --context "$SOURCE" get storageclass,csidriver -o yaml > source-csi.yaml
kubectl --context "$TARGET" get storageclass,csidriver -o yaml > target-csi.yaml
```

For each application PVC, read its bound PV individually and record provisioner, `volumeMode`, filesystem/protocol, topology, mount options, reclaim policy, capacity, and references to CSI Secrets. Do not dump unrelated PVs or fetch the referenced Secret values. Resolve CSI driver versions through installed workload images or administrator evidence; a `CSIDriver` object alone does not contain the running driver version.

For Azure Files, determine SMB or NFS from effective volume configuration. Record whether UID/GID and modes come from mount options. Inventory StatefulSet claim templates, snapshots/data sources, and any application use of a share outside Kubernetes.

If Secrets Store APIs are served and the application uses them:

```bash
kubectl --context "$SOURCE" -n "$SOURCE_NAMESPACE" get secretproviderclasses.secrets-store.csi.x-k8s.io -o yaml > source-secretproviderclasses.yaml
```

Record provider installation, selected identity, Key Vault endpoint, mounted object references, and secret sync/rotation settings. Review CR parameters before sharing artifacts because custom resource fields can contain sensitive configuration.

## Finish the discovery gate

Before cluster-writing validation begins, complete the dependency register in [AKS.md](AKS.md) and answer:

- Can the CLI authenticate to and reach both APIs for the duration of a transfer?
- Which exposure objects are retained, replaced, or blocked, and how is private access preserved?
- Which Azure identities, registries, external services, and controllers need target preparation?
- Which target CSI class and permissions satisfy each PVC and claim template?
- Which transport will be tested, and who can verify the relevant DNS/firewall path?
- Which findings remain unknown because of denied access or missing evidence?

Actual pod-to-router connectivity, storage provisioning, SCC admission, image pulls, and data checks belong to the validation phase. Do not mark them passed based on discovery configuration alone.
