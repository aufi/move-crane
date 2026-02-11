# Analysis of migtools/crane-lib Repository

**Analysis Date:** 2026-02-11
**Repository:** https://github.com/migtools/crane-lib
**Latest Version:** v0.1.5

---

## 📊 Overview

**Open Issues:** 16
**Closed Issues:** 7
**Total Commits Analyzed:** ~100 commits
**Project Timespan:** April 2021 - January 2026
**Release Versions:** v0.0.1 → v0.1.5 (17 releases)

### Purpose
crane-lib is the **core library** that provides reusable functionality for:
- Transform operations (plugin system)
- Apply operations (patch application)
- State transfer (PVC migration with rsync)
- Export/discovery helpers

---

## 🐛 Issues Analysis

### Open Issues (16)

#### High Priority / Important:

**#89 - Safe version checking**
- Author: jmontleon
- Created: 2021-11-11
- No labels, no comments
- Status: Still open after 4+ years

**#87 - Schema Register Function for Clients**
- Author: jmontleon
- Created: 2021-11-11
- No labels, no comments
- Status: Still open after 4+ years

**#52 - State Transfer Rsync Endpoint: allow setting custom hostname based on cluster domain**
- Author: pranavgaikwad
- Created: 2021-07-16
- Label: `state-lib`
- Status: Open

**#51 - State Transfer: Provide default option for Rsync extra arguments**
- Author: pranavgaikwad
- Created: 2021-07-14
- Label: `state-lib`
- Status: Open

**#49 - Create a PluginRequest type to encapsulate Object, extras and set version**
- Author: shawn-hurley
- Created: 2021-07-14
- Label: `transform-lib`
- Status: Open

**#46 - Support namespace names greater than 60 chars for route endpoint**
- Author: alaypatel07
- Created: 2021-07-12
- Label: `state-lib`
- Status: Open - namespace length limitation issue

**#41 - Consider "from" member when determining patch conflicts**
- Author: sseago
- Created: 2021-07-02
- No labels
- Status: Open

**#31 - Check that routes are admitted before looking up the hostname**
- Author: jmontleon
- Created: 2021-06-25
- Labels: `kind/bug`, `state-lib`
- Status: Open - important for state transfer reliability

**#30 - Should we check for `IsAlreadyExists(err)` errors and overwrite existing resources**
- Author: jmontleon
- Created: 2021-06-25
- Label: `state-lib`
- Status: Open - design decision needed

**#29 - Use md5hash to ensure unique names**
- Author: jmontleon
- Created: 2021-06-25
- Labels: `kind/bug`, `state-lib`
- Status: Open

**#28 - Validate Endpoint rather than sleeping and praying**
- Author: jmontleon
- Created: 2021-06-25
- Labels: `kind/bug`, `state-lib`
- Comment: Suggestion to use poller instead of sleep
- Status: Open - reliability issue

**#27 - Label (Selectors) won't work with long PVC Names**
- Author: jmontleon
- Created: 2021-06-25
- Labels: `kind/bug`, `state-lib`
- Status: Open - Kubernetes label length restrictions

**#24 - Define a way for callers to wait for resource created by library to be in expected state**
- Author: alaypatel07
- Created: 2021-06-24
- Label: `state-lib`
- Status: Open - API design issue

**#13 - Validate the output of binary plugin**
- Author: alaypatel07
- Created: 2021-06-15
- Labels: `kind/feature`, `transform-lib`
- Status: Open - plugin validation

**#9 - Decide on correct way to wrap errors**
- Author: shawn-hurley
- Created: 2021-06-11
- Labels: `kind/feature`, `state-lib`, `apply-lib`, `transform-lib`
- Status: Open - affects all libraries

**#8 - Add logging to transform and apply packages**
- Author: shawn-hurley
- Created: 2021-06-11
- Labels: `kind/feature`, `state-lib`, `apply-lib`, `transform-lib`
- Status: Open - observability gap

**#5 - How do I write a single patch to apply to every instance of a GVK**
- Author: jmontleon
- Created: 2021-06-03
- Labels: `kind/feature`, `apply-lib`, `transform-lib`
- Status: Open - usability question

