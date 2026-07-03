# AGENTS.md - Context for AI Agents

## Repository Purpose

This repository (`move-crane`) is a **planning, documentation, and research workspace** for the development of Crane - a Kubernetes workload migration tool being integrated into the Konveyor ecosystem.

**⚠️ CRITICAL: This is NOT an implementation repository.**

- ✅ Planning documents, design proposals, and implementation plans
- ✅ Research notes and comparative analyses
- ✅ Experimental POCs and playground code
- ✅ Test scenarios and validation notes
- ❌ NO production code implementation
- ❌ NO actual crane CLI or library code

The actual implementation happens in separate repositories under the `migtools` organization (see below).

## About Crane

**Crane** is a Kubernetes application migration tool that helps application owners migrate workloads and their persistent data between Kubernetes clusters.

### Core Philosophy

- **Non-destructive**: All operations write to disk without affecting live workloads
- **Idempotent**: Commands can be run repeatedly with consistent results
- **Transparent**: All transformations visible as JSONPatch files
- **Auditable**: Full history of changes for version control
- **GitOps-ready**: Output designed for Git repository storage

### Key Capabilities

1. **Export** - Discover and export all Kubernetes resources from a namespace
2. **Transform** - Apply plugin-based transformations to exported resources
3. **Apply** - Generate final redeployable manifests
4. **Transfer-PVC** - Transfer PersistentVolumeClaims and their data between clusters
5. **Plugin System** - Extensible architecture for custom transformations

### Migration Workflow

```
Source Cluster
    ↓
crane export      → export/resources/
    ↓
crane transform   → transform/patches/
    ↓
crane apply       → output/resources/
    ↓
kubectl apply     → Target Cluster

(Parallel: crane transfer-pvc for stateful workloads)
```

## Crane Ecosystem Repositories

The Crane ecosystem consists of multiple repositories under the `migtools` organization:

