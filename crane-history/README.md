# Crane History Analysis - Overview

**Analysis Date:** 2026-02-11
**Purpose:** Document crane project history to inform future development decisions

---

## 📌 Executive Summary

**Crane** was a Kubernetes migration tool developed by the Konveyor community (2021-2026) that provided export, transform, and apply workflows for migrating workloads between clusters. The project is **no longer actively maintained** as of March 2025, with Velero recommended as the alternative.

### Project Status
- **Main repository:** Not actively developed ([confirmed March 2025](crane-issues-analysis.md#-critical-project-status))
- **Last significant feature:** Shipwright BuildConfig conversion ([Sep 2025 - Jan 2026](crane-commit-history-analysis.md#phase-6-maintenance--security-2024---2026))
- **Latest release:** [v0.0.6 (January 2026)](crane-commit-history-analysis.md#-release-history)
- **Recommended alternative:** [Velero](https://github.com/vmware-tanzu/velero/)

---

## 🎯 Key Takeaways for Continued Development

### What Worked Well ✅

1. **Plugin Architecture** ([crane-lib](crane-lib-analysis.md#1-transform-library-transform-lib))
   - Extensible transform system with priorities
   - Binary plugin support for community extensions
   - Version validation prevents incompatibilities
   - Enabled OpenShift-specific plugins in separate repos

2. **Modular Library Design** ([crane-lib](crane-lib-analysis.md#-technical-focus-areas-by-component))
   - Separate concerns: transform-lib, apply-lib, state-lib
   - Reusable across CLI and Tekton runners
   - [17 releases](crane-lib-analysis.md#-release-history) (v0.0.1 → v0.1.5) with continuous improvements

3. **Stateful Workload Support** ([details](crane-lib-analysis.md#3-state-library-state-lib))
   - PVC transfer with rsync/stunnel
   - **Block volume support** ([added v0.1.0, 2024](crane-lib-analysis.md#phase-7-block-volume-support-june-2024---august-2024)) - major differentiator
   - Progress reporting and checksum verification
   - Storage class and node name mappings

4. **API Version Handling** ([commit history](crane-commit-history-analysis.md#6-api-version-management-july-2022))
   - Export using PreferredVersion (critical for multi-cluster)
   - Metadata cleanup (managedFields, default RBAC, CABundle)
   - Multi-version API compatibility

5. **Enterprise Features** ([timeline](crane-commit-history-analysis.md#phase-5-enterprise-features-march-2023---october-2023))
   - Cluster-scoped RBAC export (ClusterRole, ClusterRoleBinding, SCC)
   - Disconnected environment support
   - HTTP proxy integration
   - User impersonation

6. **Image Migration** ([commit history](crane-commit-history-analysis.md#5-image-migration-april-july-2022))
   - Skopeo integration for registry synchronization
   - ImageStream handling
   - Registry info discovery

7. **Modern CI/CD Support** ([Shipwright integration](crane-lib-analysis.md#phase-8-shipwright-integration-september-2025---january-2026))
   - Shipwright Builds conversion (latest feature, 2025-2026)
   - BuildConfig → Shipwright transformation
   - Multiple build strategy support

8. **Tekton Integration** ([crane-runner](crane-runner-analysis.md#-core-features-provided))
   - ClusterTasks for automation
   - [4 comprehensive example scenarios](crane-runner-analysis.md#-example-scenarios)
   - GitOps integration (Argo CD)
   - Rapid development (Nov-Dec 2021)

---

### Critical Issues & Lessons Learned ⚠️

#### 1. **Project Sustainability** ([details](crane-issues-analysis.md#-conclusions-and-recommendations))
- **Issue:** Project became unmaintained despite active development
- **Impact:** [12 open issues](crane-issues-analysis.md#-overview) in main repo, 10 need triage
- **Lesson:** Need clear sustainability and community engagement plan from start

#### 2. **Documentation Gaps** ([issues](crane-issues-analysis.md#-main-bugs-open))
- **Issue:** Broken README links ([#165](crane-issues-analysis.md#165---broken-readme-link)), missing contributor guides ([#88](crane-commit-history-analysis.md#phase-4-advanced-features--optimization-april-2022---august-2022))
- **Impact:** Users reported non-existent documentation
- **Lesson:** Maintain documentation alongside code; automate link checking

#### 3. **Platform Support** ([Windows issues](crane-issues-analysis.md#162---unable-to-build-source-code))
- **Issue:** Windows build/runtime issues (#162, #161)
- **Impact:** Unclear platform support matrix
- **Lesson:** Define supported platforms early; test on all targets

#### 4. **Backlog Management**
- **crane-lib:** [16 open issues](crane-lib-analysis.md#-overview) (many from 2021)
- **crane-runner:** [12 open issues](crane-runner-analysis.md#-issues-analysis) (8 from [Feb 2022 hackathon](crane-runner-analysis.md#hackathon-issues-still-open))
- **Lesson:** Hackathons create technical debt; need triage commitment

#### 5. **Error Handling Standards** ([crane-lib open issues](crane-lib-analysis.md#open-issues-16))
- **Issue:** crane-lib issues [#8 (logging)](crane-lib-analysis.md#1-transform-library-transform-lib) and [#9 (error wrapping)](crane-lib-analysis.md#1-transform-library-transform-lib) open since 2021
- **Lesson:** Establish patterns early before codebase grows

#### 6. **State Transfer Complexity** ([state-lib details](crane-lib-analysis.md#3-state-library-state-lib))
- **[10 open issues](crane-lib-analysis.md#3-state-library-state-lib)** in crane-lib state-lib component
- Edge cases: long namespace names, label length limits, endpoint validation
- **Lesson:** State transfer is most complex part; allocate significant time

#### 7. **Release Cadence** ([history](crane-commit-history-analysis.md#-release-history))
- Long gaps between releases (v0.0.5: Aug 2022 → Jul 2024)
- crane-runner has [no version tags](crane-runner-analysis.md#-overview) (container-only)
- **Lesson:** Frequent, predictable releases build trust

---

## 📊 Development Timeline

### Crane Main Repository ([full timeline](crane-commit-history-analysis.md#-development-timeline-overview))
```
2021 (Apr-Dec):  Foundation - Export, Transform, Apply, Plugins
2022 (Jan-Aug):  Peak Activity - PVC transfer, API versions, Image sync
2023 (Mar-Oct):  Enterprise - RBAC, Security fixes
2024 (Mar-Jul):  Maintenance - Dependency updates
2025-2026:       Modernization - Shipwright support
```

### Crane-lib (Core Library) ([phases](crane-lib-analysis.md#-commit-history-analysis))
```
Phase 1 (2021):      Plugin system, state transfer foundation
Phase 2 (2022):      Production hardening, block volumes (v0.1.0)
Phase 3 (2023-24):   Security patches, symlink handling
Phase 4 (2025-26):   Shipwright integration (v0.1.5)
```

### Crane-runner (Tekton) ([development timeline](crane-runner-analysis.md#-commit-history-analysis))
```
Nov-Dec 2021:  Rapid development - 4 scenarios, all ClusterTasks
Jan-Jul 2022:  Refinements - Image sync, optional flags
Aug 2022+:     Dormant (no commits after Sep 2022)
```

---

## 🔧 Technical Architecture Highlights

### Core Components

**crane** (CLI) ([commit history](crane-commit-history-analysis.md#-core-development-focus-areas-chronological))
- Cobra + Viper framework
- Commands: export, transform, apply, transfer-pvc, skopeo-sync-gen
- Plugin manager (add/list/remove)
- Config file support (flags-file)

**crane-lib** (Libraries) ([technical details](crane-lib-analysis.md#-technical-focus-areas-by-component))
- **transform-lib:** Plugin system, priorities, optional fields
- **apply-lib:** JSON Patch application, conflict detection
- **state-lib:** PVC/block volume transfer via rsync

**crane-runner** (Tekton) ([ClusterTasks](crane-runner-analysis.md#clustertasks))
- ClusterTasks for crane operations
- Image sync workflow (registry-info → sync-gen → sync)
- Example pipelines (stateless, stateful, GitOps, Kustomize)

---

## 🚨 Security Considerations

### Vulnerabilities Fixed ([timeline](crane-commit-history-analysis.md#phase-5-enterprise-features-march-2023---october-2023))
- CVE-2023-44487 (x/net)
- protobuf (Bug 2268141)
- oauth2 vulnerabilities

### Known Issues
- Segmentation fault with insufficient RBAC permissions ([#150](crane-issues-analysis.md#150---export-segmentation-violation-with-forbidden-access)) - FIXED in [#151](crane-commit-history-analysis.md#phase-5-enterprise-features-march-2023---october-2023)
- Need proper permission error handling

---

## 💡 Recommendations for Future Work

### If Forking/Continuing Crane:

#### High Priority
1. **Resolve project status**
   - Fork or archive? Decide clearly
   - If continuing, commit to maintenance schedule

2. **Fix documentation**
   - Update broken links ([#165](crane-issues-analysis.md#165---broken-readme-link))
   - Create HACKING.md ([#88](crane-issues-analysis.md#88---need-a-hackingmd-to-help-onboard-new-contributors))
   - Document platform support ([Windows issues](crane-issues-analysis.md#-windows-support-is-problematic))

3. **Triage backlog** ([full issue list](crane-issues-analysis.md#-statistics-by-labels))
   - crane: [10 issues need triage](crane-issues-analysis.md#-overview)
   - crane-lib: [16 open issues](crane-lib-analysis.md#-issues-analysis) (oldest from 2021)
   - crane-runner: Close or resolve [hackathon issues](crane-runner-analysis.md#hackathon-issues-still-open)

4. **Establish standards**
   - Logging patterns ([crane-lib #8](crane-lib-analysis.md#open-issues-16))
   - Error wrapping ([crane-lib #9](crane-lib-analysis.md#open-issues-16))
   - Code review checklist

#### Medium Priority
5. **Improve state transfer reliability** ([state-lib issues](crane-lib-analysis.md#3-state-library-state-lib))
   - Address crane-lib state-lib edge cases
   - Endpoint validation vs sleeping ([crane-lib #28](crane-lib-analysis.md#open-issues-16))
   - Long namespace/label handling ([#46](crane-lib-analysis.md#open-issues-16), [#27](crane-lib-analysis.md#open-issues-16))

6. **Platform support clarity**
   - Test and document Windows support
   - CI/CD for multiple platforms

7. **Version everything**
   - crane-runner needs Git tags
   - Semantic versioning for all components

#### Nice to Have
8. **Feature enhancements**
   - Custom JSONPatch operations ([#153](crane-issues-analysis.md#153---ability-to-specify-additional-jsonpatch-operations-for-transform))
   - Documentation review for OADP/GitOps ([#159](crane-issues-analysis.md#159---review-documentation-for-oadp--gitops-approach))

---

### If Building New Tool (kubectl-migrate, etc.):

#### Adopt These Patterns ✅ ([see what worked](crane-lib-analysis.md#-key-insights))
- Plugin architecture for extensibility ([crane-lib transform](crane-lib-analysis.md#1-transform-library-transform-lib))
- Separate libraries (transform/apply/state) ([architecture](crane-lib-analysis.md#-technical-focus-areas-by-component))
- Config file support to reduce CLI complexity ([commit history](crane-commit-history-analysis.md#phase-2-plugin-system--extensibility-july-2021---november-2021))
- Block volume support (differentiator) ([added 2024](crane-lib-analysis.md#phase-7-block-volume-support-june-2024---august-2024))
- API version preference handling ([critical feature](crane-commit-history-analysis.md#6-api-version-management-july-2022))
- Metadata cleanup (managedFields, etc.)
- Progress reporting for long operations
- Tekton ClusterTasks for automation ([crane-runner](crane-runner-analysis.md#-core-features-provided))
- Multiple example scenarios ([4 scenarios](crane-runner-analysis.md#-example-scenarios))

#### Avoid These Pitfalls ⚠️ ([lessons learned](crane-lib-analysis.md#challenges))
- Don't defer logging/error standards ([issues #8, #9](crane-lib-analysis.md#open-issues-16))
- Plan sustainability from start ([project became unmaintained](crane-issues-analysis.md#-critical-project-status))
- Maintain documentation alongside code ([broken docs](crane-issues-analysis.md#-documentation-is-broken))
- Triage issues regularly (don't accumulate debt) ([16 open issues](crane-lib-analysis.md#-overview))
- Test all platforms before claiming support ([Windows issues](crane-issues-analysis.md#-windows-support-is-problematic))
- Version releases predictably ([long gaps](crane-commit-history-analysis.md#-release-history))
- State transfer is complex - allocate time ([10 open issues](crane-lib-analysis.md#3-state-library-state-lib))
- Hackathons create debt - plan cleanup time ([8 hackathon issues](crane-runner-analysis.md#hackathon-issues-still-open))

#### Consider Modern Alternatives
- Shipwright for builds ([crane added this late](crane-lib-analysis.md#phase-8-shipwright-integration-september-2025---january-2026))
- Velero for backup/restore ([recommended replacement](crane-issues-analysis.md#-critical-project-status))
- Evaluate if new tool is needed vs extending existing

---

## 📚 Key Statistics

### Commits & Contributors
| Repo | Commits | Key Contributors | Timespan |
|------|---------|-----------------|----------|
| crane | [~113](crane-commit-history-analysis.md#-key-contributors) | djzager (30), jmontleo (15), sseago (12) | Apr 2021 - Jan 2026 |
| crane-lib | [~100](crane-lib-analysis.md#-key-contributors) | djzager (30), pranavgaikwad (25), sseago (20) | Apr 2021 - Jan 2026 |
| crane-runner | [~67](crane-runner-analysis.md#-key-contributors) | djzager (35), eriknelson (10) | Nov 2021 - Sep 2022 |

### Issues
| Repo | Open | Closed | Needs Triage |
|------|------|--------|--------------|
| crane | [12](crane-issues-analysis.md#-overview) | [154](crane-issues-analysis.md#-closed-issues-notable) | [10](crane-issues-analysis.md#-statistics-by-labels) |
| crane-lib | [16](crane-lib-analysis.md#-issues-analysis) | [7](crane-lib-analysis.md#closed-issues-7) | Most |
| crane-runner | [12](crane-runner-analysis.md#-issues-analysis) | [8](crane-runner-analysis.md#closed-issues-8) | Most |

### Releases
- **crane:** [v0.0.1 → v0.0.6](crane-commit-history-analysis.md#-release-history) (6 releases)
- **crane-lib:** [v0.0.1 → v0.1.5](crane-lib-analysis.md#-release-history) (17 releases)
- **crane-runner:** [No version tags](crane-runner-analysis.md#-overview)

---

## 🔗 Resources

### Repositories
- **crane:** https://github.com/migtools/crane
- **crane-lib:** https://github.com/migtools/crane-lib
- **crane-runner:** https://github.com/migtools/crane-runner
- **Recommended alternative:** https://github.com/vmware-tanzu/velero/

### Documentation
- Enhancement proposals: https://github.com/konveyor/enhancements
- Konveyor community: https://github.com/konveyor

---

## 📝 Analysis Files

This directory contains detailed analyses:

- **crane-commit-history-analysis.md** - Chronological development history, 6 phases
- **crane-issues-analysis.md** - Open/closed issues breakdown, project status
- **crane-lib-analysis.md** - Core library evolution, technical focus areas
- **crane-runner-analysis.md** - Tekton integration, ClusterTasks, examples

---

**Analysis by:** Claude Code
**Date:** 2026-02-11
**Purpose:** Inform future Kubernetes migration tool development decisions
