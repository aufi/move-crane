# Crane Ecosystem - Dependencies and Relationships

This document describes the dependencies and relationships between all crane-related repositories.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Crane Ecosystem Architecture                     │
└─────────────────────────────────────────────────────────────────────────┘

                        ┌──────────────────────┐
                        │  crane-operator      │
                        │  (OLM Operator)      │
                        └──────────┬───────────┘
                                   │
                                   │ deploys & manages
                                   │
           ┌───────────────────────┼────────────────────────┐
           │                       │                        │
           ▼                       ▼                        ▼
    ┌─────────────┐      ┌─────────────────┐     ┌──────────────────┐
    │crane-runner │      │ crane-ui-plugin │     │ Support Services │
    │ ClusterTasks│◄─────┤   (UI/React)    │     │                  │
    └──────┬──────┘      └────────┬────────┘     │ • reverse-proxy  │
           │                      │              │ • secret-service │
           │ uses                 │ uses         └────────┬─────────┘
           │                      │                       │
           ▼                      ▼                       │
    ┌─────────────────────────────────────┐               │
    │        crane CLI Tool               │               │
    │     (Go Binary/Container)           │◄──────────────┘
    └────────────┬────────────────────────┘
                 │
                 │ depends on
                 │
                 ▼
    ┌──────────────────────────┐
    │      crane-lib           │
    │  (Core Library/Go)       │
    └────────┬─────────────────┘
             │
             │ used by
             │
             ▼
    ┌──────────────────────────┐
    │    Plugin System         │
    │                          │
    │  • crane-plugins         │◄─── index/registry
    │  • plugin-openshift      │◄─── binary plugin
    │  • plugin-imagestream    │◄─── binary plugin
    └──────────────────────────┘
