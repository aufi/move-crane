# move-crane

This repository supports the integration of the `crane` container migration tool into the Konveyor applications migration project.

## About

Crane is a container migration tool that is being integrated into the Konveyor ecosystem to enhance application migration capabilities.

Great starting point is crane README https://github.com/migtools/crane?tab=readme-ov-file#overview, then feel free continue here.

## Crane Repositories in migtools Organization

The following repositories are part of the crane ecosystem under the migtools organization:

| Repository | Description |
|------------|-------------|
| [crane](https://github.com/migtools/crane) | Tool for migrating Kubernetes workloads, and their data, between clusters |
| [crane-operator](https://github.com/migtools/crane-operator) | Migration Toolkit for Red Hat Operator |
| [crane-runner](https://github.com/migtools/crane-runner) | Migrate Kubernetes workloads using crane CLI tool, Tekton ClusterTasks, and Tekton Pipelines |
| [crane-lib](https://github.com/migtools/crane-lib) | Library for crane |
| [crane-ui-plugin](https://github.com/migtools/crane-ui-plugin) | OpenShift Dynamic Plugin that provides a UI for constructing container migration pipelines within the OpenShift console |
| [crane-ui-tests](https://github.com/migtools/crane-ui-tests) | Crane UI tests |
| [crane-plugins](https://github.com/migtools/crane-plugins) | A place for managed crane plugins to live happily |
| [crane-plugin-openshift](https://github.com/migtools/crane-plugin-openshift) | OpenShift plugin for crane |
| [crane-plugin-imagestream](https://github.com/migtools/crane-plugin-imagestream) | ImageStream plugin for crane |
| [crane-reverse-proxy](https://github.com/migtools/crane-reverse-proxy) | Reverse proxy proof of concept for proxying OpenShift cluster connections |
| [crane-secret-service](https://github.com/migtools/crane-secret-service) | Service to proxy requests from crane-ui-plugin creating Secrets to the API Server |
| [crane-documentation](https://github.com/migtools/crane-documentation) | Documentation for crane |

---

## Crane CLI Tool - Features and Capabilities

### Overview

Crane is a Kubernetes migration tool that helps application owners migrate workloads and their state between clusters. It follows the Unix philosophy of building focused, composable tools that can be assembled in powerful ways.

### Key Design Principles

- **Non-Destructive**: All operations write to disk without affecting live workloads
- **Idempotent**: Commands can be run repeatedly with consistent results
- **Transparent**: All transformations are visible as JSONPatch files
- **Auditable**: Full history of changes for version control
- **GitOps-Ready**: Output designed for Git repository storage

### Core Commands

#### 1. Export (`crane export`)

Discovers and exports all Kubernetes resources from a namespace.

**Features**:
- Exports all namespace-scoped resources to YAML files
- Optionally exports cluster-scoped RBAC resources (ClusterRoles, ClusterRoleBindings, SecurityContextConstraints)
- Supports label selectors to filter resources
- User/group impersonation support for access control
- Automatic discovery of all available API resources
- Intelligent filtering of cluster-scoped resources based on ServiceAccount usage

#### 2. Transform (`crane transform`)

Applies plugin-based transformations to exported resources.

**Features**:
- Plugin-based architecture for extensible transformations
- Built-in Kubernetes plugin that removes non-redeployable metadata
- Generates JSONPatch files for each exported resource
- Supports plugin priorities for conflict resolution
- Optional flags can be passed to plugins

**Subcommands**:
- `crane transform list-plugins` - Lists all configured plugins
- `crane transform optionals` - Shows optional fields accepted by plugins

#### 3. Apply (`crane apply`)

Applies transformations to exported resources to create redeployable manifests.

**Features**:
- Reads exported resources and transform patches
- Applies JSONPatch transformations
- Generates final redeployable YAML files
- Produces GitOps-ready manifests

#### 4. Transfer-PVC (`crane transfer-pvc`)

Transfers PersistentVolumeClaims and their data between clusters.

**Features**:
- Cross-cluster PVC migration using rsync
- Encrypted data transfer using self-signed certificates
- Support for different storage classes
- Multiple endpoint types (OpenShift Route, Nginx Ingress)
- Optional data verification using checksums
- Progress tracking and statistics output

#### 5. Plugin-Manager (`crane plugin-manager`)

Manages Crane plugins.

**Features**:
- `plugin-manager add` - Install plugins from repositories
- `plugin-manager list` - List available plugins
- `plugin-manager remove` - Remove installed plugins
- Version-specific plugin installation
- Multi-architecture plugin support

#### 6. Skopeo-Sync-Gen (`crane skopeo-sync-gen`)

Generates configuration for container image synchronization.

**Features**:
- Analyzes ImageStream resources
- Generates Skopeo sync YAML configuration
- Identifies internal registry images
- Enables container image migration workflows

#### 7. Tunnel-API (`crane tunnel-api`)

Establishes OpenVPN tunnel between source and destination clusters.

**Features**:
- Creates secure VPN tunnel for cluster-to-cluster connectivity
- Automatic SSL certificate generation
- HTTP proxy support for restricted networks
- Enables migrations when direct cluster-to-cluster connectivity is not available

### Migration Workflows

#### Standard Migration Workflow
1. **Export** - Extract all resources from source namespace
2. **Transform** - Apply plugins to modify resources for target environment
3. **Apply** - Generate final redeployable manifests
4. **Deploy** - Apply manifests to destination cluster (or commit to GitOps)

#### State Migration Workflow
1. Export application resources
2. Transform resources
3. Use `transfer-pvc` to migrate persistent volumes
4. Deploy transformed manifests to destination

#### Image Migration Workflow
1. Export resources including ImageStreams
2. Use `skopeo-sync-gen` to create image sync configuration
3. Sync container images using Skopeo
4. Deploy migrated application

### Use Cases

- **GitOps Onboarding**: Reconstruct redeployable YAML from running applications
- **Cross-Cloud Migration**: Migrate from one cloud provider to another
- **Configuration Drift Recovery**: Capture current application state
- **Cluster Upgrade**: Migrate to new cluster version with API compatibility
- **Namespace Migration**: Move applications to different namespaces
- **Multi-Cluster DR Setup**: Replicate applications across clusters for disaster recovery
- **Platform Migration**: Move from OpenShift to vanilla Kubernetes or vice versa

---

## Crane UI Plugin - Features and Capabilities

### Overview

The Crane UI Plugin is an OpenShift Console Dynamic Plugin that provides a user-friendly interface for constructing container migration pipelines within the OpenShift console.

**Requirements**: OpenShift 4.11 or greater

### Key Features

#### 1. Import Application Wizard

A guided 6-step wizard for creating migration pipelines:

**Step 1: Source Cluster and Project**
- API URL input with validation
- OAuth token authentication
- Project/namespace selection
- Real-time credential validation

**Step 2: Source Project Details**
- Overview of Pods, PVCs, and Services
- Information fetched from source cluster

**Step 3: PVC Selection**
- Table view of all PVCs in source namespace
- Multi-select capability
- JSON view for each PVC
- Option to proceed without PVCs (stateless migration)

**Step 4: PVC Editing** (if PVCs selected)
- Per-PVC configuration:
  - Target PVC name customization
  - Storage class selection
  - Capacity configuration
  - Verify copy option (checksum verification)

**Step 5: Pipeline Settings**
- Pipeline group name configuration
- Auto-generated naming
- Validation against existing pipelines

**Step 6: Review and Finish**
- Summary of all settings
- Pipeline visualization using topology graphs
- Advanced mode with YAML editor for customization
- Monaco code editor integration

#### 2. Imported Applications Management

**Pipeline Group Dashboard**:
- Tabbed interface for multiple pipeline groups
- Real-time status monitoring
- Action buttons for pipeline execution
- Pipeline run history table

**Pipeline Actions**:
- **Stage** (for stateful migrations): Pre-copy PVC data to reduce downtime
- **Cutover**: Final migration including workloads
- Disabled states with explanatory tooltips
- Confirmation modals for operations

#### 3. Pipeline Construction

The UI generates Tekton Pipelines with ClusterTasks including:
- Kubeconfig generation
- Resource export from source
- Registry information gathering
- Container image synchronization
- Resource transformation
- Kustomize configuration
- Workload deployment
- PVC transfer (for stateful migrations)
- Application quiescing (scale-down)

**Pipeline Types**:
- **Stage Pipeline**: Pre-copy PVC data (can run multiple times)
- **Cutover Pipeline**: Final migration (run once)

### OpenShift Console Integration

**Extension Points**:
- Developer Perspective Navigation: "Imported Applications" menu item
- Add Page Actions: "Import Application" card
- Topology Context Menu: "Import from another cluster" action

**Integration Services**:
- OpenShift Pipelines (Tekton) for workflow execution
- OAuth authentication
- crane-reverse-proxy for source cluster communication
- crane-secret-service for secure credential management

### Migration Scenarios

1. **Stateless Application Migration**: Web applications without persistent storage
2. **Single PVC Migration**: Small databases, WordPress sites with data verification
3. **Multi-PVC Migration**: Complex stateful applications with staged synchronization
4. **Cross-Infrastructure Migration**: Moving between on-premise and cloud
5. **Cluster Consolidation**: Merging multiple clusters

### User Experience Features

- Welcome modal with educational content
- Route guards for unsaved changes
- Real-time validation
- Progressive disclosure of advanced features
- Contextual help popovers
- Empty states with helpful guidance
- Pipeline topology visualization
- Status badges and timestamps
- Responsive, sortable, filterable data grids

### Technology Stack

- **Frontend**: React 17, TypeScript
- **UI Framework**: PatternFly 4 (OpenShift design system)
- **Build**: Webpack 5
- **Deployment**: Nginx, OpenShift
- **Code Editor**: Monaco Editor for YAML editing

---

## Summary

The Crane ecosystem provides comprehensive tools for Kubernetes application migration:

- **crane CLI**: Command-line tool for resource export, transformation, and PVC migration
- **crane-ui-plugin**: User-friendly OpenShift console interface for guided migrations
- **Supporting components**: Operators, plugins, proxy services, and documentation

Together, these tools enable seamless migration of both stateless and stateful applications across Kubernetes clusters with minimal downtime and maximum control.
