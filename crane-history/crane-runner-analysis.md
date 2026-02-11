# Analysis of migtools/crane-runner Repository

**Analysis Date:** 2026-02-11
**Repository:** https://github.com/migtools/crane-runner
**Latest Version:** No version tags found (container image based)

---

## 📊 Overview

**Open Issues:** 12
**Closed Issues:** 8
**Total Commits Analyzed:** ~67 commits
**Project Timespan:** November 2021 - September 2022
**Purpose:** Tekton ClusterTasks and Pipelines for crane automation

### Project Description
crane-runner provides **Tekton integration** for crane, enabling:
- ClusterTasks for crane commands (export, transform, apply)
- PVC transfer automation
- Image synchronization with Skopeo
- GitOps integration examples
- Kustomize support
- Stateful/stateless migration scenarios

---

## 🐛 Issues Analysis

### Open Issues (12)

#### Critical / Accepted Issues:

**#67 - k8s.gcr.io Image Registry Will Be Frozen From 3rd of April 2023**
- Author: kaovilai (Tiger Kaovilai)
- Created: 2023-02-28
- Labels: `kind/feature`, `needs-triage`, `needs-priority`
- **Impact:** Images need migration from k8s.gcr.io to registry.k8s.io
- Status: Still open

**#63 - Incorporate tekton/catalog recommendations**
- Author: djzager
- Created: 2022-07-27
- Labels: `kind/bug`, `kind/feature`, `triage/accepted`, `needs-priority`
- Status: Accepted but no priority assigned

**#57 - Add ability to use custom pvc transfer image for source and destination**
- Author: jmontleon
- Created: 2022-07-18
- Labels: `kind/feature`, `triage/accepted`, `priority/normal`
- Status: Accepted, normal priority

#### Hackathon Issues (Still Open):

**#32 - Ensure verification steps are present that prove scenario succeeded**
- Author: eriknelson
- Created: 2022-02-01
- Labels: `documentation`, `kind/feature`, `hackathon`
- Status: Documentation improvement needed

**#31 - Flesh out the plugin development model**
- Author: eriknelson
- Created: 2022-02-01
- Labels: `documentation`, `kind/feature`, `hackathon`
- Status: Documentation gap

**#29 - State transfer scenario results are indeterminate**
- Author: eriknelson
- Created: 2022-02-01
- Labels: `kind/bug`, `hackathon`
- Comment: Suspected Redis data consistency issue
- Status: Open

**#28 - After migrating to OCP4.9 pods are not running**
- Author: varodrig (Valentina Rodriguez Sosa)
- Created: 2022-02-01
- Labels: `kind/bug`, `hackathon`
- Status: Migration issue

**#20 - Show how to wait for TaskRun/PipelineRun in examples**
- Author: djzager
- Created: 2021-12-13
- Labels: `kind/bug`, `hackathon`
- Status: Documentation gap

**#16 - Add scenario running crane manually to get baseline**
- Author: eriknelson
- Created: 2021-12-13
- Labels: `kind/feature`, `hackathon`
- Comment: Suggestion to show manual crane usage before Tekton automation
- Status: Documentation improvement

**#15 - Piping minikube start script into bash fails to run full script**
- Author: eriknelson
- Created: 2021-12-13
- Labels: `kind/bug`, `hackathon`
- Workaround: wget script directly and chmod +x
- Status: Open

### Closed Issues (8)

**#58 - Stop hard coding crane-runner in all tasks**
- Closed: 2022-08-02
- Labels: `kind/feature`, `triage/accepted`, `priority/critical`
- Resolution: Can specify image via params

**#56 - Skopeo Sync ClusterTask**
- Closed: 2022-07-21
- Labels: `kind/feature`, `triage/accepted`, `priority/critical`
- **Major feature** - Added skopeo sync task
- Enhancement: https://github.com/konveyor/enhancements/pull/77

**#55 - Need ClusterTask to execute `crane skopeo-sync-gen`**
- Closed: 2022-07-21
- Labels: `kind/feature`, `triage/accepted`, `priority/critical`
- Enhancement: https://github.com/konveyor/enhancements/pull/77

**#54 - Need ClusterTask that gets cluster registry information**
- Closed: 2022-07-20
- Labels: `kind/feature`, `triage/accepted`, `priority/critical`
- Enhancement: https://github.com/konveyor/enhancements/pull/77

