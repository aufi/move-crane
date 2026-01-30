

# **Migration tool comparison** including **Konveyor Crane** — focused on **application migration and backup from an app-owner / namespace admin perspective**:

---

## Tools with **Konveyor Crane**

**What it is:**
Crane is a migration tool from the **Konveyor community** (a CNCF Sandbox project) that helps **application owners migrate Kubernetes workloads and their state between clusters** — including manifests, PVs, and Secrets. It aims to automate and streamline cluster-to-cluster migrations and support conversion to GitOps-ready manifests. ([GitHub][1])

**Key Capabilities:**

* Migrate workloads *and data* between Kubernetes clusters. ([GitHub][1])
* Inspect running applications and help *reconstruct redeployable manifests*. ([GitHub][1])
* Export PVs and state via rsync-based transfer. ([www.slideshare.net][2])
* Can help “bootstrapping” GitOps pipelines by generating usable manifests. ([GitHub][1])

**Admin Privileges:**

* Designed so **application owners can run migrations without full cluster-admin**.
* Storage migration may still require certain access or coordination with cluster admins (e.g., RBAC for PV access).

---

## Updated Tool Comparison Matrix

| Tool / Approach             | Config (YAML) | Data / State | Cross-cluster | No Admin | Portability | Notes                                                                  |
| --------------------------- | ------------- | ------------ | ------------- | -------- | ----------- | ---------------------------------------------------------------------- |
| **GitOps** (Argo CD / Flux) | ✅             | ❌            | ✅             | ✅        | High        | Great for config; doesn’t handle data natively                         |
| **Velero**                  | ✅             | ✅            | ✅             | ⚠️       | Medium      | Namespace backup & restore; object storage dependency ([velero.io][3]) |
| **DB-native tools**         | ❌             | ✅            | ✅             | ✅        | High        | Focuses on data; not Kubernetes manifests                              |
| **CSI snapshots**           | ❌             | ✅            | ⚠️            | ❌        | Low         | Fast local snapshots; not portable across providers                    |
| **🌟 Konveyor Crane**       | ✅             | ✅            | ✅             | ⚠️       | High        | Combines workload + state migration; creates manifests ([GitHub][1])   |

---

## How Crane Compares

### Compared to **Velero**

* **Velero** focuses on backup + restore (namespace or broader), storing data in object storage for later restore. ([velero.io][3])
* **Crane** focuses on *live migration*: exporting state and manifests and applying them to a target cluster, with built-in logic to help transform workloads. ([GitHub][1])

### Compared to **GitOps**

* GitOps is about *desired state* and consistent deployments.
* Crane helps *generate or reconstruct* that desired state from running clusters, which can feed into GitOps flows. ([GitHub][1])

### Compared to **DB-native backups**

* DB tools handle deep state (schema + data) but **don’t handle Kubernetes manifests** — Crane handles both. ([GitHub][1])

### Compared to **CSI snapshots**

* CSI snapshots are low-level and tied to a specific storage provider; Crane offers a more application-centric experience.

---

## Practical Use Cases for Crane

✔ Migrating an app + its persistent data to a new cluster
✔ Extracting stateful workloads when manifests are outdated or missing
✔ Bootstrapping a GitOps repository from an existing cluster
✔ Rehosting across distributions (e.g., vanilla Kubernetes → OpenShift) ([www.slideshare.net][2])

---

## Summary (with Crane)

**Tool strategy by need:**

* **Config only, stateless app:** GitOps
* **Backup restore + scheduled DR:** Velero
* **Deep data + schema fidelity:** DB-native tools
* **Live cluster-to-cluster migration (config + data):** **Konveyor Crane**
* **Fast snapshots same storage:** CSI snapshots

---

## Decision Tree (Which tool when)

**Q1: Is the application stateless?**

* **Yes** → **GitOps only**
* **No** → go to Q2

**Q2: Do you need data portability across storage/providers?**

* **Yes** → **GitOps + DB-native backup**
* **No / same storage** → go to Q3

**Q3: Do you want backup/restore or live migration?**

* **Backup/DR** → **Velero**
* **Live migration / reconstruct manifests** → **Konveyor Crane**

**Q4: Do you lack up-to-date manifests?**

* **Yes** → **Konveyor Crane → GitOps**
* **No** → chosen tool + **GitOps**

---

## Step-by-Step Migration Flows

### A) Stateless App (GitOps)

1. Export/maintain manifests (Helm/Kustomize)
2. Commit to Git
3. Connect repo to target cluster (Argo CD / Flux)
4. Deploy
5. Switch traffic

---

