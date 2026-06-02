# Test day notes

## Main objections

- test that state-less kubernetes/openshift deployments could be migrated from one cluster to another (same cluster versions), but all possible wokrload needs to be supported (KubernetesPlugin is capable cleanup all possible resources to allow its import to target cluster)
- test multistage transformation with custom stages with kustomize, try namespaces change, labels or image changes
- test cluster-level resouces migration
- test validation
- test custom plugin creation with assistant (buildconfig to shipwright)
- ensure a relevant docs exist for crane (state-less use cases)

## Prerequisites
- Linux or Mac or Windows machine
- source and destination clusters, need to cover: openshift current 4 version, upstream kubernetes (minikube or kind)
- crane tool

## Focus areas (by priority)

### State-less resources could be migrated (KubernetesPlugin cleanup fully works)

Main target: find or create relevant real-world deployments (stateless or being possible to start after stateless migration) and confirm it gets successfully migrated.

### Multistage transformation with kustomize works and its clear to users

Main target: ensure multistage transform with custom changes using kustomize (or multiple plugins if available) works, has reasonable docs and is user-friendly enough.


### Cluster-level resources referenced from migrated app are correctly migrated

Main target: prepare application with refs to cluster-level resources (CLRB, CR, etc.) and ensure those resources gets migrated (with cluster-admin permissions), so application can start on target cluster.

Resources required by application that cannot be migrated by crane, needs to be reported by crane to user with docs to migrate on their own.


## Expected reports

- blocking bugs
- workaround-able bugs
- docs&recommendations

## Questions
- does it make sense work on transform/ dir iteratively stage-by-stage or just generate whole dir again if some change is needed?
