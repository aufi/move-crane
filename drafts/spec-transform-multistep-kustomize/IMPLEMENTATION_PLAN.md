# Implementation Plan: Kustomize-Only Multi-Stage Transform

## Overview

This document provides a phased implementation plan for migrating crane from JSONPatch files to Kustomize-only workflow with optional multi-stage pipeline support.

**Target Repositories**:
- `crane-lib` - Core transformation logic
- `crane` - CLI commands and orchestration

**Estimated Timeline**: 8-12 weeks (depending on team size and parallel work)

---

## Phase 0: Preparation & Setup (Week 1)

### Goals
- Set up development environment
- Create feature branch
- Establish testing infrastructure

### Tasks

#### 0.1 Repository Setup
- [ ] Create feature branch: `feature/kustomize-transform`
- [ ] Set up CI pipeline for feature branch
- [ ] Document development setup in CONTRIBUTING.md

#### 0.2 Testing Infrastructure
- [ ] Create fixture directory: `crane/test-data/kustomize-transform/`
- [ ] Port existing test fixtures to new structure
- [ ] Set up golden file testing framework
- [ ] Create sample export directory with various resource types

#### 0.3 Design Review
- [ ] Review specification with team
- [ ] Identify any missing edge cases
- [ ] Confirm API contracts between crane-lib and crane

### Deliverables
- ✅ Feature branch ready
- ✅ Test fixtures prepared
- ✅ Team alignment on design

---

## Phase 1: crane-lib Foundations (Weeks 2-3)

### Goals
- Implement core data structures
- Add Kustomize serialization logic
- Add resource grouping functionality

### Epic A: Core Data Structures

#### A1: Transform Artifact Types
**Issue**: `crane-lib: Add TransformArtifact + PatchTarget structs`

**Files to modify**:
- `crane-lib/transform/types.go` (new file)

**Implementation**:
```go
// types.go
package transform

type TransformArtifact struct {
    Resource      Resource
    HaveWhiteOut  bool
    Patches       []jsonpatch.Operation
    IgnoredOps    []IgnoredOperation
    Target        PatchTarget
}

type PatchTarget struct {
    Group     string
    Version   string
    Kind      string
    Name      string
    Namespace string
}

type IgnoredOperation struct {
    Operation    jsonpatch.Operation
    Plugin       string
    Reason       string
    WinnerPlugin string
}

type ResourceGroup struct {
    TypeKey   string  // e.g., "deployment.apps", "service"
    Resources []Resource
}
```

**Tests**:
- [ ] Unit tests for struct creation
- [ ] Test target derivation from resource metadata

**Acceptance**:
- [ ] All types compile without errors
- [ ] Unit tests pass

---

#### A2: Kustomize Serialization Package
**Issue**: `crane-lib: Add kustomize serializer package`

**Files to create**:
- `crane-lib/transform/kustomize/serializer.go`
- `crane-lib/transform/kustomize/naming.go`
- `crane-lib/transform/kustomize/kustomization.go`

**Implementation**:

```go
// serializer.go
package kustomize

func SerializePatchToYAML(ops []jsonpatch.Operation) ([]byte, error)
func GeneratePatchFilename(target PatchTarget) string
func DeriveTargetFromResource(resource Resource) PatchTarget

// naming.go
func GetResourceTypeFilename(kind, apiGroup string) string
func SanitizeFilename(name string) string

// kustomization.go
type KustomizationFile struct {
    APIVersion string
    Kind       string
    Resources  []string
    Patches    []Patch
}

type Patch struct {
    Path   string
    Target PatchTarget
}

func GenerateKustomization(resources []string, patches []Patch) ([]byte, error)
```

**Tests**:
- [ ] Test patch YAML serialization (golden files)
- [ ] Test filename generation with edge cases
- [ ] Test kustomization.yaml generation
- [ ] Test sanitization of special characters

**Acceptance**:
- [ ] JSONPatch ops serialize to valid Kustomize YAML
- [ ] Filenames are deterministic and filesystem-safe
- [ ] Generated kustomization.yaml validates with kubectl

