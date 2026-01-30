# Tools distribution and usage
Sample steps for migrating stateful Wordress CMS deployment:

* namespace: `wordpress`
* app: `wordpress` Deployment
* DB: `mysql` StatefulSet with PVC `mysql-pv-claim`

I’ll show **minimal, real commands** for each tool, not full production hardening.

---

## 0) Common pre-checks (all tools)

```bash
# Source cluster
kubectl config use-context src
kubectl get ns wordpress
kubectl get deploy,sts,svc,pvc -n wordpress
```

On target cluster:

```bash
kubectl config use-context dst
kubectl create ns wordpress
```

---

## 1) DIY with `kubectl` + MySQL CLI

Here we migrate **manifests + DB data**, no special backup tool.

### 1.1 Export manifests (source)

```bash
kubectl config use-context src

kubectl get all,configmap,secret,svc,ingress,pvc \
  -n wordpress -o yaml > wordpress-src.yaml
```

*Tip:* you may want to edit out `status`, `resourceVersion`, etc. (or run through `kustomize`).

### 1.2 Logical DB backup (source)

Find MySQL pod:

```bash
kubectl -n wordpress get pods -l app=mysql
MYSQL_POD=$(kubectl -n wordpress get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
```

Dump DB (example creds):

```bash
kubectl -n wordpress exec -it "$MYSQL_POD" -- \
  mysqldump -u root -p wordpress > wordpress.sql
```

(You’ll be prompted for the password.)

### 1.3 Recreate app on target

```bash
kubectl config use-context dst
kubectl apply -f wordpress-src.yaml
kubectl -n wordpress get pods
```

Wait until MySQL is Running.

### 1.4 Restore DB on target

```bash
MYSQL_POD_DST=$(kubectl -n wordpress get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')

kubectl -n wordpress cp wordpress.sql "$MYSQL_POD_DST":/tmp/wordpress.sql

kubectl -n wordpress exec -it "$MYSQL_POD_DST" -- \
  sh -c 'mysql -u root -p wordpress < /tmp/wordpress.sql'
```

Then switch DNS / Ingress to point to the new cluster.

👉 Pros: pure CLI, no extra deps.
👉 Cons: manual, easy to mess up, no history.

---

## 2) Velero CLI (namespace backup & restore)

Assume Velero already installed on both clusters and configured with same backup storage. Commands taken from Velero examples for namespace backup/restore. ([velero.io][1])

### 2.1 Create backup on source

```bash
kubectl config use-context src

# optional: check location
velero backup-location get

# backup whole wordpress namespace (incl. PVs if CSI/restic is configured)
velero backup create wordpress-backup \
  --include-namespaces wordpress \
  --wait
```

### 2.2 Check backup

```bash
velero backup describe wordpress-backup --details
velero backup logs wordpress-backup
```

### 2.3 Restore on target

```bash
kubectl config use-context dst

# namespace must exist or be auto-created depending on setup
kubectl create ns wordpress || true

velero restore create wordpress-restore \
  --from-backup wordpress-backup \
  --wait
```

If you need to change namespace name:

````bash
velero restore create wordpress-restore \
  --from-backup wordpress-backup \
  --namespace-mappings wordpress:wordpress2 \
  --wait
``` :contentReference[oaicite:1]{index=1}  

### 2.4 Verify

```bash
kubectl -n wordpress get all,pvc
````

Then update DNS / Ingress.

👉 Pros: simple end-to-end, keeps PVC data.
👉 Cons: depends on storage integration and Velero config.

---

## 3) Konveyor Crane CLI (config via Crane + MySQL dump for data)

Crane handles manifests; we’ll use DB-native backup for data to avoid guessing `transfer-pvc` flags. Commands from official README. ([GitHub][2])

### 3.1 Export from source

```bash
kubectl config use-context src

# Export all resources from wordpress namespace
crane export -n wordpress
```

This creates `export/resources/wordpress/*`.

### 3.2 Transform manifests

```bash
crane transform
```

Results go to `transform/resources/wordpress`.

### 3.3 Generate redeployable YAML

```bash
crane apply
```

You now have `output/resources/wordpress/*.yaml` cleaned of cluster-specific metadata.

### 3.4 Apply to target

```bash
kubectl config use-context dst
kubectl create ns wordpress || true

kubectl -n wordpress apply -f output/resources/wordpress
```

### 3.5 Migrate MySQL data (same as DIY flow)

On **source**:

```bash
kubectl config use-context src
MYSQL_POD=$(kubectl -n wordpress get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
kubectl -n wordpress exec -it "$MYSQL_POD" -- \
  mysqldump -u root -p wordpress > wordpress.sql
```

On **target**:

```bash
kubectl config use-context dst
MYSQL_POD_DST=$(kubectl -n wordpress get pod -l app=mysql -o jsonpath='{.items[0].metadata.name}')
kubectl -n wordpress cp wordpress.sql "$MYSQL_POD_DST":/tmp/wordpress.sql
kubectl -n wordpress exec -it "$MYSQL_POD_DST" -- \
  sh -c 'mysql -u root -p wordpress < /tmp/wordpress.sql'
```

👉 Pros: nice for reconstructing manifests / preparing GitOps.
👉 Cons: data step is separate; you can look into `crane transfer-pvc` later if you want PV-level copy. ([GitHub][3])