| Repository | Purpose | Language |
|------------|---------|----------|
| [crane](https://github.com/migtools/crane) | CLI tool for migration | Go |
| [crane-lib](https://github.com/migtools/crane-lib) | Core transformation library | Go |
| [crane-operator](https://github.com/migtools/crane-operator) | Kubernetes operator (OLM) | Go |
| [crane-runner](https://github.com/migtools/crane-runner) | Tekton ClusterTasks | YAML/Tekton |
| [crane-ui-plugin](https://github.com/migtools/crane-ui-plugin) | OpenShift Console UI | TypeScript/React |
| [crane-plugins](https://github.com/migtools/crane-plugins) | Plugin registry | YAML |
| [crane-plugin-openshift](https://github.com/migtools/crane-plugin-openshift) | OpenShift transformations | Go |
| [crane-plugin-imagestream](https://github.com/migtools/crane-plugin-imagestream) | ImageStream handling | Go |

### Dependency Flow

```
crane-lib (foundation)
    ↓
crane CLI + plugins
    ↓
crane-runner (Tekton tasks)
    ↓
crane-ui-plugin (UI) + crane-operator (deployment)
```

## Repository Structure

```
move-crane/
├── README.md                    # Overview and ecosystem description
├── DEPENDENCIES.md              # Detailed architecture and dependencies
├── AGENTS.md                    # This file - context for AI agents
│
├── research/                    # Research and comparative analysis
│   ├── README.md                # Index of research notes
│   ├── migration_general_steps.md
│   ├── personas.md
│   ├── k8s_migrate_tools_and_needs.md
│   ├── k8s_migrate_tools_usage.md
│   └── kubectl_krew_overview.md
│
├── drafts/                      # Implementation plans and proposals
│   ├── README.md                # Workflow diagram
│   ├── IMPLEMENTATION_PLAN_NEW_RESOURCES.md  # Plugin API extension
│   ├── STAGE_DIRECTORY_REFACTOR_PLAN.md     # UX improvement plan
│   ├── transform-redesign-and-validation.md
│   ├── discovery-step-proposal.md
│   ├── plugin-request-response-v2-draft.md
│   └── crane-helm-template-transform-proposal.md
│
├── notes/                       # Technical notes and decisions
│   ├── data-migrations/         # PVC transfer research
│   ├── transform-multistage.md  # Multi-stage pipeline guide
│   ├── kantra-crane-embedding-plan.md
│   ├── namespace-app-cluster-dependencies.md
│   └── ocp-4x-compatibility.md
│
├── playground/                  # Working examples and POCs
│   ├── README.md                # Playground overview
│   ├── crane-plugin-agent-instructions.md  # Plugin development guide
│   ├── buildconfig-kustomize-converter/    # Kustomize-based POC
│   ├── manifest-migration-poc/
│   └── scenario-06-advanced-plugin-based-conversion.md
│
├── crane-history/               # Historical analysis
│   ├── crane-commit-history-analysis.md
│   ├── crane-issues-analysis.md
│   ├── crane-lib-analysis.md
│   └── crane-runner-analysis.md
│
├── crane-ui-plugin/             # UI plugin roadmap and notes
│   └── roadmap.md
│
└── test-day-june2026/           # Test scenarios and validation
    └── (test scenarios, sample apps, validation results)
```

## Key Documents for AI Agents

### Starting Points

1. **README.md** - High-level overview, feature list, use cases
2. **DEPENDENCIES.md** - Complete architecture and component relationships
3. **This file (AGENTS.md)** - Context and navigation guide

### Planning Documents

Located in `drafts/`:

- **IMPLEMENTATION_PLAN_NEW_RESOURCES.md** - Plan for extending plugin API to create new resource types (e.g., BuildConfig → Shipwright)
- **STAGE_DIRECTORY_REFACTOR_PLAN.md** - UX improvement for transform stage directory structure
- **transform-redesign-and-validation.md** - Transform workflow improvements
- **discovery-step-proposal.md** - Pre-export discovery command proposal

### Technical Guides

Located in `notes/`:

- **transform-multistage.md** - Guide to multi-stage transformation pipelines
- **data-migrations/** - Research on PVC transfer strategies (rsync, rclone, restic)
- **namespace-app-cluster-dependencies.md** - Analysis of resource dependencies

### Development Resources

Located in `playground/`:

- **crane-plugin-agent-instructions.md** - Complete guide for plugin development with AI assistance
- **buildconfig-kustomize-converter/** - Working example of Kustomize-based transformation
- **scenario-06-advanced-plugin-based-conversion.md** - Advanced plugin patterns

## Current Focus Areas

### 1. Plugin API Enhancement

**Goal**: Enable plugins to create new resource types, not just transform existing ones

**Status**: Implementation plan complete (`drafts/IMPLEMENTATION_PLAN_NEW_RESOURCES.md`)

**Key changes**:
- Extend `PluginResponse` with `NewResources []unstructured.Unstructured`
- Update `RunnerResponse` to collect new resources
- Maintain 100% backward compatibility

**Use cases**:
- BuildConfig → Shipwright Build conversion
- DeploymentConfig → Deployment migration
- ImageStream → registry reference translation

### 2. Stage Directory UX Improvement

**Goal**: Make transform stage structure more intuitive

**Status**: Refactoring plan drafted (`drafts/STAGE_DIRECTORY_REFACTOR_PLAN.md`)

**Current** (confusing):
```
transform/
├── 10_KubernetesPlugin/
│   ├── resources/           # unclear name
│   └── patches/
└── .work/                   # hidden
    └── 10_KubernetesPlugin/
        ├── input/
        └── output/
```

**Proposed** (clear):
```
transform/
└── 10_KubernetesPlugin/
    ├── input/               # explicit input
    ├── patches/
    └── output/              # explicit output
```

### 3. Validation and Discovery

**Goal**: Reduce migration iteration cycles through proactive validation

**Status**: Proposal in `drafts/discovery-step-proposal.md`

**New workflow**:
```
crane discover → crane export → crane transform ⇄ crane validate → kubectl apply
                                    ↑________________↓
                                 (iterate until valid)
```

### 4. Data Migration Strategies

**Goal**: Improve PVC transfer reliability and performance

**Status**: Research complete (`notes/data-migrations/`)

**Options compared**:
- rsync (current)
- rclone (cloud-friendly)
- restic (encrypted backups)
- In-cluster Job-based transfer
- Backube pvc-transfer library

## Common Task Scenarios

### When Asked to Create Implementation Plans

1. **Check if this is the right repository**: Remember, NO implementation here
2. **Create plans in `drafts/`**: Use existing plans as templates
3. **Reference actual code**: Link to `migtools/crane` or `migtools/crane-lib`
4. **Use Czech for planning docs**: Most plans are in Czech
5. **Include backward compatibility**: Crane values compatibility highly

### When Asked About Migration Strategies

1. **Consult `research/`**: Start with comparative analyses
2. **Check `notes/`**: Look for technical decisions
3. **Review `playground/`**: Working examples often answer questions
4. **Reference workflow**: See `drafts/README.md` for current workflow diagram

### When Asked to Design Plugins

1. **Read `playground/crane-plugin-agent-instructions.md`** FIRST
2. **Study examples**: Check `playground/buildconfig-kustomize-converter/`
3. **Understand two approaches**:
   - Kustomize-based (easier, no Go needed)
   - Plugin-based (production-grade, Go required)
4. **Check API extensions**: See `drafts/IMPLEMENTATION_PLAN_NEW_RESOURCES.md`

### When Asked About Architecture

1. **Start with DEPENDENCIES.md**: Complete architecture overview
2. **Check layer boundaries**: Foundation → Tools → Orchestration → UI
3. **Understand plugin system**: crane-lib → crane CLI → plugins
4. **Note runtime relationships**: UI → Tekton → crane CLI → crane-lib

## Important Constraints

### Language Preferences

- **Planning documents**: Czech (most existing plans)
- **Code comments**: English
- **Technical guides**: English
- **User-facing docs**: English

### Design Principles

1. **Backward compatibility**: Never break existing plugins or workflows
2. **Transparency**: All transformations must be visible and auditable
3. **Idempotency**: Commands must be safely repeatable
4. **GitOps-first**: Output designed for version control
5. **Unix philosophy**: Composable, focused tools

### Technical Standards

- **Go version**: Match crane-lib (currently using client-go v0.24.x era)
- **Kubernetes API**: Support multiple versions (v1.21+)
- **JSON Patch**: RFC 6902 for all transformations
- **Plugin interface**: V1 API (extend, don't replace)

## Anti-Patterns to Avoid

### In Planning Documents

- ❌ Implementing code in this repo
- ❌ Creating V2 APIs when V1 can be extended
- ❌ Breaking backward compatibility
- ❌ Proposing destructive operations
- ❌ Ignoring GitOps workflow requirements

### In Plugin Design

- ❌ Modifying input resources directly
- ❌ Assuming cluster connectivity during transform
- ❌ Generating non-deterministic output
- ❌ Requiring user interaction during transform
- ❌ Creating dependencies between plugins

### In Migration Workflows

- ❌ Modifying source cluster during export
- ❌ Auto-applying to target cluster
- ❌ Losing transformation history
- ❌ Mixing automated and manual changes in same stage
- ❌ Skipping validation before apply

## Useful Patterns

### Multi-Stage Transformations

```
10_KubernetesPlugin    → Clean metadata, remove cluster-specific fields
20_OpenshiftPlugin     → Convert Routes, BuildConfigs, etc.
30_StorageClassPlugin  → Map storage classes for target
50_CustomEdits         → Manual tweaks (pass-through stage)
```

### Plugin Development

**Kustomize approach** (recommended for most):
```bash
Bash script → Extract data → Helm template → YAML output
```

**Go plugin approach** (for production):
```go
Implement Plugin interface → Return PluginResponse → Generate patches
```

### Validation Workflow

```bash
# Export
crane export -n source-ns > export/

# Transform (iterate)
crane transform 10_KubernetesPlugin
crane transform 20_OpenshiftPlugin

# Validate (proposed)
crane validate --target-context prod-cluster --input output/
# Exit code 0 = ready, 2 = needs fixes

# Apply when valid
kubectl apply -f output/resources/
```

## Testing and Validation

### Test Day Scenarios

Located in `test-day-june2026/`:
- Real-world application samples (WordPress, etc.)
- Validation scripts
- Migration scenarios
- Output analysis

### Playground Examples

Located in `playground/`:
- BuildConfig → Shipwright conversion
- Manifest migration POCs
- Kustomize-based transformers

## Common Questions Answered

### Q: Where is the crane CLI code?
**A**: https://github.com/migtools/crane - this repo only has planning docs

### Q: Can I implement features here?
**A**: No - create implementation plans here, implement in `migtools/crane*` repos

### Q: How do I create a new plugin?
**A**: Read `playground/crane-plugin-agent-instructions.md`, choose Kustomize or Go approach

### Q: What's the difference between transform stages?
**A**: Stages ending in `Plugin` auto-regenerate; others are pass-through for manual edits

### Q: How does crane handle PVC migration?
**A**: See `notes/data-migrations/` - uses rsync via backube/pvc-transfer, alternatives researched

### Q: What Kubernetes versions are supported?
**A**: v1.21+ (client-go v0.24 era), with focus on OpenShift 4.x compatibility

### Q: How to migrate from OpenShift to vanilla Kubernetes?
**A**: Use multi-stage: KubernetesPlugin + OpenshiftPlugin (Routes→Ingress, BuildConfigs→Shipwright, etc.)

## Quick Reference Links

### External Documentation
- Crane README: https://github.com/migtools/crane#readme
- crane-lib API: https://github.com/migtools/crane-lib
- Shipwright (BuildConfig target): https://shipwright.io/
- Tekton (pipeline engine): https://tekton.dev/

### Internal Key Files
- Workflow diagram: `drafts/README.md`
- Plugin API plan: `drafts/IMPLEMENTATION_PLAN_NEW_RESOURCES.md`
- Plugin dev guide: `playground/crane-plugin-agent-instructions.md`
- Multi-stage guide: `notes/transform-multistage.md`
- Architecture: `DEPENDENCIES.md`

## Summary

This repository is a **planning and research workspace** for Crane development. When working here:

1. ✅ Create implementation plans and proposals
2. ✅ Document research and decisions
3. ✅ Build POC examples in playground
4. ✅ Write test scenarios and validation
5. ❌ DO NOT implement production code here

For actual implementation, reference the appropriate `migtools/crane*` repository and create detailed plans here first.

**Remember**: Crane values backward compatibility, transparency, and GitOps workflow. All proposals should respect these principles.
