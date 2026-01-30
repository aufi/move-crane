# Application Migration, Backup & Restore (App-centric, non-cluster-admin)


# General steps

---

## 1. Scope & Perspective

**Role:** application owner / namespace admin
**Goal:** migrate an application between Kubernetes clusters
**Out of scope:** cluster setup, infrastructure, storage classes, CRDs

---

## 2. Problem Definition

**Application migration =**

* redeploying workloads in a different cluster
* preserving configuration
* restoring data
* minimizing downtime

**It is NOT:**

* moving a cluster
* replicating infrastructure

---

## 3. What “an application” means in Kubernetes

### Configuration layer

* Deployments / StatefulSets
* Services
* Ingress / Gateway
* ConfigMaps
* Secrets
* Labels / annotations

### State layer

* Persistent Volumes (data)
* External services (databases, caches, object storage)

---

## 4. Migration – core strategies

### A) Stateless applications

**Steps:**

1. Export manifests
2. Redeploy in target cluster
3. Redirect traffic

**Risk:** low
**Admin privileges:** not required

---

### B) Stateful applications

**Additional concerns:**

* data consistency
* data format
* storage compatibility

**Common approaches:**

* DB dump → import
* CSI snapshot → restore
* Application-level backup (Velero)

**Admin privileges:** sometimes partially required (storage-related)

---

## 5. Backup & Restore (application level)

### What must be backed up

* Kubernetes resources (YAML)
* Persistent data
* Metadata

### What is NOT sufficient

* only PV snapshots
* only Git manifests without data

### Tools & methods

* Velero (namespace-scoped)
* Database-native backups (pg_dump, mysqldump)
* Object storage exports

---

## 6. GitOps as a migration mechanism

**Principle:**

* Git is the source of truth
* The cluster is only a runtime

**Migration means:**

* connecting the same repo to a new cluster
* letting the GitOps engine reconcile state

**Pros:**

* auditability
* rollback
* repeatability

**Cons:**

* does not solve data migration automatically

---

## 7. What a non-admin can / cannot do

### Can do

* export YAML manifests
* manage resources within a namespace
* run Velero backups (if permitted)
* control GitOps deployments

### Cannot do

* change storage classes
* snapshot PVs without support
* modify cluster-wide RBAC

---

## 8. Typical migration scenarios

* on-prem → cloud
* dev → prod cluster
* cloud A → cloud B
* cluster upgrade without downtime

---

## 9. Common mistakes

* ignoring Secrets
* overlooking DNS / ingress changes
* backing up data without application context
* migrating without testing restore

---

## 10. Recommended migration checklist

1. Identify application resources
2. Separate stateless vs stateful parts
3. Prepare data backups
4. Prepare Git / manifests
5. Deploy to target cluster
6. Restore data
7. Test
8. Cut over traffic

---

## 11. Research-style Q&A

**Q: Do I need cluster-admin privileges?**
A: No, unless you need to manage storage or cluster-wide resources.

**Q: Is GitOps required?**
A: No, but it significantly simplifies migration.

**Q: Can applications be migrated with zero downtime?**
A: Yes, especially stateless or read-only workloads.

**Q: What is the hardest part?**
A: Data and data consistency.

---

## 12. One-line summary

**Kubernetes application migration is primarily redeployment plus state restoration, not cluster movement.**

---

If you want next:

* 📄 **internal guideline / playbook**
* 🧠 **decision tree**
* 🛠️ **tool comparison (Velero vs GitOps vs DB-native)**


---

## Resources

### Core concepts (application-centric view)

1. **Kubernetes Docs – Managing Applications**
   [https://kubernetes.io/docs/concepts/workloads/controllers/](https://kubernetes.io/docs/concepts/workloads/controllers/)
2. **CNCF TAG Storage – Cloud Native App Backup & Migration**
   [https://github.com/cncf/tag-storage/blob/main/app-backup-migration.md](https://github.com/cncf/tag-storage/blob/main/app-backup-migration.md)
3. **Google Cloud Blog – Application portability in Kubernetes**
   [https://cloud.google.com/blog/products/containers-kubernetes/portable-applications-with-kubernetes](https://cloud.google.com/blog/products/containers-kubernetes/portable-applications-with-kubernetes)

### Backup & restore (namespace / app scope)

4. **Velero Documentation (User Guides)**
   [https://velero.io/docs/](https://velero.io/docs/)
5. **Velero Blog – Backup and Restore Kubernetes Applications**
   [https://velero.io/blog/backup-and-restore-kubernetes-applications/](https://velero.io/blog/backup-and-restore-kubernetes-applications/)
6. **VMware Tanzu Blog – App-level backup strategies**
   [https://tanzu.vmware.com/content/blog/kubernetes-backup-and-restore-considerations](https://tanzu.vmware.com/content/blog/kubernetes-backup-and-restore-considerations)

### Migration between clusters

7. **Kubernetes Patterns – Application Migration**
   [https://k8spatterns.io/migrating/](https://k8spatterns.io/migrating/)
8. **Red Hat Blog – Moving applications between OpenShift clusters**
   [https://www.redhat.com/en/blog/migrating-applications-between-openshift-clusters](https://www.redhat.com/en/blog/migrating-applications-between-openshift-clusters)
9. **Weaveworks Blog – GitOps-based application migration**
   [https://www.weave.works/blog/migrating-kubernetes-workloads-with-gitops](https://www.weave.works/blog/migrating-kubernetes-workloads-with-gitops)
10. **Argo CD Documentation – Multi-cluster deployments**
    [https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters)

### Stateful apps & data (application owner perspective)

11. **Google SRE Blog – Running Stateful Applications**
    [https://sre.google/sre-book/running-distributed-systems/](https://sre.google/sre-book/running-distributed-systems/)
12. **CNCF Webinar – Stateful Workload Migration**
    [https://www.cncf.io/online-programs/stateful-workload-migration-in-kubernetes/](https://www.cncf.io/online-programs/stateful-workload-migration-in-kubernetes/)
13. **Portworx Blog – Application-centric migration**
    [https://portworx.com/blog/application-migration-kubernetes/](https://portworx.com/blog/application-migration-kubernetes/)

### Practical guides / community experience

14. **Medium – Kubernetes app migration without cluster-admin**
    [https://medium.com/@joshrosso/kubernetes-application-migration-without-cluster-admin-access-8c4c1f5e2c6a](https://medium.com/@joshrosso/kubernetes-application-migration-without-cluster-admin-access-8c4c1f5e2c6a)
15. **Awesome Kubernetes – Backup & Migration**
    [https://github.com/ramitsurana/awesome-kubernetes#backup-and-restore](https://github.com/ramitsurana/awesome-kubernetes#backup-and-restore)