---

#### A3: Resource Type Grouping
**Issue**: `crane-lib: Add resource type grouping logic`

**Files to create**:
- `crane-lib/transform/grouping.go`

**Implementation**:

```go
package transform

func GroupResourcesByType(resources []Resource) map[string][]Resource {
    grouped := make(map[string][]Resource)

    for _, resource := range resources {
        typeKey := getResourceTypeKey(resource)
        grouped[typeKey] = append(grouped[typeKey], resource)
    }

    return grouped
}

func getResourceTypeKey(resource Resource) string {
    kind := strings.ToLower(resource.Kind)
    group := extractGroupFromAPIVersion(resource.APIVersion)

    if group == "" {
        return kind
    }
    return kind + "." + group
}

func WriteResourceTypeFile(filename string, resources []Resource) error {
    var buf bytes.Buffer

    for i, resource := range resources {
        if i > 0 {
            buf.WriteString("\n---\n")
        }

        yamlBytes, err := yaml.Marshal(resource)
        if err != nil {
            return err
        }

        buf.Write(yamlBytes)
    }

    return os.WriteFile(filename, buf.Bytes(), 0644)
}
```

**Tests**:
- [ ] Test grouping with mixed resource types
- [ ] Test core vs non-core API grouping
- [ ] Test multi-doc YAML writing
- [ ] Test preservation of creation order

**Acceptance**:
- [ ] Resources grouped correctly by kind+group
- [ ] Multi-doc YAML files valid
- [ ] Order preserved within each type

---

#### A4: Report Structures
**Issue**: `crane-lib: Add whiteout/ignored-patches report structs`

**Files to create**:
- `crane-lib/transform/reports.go`

**Implementation**:

```go
package transform

type WhiteoutReport struct {
    APIVersion  string   `json:"apiVersion"`
    Kind        string   `json:"kind"`
    Name        string   `json:"name"`
    Namespace   string   `json:"namespace,omitempty"`
    RequestedBy []string `json:"requestedBy"`
}

type IgnoredPatchReport struct {
    Resource       ResourceIdentity `json:"resource"`
    Path           string          `json:"path"`
    SelectedPlugin string          `json:"selectedPlugin"`
    IgnoredPlugin  string          `json:"ignoredPlugin"`
    Reason         string          `json:"reason"`
}

type ResourceIdentity struct {
    APIVersion string `json:"apiVersion"`
    Kind       string `json:"kind"`
    Name       string `json:"name"`
    Namespace  string `json:"namespace,omitempty"`
}

func GenerateWhiteoutReport(whiteouts []WhiteoutReport) ([]byte, error)
func GenerateIgnoredPatchReport(ignored []IgnoredPatchReport) ([]byte, error)
func SortWhiteouts(whiteouts []WhiteoutReport)
func SortIgnoredPatches(reports []IgnoredPatchReport)
```

**Tests**:
- [ ] Test report serialization to JSON
- [ ] Test deterministic sorting
- [ ] Test empty report handling

**Acceptance**:
- [ ] Reports serialize to valid JSON
- [ ] Sorting is deterministic
- [ ] Empty reports handled gracefully

---

### Phase 1 Deliverables
- ✅ Core data structures implemented
- ✅ Kustomize serialization working
- ✅ Resource grouping functional
- ✅ Report generation working
- ✅ All unit tests passing

---

## Phase 2: crane Transform Command (Weeks 4-6)

### Goals
- Replace JSONPatch file writer
- Implement Kustomize overlay generation
- Add dirty check mechanism

### Epic B: Transform Refactor

#### B1: Kustomization Output Writer
**Issue**: `crane: Refactor transform to emit kustomization.yaml + patches`

**Files to modify**:
- `crane/cmd/transform/transform.go`
- `crane/internal/transform/writer.go` (new)

**Implementation**:

```go
// writer.go
package transform

type KustomizeWriter struct {
    transformDir string
    stageDir     string
}

func NewKustomizeWriter(transformDir, stageName string) *KustomizeWriter

func (w *KustomizeWriter) WriteStageOutput(
    resources []Resource,
    artifacts []TransformArtifact,
    whiteouts []WhiteoutReport,
    ignored []IgnoredPatchReport,
) error {
    // 1. Create stage directory structure
    // 2. Write resources/ directory
    // 3. Write patches/ directory
    // 4. Write reports/ and whiteouts/
    // 5. Generate kustomization.yaml
    // 6. Write .crane-metadata.json
}

func (w *KustomizeWriter) WriteResources(grouped map[string][]Resource) error
func (w *KustomizeWriter) WritePatches(artifacts []TransformArtifact) error
func (w *KustomizeWriter) WriteKustomization(resources, patches []string) error
```

**Tests**:
- [ ] Test full transform output structure
- [ ] Test with various resource types
- [ ] Test with whiteouts
- [ ] Test with empty resources

**Acceptance**:
- [ ] No transform-* files created
- [ ] Valid kustomization.yaml generated
- [ ] kubectl kustomize works on output

---

#### B2: Resource Type File Generation
**Issue**: `crane: Implement resource type file generation (multi-doc YAML)`

**Files to modify**:
- `crane/internal/transform/writer.go`

**Implementation**:

```go
func (w *KustomizeWriter) WriteResourcesByType(resources []Resource) error {
    // 1. Group resources by type
    grouped := transform.GroupResourcesByType(resources)

    // 2. Filter out whiteouts
    filtered := filterWhiteouts(grouped, w.whiteouts)

    // 3. Create resources/ directory
    resourcesDir := filepath.Join(w.stageDir, "resources")
    os.MkdirAll(resourcesDir, 0755)

    // 4. Write each type to separate file
    for typeKey, typeResources := range filtered {
        filename := kustomize.GetResourceTypeFilename(typeKey)
        path := filepath.Join(resourcesDir, filename)

        if err := transform.WriteResourceTypeFile(path, typeResources); err != nil {
            return err
        }
    }

    return nil
}
```

**Tests**:
- [ ] Test multi-doc YAML creation
- [ ] Test resource type segregation
- [ ] Test whiteout filtering
- [ ] Test empty type handling

**Acceptance**:
- [ ] Each resource type in separate file
- [ ] Multi-doc YAML valid
- [ ] Whiteouts excluded

---

#### B3: Deterministic Ordering
**Issue**: `crane: Add deterministic ordering for overlay artifacts and resources`

**Files to modify**:
- `crane/internal/transform/ordering.go` (new)

**Implementation**:

```go
package transform

func SortResourceFiles(files []string) []string {
    // Lexical sort by filename
    sort.Strings(files)
    return files
}

func SortPatchFiles(patches []string) []string {
    // Lexical sort by filename
    sort.Strings(patches)
    return patches
}

func PreserveCreationOrder(resources []Resource) []Resource {
    // Resources already in discovery order - no sorting
    return resources
}
```

**Tests**:
- [ ] Test file list sorting
- [ ] Test patch list sorting
- [ ] Test resource order preservation

**Acceptance**:
- [ ] Output deterministic across runs
- [ ] Git diffs stable

---

#### B4: Dirty Check Implementation
**Issue**: `crane: Implement dirty check with SHA256 hashing`

**Files to create**:
- `crane/internal/transform/metadata.go`
- `crane/internal/transform/dirtycheck.go`

**Implementation**:

```go
// metadata.go
type Metadata struct {
    CreatedAt      time.Time         `json:"createdAt"`
    CreatedBy      string            `json:"createdBy"`
    Plugin         string            `json:"plugin"`
    PluginVersion  string            `json:"pluginVersion,omitempty"`
    CraneVersion   string            `json:"craneVersion"`
    ContentHashes  map[string]string `json:"contentHashes"`
}

func WriteMetadata(stageDir string, metadata Metadata) error
func ReadMetadata(stageDir string) (Metadata, error)

// dirtycheck.go
func IsDirectoryDirty(stageDir string) (bool, error) {
    metadataPath := filepath.Join(stageDir, ".crane-metadata.json")

    if !fileExists(metadataPath) {
        return false, nil // Clean (first run)
    }

    metadata := ReadMetadata(stageDir)

    // Check each file hash
    for file, expectedHash := range metadata.ContentHashes {
        currentHash := computeSHA256(filepath.Join(stageDir, file))
        if currentHash != expectedHash {
            return true, nil
        }
    }

    // Check for new files
    actualFiles := listFiles(stageDir, exclude: [".crane-metadata.json"])
    if hasNewFiles(actualFiles, metadata.ContentHashes) {
        return true, nil
    }

    return false, nil
}

func computeSHA256(path string) string {
    data, _ := os.ReadFile(path)
    hash := sha256.Sum256(data)
    return fmt.Sprintf("sha256:%x", hash)
}

func GenerateContentHashes(stageDir string) (map[string]string, error) {
    hashes := make(map[string]string)

    files := []string{
        "kustomization.yaml",
        // All files in resources/, patches/, reports/, whiteouts/
    }

    for _, file := range files {
        hash := computeSHA256(filepath.Join(stageDir, file))
        hashes[file] = hash
    }

    return hashes, nil
}
```

**Tests**:
- [ ] Test clean directory detection
- [ ] Test modified file detection
- [ ] Test new file detection
- [ ] Test deleted file detection
- [ ] Test hash computation

**Acceptance**:
- [ ] Dirty check accurate
- [ ] SHA256 hashes correct
- [ ] Metadata persists correctly

---

#### B5: Path Helpers Update
**Issue**: `crane: Update path helpers for new layout`

**Files to modify**:
- `crane/internal/file/file_helper.go`

**Implementation**:

```go
func GetStageDir(transformDir, stageName string) string
func GetResourcesDir(stageDir string) string
func GetPatchesDir(stageDir string) string
func GetReportsDir(stageDir string) string
func GetWhiteoutsDir(stageDir string) string
func GetKustomizationPath(stageDir string) string
func GetMetadataPath(stageDir string) string

// Remove old helpers
// func GetTransformFilePath(...) // DELETE
```

**Tests**:
- [ ] Test all path helpers
- [ ] Test cross-platform paths

**Acceptance**:
- [ ] All paths correct
- [ ] Old helpers removed

---

### Phase 2 Deliverables
- ✅ Transform generates Kustomize overlays
- ✅ Resources grouped by type
- ✅ Dirty check functional
- ✅ Deterministic output
- ✅ All integration tests passing

---

## Phase 3: crane Apply Command (Weeks 7-8)

### Goals
- Replace JSONPatch applier
- Delegate to kubectl kustomize
- Add preflight validation

### Epic C: Apply Refactor

#### C1: kubectl kustomize Integration
**Issue**: `crane: Refactor apply to kubectl kustomize only`

**Files to modify**:
- `crane/cmd/apply/apply.go`
- `crane/internal/apply/renderer.go` (new)

**Implementation**:

```go
// renderer.go
package apply

type KustomizeRenderer struct {
    kubectlPath string
    flags       []string
}

func NewKustomizeRenderer(flags []string) (*KustomizeRenderer, error) {
    kubectlPath, err := exec.LookPath("kubectl")
    if err != nil {
        return nil, fmt.Errorf("kubectl not found in PATH")
    }

    return &KustomizeRenderer{
        kubectlPath: kubectlPath,
        flags:       flags,
    }, nil
}

func (r *KustomizeRenderer) RenderStage(stageDir string) ([]byte, error) {
    args := []string{"kustomize", stageDir}
    args = append(args, r.flags...)

    cmd := exec.Command(r.kubectlPath, args...)

    var stdout, stderr bytes.Buffer
    cmd.Stdout = &stdout
    cmd.Stderr = &stderr

    if err := cmd.Run(); err != nil {
        return nil, fmt.Errorf("kubectl kustomize failed: %w\n%s", err, stderr.String())
    }

    return stdout.Bytes(), nil
}

func (r *KustomizeRenderer) RenderPipeline(stages []string) ([]byte, error) {
    // For multi-stage: render each stage sequentially
    // Return output from last stage

    var finalOutput []byte

    for _, stageDir := range stages {
        output, err := r.RenderStage(stageDir)
        if err != nil {
            return nil, fmt.Errorf("stage %s: %w", stageDir, err)
        }
        finalOutput = output
    }

    return finalOutput, nil
}
```

