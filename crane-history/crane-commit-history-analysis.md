# Crane Project - Commit History Analysis

**Analysis Date:** 2026-02-11
**Repository:** https://github.com/migtools/crane
**Total Commits Analyzed:** ~113 commits
**Project Timespan:** April 2021 - January 2026
**Latest Version:** v0.0.6

---

## 📊 Development Timeline Overview

### Phase 1: Foundation (April 2021 - June 2021)
**Focus:** Core CLI structure and basic export functionality

- **2021-04-26**: Project initialization with LICENSE and .gitignore
- **2021-06-10**: Modified POC code to use Velero discovery helper (#2)
  - Used pager to list objects and reduce API server load
  - Proper error handling and logging
- **2021-06-11**: Fixed extracted files being empty (#4)
- **2021-06-17**: Enabled GitHub Actions for unit tests (#6)
- **2021-06-18**: **Apply CLI implementation** (#5)
  - Added apply functionality
  - Created filepath helpers for CLI
- **2021-06-23**: **Transform command implementation** (#8)
  - Initial implementation of transform command
  - Handle missing transform files (#9, #10, #12)
  - Creating folders for output directories

**Key Achievement:** Core export → transform → apply workflow established

---

### Phase 2: Plugin System & Extensibility (July 2021 - November 2021)
**Focus:** Plugin architecture, configuration, and user experience

- **2021-07-06**: Plugin priorities for transform CLI (#14)
- **2021-07-14**:
  - Added README and gitignore (#16)
  - Support for `--optional-flags` transform argument (#17)
  - Handle missing transform files during apply (#18)
- **2021-07-29**: Debug logging capability (#20)
- **2021-08-10**: Enable k8s plugins for transform (#24)
- **2021-08-11**: Skip plugins functionality and list-plugins subcommand (#23)
- **2021-08-24**: **Transfer-PVC subcommand** - PVC data migration (#19)
- **2021-08-25**: User impersonation flags (as-user, as-group, as-extras) (#26)
- **2021-09-27**:
  - GitHub Actions for releasing binaries (#36)
  - Plugin log handling with debug flag (#38)
  - Pinning to particular crane-lib versions
- **2021-10-18**: Plugin manager add/list/remove functionality (#39)
- **2021-10-20**: **Config file input support** (#40)
  - YAML config file input for export, transform, apply
  - CLI flag: `--config-file` / `-c`
- **2021-10-27**: List plugins from default source and installed plugins (#43)
- **2021-11-02**: Fixed pager list processing (#45)
- **2021-11-04**:
  - Updated crane-lib dependency to v0.0.2 (#44)
  - Changed default plugin directory (#46)
- **2021-11-10**: Lowercase optional arg names for consistency (#48)
- **2021-11-11**:
  - Updated to crane-lib 0.0.3 (#50)
  - Changed default source repository branch (#49)
- **2021-11-15**: **Version command** + crane-lib 0.0.4 (#52)
- **2021-11-16**:
  - Plugin-manager works in disconnected environments (#51)
  - Documented known issues with new-namespace param (#53)

**Key Achievements:**
- Complete plugin architecture
- Config file support
- PVC transfer capability
- Disconnected environment support

---

### Phase 3: Production Readiness (December 2021 - March 2022)
**Focus:** Minikube testing, ingress support, and robustness

- **2021-12-02**: Code formatting (goimports, gofmt) (#58)
- **2021-12-06**: Changed output format for list plugins (#59)
- **2021-12-08**:
  - **Version v0.0.3 released**
  - Changed "config-file" flag to "flags-file" (#57)
  - **Ingress support** + Minikube automation (#56)
    - Added `--endpoint` flag to transfer-pvc
    - Created automation for two minikube clusters
    - Added hack scripts for cluster creation/deletion
- **2021-12-09**:
  - Kube version override for minikube (#63)
  - Removed hackathon bug (#64)
- **2021-12-10**: Fixed nginx name (#65)
- **2022-01-13**: Export respects context (#68)
  - Fixed handling of context/namespace/cluster/auth
- **2022-02-09**: Options to specify custom images for source/destination (#72)
- **2022-02-23**: HTTP proxy support with tunnel-api (#73)
- **2022-03-18**: Skip 'failures' directory when reading files (#76)
- **2022-03-29**: **Stateful migrations support** (#75)
  - Node name discovery
  - PVC name & namespace mappings
  - Checksum verification
  - Storage class mappings
  - Capacity selection
- **2022-03-31**: **Crane in container image** (#77)
  - Built and published container images

**Key Achievements:**
- Container image distribution
- Stateful migration capabilities
- Production-grade error handling
- Developer testing automation

---

### Phase 4: Advanced Features & Optimization (April 2022 - August 2022)
**Focus:** Performance, API version handling, image sync, and RBAC

- **2022-04-11**: Added OWNERS file (#79)
- **2022-04-12**: Fixed ImageStreamTags and ImageTags (#78)
  - Different list/get semantics required iteration with GET calls
- **2022-04-28**: Redefined plugin structure (#81)
- **2022-05-04**: Added Overview section to README (#86)
- **2022-05-23**: Create Jira issues when GitHub issues opened (#97)
- **2022-06-06**: Updated .gitignore & owners (#104)
- **2022-06-07**:
  - **Integrated pvc-transfer library** (#87)
  - Updated templates to use k8s style labels (#107)
  - Used konveyor/github-actions for issue reconciliation (#106)
  - CLI documentation for slice/map params (#92)
  - Added approvers (#93)
- **2022-06-13**: Removed contributor from owners (#108)
- **2022-06-15**: **Bumped crane-lib to v0.0.7** (#109)
  - Handled metadata.managedFields
  - Handled default RBAC (default service accounts)
  - Handled default CABundle
- **2022-06-21**: Workflow for issues needing triage (#117)
- **2022-06-27**: Workflow improvements (reconcile only 1 issue at a time) (#123, #121)
- **2022-07-05**: Fixed ingress/route name length limits (#124)
- **2022-07-07**: Fixed plugin not found exit code (#129)
- **2022-07-14**:
  - **Set higher QPS and Burst defaults** (#133)
  - **Rsync options override** (#114)
  - Workflow improvements (#130)
- **2022-07-18**:
  - **Export using PreferredVersion** (#134) - Critical feature
  - **KRM functions subcommand** (#136)
    - Run Kubernetes Resource Model functions
    - Updated to Go 1.17
- **2022-07-19**:
  - **Skopeo-sync-gen subcommand** (#140)
    - Parse ImageStreams for local images
    - Generate source list for `skopeo sync`
  - Custom image for pvc-transfer (#139)
  - Multiple paths for plugins (#137)
- **2022-07-22**:
  - **Label selector for export** (#142)
  - **Progress reporting** (#141)
    - Progress reporting checkpoint
    - Rsync progress reporting
- **2022-07-25**: State-transfer README (#143)
- **2022-07-27**: Export default label-selector to empty string (#144)
- **2022-07-29**: Transform takes optional-flags as JSON (#145)
- **2022-08-03**:
  - **Version v0.0.5 released**
  - Bumped crane-lib dependency (#146)
  - Bumped Go version in release process (#147)

**Key Achievements:**
- API version preference handling (critical for multi-cluster migrations)
- Image synchronization with Skopeo integration
- Progress reporting
- Performance optimizations (QPS/Burst)
- Label-based filtering

---

### Phase 5: Enterprise Features (March 2023 - October 2023)
**Focus:** Cluster-scoped RBAC, security

- **2023-03-07**: **Cluster-scoped RBAC export** (#149)
  - Added `--cluster-scoped-rbac` flag
  - Export ClusterRole, ClusterRoleBinding, SecurityContextConstraints
  - Store in dedicated `_cluster` folder under namespace
  - Proper filtering for ServiceAccount linkage
- **2023-03-10**: **Fixed segmentation violation** (#151)
  - Fixed #150 - initialized filteredClusterRoleBindings
  - Added error messages for permission issues
- **2023-10-19**:
  - CVE-2023-44487 fix - bumped x/net to 0.17.0 (#155)
  - Used new konveyor builder golang image (#158)

**Key Achievements:**
- Complete RBAC migration support
- Security vulnerability fixes
- Enterprise-ready cluster-scoped resource handling

---

### Phase 6: Maintenance & Security (2024 - 2026)
**Focus:** Dependency updates, security patches, new features

- **2024-03-12**: Updated protobuf dep to 1.33.0 (Bug 2268141)
- **2024-07-18**:
  - **Version v0.0.5 (re-released)**
  - Updated x/net dependency (Bug 2269447)
  - Updated to Go 1.21
- **2025-05-06**: Updated golang.org/x/oauth2 (#167)
- **2025-09-09**: **Convert OpenShift BuildConfigs to Shipwright Builds** (#168)
  - Major new feature for CI/CD pipeline migration
  - Fixed failing tests
- **2025-12-12**: **Added debug flag** for debug logging level (#173)
- **2026-01-12**:
  - **Version v0.0.6 released**
  - Bumped crane-lib dependency for Shipwright support (#174)
  - Updated golang version in release workflow (#175)

**Key Achievement:** Shipwright Builds support - modernizing CI/CD migrations

---

## 🎯 Core Development Focus Areas (Chronological)

### 1. **Export Infrastructure** (April-June 2021)
- Velero discovery helper integration
- Paging support for large clusters
- Resource extraction and serialization

### 2. **Transform & Plugin System** (June-November 2021)
- Plugin architecture
- Plugin priorities
- Optional flags
- Config file support
- Plugin manager (add/list/remove)

### 3. **Apply & Migration** (June 2021 onwards)
- Apply command
- Handle missing resources
- Context and namespace handling
- User impersonation

### 4. **PVC & State Transfer** (August 2021 - March 2022)
- Transfer-PVC subcommand
- Rsync integration
- Progress reporting
- Checksum verification
- Storage class mapping
- Node name discovery

### 5. **Image Migration** (April-July 2022)
- ImageStream handling
- Skopeo sync integration
- Registry migration support

### 6. **API Version Management** (July 2022)
- PreferredVersion export
- Multi-version API handling
- Kubernetes version compatibility

### 7. **RBAC & Security** (March 2023)
- Cluster-scoped RBAC
- SecurityContextConstraints
- ServiceAccount filtering
- Permission error handling

### 8. **CI/CD Modernization** (September 2025)
- BuildConfig → Shipwright conversion
- Modern build pipeline support

---

## 👥 Key Contributors

### Most Active Contributors (by commits):
1. **David Zager (djzager)** - ~30 commits
   - Plugin system architecture
   - CI/CD workflows
   - Skopeo integration
   - Core infrastructure

2. **Jason Montleon (jmontleo)** - ~15 commits
   - PreferredVersion export
   - Image handling
   - Proxy support
   - Latest features (Shipwright)

3. **Scott Seago (sseago)** - ~12 commits
   - Config file support
   - Plugin priorities
   - Version command
   - CLI improvements

4. **Shawn Hurley** - ~10 commits
   - Transform command
   - Debug logging
   - Release automation
   - Error handling

5. **Pranav Gaikwad (pranavgaikwad)** - ~8 commits
   - PVC transfer library
   - Rsync integration
   - Progress reporting
   - State transfer

6. **Alay Patel (alaypatel07)** - ~8 commits
   - Transfer-PVC subcommand
   - Minikube automation
   - Pager fixes
   - Ingress support

7. **Jaydipkumar Gabani** - ~7 commits
   - Plugin manager
   - Route/Ingress naming
   - Disconnected environments

8. **Daniele Martinoli (dmartinol)** - ~2 commits
   - Cluster-scoped RBAC (major feature)
   - Segmentation violation fixes

---

## 🔧 Technical Evolution

### Dependency Management
- **crane-lib versions:** 0.0.2 → 0.0.3 → 0.0.4 → 0.0.7 → 0.1.5
- **Go versions:** 1.17 → 1.21
- **Kubernetes client updates:** Regular updates for compatibility
- **Security patches:** Regular CVE fixes (x/net, protobuf, oauth2)

### Architecture Patterns
1. **CLI Framework:** Cobra + Viper
2. **Kubernetes Integration:** Velero discovery helper
3. **Plugin System:** Runner library with priorities
4. **Config Management:** YAML-based flags file
5. **State Transfer:** Rsync-based with progress reporting
6. **Image Sync:** Skopeo integration
7. **Testing:** GitHub Actions, unit tests, Minikube automation

---

## 📦 Release History

| Version | Date | Key Features |
|---------|------|-------------|
| v0.0.1 | Sep 2021 | Initial release with plugin logs, crane-lib pinning |
| v0.0.2 | Nov 2021 | Disconnected environment support |
| v0.0.3 | Dec 2021 | Ingress support, Minikube automation |
| v0.0.4 | May 2022 | Workflow improvements |
| v0.0.5 | Aug 2022 / Jul 2024 | PreferredVersion, Skopeo sync, Go 1.21 |
| v0.0.6 | Jan 2026 | Shipwright Builds support |

---

## 🎓 Lessons & Development Patterns

### What the Project Prioritized:

1. **User Experience**
   - Config file support to reduce command-line complexity
   - Debug logging for troubleshooting
   - Progress reporting for long-running operations
   - Clear error messages

2. **Extensibility**
   - Plugin architecture from early stages
   - Plugin manager for easy extension
   - Multiple plugin search paths
   - Optional flags system

3. **Enterprise Requirements**
   - Disconnected environment support
   - HTTP proxy support
   - RBAC migration
   - Security context constraints
   - User impersonation

4. **Stateful Workloads**
   - PVC transfer with rsync
   - Progress reporting
   - Checksum verification
   - Storage class mapping

5. **Multi-cluster Compatibility**
   - API version preference handling
   - Context awareness
   - Kubernetes version compatibility
   - OpenShift-specific features

6. **Image Migration**
   - ImageStream handling
   - Skopeo sync generation
   - Registry migration support

7. **CI/CD Migration**
   - Latest focus on Shipwright Builds
   - Converting legacy BuildConfigs
   - Modern pipeline support

---

## 🔍 Notable Bug Fixes

### Critical Fixes:
- **Segmentation violation** with cluster-scoped RBAC (#151)
- **Empty extracted files** (#4)
- **ImageStreamTags API semantics** (#78)
- **Pager list processing** (#45)
- **Context not respected** in export (#68)
- **Plugin not found exit code** (#129)
- **Route/Ingress name length limits** (#124)

### Security Fixes:
- CVE-2023-44487 (x/net dependency)
- Bug 2268141 (protobuf)
- Bug 2269447 (x/net)
- oauth2 vulnerability

---

## 📈 Development Activity Timeline

```
2021: █████████████████████████████████████ (Foundation + Plugin System)
2022: ████████████████████████████████████████████████ (Peak activity - Features)
2023: ████████ (RBAC + Security)
2024: ██ (Maintenance)
2025: ████ (Shipwright + Security)
2026: █ (Latest release)
```

**Peak Development:** Mid-2022 (June-August)
**Feature-Complete:** Late 2022
**Current State:** Maintenance mode with occasional new features

---

## 🎯 Recommendations for kubectl-migrate

Based on crane's development history, consider these insights:

### What Worked Well:
1. ✅ **Plugin architecture** - Enabled community extensions
2. ✅ **Config file support** - Reduced CLI complexity
3. ✅ **Velero integration** - Leveraged existing tooling
4. ✅ **Progressive feature development** - Export → Transform → Apply
5. ✅ **Stateful workload support** - Critical for real migrations
6. ✅ **API version handling** - Essential for multi-cluster

### Areas to Improve/Avoid:
1. ⚠️ **Project became unmaintained** - Need sustainability plan
2. ⚠️ **Windows support unclear** - Platform strategy needed upfront
3. ⚠️ **Documentation gaps** - Broken links, missing HACKING.md
4. ⚠️ **Issue triage backlog** - 10/12 issues not triaged
5. ⚠️ **Long gap between releases** - More frequent releases recommended

### Key Takeaways for kubectl-migrate:
1. **Start with clear use cases** - crane evolved from PVC transfer → full cluster migration
2. **Prioritize stateful workloads early** - Most complex part
3. **API version compatibility is critical** - Implement early
4. **Plugin system adds value** - But requires maintenance commitment
5. **Container image distribution** - Easier adoption (added in v0.0.4)
6. **Progress reporting matters** - For long-running operations
7. **Security must be ongoing** - Regular dependency updates
8. **Documentation is critical** - crane suffered from broken docs
9. **Community engagement** - Active triage and issue management needed
10. **Modern CI/CD support** - Shipwright shows evolution to modern tools

---

**Analysis Generated:** 2026-02-11
**Tool Used:** GitHub CLI (`gh api`)
**Data Source:** migtools/crane repository commit history
