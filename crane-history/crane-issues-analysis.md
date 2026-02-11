# Analysis of Issues in migtools/crane Repository

**Analysis Date:** 2026-02-11
**Repository:** https://github.com/migtools/crane

## 📊 Overview

**Open Issues: 12**
- **Bugs:** 4 issues
- **Feature Requests (RFE):** 3 issues
- **Other:** 5 issues (uncategorized or other labels)

## 🔴 Critical Project Status

**Issue #166** (closed March 2025) revealed important information:
> "Hi @guettli this project is not actively being developed by the team."

**The project is NOT actively maintained!** The recommended alternative is **Velero** (https://github.com/vmware-tanzu/velero/).

## 🐛 Main Bugs (Open)

### #165 - Broken README Link
- **Author:** draghuram
- **Created:** 2024-09-04
- **Status:** Needs triage
- **Description:** README references non-existing documentation: https://konveyor.github.io/crane/overview/
- **Labels:** `kind/bug`, `needs-triage`, `needs-priority`

### #162 - Unable to Build Source Code
- **Author:** debkantap
- **Created:** 2024-06-05
- **Status:** Needs triage
- **Description:**
  - User cannot build crane on Windows (Go 1.22.3)
  - Initial proxy issues resolved, but executable not created
  - Windows support unclear
- **Labels:** `kind/bug`, `needs-triage`, `needs-priority`

### #150 - Export Segmentation Violation with Forbidden Access
- **Author:** dmartinol
- **Created:** 2023-03-07
- **Status:** Needs triage
- **Description:**
  - Segmentation violation when using `--cluster-scoped-rbac` without admin privileges
  - Panic in `ClusterScopedRbacHandler.acceptClusterRole`
- **Technical Details:**
  ```
  panic: runtime error: invalid memory address or nil pointer dereference
  [signal SIGSEGV: segmentation violation code=0x1 addr=0xe0 pc=0x10110cfe1]
  ```
- **Labels:** `kind/bug`, `needs-triage`, `needs-priority`

## ✨ Feature Requests (Open)

### #153 - Ability to Specify Additional JSONPatch Operations for Transform
- **Author:** knandras
- **Created:** 2023-06-22
- **Status:** Needs triage
- **Description:**
  - Request for ability to specify custom JSONPatch operations
  - Use case: Cleaning Rancher-specific annotations during cluster migrations
  - Rancher embeds annotations in `.spec.template.metadata.annotations`
- **Proposed Implementation:** New flag for `crane transform` pointing to file/directory with JSONPatch operations
- **Labels:** `kind/feature`, `needs-triage`, `needs-priority`

### #148 - Add Option to Export Cluster-Scoped RBAC Resources (ACCEPTED)
- **Author:** dmartinol
- **Created:** 2023-02-28
- **Status:** **Triage accepted** ✅
- **Description:**
  - Add `--cluster-scoped-rbac` flag to `crane export` (default: false)
  - Export ClusterRole, ClusterRoleBinding, SecurityContextConstraints
  - Enables complete manifest generation for re-deployment without manual RBAC setup
- **Proposed Implementation:**
  - Optional flag in crane core module
  - Store cluster-scoped resources in dedicated folder (e.g., `_cluster`)
  - Only include resources linked to exported ServiceAccounts
- **Labels:** `kind/feature`, `needs-triage`, `needs-priority`

### #159 - Review Documentation for OADP + GitOps Approach
- **Author:** jwmatthews
- **Created:** 2023-10-31
- **Status:** Needs triage
- **Description:** Review documentation sharing approach with OADP and GitOps
- **Labels:** `needs-triage`, `needs-priority`, `needs-kind`

## 🔧 Other Notable Open Issues

### #161 - Unable to Run Crane Image
- **Author:** debkantap
- **Created:** 2024-05-30
- **Description:** Issues running crane as Docker container on Windows
- **Status:** Needs triage, needs kind

### #91 - Researching Virtual Machine (kubevirt) Migration with Crane
- **Author:** djzager
- **Created:** 2022-05-16
- **Status:** Needs triage
- **Priority:** Normal
- **Description:**
  - Extensive research issue with multiple comments
  - Includes demonstration video and multiple PRs
  - Related projects: crane, crane-lib, crane-plugin-openshift, crane-runner
- **Labels:** `kind/feature`, `needs-triage`, `priority/normal`

### #88 - Need a HACKING.md to Help Onboard New Contributors
- **Author:** jwmatthews
- **Created:** 2022-05-11
- **Priority:** Normal
- **Status:** Triage accepted
- **Labels:** `kind/bug`, `triage/accepted`, `priority/normal`

### #84 - Plugin for Easy Empty-Dir Mounts
- **Author:** shawn-hurley
- **Created:** 2022-04-26
- **Priority:** Normal
- **Status:** Triage accepted
- **Description:** Consider having a plugin that allows users to easily add empty-dir mounts
- **Labels:** `kind/feature`, `triage/accepted`, `priority/normal`

### #83 - Warnings Around Security Context Constraint When Exporting
- **Author:** shawn-hurley
- **Created:** 2022-04-26
- **Priority:** Major
- **Status:** Triage accepted
- **Description:** Should add warnings around security context constraints during export
- **Labels:** `kind/bug`, `triage/accepted`, `priority/major`

## 📈 Statistics by Labels

| Label | Count |
|-------|-------|
| `needs-triage` | 10 |
| `needs-priority` | 9 |
| `needs-kind` | 3 |
| `triage/accepted` | 1 (#148 only) |
| `kind/bug` | 4 |
| `kind/feature` | 3 |
| `priority/normal` | 3 |
| `priority/major` | 1 |

## 📋 Closed Issues (Notable)

### #166 - State of the Project?
- **Closed:** 2025-03-19
- **Key Information:** Project maintainer confirmed the project is NOT actively developed
- **Recommended Alternative:** Velero (https://github.com/vmware-tanzu/velero/)

### #152 - transfer-pvc Sets ingressClassName as Null
- **Closed:** 2023-03-30
- **Type:** Bug

### #138 - Add Command to Generate Source YAML for Skopeo Sync
- **Closed:** 2022-07-20
- **Type:** Feature (critical priority when active)

### #132 - Bug: "hello"
- **Closed:** 2022-07-11
- **Type:** Bug (blocker priority when active)

### #128 - Export Resources Using Preferred API Versions
- **Closed:** 2022-07-20
- **Type:** Feature (critical priority when active)
- **Related to:** #102

## 💡 Conclusions and Recommendations

### 1. Project is Not Active
- Majority of issues are not triaged
- Development team is not actively working on the project
- Official recommendation is to use Velero instead

### 2. Documentation is Broken
- README links are non-functional
- Documentation website doesn't exist

### 3. Windows Support is Problematic
- Build issues on Windows platform
- Runtime issues with Docker containers on Windows
- Unclear if Windows is officially supported

### 4. Security Issues Present
- Segmentation fault when missing permissions (#150)
- Needs proper error handling for permission-denied scenarios

### 5. Triage Backlog
- Only 1 out of 12 open issues has been triaged and accepted
- 10 issues are waiting for triage
- 9 issues need priority assignment
- 3 issues need kind/type classification

### 6. Migration Path
- **Current recommendation:** Migrate to Velero for Kubernetes backup/restore/migration needs
- Velero is actively maintained by VMware Tanzu
- More robust community and enterprise support

## 🔗 Useful Links

- **Crane Repository:** https://github.com/migtools/crane
- **Recommended Alternative (Velero):** https://github.com/vmware-tanzu/velero/
- **Konveyor Organization:** https://github.com/konveyor

---

**Generated:** 2026-02-11
**Tool Used:** GitHub CLI (`gh`)
**Total Issues Analyzed:** 166 (12 open, rest closed)