**#48 - PVC rename does not work properly when renamed in UI**
- Closed: 2022-06-27
- Labels: `kind/bug`
- Fixed by #49

**#40 - Input to optional field in clustertask "crane-transform" is invalid**
- Closed: 2022-06-27
- Labels: `kind/bug`
- Fixed by #49

**#34 - Issues with tasks fixed for e2e demo**
- Closed: 2022-03-24
- Labels: `kind/bug`
- Multiple task issues fixed

**#33 - Add build info to container image**
- Closed: 2022-02-17
- Moved to Jira: MIG-1087

**#30 - No Auth provider found for "oidc"**
- Closed: 2022-06-27
- Labels: `kind/bug`, `hackathon`
- Related to IBM Cloud OIDC auth

**#17 - Confusion between crane apply and kubectl apply steps**
- Closed: 2022-06-27
- Labels: `kind/feature`, `hackathon`
- Resolved by renaming tasks: `crane-apply` vs `kubectl-apply-(files|kustomize)`

**#13 - Github uploads to "base" but Argo Application looks for "app"**
- Closed: 2021-12-13
- Labels: `kind/bug`, `hackathon`

**#12 - Argo Application doesn't see changes to deployed resources**
- Closed: 2021-12-13
- Labels: `kind/bug`, `hackathon`

---

## 📈 Commit History Analysis

### Development Timeline

#### Phase 1: Initial Creation (November 2021 - December 2021)
**Focus:** Project setup, basic tasks, examples

- **2021-11-23**: Initial commit (eriknelson)
- **2021-12-01**: Initial commit with structure (djzager)
- **2021-12-01**: Cleanup readme, hack scripts, manifests
- **2021-12-02**:
  - Expand examples with introduction + roadmap
  - Move away from personal (djzager) references
- **2021-12-03**: Add stateful app migration example
- **2021-12-06**: Move guestbook to kustomize overlays
- **2021-12-07**:
  - **Add Makefile** for local dev
  - **Add yq to crane-runner**
  - Better organization for examples
  - Cleanup clustertasks
  - Remove minikube startup scripts
  - Improve apply-manifests script