```

## Component Dependencies

### 1. crane (CLI Tool)
**Repository**: https://github.com/migtools/crane
**Language**: Go
**Type**: Command-line tool / Container image

**Dependencies**:
- **crane-lib** (`github.com/konveyor/crane-lib v0.0.8`) - Core transformation library
- **pvc-transfer** (`github.com/backube/pvc-transfer v0.0.0-20220718185428-1d2440958552`) - PVC migration
- **Kubernetes client-go** (v0.24.2) - Kubernetes API client
- **OpenShift API** (v0.0.0-20220525145417-ee5b62754c68) - OpenShift resources
- **Velero** (v1.6.3) - Backup/restore integration
- **Kustomize** (v0.13.7) - YAML transformations
- **Cobra/Viper** - CLI framework

**Provides**:
- Binary executable: `crane`
- Container image: `quay.io/konveyor/crane`
- Commands: export, transform, apply, transfer-pvc, plugin-manager, etc.

**Used By**:
- crane-runner (as container in ClusterTasks)
- crane-ui-plugin (indirectly via ClusterTasks)
- End users (direct CLI usage)

---

### 2. crane-lib
**Repository**: https://github.com/migtools/crane-lib
**Language**: Go
**Type**: Go library

**Dependencies**:
- **Kubernetes client-go** (v0.21.2)
- **OpenShift API** (v0.0.0-20210625082935-ad54d363d274)
- **json-patch** (v5.5.0) - JSONPatch operations
- **controller-runtime** (v0.9.2)

**Provides**:
- Transform library functions
- Plugin interface definitions
- Resource transformation utilities
- Common Kubernetes/OpenShift helpers

**Used By**:
- **crane** CLI tool
- **crane-plugin-openshift**
- **crane-plugin-imagestream**

---

### 3. crane-operator
**Repository**: https://github.com/migtools/crane-operator
**Language**: Go
**Type**: Kubernetes Operator (OLM)

**Dependencies**:
- **Kubernetes client-go** (v0.23.0)
- **OpenShift API** (v0.0.0-20220322000322-9c4998a4d646)
- **Tekton Pipeline API** (`github.com/tektoncd/pipeline v0.33.0`)
- **controller-runtime** (v0.11.1)

**Manages/Deploys**:
- crane-runner (ClusterTasks)
- crane-ui-plugin (ConsolePlugin + Deployment)
- crane-reverse-proxy (Service)
- crane-secret-service (Service)

**Provides**:
- CRD: OperatorConfig
- Deployment manifests for all components
- RBAC configuration
- OLM bundle

**Used By**:
- Cluster administrators (via OLM)

---

### 4. crane-runner
**Repository**: https://github.com/migtools/crane-runner
**Language**: YAML/Tekton
**Type**: Tekton ClusterTasks

**Dependencies**:
- **Tekton Pipelines** (required operator)
- **crane** container image (uses in tasks)

**Provides ClusterTasks**:
- `crane-export` - Export resources
- `crane-transform` - Transform resources
- `crane-apply` - Apply transformations
- `crane-transfer-pvc` - Transfer PVCs
- `crane-kubeconfig-generator` - Generate kubeconfigs
- `crane-image-sync` - Sync container images
- `crane-kustomize-init` - Initialize kustomize
- `crane-kubectl-scale-down` - Scale down workloads
- `kubectl-apply-kustomize` - Apply kustomize
- `kubectl-apply-files` - Apply files
- `oc-registry-info` - Get registry info

**Used By**:
- crane-ui-plugin (generates Pipelines using these ClusterTasks)
- crane-operator (deploys these ClusterTasks)
- Users (creating Tekton Pipelines manually)

---

### 5. crane-ui-plugin
**Repository**: https://github.com/migtools/crane-ui-plugin
**Language**: TypeScript/React
**Type**: OpenShift Console Dynamic Plugin

**Dependencies**:
- **@openshift-console/dynamic-plugin-sdk** (0.0.12) - Console integration
- **@migtools/lib-ui** (8.4.1) - Migration UI library
- **PatternFly React** (4.x) - UI components
- **React** (17.0.1)
- **react-query** (3.34.8) - Data fetching
- **axios** (0.21.1) - HTTP client

**Backend Service Dependencies**:
- **crane-reverse-proxy** - Proxies requests to source cluster
- **crane-secret-service** - Manages OAuth secrets
- **crane-runner ClusterTasks** - Executes migrations

**Provides**:
- OpenShift Console plugin
- Import Application wizard
- Pipeline management UI
- Container image: `quay.io/konveyor/crane-ui-plugin`

**Used By**:
- OpenShift Console users
- crane-operator (deploys)

---

### 6. crane-reverse-proxy
**Repository**: https://github.com/migtools/crane-reverse-proxy
**Language**: Go
**Type**: HTTP Proxy Service

**Dependencies**:
- **gin-gonic/gin** (v1.7.7) - Web framework
- **go-cache** (v2.1.0) - Caching
- **Kubernetes client-go** (v0.22.1)

**Provides**:
- HTTP proxy endpoint for remote cluster access
- Token-based authentication passthrough
- Service on port 8443

**Used By**:
- crane-ui-plugin (proxies API calls to source cluster)

---

### 7. crane-secret-service
**Repository**: https://github.com/migtools/crane-secret-service
**Language**: Go
**Type**: Secret Management Service

**Dependencies**:
- **gin-gonic/gin** (v1.7.7) - Web framework
- **Kubernetes API** (v0.23.5)

**Provides**:
- Secret creation/management API
- OAuth token storage
- Service on port 8443

**Used By**:
- crane-ui-plugin (creates/updates cluster credential secrets)

---

### 8. crane-plugins
**Repository**: https://github.com/migtools/crane-plugins
**Language**: YAML (manifest repository)
**Type**: Plugin index/registry

**Dependencies**: None (just metadata)

**Provides**:
- Plugin index (index.yaml)
- Plugin metadata for:
  - ImageStreamPlugin
  - OpenShiftPlugin
- Binary download links

**Used By**:
- crane CLI (plugin-manager command)

---

### 9. crane-plugin-openshift
**Repository**: https://github.com/migtools/crane-plugin-openshift
**Language**: Go
**Type**: Binary plugin

**Dependencies**:
- **crane-lib** (`github.com/konveyor/crane-lib v0.0.8`)
- **OpenShift API** (v0.0.0-20211028135425-c4970133b5ba)
- **json-patch** (v4.11.0)

**Provides**:
- Binary plugin for OpenShift-specific transformations
- Handles Routes, ImageStreams, etc.

**Used By**:
- crane CLI (via plugin system)
- Listed in crane-plugins registry

---

### 10. crane-plugin-imagestream
**Repository**: https://github.com/migtools/crane-plugin-imagestream
**Language**: Go
**Type**: Binary plugin

**Dependencies**:
- **crane-lib** (`github.com/konveyor/crane-lib v0.0.8`)
- **OpenShift API** (v0.0.0-20210625082935-ad54d363d274)
- **json-patch** (v4.11.0)

**Provides**:
- Binary plugin for ImageStream transformations
- Image reference updates

**Used By**:
- crane CLI (via plugin system)
- Listed in crane-plugins registry

---

## Dependency Flow Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                         Dependency Layers                          │
└────────────────────────────────────────────────────────────────────┘

Layer 1 (Foundation):
    ┌──────────────┐
    │  crane-lib   │  (Core library)
    └──────┬───────┘
           │
           │
Layer 2 (Core Tools):
    ┌──────▼───────┐       ┌──────────────────┐
    │  crane CLI   │       │  Plugin Binaries │
    │              │       │  • openshift     │
    └──────┬───────┘       │  • imagestream   │
           │               └──────────────────┘
           │
           │
Layer 3 (Orchestration):
    ┌──────▼────────┐
    │ crane-runner  │  (Tekton ClusterTasks)
    │ (ClusterTasks)│
    └──────┬────────┘
           │
           │
Layer 4 (User Interface):
    ┌──────▼──────────┐      ┌─────────────────┐
    │ crane-ui-plugin │◄─────┤ Support Services│
    │   (Console UI)  │      │ • reverse-proxy │
    └─────────────────┘      │ • secret-service│
                             └─────────────────┘

Layer 5 (Deployment):
    ┌────────────────┐
    │ crane-operator │  (Manages all above)
    └────────────────┘
```