### Closed Issues (7)

**#88 - Accept a value for different network range for OpenVPN connection**
- Closed: 2022-06-22
- Author: jmontleon

**#73 - Binary plugin stderr isn't being logged in crane transform CLI invocation**
- Closed: 2021-09-27
- Author: sseago

**#66 - Service example plugin strips clusterIP, still seeing clusterIPs**
- Closed: 2021-09-28
- Labels: `kind/bug`
- Multiple comments, resolved with plugin updates

**#65 - Openshift example plugin returns error code 2**
- Closed: 2021-10-04
- Labels: `kind/bug`
- Issue: logger.Info() calls breaking stdout format
- Fixed by proper logger initialization

**#61 - Add BuildConfig to OpenShift binary plugin**
- Closed: 2021-09-28
- Author: sseago

**#32 - Two different operation kinds with same patch should be considered in conflict**
- Closed: 2021-07-06
- Labels: `transform-lib`

**#23 - Apply - Error: invalid patch file - no data**
- Closed: 2021-07-06
- Labels: `kind/bug`, `apply-lib`
- Fixed: Now creates "[]" for empty patches

**#7 - Add ability for runner to handle missing objects or lists**
- Closed: 2021-06-16
- Duplicate of #4

**#4 - How do we handle writing patches when parent parameter may or may not exist**
- Closed: 2021-06-23

---

## 📈 Commit History Analysis

### Development Phases

#### Phase 1: Foundation (April 2021 - June 2021)
**Focus:** Core libraries and plugin system