- **2021-12-08**: Start GitOps integration example
- **2021-12-09**:
  - **Cluster task for state migration** (#4)
  - Add issue templates (#2)
  - Updates for GitOps example
- **2021-12-10**: Correct branch names and transform flags (#3)
- **2021-12-11**:
  - **Make /crane the entrypoint** (#5)
  - **Stateful Application Examples** (#6)
  - Finalize basic stateless mirror example
  - Finalize kustomize example
  - Finalize GitOps example
  - Finalize stateful migration example
  - Doc refactor: stop numbering examples
  - Make high-level READMEs better
  - Show how to keep tabs on pipeline progress
- **2021-12-13**: Multiple fixes and improvements
  - Use correct context for target workload verification (#19)
- **2021-12-14**: Add tips and tricks doc (#21)

**Key Achievements:**
- Complete project structure
- 4 major example scenarios
- ClusterTasks for core crane operations
- Documentation foundation

---

#### Phase 2: Refinements & Hackathon (January 2022 - February 2022)
**Focus:** Bug fixes, documentation improvements

- **2022-01-27**:
  - Drop pipe bash (#24)
  - Lessen need for kustomize binary (#23)
  - Add link to crane 101 manual CLI (#26)
  - Update crane export (#25)
- **2022-02-03**: Use github_username instead of id (#27)

**Hackathon Activity:** Multiple issues filed (Feb 1-2, 2022)
- Issues #28-34 all created during hackathon
- Focus on state transfer, plugin development, verification

---

#### Phase 3: Production Readiness (March 2022 - April 2022)
**Focus:** Integration improvements, ownership

- **2022-03-18**: **Crane UI + Tekton Integration Enhancement** (#35)
- **2022-03-31**:
  - Use crane container image (#38)
  - Update ubi registry (#39)
  - Drop --server flag (#37)
  - **State transfer changes** (#36)
  - Fix transfer-pvc clustertask bad default value (#41)
- **2022-04-05**: Add OWNERS (#43)
- **2022-04-12**: **Add ImageStreamPlugin** (#42)

**Key Achievements:**
- Container image integration
- ImageStream support
- State transfer improvements

---

#### Phase 4: Major Features (May 2022 - June 2022)
**Focus:** Optional flags, templates

- **2022-05-12**:
  - Transfer-pvc handle defaults (#45)
  - Update stateful app example (#44)
- **2022-06-24**:
  - **Enable passing optional flags to crane transform** (#49) - Critical fix
  - Enable slack digest + jira sync (#50)
  - Update stateless app mirror example (#47)
- **2022-06-27**: Update templates (#46)

**Key Achievement:**
- Optional flags support (fixed issues #40, #48)

---

#### Phase 5: Advanced Features (July 2022 - September 2022)
**Focus:** Image sync, registry info, TLS verification

- **2022-07-05**: Configure actions after updates (#51)
- **2022-07-06**: Fix plugin install (#52)
- **2022-07-19**: Update reconcile_gh_issue.yaml
- **2022-07-20**: **Add registry info task** (#53) - Critical for image sync
- **2022-07-21**: **Add image-sync task** (#60) - Major feature
- **2022-07-26**: Set bash optionals for better debug (#61)
- **2022-07-28**: Add `verify` param to crane-transfer-pvc (#64)
- **2022-07-29**:
  - Enable silent failure for registry-info (#65)
  - **Parameterize tls-verify params to skopeo** (#62)
- **2022-09-15**: Update needs-triage.yaml

**Key Achievements:**
- **Complete image synchronization workflow** (registry-info + skopeo-sync)
- TLS verification configurability
- Better debugging support

---

## 🎯 Core Features Provided

### ClusterTasks

1. **crane-export**
   - Export Kubernetes resources from namespace
   - Supports label selectors
   - Context-aware

2. **crane-transform**
   - Apply plugin transformations
   - Optional flags support (added in #49)
   - Plugin priorities

3. **crane-apply** / **kubectl-apply**
   - Apply transformed resources
   - Separate tasks for clarity (renamed to avoid confusion)
   - kubectl-apply-files
   - kubectl-apply-kustomize

4. **crane-transfer-pvc**
   - PVC data migration
   - Verify parameter (#64)
   - Custom image support (requested in #57)
   - Default handling (#45)

5. **crane-registry-info** (#53)
   - Get cluster registry information
   - Find registry routes
   - Prepare for image sync

6. **crane-skopeo-sync-gen** (#55)
   - Generate skopeo sync source list
   - Parse ImageStreams

7. **crane-skopeo-sync** (#56)
   - Sync images between registries
   - TLS verify parameterization (#62)
   - Silent failure option (#65)

8. **crane-image-plugin** (#42)
   - ImageStream handling

---

## 📚 Example Scenarios

### 1. **Basic Stateless Mirror**
- Simple export → transform → apply
- Foundation for all scenarios

### 2. **Kustomize Integration**
- Use Kustomize for resource customization
- Overlay support

### 3. **GitOps Integration**
- Integration with Argo CD
- Automated sync
- Issues #12, #13 addressed

### 4. **Stateful Application Migration**
- PVC transfer
- State migration examples
- Redis example (issue #29)

---

## 👥 Key Contributors

1. **David Zager (djzager)** - ~35 commits
   - Project creator and primary maintainer
   - All major features
   - Examples and documentation

2. **Erik Nelson (eriknelson)** - ~10 commits
   - Examples refinement
   - Hackathon organization
   - Documentation

3. **Alay Patel (alaypatel07)** - ~3 commits
   - State migration task
   - Documentation fixes

4. **Jason Montleon (jmontleon)** - ~2 commits
   - Plugin install fix
   - Verify parameter

5. **Mike Turley** - ~1 commit
   - Verify param for transfer-pvc

6. **Pranav Gaikwad (pranavgaikwad)** - ~1 commit
   - State transfer changes

7. **Ankur Mundra** - ~1 commit
   - Stateless app example update

8. **Savitha Raghunathan** - ~1 commit
   - Stateful app example update

---

## 🔍 Key Insights

### What Worked Well:
1. ✅ **Tekton integration** - Natural fit for CI/CD pipelines
2. ✅ **Comprehensive examples** - 4 different scenarios cover major use cases
3. ✅ **ClusterTask modularity** - Separate tasks for each crane operation
4. ✅ **Image sync workflow** - Complete solution with registry-info + skopeo
5. ✅ **Rapid development** - Most features in 9 months (Nov 2021 - Jul 2022)

### Challenges:
1. ⚠️ **Hackathon issues unresolved** - Many from Feb 2022 still open
2. ⚠️ **Documentation gaps** - Issues #31, #32, #16 about docs
3. ⚠️ **State transfer reliability** - Issue #29 indeterminate results
4. ⚠️ **Image registry migration** - Issue #67 k8s.gcr.io deprecation
5. ⚠️ **No version tags** - Container image based, no Git releases

### Development Pattern:
- **2021 (Nov-Dec)**: Intense initial development (2 months, ~40 commits)
- **2022 (Jan-Jul)**: Refinements and features (~25 commits)
- **2022 (Aug-Sep)**: Minimal activity (2 commits)
- **After Sep 2022**: No commits (project appears dormant)

---

## 📊 Activity Analysis

### Commit Frequency:
```
Nov 2021: ████████████████ (20+ commits - initial creation)
Dec 2021: ████████████ (15+ commits - examples)
Jan 2022: ██ (3 commits - refinements)
Feb 2022: ██ (3 commits - hackathon issues)
Mar 2022: ████ (5 commits - production)
Apr 2022: ██ (2 commits)
May 2022: ██ (2 commits)
Jun 2022: ████ (4 commits)
Jul 2022: ████████ (8 commits - peak features)
Aug 2022: (0 commits)
Sep 2022: █ (1 commit)
After Sep 2022: (0 commits - project dormant)
```

**Peak Activity:** November-December 2021 and July 2022
**Last Commit:** September 15, 2022
**Status:** Appears dormant since late 2022

---

## 💡 Recommendations for kubectl-migrate

### Based on crane-runner's experience:

### What to Adopt:
1. ✅ **Tekton ClusterTasks** - Excellent automation mechanism
2. ✅ **Modular task design** - One task per crane operation
3. ✅ **Example-driven docs** - Multiple scenarios help users
4. ✅ **Image sync workflow** - Registry-info + skopeo pattern works well
5. ✅ **Makefile for dev** - Simplifies local development

### What to Improve:
1. ⚠️ **Version strategy** - crane-runner has no Git tags
   - 💡 Use semantic versioning for container images AND Git tags
2. ⚠️ **Issue triage** - 12 open issues, many from hackathon
   - 💡 Close or resolve hackathon issues
   - 💡 Prioritize documentation improvements
3. ⚠️ **Maintenance commitment** - No commits since Sep 2022
   - 💡 Plan for long-term maintenance
   - 💡 Community engagement strategy
4. ⚠️ **State transfer reliability** - Issue #29 still open
   - 💡 Add comprehensive verification steps
   - 💡 Handle edge cases (Redis consistency, etc.)
5. ⚠️ **Registry migration** - k8s.gcr.io deprecation (#67)
   - 💡 Use registry.k8s.io from start
   - 💡 Make registry configurable

### Key Takeaways:
1. **Rapid prototyping works** - Most value delivered in first 2 months
2. **Examples are critical** - Users learn from scenarios
3. **Hackathons create debt** - Many issues filed, few resolved
4. **Tekton is powerful** - But requires understanding of concepts
5. **Image sync is complex** - Multi-step process (registry-info → sync-gen → sync)
6. **Documentation matters** - 3 open issues about docs
7. **Verification is hard** - Issue #32 about proving success
8. **Maintenance is essential** - Project went dormant

### Specific Recommendations:
1. **Start with core tasks** - export, transform, apply, transfer-pvc
2. **Add image sync early** - Critical for complete migrations
3. **Provide manual scenarios** - Before automation (issue #16)
4. **Show verification steps** - Prove migration success (issue #32)
5. **Document plugin development** - Enable community (issue #31)
6. **Handle wait/polling** - For async operations (issue #20)
7. **Plan for multiple K8s distros** - Not just OpenShift
8. **Make images configurable** - Don't hardcode registry paths
9. **Version everything** - Tasks, images, and Git tags
10. **Commit to maintenance** - Or clearly mark as archived

---

## 🔗 Related Resources

- **Crane main:** https://github.com/migtools/crane
- **Crane lib:** https://github.com/migtools/crane-lib
- **Tekton Catalog:** https://github.com/tektoncd/catalog
- **Enhancement Proposal:** https://github.com/konveyor/enhancements/pull/77

---

**Analysis Generated:** 2026-02-11
**Data Source:** migtools/crane-runner repository
**Note:** Project appears dormant since September 2022
