# Migration Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          SOURCE CLUSTER ANALYSIS                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                        ┌───────────────────────┐
                        │   crane discover      │
                        │                       │
                        │  • Inspect resources  │
                        │  • Test selectors     │
                        │  • Plan scope         │
                        │  • [--plan-target]    │
                        └───────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              EXPORT PHASE                               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                        ┌───────────────────────┐
                        │    crane export       │
                        │                       │
                        │  • Export resources   │
                        │  • Namespace/labels   │
                        └───────────────────────┘
                                    │
                                    ▼
                              export/resources/
                                    │
                ┌───────────────────┴───────────────────┐
                │                                       │
                ▼                                       ▼
┌───────────────────────────┐           ┌───────────────────────────┐
│   crane transfer-pvc      │           │   TRANSFORM-VALIDATE LOOP │
│                           │           └───────────────────────────┘
│  • Rsync PV data          │                       │
│  • Cross storage class    │                       │
│  • Source → Target        │                       ▼
│  (runs in parallel)       │           ┌───────────────────────┐
└───────────────────────────┘           │ crane transform-      │
                │                       │       prepare         │
                │                       │                       │
                │                       │ • Create patches      │
                │                       │ • Apply plugins       │
                │                       │ • Handle whiteouts    │
                │                       │ • Generate resources  │
                │                       └───────────────────────┘
                │                                   │
                │                                   ▼
                │                         transform/resources/
                │                                   │
                │                                   ▼
                │                       ┌───────────────────────┐
                │                       │ crane transform-apply │
                │                       │                       │
                │                       │ • Apply transforms    │
                │                       │ • Merge patches       │
                │                       │ • Generate manifests  │
                │                       └───────────────────────┘
                │                                   │
                │                                   ▼
                │                           output/resources/
                │                                   │
                │                                   ▼
                │                       ┌───────────────────────┐
                │                       │   crane validate      │
                │                       │   --target-context    │
                │                       │                       │
                │                       │ • API compatibility   │
                │                       │ • Auth & permissions  │
                │                       │ • Capacity checks     │
                │                       │ • Dry-run validation  │
                │                       └───────────────────────┘
                │                                   │
                │                       ┌───────────┴────────────┐
                │                       │                        │
                │                   Exit Code 0             Exit Code 2
                │                   (PASS)                  (NEEDS ADJUSTMENT)
                │                       │                        │
                │                       │                        │
                │                       │    ┌───────────────────┘
                │                       │    │
                │                       │    │ • Enable plugins
                │                       │    │ • Adjust mappings
                │                       │    │ • Fix incompatibilities
                │                       │    │
                │                       │    └──────────┐
                │                       │               │
                │                       │               ▼
                │                       │    ┌─────────────────────┐
                │                       │    │ Back to transform-  │
                │                       │    │ prepare with fixes  │
                │                       │    └─────────────────────┘
                │                       │               │
                │                       │               │
                │                       └───────────────┘
                │                           (Loop until valid)
                │                                   │
                └───────────────┬───────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          TARGET CLUSTER IMPORT                          │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
                        ┌───────────────────────┐
                        │   kubectl apply       │
                        │                       │
                        │ • Apply manifests     │
                        │ • Import to target    │
                        │ • Verify deployment   │
                        └───────────────────────┘
                                │
                                ▼
                        ┌───────────────────────┐
                        │  Migration Complete   │
                        └───────────────────────┘
```

## Workflow Phases

### 1. Discovery (Optional Pre-Export)
- **Command:** `crane discover --source-context <src> [--plan-target <dst>]`
- **Purpose:** Understand what exists, test selectors, plan scope
- **Output:** Resource inventory, migration plan hints

### 2. Export
- **Command:** `crane export -n <namespace> [--selector <labels>]`
- **Purpose:** Extract resources from source cluster
- **Output:** `export/resources/` with raw YAML manifests

### 3. Parallel Operations

#### 3a. PVC Transfer (Parallel)
- **Command:** `crane transfer-pvc --source-context <src> --dest-context <dst>`
- **Purpose:** Migrate persistent volume data
- **Runs:** In parallel with transform-validate loop
- **Technology:** Rsync via pvc-transfer library

#### 3b. Transform-Validate Loop (Iterative)
Repeats until validation passes:

##### Step 1: Transform Prepare
- **Command:** `crane transform-prepare --export-dir ./export --output-dir ./transforms`
- **Purpose:** Generate JSONPatch transforms and plugin outputs
- **Output:** `transform/resources/` with patches and generated resources

##### Step 2: Transform Apply
- **Command:** `crane transform-apply --export-dir ./export --transform-dir ./transforms --output-dir ./output`
- **Purpose:** Apply patches to create final manifests
- **Output:** `output/resources/` with redeployable YAML

##### Step 3: Validate
- **Command:** `crane validate --target-context <dst> --input-dir ./output`
- **Purpose:** Check target cluster compatibility
- **Checks:**
  - API availability (GVK support)
  - Authentication & RBAC permissions
  - Resource capacity (storage, compute)
  - Dry-run server-side validation
- **Exit Codes:**
  - `0` = PASS (proceed to import)
  - `2` = UNRESOLVED (loop back with adjustments)
  - `5` = TARGET UNREACHABLE (fix connectivity)

##### Loop Back (If Exit Code != 0)
- Review validation findings
- Enable additional plugins (e.g., `RouteToIngress`, `DeploymentConfigToDeployment`)
- Adjust storage class mappings
- Fix security context issues
- Return to Step 1 with updated configuration

### 4. Import
- **Command:** `kubectl apply -f output/resources/`
- **Purpose:** Deploy to target cluster
- **Prerequisite:** Validation must pass (exit code 0)

## Key Improvements Over Original Workflow

| Aspect | Original | New Design |
|--------|----------|------------|
| **Pre-export planning** | None | `crane discover` with optional target planning |
| **Validation timing** | After import attempt (reactive) | Before import (proactive) |
| **Target awareness** | None during transform | Full target context via `validate` |
| **Iteration cycles** | 3-5 attempts average | <2 attempts (60% reduction goal) |
| **Failure detection** | Import-time errors | Transform-time warnings |
| **Plugin activation** | Manual/guesswork | Guided by validation findings |
| **PVC migration** | Separate manual process | Parallel with transform loop |

## Selected command Changes

### Renamed (backward compatible)
- `crane transform` → `crane transform-prepare`
- `crane apply` → `crane transform-apply`

### New Commands
- `crane discover` - Pre-export analysis
- `crane validate` - Target compatibility validation

### Unchanged
- `crane export` - Still the primary export mechanism
- `crane transfer-pvc` - PVC migration (already exists)