**Tests**:
- [ ] Test single stage rendering
- [ ] Test multi-stage pipeline
- [ ] Test error handling
- [ ] Test flag passthrough

**Acceptance**:
- [ ] kubectl kustomize executes correctly
- [ ] Errors propagate clearly
- [ ] Flags work

---

#### C2: Output Handling
**Issue**: `crane: Add apply output behavior (stdout / file)`

**Files to modify**:
- `crane/cmd/apply/apply.go`

**Implementation**:

```go
func (o *ApplyOptions) Run() error {
    renderer := NewKustomizeRenderer(o.KustomizeFlags)

    // Discover or select stages
    stages := discoverStages(o.TransformDir)
    stages = filterStages(stages, o.StageSelectors)

    // Render
    output, err := renderer.RenderPipeline(stages)
    if err != nil {
        return err
    }

    // Output
    if o.OutputDir != "" {
        outputPath := filepath.Join(o.OutputDir, "all.yaml")
        return os.WriteFile(outputPath, output, 0644)
    } else {
        fmt.Print(string(output))
        return nil
    }
}
```

**Tests**:
- [ ] Test stdout output
- [ ] Test file output
- [ ] Test output directory creation

**Acceptance**:
- [ ] Output written correctly
- [ ] STDOUT vs file works

---

#### C3: Preflight Validation
**Issue**: `crane: Add apply preflight checks and output behavior`

**Files to create**:
- `crane/internal/apply/preflight.go`

**Implementation**:

```go
package apply

func ValidatePreflight(transformDir string, stages []string) error {
    // Check kubectl exists
    if _, err := exec.LookPath("kubectl"); err != nil {
        return fmt.Errorf("kubectl not found: please install kubectl")
    }

    // Check each stage
    for _, stageDir := range stages {
        if err := validateStage(stageDir); err != nil {
            return fmt.Errorf("stage %s: %w", stageDir, err)
        }
    }

    return nil
}

func validateStage(stageDir string) error {
    // Check kustomization.yaml exists
    kustomizationPath := filepath.Join(stageDir, "kustomization.yaml")
    if !fileExists(kustomizationPath) {
        return fmt.Errorf("kustomization.yaml not found")
    }

    // Check resources/ directory exists (if stage > 1)
    // (implementation depends on stage detection logic)

    return nil
}
```

**Tests**:
- [ ] Test kubectl detection
- [ ] Test missing kustomization.yaml
- [ ] Test invalid stage directory

**Acceptance**:
- [ ] Preflight checks pass/fail correctly
- [ ] Error messages actionable

---

### Phase 3 Deliverables
- ✅ Apply uses kubectl kustomize only
- ✅ Output handling works
- ✅ Preflight validation functional
- ✅ All integration tests passing

---

## Phase 4: Compatibility & Testing (Weeks 9-10)

### Goals
- Verify existing plugin compatibility
- Add edge-case regression tests
- Performance testing

### Epic D: Compatibility

#### D1: Plugin Compatibility
**Issue**: `crane+crane-lib: Add plugin compatibility fixture suite`

**Tasks**:
- [ ] Create fixture for each first-party plugin
- [ ] Test KubernetesPlugin output
- [ ] Test OpenShiftPlugin output (if exists)
- [ ] Test ImageStreamPlugin output (if exists)
- [ ] Verify patch conversion accuracy
- [ ] Compare rendered outputs (old vs new)

**Tests to add**:
```
crane/test-data/kustomize-transform/compatibility/
  kubernetes-plugin/
    export/
    expected-transform/
    expected-apply.yaml
  openshift-plugin/
    export/
    expected-transform/
    expected-apply.yaml
```

**Acceptance**:
- [ ] All first-party plugins work
- [ ] No behavior regressions

---