### B) Stateful App – Portable Data (GitOps + DB tools)

1. Identify stateful components
2. Take DB backup (logical dump)
3. Deploy app via GitOps in target
4. Restore DB
5. Validate & cut over

---

### C) Stateful App – Backup/Restore (Velero)

1. Velero backup (namespace + PV if supported)
2. Deploy Velero in target cluster
3. Restore namespace
4. Validate data & app
5. Cut over

---

### D) Live App Migration / Missing Manifests (Konveyor Crane)

1. Analyze running app with Crane
2. Export manifests + migrate data (rsync/PV)
3. Apply to target cluster
4. (Optional) Commit generated manifests to Git
5. Validate & cut over

---

## Quick Mapping

* **Config only** → GitOps
* **Config + data (DR)** → Velero
* **Config + data (live, app-centric)** → Konveyor Crane
* **Highest data fidelity** → DB-native backups
* **Repeatability & audit** → always add GitOps

If you want, I can compress this into a **1-page internal playbook** or add **downtime vs zero-downtime variants**.

# CLI

Yes. There **are other CLI-style migration tools**, but **Crane is the only one that is truly app-centric and Kubernetes-native**.
Below is a **concise, research-oriented overview** of the realistic alternatives and how they differ.

---

## CLI Migration Tools (besides Konveyor Crane)

### 1) **Velero CLI**

**Type:** Backup / restore CLI
**Focus:** Recovery, not live migration

**What it can do**

* Backup and restore namespaces between clusters
* Migrate apps indirectly via backup → restore
* Handle PVs via snapshots or restic

**What it cannot do**

* Live migration
* Reconstruct manifests from running apps
* Fine-grained app transformation

**Typical user**

* SRE / platform engineer

**Position vs Crane**

* **Velero = DR-first**
* **Crane = migration-first**

---

### 2) **Kasten K10 (CLI + UI)** *(commercial)*

**Type:** Backup & mobility platform
**Focus:** Application mobility

**What it can do**

* App-centric backup and restore
* Cross-cluster migration
* Policy-based automation

**Limitations**

* Heavy platform component
* Commercial licensing

**Typical user**

* Enterprises with compliance needs

**Position vs Crane**

* More complete but heavier
* Less developer-friendly than Crane

---

### 3) **Portworx px-migrate / storkctl** *(commercial / semi-open)*

**Type:** Storage-centric migration CLI
**Focus:** Stateful workloads

**What it can do**

* Migrate PVs between clusters
* Handle large datasets efficiently

**Limitations**

* Tied to Portworx storage
* Not Kubernetes-resource focused

**Typical user**

* Storage / infra teams

**Position vs Crane**

* Data-first vs app-first

---

### 4) **Kubectl-based DIY migration**

**Type:** Native CLI workflow
**Focus:** Manual, flexible

**Tools**

* `kubectl get -o yaml`
* `kubectl apply`
* `kubectl cp`
* `rsync`

**Strengths**

* No extra tooling
* Works with minimal permissions

**Weaknesses**

* Error-prone
* No automation
* No state awareness

**Position vs Crane**

* Crane automates this pattern

---

### 5) **Operator-specific CLIs**

**Type:** Domain-specific tools
**Examples**

* `rook-ceph` tools
* DB operator backup CLIs
* Kafka MirrorMaker

**Strengths**

* Deep consistency guarantees

**Weaknesses**

* Narrow scope
* Not general app migration

**Position vs Crane**

* Complementary, not competing

---

## Why Crane Is (Mostly) Unique

Crane is the only tool that:

* Works primarily as a **CLI**
* Is **Kubernetes-native**
* Migrates **both manifests and data**
* Is **app/namespace-scoped**
* Does **not require permanent controllers**

That’s why it appears often in **modernization / rehosting** discussions.

---

## Quick Comparison

| Tool           | CLI-first | App-centric | Data | Live migration | Open |
| -------------- | --------- | ----------- | ---- | -------------- | ---- |
| Konveyor Crane | ✅         | ✅           | ✅    | ⚠️             | ✅    |
| Velero CLI     | ✅         | ⚠️          | ✅    | ❌              | ✅    |
| Kasten K10     | ⚠️        | ✅           | ✅    | ❌              | ❌    |
| Portworx       | ⚠️        | ❌           | ✅    | ⚠️             | ⚠️   |
| kubectl DIY    | ✅         | ❌           | ⚠️   | ❌              | ✅    |

---

### Bottom line

* **Crane** → best general-purpose CLI for Kubernetes app migration
* **Velero** → backup-driven migration
* **Others** → storage- or vendor-specific
