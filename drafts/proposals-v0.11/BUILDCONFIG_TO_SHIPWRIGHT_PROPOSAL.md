# Proposal: BuildConfig to Shipwright Conversion Plugin

**Date:** 2026-07-21  
**Status:** Proposal  
**Target Version:** v0.11+  
**Goal:** Enable GitOps-friendly migration of OpenShift BuildConfig resources to Shipwright Build CRs via a new crane transform plugin

---

## Executive Summary

OpenShift `BuildConfig` (`build.openshift.io/v1`) is a platform-specific resource with no equivalent in vanilla Kubernetes. Organizations migrating from OpenShift need to convert their CI/CD build definitions to a portable, cloud-native alternative. [Shipwright](https://shipwright.io/) (`shipwright.io/v1beta1`) is an open-source CNCF project that provides a Kubernetes-native build framework and is the natural successor.

This proposal introduces a new crane transform plugin — `BuildConfigToShipwrightPlugin` — that converts BuildConfig resources to Shipwright Build CRs as part of crane's standard export → transform → apply workflow, following crane's GitOps-friendly principles (no live cluster API calls during transformation).

**Existing work:** An earlier PoC exists in [crane-lib/convert/buildconfigs.go](https://github.com/migtools/crane-lib/blob/main/convert/buildconfigs.go) implementing direct API-based conversion (`crane convert`). This proposal replaces that approach with a plugin-based, offline transformation that generates auditable YAML artifacts.

**Prerequisite:** The plugin system must support creating new resources (see [plugin-update-new-resource-plan.md](../plugin-update-new-resource-plan.md)), since converting a BuildConfig requires generating a new Shipwright Build CR, not just patching the original.

---

## Motivation

### Why BuildConfig Migration Matters

BuildConfig is one of the most complex OpenShift-specific resources. Unlike Routes (→ Ingress) or DeploymentConfigs (→ Deployment), build definitions carry significant semantic weight — source references, build strategies, registry credentials, and output image targets — that must be carefully mapped to their Shipwright equivalents.

Many organizations running OpenShift 3.x/4.x have dozens to hundreds of BuildConfigs. Manual conversion is error-prone and time-consuming. An automated, reviewable conversion accelerates migration timelines significantly.

### Why Shipwright

- CNCF Sandbox project, backed by Red Hat (productized as "Builds for Red Hat OpenShift")
- Kubernetes-native: works on any cluster with Tekton installed
- Supports the same build paradigms: Dockerfile/Buildah builds, Source-to-Image (S2I), Buildpacks
- Clean API (`shipwright.io/v1beta1`) designed for extensibility via BuildStrategy CRDs
- Active community and growing adoption

### Why a Transform Plugin (Not `crane convert`)

The existing [crane-lib/convert](https://github.com/migtools/crane-lib/blob/main/convert/buildconfigs.go) PoC uses a direct API approach: it queries the live source cluster, resolves ImageStream references in real-time, and outputs converted resources. This works but violates crane's core design principles:

| Aspect | `crane convert` (PoC) | Transform Plugin (this proposal) |
|--------|----------------------|----------------------------------|
| Cluster connectivity | Required during conversion | Not required (offline) |
| Auditability | Output only, no patch trail | Full JSONPatch + whiteout trail |
| GitOps workflow | Separate from export/transform/apply | Integrated into standard pipeline |
| Idempotency | Depends on cluster state | Deterministic from exported YAML |
| Reviewability | Binary before/after | Reviewable patches in Git |
| Multi-stage pipeline | Standalone command | Composable with other plugins |

---

## Scope

### Goals

- Convert the three main BuildConfig strategy types to Shipwright Build CRs:
  - **Docker strategy** → Shipwright Build with `buildah` ClusterBuildStrategy
  - **Source (S2I) strategy** → Shipwright Build with `source-to-image` ClusterBuildStrategy
  - **Custom strategy** → Warning + passthrough (no automatic conversion)
- Map source configuration (Git, Binary, Image) to Shipwright source spec
- Map output image references (including ImageStreamTag resolution from exported data)
- Generate related resources where needed (ServiceAccount with pull/push secrets)
- Whiteout (mark for deletion) the original BuildConfig
- Produce reviewable YAML artifacts in the standard transform directory structure
- Document unsupported fields clearly in plugin output (warnings/annotations)

### Non-Goals

- JenkinsPipeline strategy conversion (deprecated, out of scope — users should migrate to Tekton Pipelines directly)
- Live cluster API calls during transformation
- Automatic Shipwright/Tekton installation on the target cluster
- BuildConfig trigger conversion (Shipwright triggers are a separate mechanism)
- Build history migration (Build objects are ephemeral)
- ImageStream migration (handled by a separate [crane-plugin-imagestream](https://github.com/migtools/crane-plugin-imagestream))

---

## How It Works

### Integration with Crane Workflow

```
crane export -n myapp
    ↓
    export/resources/
    ├── BuildConfig_build.openshift.io_v1_myapp_myapp-build.yaml
    ├── Deployment_apps_v1_myapp_myapp.yaml
    ├── ImageStream_image.openshift.io_v1_myapp_myapp.yaml  (if present)
    └── ...
    ↓
crane transform  (multi-stage pipeline)
    ↓
    Stage 10_KubernetesPlugin     → clean metadata, cluster-specific fields
    Stage 20_OpenshiftPlugin      → Route→Ingress, other OCP conversions
    Stage 30_BuildConfigPlugin    → BuildConfig→Shipwright Build  ← THIS PROPOSAL
    ↓
    transform/30_BuildConfigPlugin/
    ├── resources/
    │   ├── BuildConfig_...myapp-build.yaml          (whiteout)
    │   ├── Build_shipwright.io_v1beta1_myapp_myapp-build.yaml   (NEW)
    │   └── ...other resources unchanged...
    ├── patches/
    │   └── myapp--build.openshift.io-v1--BuildConfig--myapp-build.patch.yaml
    └── kustomization.yaml
    ↓
crane apply  →  output/resources/  →  kubectl apply -f
```

### Conversion Logic

The plugin processes each resource in the stage input. For non-BuildConfig resources, it passes through unchanged (empty response). For BuildConfig resources:

1. **Whiteout** the original BuildConfig (mark for deletion)
2. **Generate** a new Shipwright Build CR with mapped fields
3. **Optionally generate** a ServiceAccount if pull/push secrets are referenced
4. Return the new resource(s) via the `NewResources` field in PluginResponse

### Field Mapping Summary

#### Strategy Mapping

| BuildConfig Strategy | Shipwright ClusterBuildStrategy | Notes |
|---------------------|-------------------------------|-------|
| `dockerStrategy` | `buildah` | Dockerfile path, build args, base image mapped |
| `sourceStrategy` (S2I) | `source-to-image` | Builder image, env vars mapped |
| `customStrategy` | _(no conversion)_ | Warning emitted, resource passed through |
| `jenkinsPipelineStrategy` | _(out of scope)_ | Warning emitted, resource passed through |

#### Source Mapping

| BuildConfig Source | Shipwright Source | Notes |
|-------------------|------------------|-------|
| `git.uri` + `git.ref` | `source.type: Git`, `source.git.url` + `revision` | Direct mapping |
| `git.httpProxy/httpsProxy` | Env vars `HTTP_PROXY`, `HTTPS_PROXY` | Injected as build env |
| `sourceSecret` | `source.git.cloneSecret` | Direct mapping |
| `contextDir` | `source.contextDir` | Direct mapping |
| `binary` | `source.type: Local` | Requires manual `shp build upload` |
| `images[0]` | `source.type: OCIArtifact` | Single image source only |
| `dockerfile` (inline) | _(not supported)_ | Warning: write to file in repo |

#### Output Mapping

| BuildConfig Output | Shipwright Output | Notes |
|-------------------|------------------|-------|
| `output.to` (DockerImage) | `output.image` | Direct reference |
| `output.to` (ImageStreamTag) | `output.image` | Resolved to registry URL from exported ImageStream data |
| `output.pushSecret` | `output.pushSecret` | Direct mapping |

#### Known Unsupported Fields

These BuildConfig features have no Shipwright equivalent and are documented as warnings in the plugin output:

| Feature | Tracking | Note |
|---------|----------|------|
| Docker volumes | BUILD-1747 | Shipwright doesn't support build-time volumes |
| S2I custom scripts | BUILD-1641 | Not available in Shipwright S2I strategy |
| Incremental builds | BUILD-1607 | Not supported |
| ConfigMaps as source | BUILD-1745 | Not available |
| Secrets as source | BUILD-1744 | Not available |
| ForcePull | BUILD-1580/1606 | No equivalent |
| Image squash | BUILD-1581 | No equivalent |
| Multiple image sources | — | Shipwright supports single source only |

The plugin emits clear warnings for each unsupported field encountered so users can address them manually.

---

## Implementation Plan

The overall effort is structured in four phases, ordered by dependency:

### Phase 1: Plugin System Update

**Prerequisite for this plugin.** Extend the crane plugin API to support generating new resources. Detailed in [plugin-update-new-resource-plan.md](../plugin-update-new-resource-plan.md).

Key changes:
- Add `NewResources []unstructured.Unstructured` to `PluginResponse` in crane-lib
- Update `Runner` and `Orchestrator` to collect and write new resource artifacts
- 100% backward compatible via `omitempty` JSON tag

**Repositories:** [crane-lib](https://github.com/migtools/crane-lib), [crane](https://github.com/migtools/crane)  
**Effort:** ~2 weeks

### Phase 2: BuildConfig-to-Shipwright Plugin

New plugin repository implementing the conversion. Ports and adapts the proven logic from [crane-lib/convert/buildconfigs.go](https://github.com/migtools/crane-lib/blob/main/convert/buildconfigs.go) into the plugin architecture.

Structure:
```
crane-plugin-buildconfig/
├── main.go              # Plugin entry point, GVK filter
├── converter.go         # BuildConfig → Shipwright Build mapping
├── converter_test.go    # Unit tests for each strategy/source type
├── testdata/            # Sample BuildConfig YAMLs for testing
├── go.mod
└── README.md
```

Plugin flags:
- `--search-registries` — comma-separated search registries for image resolution
- `--insecure-registries` — comma-separated insecure registries
- `--block-registries` — comma-separated blocked registries
- `--default-build-strategy` — override default ClusterBuildStrategy name

**Repository:** new `migtools/crane-plugin-buildconfig`  
**Effort:** ~2 weeks

### Phase 3: Crane Workflow Updates

Improvements to the overall crane transform workflow that benefit this plugin but are generally useful:

- **Export resource filtering by type** — allow `crane export` to filter by GVK so users can export only BuildConfigs (or exclude them) for targeted transformation runs
- **Full plugin execution control in transform** — ability to select/skip specific plugins per stage, enable plugin ordering and dependency declarations

**Repositories:** [crane](https://github.com/migtools/crane)  
**Effort:** ~2 weeks

### Phase 4: Documentation and AI-Friendly Plugin Development Guide

- Step-by-step guide for building custom crane transform plugins
- Annotated example: the BuildConfig plugin as a reference implementation
- Machine-readable plugin development instructions optimized for AI coding assistants
- Plugin testing patterns and testdata conventions

**Repository:** [crane](https://github.com/migtools/crane) (docs), [move-crane](https://github.com/konveyor/move-crane) (playground)  
**Effort:** ~1 week

---

## Example: End-to-End Conversion

### Input: OpenShift BuildConfig

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: myapp-build
  namespace: myapp
spec:
  source:
    type: Git
    git:
      uri: https://github.com/example/myapp.git
      ref: main
    contextDir: src
    sourceSecret:
      name: git-credentials
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile.prod
      buildArgs:
        - name: GO_VERSION
          value: "1.21"
      from:
        kind: DockerImage
        name: golang:1.21-alpine
  output:
    to:
      kind: DockerImage
      name: quay.io/example/myapp:latest
    pushSecret:
      name: quay-push-secret
```

### Output: Shipwright Build

```yaml
apiVersion: shipwright.io/v1beta1
kind: Build
metadata:
  name: myapp-build
  namespace: myapp
  annotations:
    crane.konveyor.io/converted-from: build.openshift.io/v1/BuildConfig/myapp-build
spec:
  source:
    type: Git
    git:
      url: https://github.com/example/myapp.git
      revision: main
      cloneSecret: git-credentials
    contextDir: src
  strategy:
    name: buildah
    kind: ClusterBuildStrategy
  paramValues:
    - name: dockerfile
      value: Dockerfile.prod
    - name: build-args
      values:
        - value: "GO_VERSION=1.21"
    - name: runtime-stage-from
      value: golang:1.21-alpine
  output:
    image: quay.io/example/myapp:latest
    pushSecret: quay-push-secret
```

### Transform Directory Output

```
transform/30_BuildConfigPlugin/
├── resources/
│   ├── BuildConfig_build.openshift.io_v1_myapp_myapp-build.yaml   # whiteout marker
│   └── Build_shipwright.io_v1beta1_myapp_myapp-build.yaml         # NEW generated
├── patches/
│   └── myapp--build.openshift.io-v1--BuildConfig--myapp-build.patch.yaml
└── kustomization.yaml
```

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Shipwright not installed on target cluster | Build CRs fail to apply | Plugin emits clear prerequisite warning; document Shipwright installation |
| ImageStreamTag references can't be resolved offline | Output image URL incomplete | Use exported ImageStream data; fallback to placeholder with annotation |
| BuildConfig uses unsupported features | Incomplete conversion | Emit warnings per field; annotate output CR with `crane.konveyor.io/warnings` |
| Plugin API extension (Phase 1) delayed | Blocks plugin development | Plugin can be developed against a local crane-lib branch in parallel |

---

## Alternatives Considered

### 1. Keep Using `crane convert` (Direct API Approach)

The existing PoC in crane-lib works but requires live cluster connectivity during conversion, produces no transformation trail, and doesn't integrate with crane's multi-stage pipeline. Rejected because it violates crane's GitOps-first design.

### 2. Kustomize-Based Conversion (No Go Plugin)

A shell script + Kustomize approach (similar to [buildconfig-kustomize-converter](../../playground/buildconfig-kustomize-converter/)) could handle simple cases but lacks the semantic understanding needed for strategy mapping, ImageStream resolution, and ServiceAccount generation. Better suited as a lightweight alternative for simple Dockerfile-only builds, not as the primary conversion path.

### 3. Manual Conversion with Templates

Provide YAML templates and let users convert manually. This doesn't scale for organizations with many BuildConfigs and defeats the purpose of automated migration tooling.

---

## Success Criteria

1. Plugin correctly converts Docker and S2I strategy BuildConfigs to functional Shipwright Builds
2. Converted Builds can be applied to a target cluster with Shipwright installed and trigger successful builds
3. All unsupported fields produce clear, actionable warnings
4. Conversion is fully offline — no cluster connectivity required during transform stage
5. Output integrates with crane's standard apply workflow and Kustomize structure
6. Existing plugins and workflows are unaffected (backward compatibility)

---

## Open Questions

1. **ImageStream resolution strategy**: When a BuildConfig references an ImageStreamTag for its base image or output, the plugin needs to resolve this to a concrete registry URL. Should it:
   - (a) Read from co-exported ImageStream YAML in the same export directory (preferred)
   - (b) Accept a mapping file as plugin flag
   - (c) Use a default OpenShift internal registry URL pattern

2. **Shipwright strategy version pinning**: Should the plugin hardcode strategy names (`buildah`, `source-to-image`) or make them configurable via flags? The PoC hardcodes them, but cluster-specific ClusterBuildStrategy names may vary.

3. **BuildRun generation**: Should the plugin also generate a BuildRun CR (the Shipwright equivalent of triggering a build), or leave that to the user? Recommendation: out of scope for initial version.

---

## Next Steps

1. Complete Phase 1 (Plugin API extension) — blocks all plugin work
2. Port conversion logic from crane-lib/convert to plugin architecture
3. Build test suite with sample BuildConfigs covering all strategy types
4. E2E validation: export from OpenShift cluster → transform → apply to Shipwright-enabled cluster