#### D2: Edge Cases
**Issue**: `crane+crane-lib: Add edge-case regression tests`

**Test scenarios**:
- [ ] Remove operation on missing path
- [ ] Array index operations
- [ ] Multiple patches on same path (conflict resolution)
- [ ] Whiteout with pending patches
- [ ] Empty namespace handling
- [ ] Cluster-scoped resources
- [ ] Resources with same name in different namespaces
- [ ] Very long resource names (filename truncation)
- [ ] Special characters in names
- [ ] Mixed API versions of same kind

**Acceptance**:
- [ ] All edge cases covered
- [ ] Regression suite passes

---

### Phase 4 Deliverables
- ✅ Plugin compatibility verified
- ✅ Edge-case regression suite
- ✅ Performance benchmarks
- ✅ All tests green

---

## Phase 5: Documentation & Rollout (Week 11)

### Goals
- Update user documentation
- Publish migration guide
- Create plugin author guide

### Epic E: Documentation

#### E1: User Documentation
**Issue**: `docs: Update usage docs and migration notes`

**Files to update**:
- `crane/README.md`
- `crane/docs/transform.md`
- `crane/docs/apply.md`
- `crane/docs/MIGRATION.md` (new)

**Content**:
- [ ] New transform output structure
- [ ] Kustomization.yaml format
- [ ] How to inspect stage outputs
- [ ] Breaking changes summary
- [ ] Migration from old workflow

**Acceptance**:
- [ ] Documentation complete
- [ ] Examples up to date

---

#### E2: Plugin Author Guide
**Issue**: `docs: Publish plugin-author migration notes`

**Files to create**:
- `crane/docs/PLUGIN_COMPATIBILITY.md`

**Content**:
- [ ] Plugin contract unchanged
- [ ] How plugins work with new transform
- [ ] Known behavior differences
- [ ] Testing plugin compatibility

**Acceptance**:
- [ ] Plugin authors can validate compatibility
- [ ] Migration path clear

---

### Phase 5 Deliverables
- ✅ User docs updated
- ✅ Migration guide published
- ✅ Plugin guide available

---

## Phase 6 (Optional): Multi-Stage Pipeline (Weeks 12-14)

### Goals
- Add stage discovery
- Add stage-aware CLI flags
- Add stage orchestration

### Epic F: Multi-Stage Pipeline

#### F1: Stage Discovery
**Issue**: `crane: Add stage discovery mechanism (directory scan)`

**Implementation**:

```go
// crane/internal/transform/stages.go
package transform

type Stage struct {
    Priority   int
    PluginName string
    DirName    string
    Path       string
}

func DiscoverStages(transformDir string) ([]Stage, error) {
    pattern := regexp.MustCompile(`^([0-9]+)_([a-zA-Z0-9_-]+)$`)

    dirs, err := os.ReadDir(transformDir)
    if err != nil {
        return nil, err
    }

    var stages []Stage
    for _, dir := range dirs {
        if !dir.IsDir() {
            continue
        }

        matches := pattern.FindStringSubmatch(dir.Name())
        if matches == nil {
            continue
        }

        priority, _ := strconv.Atoi(matches[1])
        plugin := matches[2]

        stages = append(stages, Stage{
            Priority:   priority,
            PluginName: plugin,
            DirName:    dir.Name(),
            Path:       filepath.Join(transformDir, dir.Name()),
        })
    }

    // Sort by priority
    sort.Slice(stages, func(i, j int) bool {
        return stages[i].Priority < stages[j].Priority
    })

    return stages, nil
}
```

**Tests**:
- [ ] Test stage discovery
- [ ] Test priority sorting
- [ ] Test invalid directory names
- [ ] Test custom stages mixed with plugin stages

**Acceptance**:
- [ ] Stages discovered correctly
- [ ] Sorted by priority

---

#### F2: Per-Stage Transform
**Issue**: `crane: Add stage execution orchestration logic`

**Implementation**:

```go
func (o *TransformOptions) RunMultiStage() error {
    // Get plugin priorities
    priorities := o.getPluginPriorities()

    // For each plugin in order
    for priority, plugin := range priorities {
        stageName := fmt.Sprintf("%d_%s", priority, plugin.Name)
        stageDir := filepath.Join(o.TransformDir, stageName)

        // Check dirty
        if isDirty(stageDir) && !o.Force {
            return fmt.Errorf("stage %s is dirty", stageName)
        }

        // Get input source
        var inputPath string
        if priority == firstPriority {
            inputPath = o.ExportDir
        } else {
            prevStage := getPreviousStage(priority, priorities)
            inputPath = filepath.Join(o.TransformDir, prevStage, "resources")
        }

        // Validate input
        if err := validateInput(inputPath); err != nil {
            return err
        }

        // Run plugin
        resources, err := readResourcesFrom(inputPath)
        if err != nil {
            return err
        }

        artifacts, err := runPlugin(plugin, resources)
        if err != nil {
            return err
        }

        // Write output
        writer := NewKustomizeWriter(o.TransformDir, stageName)
        if err := writer.WriteStageOutput(artifacts); err != nil {
            return err
        }
    }

    return nil
}
```

**Tests**:
- [ ] Test single-stage execution
- [ ] Test multi-stage execution
- [ ] Test stage chaining
- [ ] Test dirty check integration

**Acceptance**:
- [ ] Stages execute in order
- [ ] Each stage reads from previous
- [ ] Dirty check prevents overwrites

---

#### F3: Stage-Aware CLI Flags
**Issue**: `crane: Add stage-aware CLI flags for transform/apply`

**Implementation**:

```go
// Add flags to TransformOptions
type TransformOptions struct {
    // Existing...

    // Stage selection
    ListStages  bool
    Stage       string
    FromStage   string
    ToStage     string
    Stages      []string
}

func (o *TransformOptions) AddFlags(cmd *cobra.Command) {
    // Existing flags...

    cmd.Flags().BoolVar(&o.ListStages, "list-stages", false, "List discovered stages and exit")
    cmd.Flags().StringVar(&o.Stage, "stage", "", "Transform only this stage")
    cmd.Flags().StringVar(&o.FromStage, "from-stage", "", "Transform from this stage to end")
    cmd.Flags().StringVar(&o.ToStage, "to-stage", "", "Transform from start to this stage")
    cmd.Flags().StringSliceVar(&o.Stages, "stages", nil, "Transform only these stages")
}

func (o *TransformOptions) selectStages(allStages []Stage) []Stage {
    // Implement selection logic based on flags
}
```

**Tests**:
- [ ] Test --list-stages
- [ ] Test --stage selector
- [ ] Test --from-stage / --to-stage
- [ ] Test --stages list
- [ ] Test selector precedence

**Acceptance**:
- [ ] All selectors work
- [ ] Help text clear

---

#### F4: Plugin Priority Auto-Assignment
**Issue**: `crane: Add plugin priority auto-assignment algorithm`

**Implementation**:

```go
func assignPluginPriorities(plugins []Plugin) map[int]Plugin {
    priorities := make(map[int]Plugin)

    // Find KubernetesPlugin
    var kubePlugin Plugin
    var otherPlugins []Plugin

    for _, p := range plugins {
        if p.Name == "KubernetesPlugin" {
            kubePlugin = p
        } else {
            otherPlugins = append(otherPlugins, p)
        }
    }

    // Assign Kubernetes priority 10
    if kubePlugin.Name != "" {
        priorities[10] = kubePlugin
    }

    // Sort others alphabetically
    sort.Slice(otherPlugins, func(i, j int) bool {
        return otherPlugins[i].Name < otherPlugins[j].Name
    })

    // Assign priorities starting at 20, step 10
    priority := 20
    for _, p := range otherPlugins {
        priorities[priority] = p
        priority += 10
    }

    return priorities
}
```

**Tests**:
- [ ] Test with KubernetesPlugin
- [ ] Test without KubernetesPlugin
- [ ] Test alphabetical ordering
- [ ] Test priority gaps

**Acceptance**:
- [ ] Priorities assigned correctly
- [ ] KubernetesPlugin always first
- [ ] Gaps allow custom stages