## External Dependencies Summary

### Common External Dependencies:
- **Kubernetes**: client-go, apimachinery, api
- **OpenShift API**: OpenShift-specific resources
- **Tekton Pipelines**: Workflow orchestration
- **Controller Runtime**: Kubernetes controllers

### Key External Libraries:
- **pvc-transfer**: PVC migration (used by crane)
- **json-patch**: JSONPatch operations
- **Velero**: Backup integration (used by crane)
- **Kustomize**: YAML manipulation (used by crane)

## Runtime Relationships

### Migration Workflow Dependencies:

```
User → crane-ui-plugin
         ↓
      Creates Tekton Pipeline
         ↓
      Uses crane-runner ClusterTasks
         ↓
      Executes crane CLI (in containers)
         ↓
      Uses crane-lib for transformations
         ↓
      Loads plugins (openshift, imagestream)
         ↓
      Migrates application
```

### Service Communication:

```
crane-ui-plugin → crane-reverse-proxy → Source Cluster
crane-ui-plugin → crane-secret-service → Kubernetes API (Secrets)
crane-ui-plugin → OpenShift Console API
crane-ui-plugin → Tekton API (Pipelines, PipelineRuns)
```

## Summary

The Crane ecosystem is organized in layers:

1. **Foundation**: crane-lib provides core transformation logic
2. **Tools**: crane CLI and plugins provide migration capabilities
3. **Orchestration**: crane-runner packages crane as Tekton tasks
4. **Interface**: crane-ui-plugin provides user-friendly UI
5. **Infrastructure**: Support services enable UI functionality
6. **Management**: crane-operator deploys and manages everything

All components work together to enable seamless Kubernetes application migration across clusters.