- **2021-04-26**: Project initialization with LICENSE
- **2021-06-09**: Transform helper functions and runner initial attempt (#3)
- **2021-06-14**: Binary plugin library (#6)
- **2021-06-15**:
  - Apply library implementation (#12)
  - Utilities for CLI custom plugins (#10)
- **2021-06-16**: Enabled GitHub Actions for unit tests (#16)
- **2021-06-17**: Documentation for plugin developers (#19)
- **2021-06-21**:
  - Test plugins added (#21)
  - Remove transform help from lib (belongs in CLI) (#15)
- **2021-06-23**: Runner enhancements (#20)
- **2021-06-25**: **Initial state transfer** (#2) - Major feature
- **2021-06-30**:
  - Determine if object has status (#35)
  - Binary plugin stderr logging (#26)
  - Error reporting from plugins (#22)

**Key Achievements:**
- Core transform/apply/state-transfer libraries
- Plugin system foundation
- Binary plugin support

---

#### Phase 2: Plugin System Maturation (July 2021 - September 2021)
**Focus:** Plugin priorities, optional fields, and refinements

- **2021-07-01**:
  - Plugin priorities for transform.Runner (#34)
  - Fix test plugin names (#38)
- **2021-07-05**: Plugin metadata capability (#33)
- **2021-07-06**:
  - Different operation kinds should conflict (#39)
  - EqualOperation, handle "from" field (#40)
- **2021-07-07**: Refactor into different packages, remove cyclic imports (#37)
- **2021-07-12**: Refine state_transfer package interfaces (#45)
- **2021-07-14**: **Initial implementation of plugin optional fields** (#44)
- **2021-07-15**: RsyncTransfer options (#47)
- **2021-07-16**:
  - PVC list and PVC mapping for Transfers (#50)
  - Expose getters for reconcilers (#48)
- **2021-07-20**: Fix build failure (#53)
- **2021-07-21**: Fix route name and namespace (#56, #57)
- **2021-07-28**:
  - Add Proxy Support (#36)
  - IsServerHealthy to transfer interface (#60)
- **2021-07-29**: Binary plugins for stateless demo (#59)
- **2021-08-03**:
  - **Plugin version validation** (#62) - Important feature
  - DVM <-> State Transfer Feature Parity (#58)
- **2021-08-10**: Kubernetes plugin updates for stateless migrations (#64)
- **2021-08-11**: Fix missing labels on route endpoint (#68)
- **2021-08-31**: Configure rsync/stunnel image (#71)
- **2021-09-07**: Fix stunnel options (#72)
- **2021-09-17**: Stunnel container sleep between rsync checks (#74)

**Key Achievements:**
- Complete plugin priority system
- State transfer with proxy support
- Plugin version validation
- Rsync/stunnel configurability

---

#### Phase 3: Production Hardening (September 2021 - November 2021)
**Focus:** OpenShift support, service plugins, debugging

- **2021-09-24**:
  - Fixes/additions for OpenShift plugin (#75)
  - Added service plugin fixes to kubernetes plugin (#69)
  - Remove service and route plugins (#77)
- **2021-09-27**: **Plugin debugging capability** (#79)
- **2021-10-20**:
  - Allow skip whiteout for owned pods/templates (#81)
  - Remove unnecessary metadata fields in kubernetes plugin (#82)
  - Remove skip-owned (handled by kubernetes.go) (#80)
- **2021-10-29**: Expose transform util (#84)
- **2021-11-01**:
  - **Additional whiteout configurability** (#83)
  - **Refactor plugin interface** - PluginRequest instead of obj/args (#76)
- **2021-11-10**: Fixes for plugin optional args (#85)
- **2021-11-11**: Remove openshift plugin (moved to separate repo) (#86)
- **2021-11-12**: Add crane-lib version const, report from kube plugin (#91)
- **2021-11-15**:
  - Handle routes longer than 63 chars (#90)
  - Add OpenVPN API Proxy (#78)

**Key Achievements:**
- OpenShift plugin moved to dedicated repository
- Whiteout configurability
- Plugin interface refactoring
- Debugging support

---

#### Phase 4: State Transfer Enhancements (December 2021 - February 2022)
**Focus:** Ingress, extra options, registry forwarding

- **2021-12-03**: Update extra options regex (#94)
- **2021-12-08**:
  - **Version v0.0.5**
  - Add ingress endpoint (#93)
  - Remove new-namespace from kubernetes plugin (#92)
- **2022-01-07**: Set route host when subdomain specified (#96)
- **2022-01-10**: Update routePrefix when too long (#97)
- **2022-02-09**: Improve logic for other cloud providers (#98)
- **2022-02-11**:
  - Add support for http-proxy with tunnel-api (#99)
  - Forward registry port (#100)
- **2022-02-23**: Update release string (#101)

**Key Achievements:**
- Multi-cloud provider support
- Ingress endpoints
- Registry port forwarding
- HTTP proxy with tunnel API

---

#### Phase 5: Core Improvements (June 2022 - July 2022)
**Focus:** Metadata cleanup, PVC updates, logging

- **2022-06-14**: **Drop managedFields + default RBAC and CABundle** (#103)
- **2022-06-23**: Add ability to update PVC values if renamed (#104)
- **2022-06-24**: Add slack digest + jira sync workflows (#105)
- **2022-06-29**: Use apimachinery validation (#106)
- **2022-07-02**: Workflow updates (#107)
- **2022-07-05**: **Plugin log lines based on log level** (#102)
- **2022-07-07**:
  - Fix RoleBinding subjects (#109)
  - Remove DeploymentConfig updates from kubernetes plugin (#110)
- **2022-07-08**: Run rsync with or without root (#108)
- **2022-07-18**: Delete duplicate resources from extensions group (#111)
- **2022-08-03**: **Version v0.0.8**

**Key Achievements:**
- Metadata cleanup (managedFields removal)
- PVC rename support
- Rsync root/rootless support
- Improved logging

---

#### Phase 6: Advanced Features (September 2022 - July 2023)
**Focus:** Exclude files, service types, symlink handling

- **2022-09-15**: Update needs-triage workflow
- **2022-10-17**: **Add exclude files option** (#114)
- **2022-11-10**: Change LoadBalancer endpoint to generic Service type (#115)
- **2023-03-03**: Update rsync extra options validation (#116)
- **2023-05-22**: **Make symlink munging functionality configurable** (#117)
- **2023-05-31**: Fix ansible templating logic for rsync server (#118)
- **2023-06-07**: Split chroot and run as root options (#119)
- **2023-07-11**: Bump x/net dependency (Bug 2189169) (#120)

**Key Achievements:**
- File exclusion support
- Symlink handling configurability
- Security improvements (chroot/root separation)
- Dependency updates

---

#### Phase 7: Block Volume Support (June 2024 - August 2024)
**Focus:** Block volume rsync, image configuration

- **2024-06-05**:
  - **Add support for syncing block volumes** (#121)
  - Change blockrsync container to rsync-transfer (#122)
- **2024-06-20**: Allow setting image for block rsync (#123)
- **2024-06-21**: Fix blockrsync container pulling wrong image (#124)
- **2024-08-05**: Allow nodeName to be set in blockrsync options (#125)
- **2024-09-19**: Return true if PVC is filesystem with correct annotations (#126)

**Key Achievements:**
- **Block volume migration support** - Major feature
- Configurable block rsync images
- Node name specification

---

#### Phase 8: Shipwright Integration (September 2025 - January 2026)
**Focus:** BuildConfig to Shipwright conversion

- **2025-09-09**: **Convert OpenShift BuildConfigs to Shipwright Builds** (#127)
- **2025-09-11**: Shipwright: DockerBuildStrategy Type Migration (#128)
- **2025-09-26**: Shipwright: SourceBuildStrategy Type Migration (#129)
- **2025-11-04**: Added BuildSource migration logic (#130)
- **2025-12-12**: Logging improvements and bug fixes (#131)
- **2025-12-18**: Improved logging for source strategy (#132)
- **2026-01-21**: **Version v0.1.5**
  - Pull secret supported in s2i strategy (#133)

**Key Achievements:**
- **Complete Shipwright Builds support**
- Modern CI/CD pipeline migration
- Multiple build strategy conversions

---

## 🔧 Technical Focus Areas (By Component)

### 1. Transform Library (`transform-lib`)
**Purpose:** Plugin system for resource transformation

**Key Features:**
- Binary plugin support
- Plugin priorities
- Optional fields/arguments
- Version validation
- Conflict detection
- PluginRequest abstraction
- Whiteout configurability
- Plugin debugging
- Kubernetes plugin (metadata cleanup)
- OpenShift plugin (moved to separate repo)
- Shipwright plugin (BuildConfig conversion)

**Open Issues:** 4
- Plugin request type encapsulation (#49)
- Validate binary plugin output (#13)
- Error wrapping (#9)
- Logging (#8)
- Single patch for GVK instances (#5)

### 2. Apply Library (`apply-lib`)
**Purpose:** Apply transformations to resources

**Key Features:**
- JSON Patch application
- Handle empty patches
- Conflict resolution
- Error handling
- PVC value updates (for renames)

**Open Issues:** 3
- Error wrapping (#9)
- Logging (#8)
- Single patch for GVK (#5)

### 3. State Library (`state-lib`)
**Purpose:** PVC data migration with rsync

**Key Features:**
- Rsync transfer
- Stunnel encryption
- Route/Ingress endpoints
- HTTP proxy support
- Registry port forwarding
- Root/rootless rsync
- Exclude files
- Symlink handling
- **Block volume support**
- Node name specification
- PVC mappings
- Namespace mappings
- Progress tracking

**Open Issues:** 10
- Custom hostname for rsync endpoint (#52)
- Default rsync extra arguments (#51)
- Namespace > 60 chars (#46)
- Check routes admitted (#31)
- Overwrite existing resources (#30)
- MD5 hash for unique names (#29)
- Validate endpoint vs sleeping (#28)
- Long PVC names (#27)
- Wait for resource state (#24)
- Error wrapping (#9)
- Logging (#8)

---

## 📦 Release History

| Version | Key Features |
|---------|--------------|
| v0.0.1 | Initial release |
| v0.0.2 | Plugin system basics |
| v0.0.3 | State transfer foundation |
| v0.0.4 | Plugin optional fields |
| v0.0.5 | Ingress endpoints |
| v0.0.6 | Route length handling |
| v0.0.7 | Metadata cleanup |
| v0.0.8 | PVC rename, rsync root/rootless |
| v0.0.9 | Exclude files |
| v0.0.10 | Service type changes |
| v0.0.11 | Symlink configurability |
| v0.1.0 | Block volume support |
| v0.1.1-v0.1.4 | Block rsync improvements |
| v0.1.5 | Shipwright support |

---

## 👥 Key Contributors

1. **David Zager (djzager)** - ~30 commits
   - Transform/apply infrastructure
   - State transfer features
   - Workflow automation

2. **Pranav Gaikwad (pranavgaikwad)** - ~25 commits
   - State transfer library
   - Rsync/stunnel integration
   - Block volume support

3. **Scott Seago (sseago)** - ~20 commits
   - Plugin system
   - Optional fields
   - Binary plugins

4. **Jason Montleon (jmontleon)** - ~18 commits
   - Proxy support
   - Registry forwarding
   - Cloud provider improvements
   - Shipwright migration

5. **Alay Patel (alaypatel07)** - ~15 commits
   - Binary plugin library
   - State transfer interfaces
   - Endpoint management

6. **Shawn Hurley (shawn-hurley)** - ~12 commits
   - Transform runner
   - Apply library
   - Plugin metadata

7. **Alexander Wels** - ~6 commits
   - Block volume support (major contribution)
   - Block rsync features

8. **Prateek Rathore** - ~5 commits
   - Shipwright migration (major contribution)
   - Logging improvements

---

## 🎯 Key Insights

### What Worked Well:
1. ✅ **Modular library structure** - Separate transform/apply/state libraries
2. ✅ **Plugin system** - Highly extensible with version validation
3. ✅ **State transfer evolution** - From basic rsync to block volumes
4. ✅ **Continuous improvement** - Regular dependency updates, bug fixes
5. ✅ **Block volume support** - Critical for stateful workloads
6. ✅ **Shipwright integration** - Modernizing CI/CD migrations

### Challenges:
1. ⚠️ **16 open issues** - Many from 2021, lack of triage
2. ⚠️ **State-lib complexity** - 10 open issues, many edge cases
3. ⚠️ **No logging/error standards** - Issues #8 and #9 still open
4. ⚠️ **Validation gaps** - Endpoint validation, plugin output validation
5. ⚠️ **Kubernetes limitations** - Label length, namespace length issues

### Development Pattern:
- **2021**: Rapid feature development (3 phases)
- **2022**: Production hardening, refinements
- **2023**: Maintenance mode with targeted fixes
- **2024**: Major feature (block volumes)
- **2025-2026**: Modern CI/CD support (Shipwright)

---

## 💡 Recommendations for kubectl-migrate

### Based on crane-lib's journey:

1. **Library Architecture**
   - ✅ Separate libraries for distinct concerns (transform/apply/state)
   - ✅ Plugin system provides excellent extensibility
   - ⚠️ Need clear error handling and logging standards from day 1

2. **State Transfer**
   - ✅ Block volume support is essential (added in v0.1.0)
   - ✅ Multiple endpoint types (route/ingress/service) needed
   - ✅ Root/rootless support for security flexibility
   - ⚠️ Many edge cases still open - plan for complexity

3. **Plugin System**
   - ✅ Version validation prevents incompatibilities
   - ✅ Optional fields provide flexibility
   - ✅ Binary plugins enable community extensions
   - ⚠️ Output validation still needed (#13)

4. **Metadata Handling**
   - ✅ Stripping managedFields, default RBAC, CABundles crucial
   - ✅ Handling long names/labels important

5. **Modern Features**
   - ✅ Shipwright support shows evolution to modern tools
   - ✅ Block volume support differentiates from competitors

6. **Issue Management**
   - ⚠️ crane-lib has 16 open issues from 2021
   - 💡 Need proactive triage and resolution
   - 💡 Document design decisions for open questions

---

**Analysis Generated:** 2026-02-11
**Data Source:** migtools/crane-lib repository