---

### Phase 6 Deliverables
- ✅ Stage discovery working
- ✅ Multi-stage transform functional
- ✅ Stage selectors implemented
- ✅ Auto-priority assignment working
- ✅ Full pipeline tests passing

---

## Testing Strategy

### Unit Tests
- All new packages have >80% coverage
- Test files colocated: `file_test.go`
- Use table-driven tests where applicable

### Integration Tests
- Fixtures in `crane/test-data/kustomize-transform/`
- Golden file testing for output validation
- End-to-end scenarios:
  - Simple transform (single plugin)
  - Complex transform (multiple plugins)
  - Multi-stage pipeline
  - Error scenarios

### Regression Tests
- Edge cases documented in issue D2
- Must pass before merge

### Performance Tests
- Benchmark transform with large exports (1000+ resources)
- Target: <5s for typical migration (100 resources)

---

## Risk Management

### High-Risk Areas

1. **Plugin Compatibility**
   - Mitigation: Extensive fixture testing in Phase 4
   - Rollback plan: Feature flag to enable/disable new workflow

2. **Kustomize Behavior Differences**
   - Mitigation: Document known differences
   - Acceptance: Semantic equivalence, not byte-for-byte

3. **Performance Regression**
   - Mitigation: Benchmark tests
   - Target: No worse than 2x slowdown vs current

### Rollback Strategy
- Feature branch allows easy rollback
- No changes to crane-lib plugin contract
- If critical issues found: disable new workflow, revert CLI

---

## Success Criteria

### Functional
- [ ] All acceptance criteria met
- [ ] All tests passing (unit + integration + regression)
- [ ] Plugin compatibility verified
- [ ] Documentation complete

### Performance
- [ ] Transform completes in reasonable time (<10s for 100 resources)
- [ ] Apply completes in reasonable time

### User Experience
- [ ] Clear error messages
- [ ] Migration guide helps users transition
- [ ] Examples work out of the box

---

## Post-Implementation

### Monitoring
- Track adoption metrics (if telemetry available)
- Monitor issue tracker for bug reports
- Collect user feedback

### Future Enhancements
- Stage visualization tool
- Interactive stage debugging
- Performance optimizations (caching, parallelization)
- Advanced stage selection (regex patterns, tags)

---

## Appendix: Dependencies

### External Dependencies
- kubectl (runtime dependency for apply)
- Go 1.21+ (for development)

### Internal Dependencies
- crane-lib (transform logic)
- crane (CLI)

### Testing Dependencies
- github.com/stretchr/testify
- sigs.k8s.io/yaml
- k8s.io/apimachinery

---

## Appendix: Team Assignments (Example)

**Phase 1: crane-lib** → Team A (2 engineers)
**Phase 2: crane transform** → Team B (2 engineers)
**Phase 3: crane apply** → Team B (2 engineers)
**Phase 4: Testing** → Team A + B (all hands)
**Phase 5: Documentation** → Tech writer + 1 engineer
**Phase 6: Multi-stage** → Team A (2 engineers, optional)

---

## Timeline Summary

| Phase | Duration | Dependencies | Deliverables |
|-------|----------|--------------|--------------|
| 0: Prep | 1 week | None | Feature branch, fixtures |
| 1: crane-lib | 2 weeks | Phase 0 | Core data structures |
| 2: crane transform | 3 weeks | Phase 1 | Kustomize output |
| 3: crane apply | 2 weeks | Phase 2 | kubectl integration |
| 4: Testing | 2 weeks | Phase 3 | Compatibility suite |
| 5: Docs | 1 week | Phase 4 | User documentation |
| 6: Multi-stage (opt) | 3 weeks | Phase 5 | Stage pipeline |

**Total: 11 weeks (core) + 3 weeks (optional) = 14 weeks**

---

## Sign-off

- [ ] Engineering Lead Review
- [ ] Product Manager Approval
- [ ] Security Review (if applicable)
- [ ] Ready for Implementation

**Date**: _____________
**Signed**: _____________
