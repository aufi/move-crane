# Practical analysis of the kubectl + Krew ecosystem

grouped by **plugin categories**, with **representative plugins** and **what problems they solve**.
(There are **200+ plugins**; listing *all* individually is not useful—this is the complete **functional coverage**.)

---

## kubectl + Krew Ecosystem Overview

**Krew** = plugin manager for kubectl
**Purpose** = extend kubectl via standalone CLIs following the kubectl UX

Install once:

```bash
kubectl krew install <plugin>
```

---

## Krew Plugin Categories & Summary Table

| Category                        | Example plugins                              | What they do                                              | Typical users      |
| ------------------------------- | -------------------------------------------- | --------------------------------------------------------- | ------------------ |
| **Resource inspection & UX**    | `neat`, `tree`, `view-secret`, `whoami`      | Improve readability, visualize ownership, inspect secrets | App owners, DevOps |
| **Debugging & troubleshooting** | `debug`, `doctor`, `sniff`, `trace`          | Pod/node debugging, network tracing, diagnostics          | SRE, platform      |
| **Context & config mgmt**       | `ctx`, `ns`, `konfig`, `kubecm`              | Switch contexts/namespaces, kubeconfig mgmt               | Everyone           |
| **RBAC & security**             | `access-matrix`, `rbac-lookup`, `who-can`    | Analyze permissions and access                            | Platform, security |
| **Backup / migration helpers**  | `velero`, `df-pv`, `pv-migrate`              | Trigger backups, inspect/move PV data                     | SRE, app owners    |
| **GitOps & delivery**           | `argo-rollouts`, `flux`, `kustomize`         | Progressive delivery, GitOps workflows                    | App & platform     |
| **Performance & capacity**      | `topology`, `node-shell`, `view-utilization` | Resource usage, node-level access                         | SRE                |
| **Cluster lifecycle**           | `deprecations`, `outdated`, `images`         | API deprecation checks, image audits                      | Platform           |
| **Networking**                  | `ingress-nginx`, `net-forward`, `sniff`      | Inspect ingress, network flows                            | SRE                |
| **CRD / API tools**             | `schemahero`, `explore`, `openapi`           | CRD/schema inspection                                     | Platform           |
| **Data & storage**              | `df-pv`, `pv-capacity`, `volume-inspector`   | PVC size, usage, mapping                                  | Storage, SRE       |
| **Compliance & policy**         | `score`, `popeye`, `kyverno`                 | Best-practice and policy checks                           | Platform           |
| **Developer productivity**      | `exec-as`, `prompt`, `aliases`               | Faster workflows, shell integration                       | Developers         |

---

## Representative Plugins (Most Used / High Signal)

| Plugin            | Purpose                                         |
| ----------------- | ----------------------------------------------- |
| **neat**          | Clean YAML (remove status, metadata noise)      |
| **tree**          | Show owner/dependency tree of resources         |
| **who-can**       | Check RBAC permissions (“who can delete pods?”) |
| **access-matrix** | RBAC matrix per namespace                       |
| **sniff**         | Packet capture inside pods                      |
| **debug**         | Debug pods/nodes with ephemeral containers      |
| **ctx / ns**      | Fast context / namespace switching              |
| **df-pv**         | Disk usage per PersistentVolume                 |
| **pv-migrate**    | Move PV data between volumes                    |
| **popeye**        | Cluster hygiene & misconfiguration scanner      |
| **deprecations**  | Find deprecated APIs before upgrades            |

---

## kubectl + Krew vs “Migration Tools”

Important distinction:

| Tool type          | What it’s good at                | What it’s NOT        |
| ------------------ | -------------------------------- | -------------------- |
| **Krew plugins**   | Inspection, automation, UX, glue | Full app migration   |
| **kubectl alone**  | Declarative resource mgmt        | Stateful data safety |
| **Crane / Velero** | App-level migration & backup     | Day-to-day ops       |
| **Krew + kubectl** | Building blocks                  | End-to-end DR        |

👉 **Krew plugins are enablers**, not migration solutions.

---

## Where Krew Fits in Migration Workflows

Typical real usage:

* `kubectl neat` → clean manifests before GitOps
* `kubectl tree` → understand app dependencies
* `kubectl df-pv` → assess data size before migration
* `kubectl who-can` → check permissions before Velero/Crane
* `kubectl popeye` → pre-migration hygiene check