---

## 4) Portworx Stork (`storkctl`) – PV-level migration

Assumes Portworx + Stork installed and both clusters paired. Commands from Portworx migration docs. ([docs.portworx.com][4])

### 4.1 Create ClusterPair (source)

```bash
kubectl config use-context src

storkctl create clusterpair migration-cluster-pair \
  --src-kube-file /tmp/src-kubeconfig \
  --dest-kube-file /tmp/dst-kubeconfig \
  --namespace portworx
```

(Flags will differ if you use NFS/object storage; see docs for storage flags.)

Check:

```bash
storkctl get clusterpair -n portworx
```

Both `STORAGE-STATUS` and `SCHEDULER-STATUS` should be `Ready`.

### 4.2 Start migration (namespace `wordpress`)

```bash
storkctl create migration wordpress-migration \
  --clusterPair migration-cluster-pair \
  --namespaces wordpress \
  --includeResources=true \
  --startApplications=true \
  --namespace portworx
```

### 4.3 Monitor

```bash
storkctl get migration -n portworx
kubectl describe migration wordpress-migration -n portworx
```

Portworx will recreate the resources + Portworx volumes on the destination cluster.

👉 Pros: full PV-level migration with Portworx smarts.
👉 Cons: tied to Portworx; a bit more setup (ClusterPair, storage backend).

---

## 5) Kasten K10 (using `kubectl` to drive K10)

K10 is mostly UI / API driven, but you still use **CLI for install and CRDs**. Commands below are from Kasten’s install and policy docs. ([Medium][5])

### 5.1 Install K10 on both clusters (Helm, once)

```bash
helm repo add kasten https://charts.kasten.io/

kubectl create ns kasten-io

helm install k10 kasten/k10 -n kasten-io
```

Mark default VolumeSnapshotClass as usable by K10:

```bash
kubectl annotate volumesnapshotclass \
  $(kubectl get volumesnapshotclass -o=jsonpath='{.items[?(@.metadata.annotations.snapshot\.storage\.kubernetes\.io\/is-default-class=="true")].metadata.name}') \
  k10.kasten.io/is-snapshot-class=true
```

Repeat (appropriately) on destination cluster.

### 5.2 Define a backup policy for `wordpress` (source)

Create `wp-backup-policy.yaml`:

```yaml
apiVersion: config.kio.kasten.io/v1alpha1
kind: Policy
metadata:
  name: wp-backup-policy
  namespace: kasten-io
spec:
  frequency: "@hourly"
  actions:
    - action: backup
  selector:
    matchLabels:
      k10.kasten.io/appNamespace: wordpress
  retention:
    daily: 7
```

Apply:

```bash
kubectl apply -f wp-backup-policy.yaml
```
## Research notes


Label app namespace so K10 discovers it:

```bash
kubectl label ns wordpress k10.kasten.io/appNamespace=wordpress
```

You can either wait for the policy to run or trigger a run via K10 UI / API.

### 5.3 Export & import to target cluster

On **source**, K10 exports backups to an object store (configured via a Location Profile). On **destination**, you:

1. Install K10 as above.
2. Create an **Import Policy** pointing to same location profile (object store). That’s also a `Policy` CR; example skeleton:

```yaml
apiVersion: config.kio.kasten.io/v1alpha1
kind: Policy
metadata:
  name: wp-import-policy
  namespace: kasten-io
spec:
  actions:
    - action: import
  selector:
    matchLabels:
      k10.kasten.io/appNamespace: wordpress
```

Apply:

```bash
kubectl apply -f wp-import-policy.yaml
```

Then trigger the policy (via K10 UI or by creating a `RunAction` object – still CLI, but a bit verbose).

👉 In practice, people typically:

* Use **CLI to install & define policies**
* Use **K10 UI** to run backup/restore/migration jobs.

---

## Which flow to actually use?

For your WordPress+MySQL case:

* **You want “pure OSS, app-owner friendly”** → Velero or Crane + mysqldump
* **You already use Portworx** → Stork migration
* **You have K10 in the stack** → K10 (CLI for policies, UI for execution)
* **You just need a lab migration / PoC** → DIY kubectl + mysqldump is fine

If you tell me which stack you actually run (cloud, storage, CSI vs in-tree, etc.), I can narrow this down to **one recommended flow** and tweak the commands (namespaces, classes, flags) to be copy-paste ready for your environment.

[1]: https://velero.io/docs/v1.4/resource-filtering/?utm_source=chatgpt.com "Velero Docs - Resource filtering"
[2]: https://github.com/migtools/crane "GitHub - migtools/crane: Tool for migrating Kubernetes workloads, and their data, between clusters."
[3]: https://github.com/migtools/crane-runner/issues/57?utm_source=chatgpt.com "Add the ability to use a custom pvc transfer image for ..."
[4]: https://docs.portworx.com/portworx-enterprise/operations/migration/migration-with-stork "Migration with Stork | Portworx Enterprise Documentation"
[5]: https://medium.com/%40saikrishnajaya1997/migrating-application-from-one-cluster-to-another-cluster-using-kasten-k10-322fcf2fbd09?utm_source=chatgpt.com "Migrating Application From One Cluster to Another ..."