---

## Key Insight

**kubectl + Krew is a power-user toolbox**, not a platform.

* No controllers
* No persistent state
* No vendor lock-in
* Extremely composable

Used correctly, it **reduces migration risk**, but **does not replace Velero / Crane / DB-native tools**.

---

## Migration-Focused kubectl / Krew Plugins

These plugins **help migration**, but **do not replace** Velero / Crane / DB-native tools.

### Core Preparation & Analysis

| Plugin          | Why it matters for migration                                               |
| --------------- | -------------------------------------------------------------------------- |
| **neat**        | Cleans exported YAML (removes status, UIDs, timestamps) before re-applying |
| **tree**        | Shows ownership graph (Deployment → ReplicaSet → Pod → PVC)                |
| **df-pv**       | Estimates data size before moving PVCs                                     |
| **pv-capacity** | Shows requested vs actual PV capacity                                      |
| **explore**     | Browse cluster API & CRDs to find hidden dependencies                      |

---

### Access & Safety Checks

| Plugin            | Migration use                                    |
| ----------------- | ------------------------------------------------ |
| **who-can**       | Verify you can read/export resources             |
| **access-matrix** | Check namespace-level RBAC before backup/restore |
| **whoami**        | Confirm identity/context before destructive ops  |

---

### Storage & Data Helpers

| Plugin               | Migration use                                  |
| -------------------- | ---------------------------------------------- |
| **pv-migrate**       | Copy PV data between volumes (rsync-style)     |
| **node-shell**       | Inspect nodes when storage behavior is unclear |
| **volume-inspector** | Debug PVC/PV binding issues post-migration     |

---

### Validation & Hygiene

| Plugin           | Migration use                                      |
| ---------------- | -------------------------------------------------- |
| **popeye**       | Detect misconfigurations before migration          |
| **deprecations** | Catch deprecated APIs that break on target cluster |
| **outdated**     | Detect images that may fail on newer clusters      |

---

## What kubectl (+ Krew) Is Good At in Migration

✔ Exporting & cleaning manifests
✔ Understanding app topology & dependencies
✔ Estimating storage impact
✔ Validating permissions & readiness
✔ Supporting **manual** or **semi-automated** flows

❌ Not good at preserving application consistency
❌ No rollback, no history, no orchestration
❌ No awareness of app-level state

---

## kubectl Migration Anti-Patterns (Very Common)

### 1) `kubectl get all -o yaml | kubectl apply`

**Why it’s wrong**

* Includes cluster-specific fields
* Breaks on UID, resourceVersion, status
* Fails silently or partially

**Symptom**

* Pods stuck in Pending / CrashLoop
* PVCs not binding

---

### 2) Treating PV copy as “app backup”

**Why it’s wrong**

* Filesystem ≠ consistent DB state
* Risk of corruption (MySQL, Postgres)

**Symptom**

* App starts but data is broken
* Subtle data loss

---

### 3) Copying Secrets blindly

**Why it’s wrong**

* Secrets often reference:

  * external systems
  * different certs
  * cloud-specific credentials

**Symptom**

* App deploys but can’t connect to anything

---

### 4) Migrating without dependency awareness

**Why it’s wrong**

* Ingress, DNS, external services not included
* Hidden CRDs or operators missing

**Symptom**

* App works locally but not end-to-end

---

### 5) Manual rsync between pods

**Why it’s wrong**

* No retry semantics
* No integrity guarantees
* No audit trail

**Symptom**

* Partial or inconsistent data

---

### 6) No restore testing

**Why it’s wrong**

* Backup ≠ restore
* YAML applies don’t validate correctness

**Symptom**

* “It worked last time” syndrome

---

### 7) Using kubectl as a migration platform

**Why it’s wrong**

* kubectl has no state, no coordination
* Human-driven, non-repeatable

**Symptom**

* Snowflake migrations
* No DR confidence

---

## Recommended Rule of Thumb

* **kubectl + Krew** → *prepare, inspect, validate*
* **GitOps** → *define desired state*
* **Velero / Crane** → *move apps*
* **DB-native tools** → *protect data*

If kubectl is the **main migration tool**, something is wrong.
