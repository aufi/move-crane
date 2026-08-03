# Knowledge Base: BuildConfig → Shipwright Conversion

Reference document for implementing the BuildConfig-to-Shipwright crane transform plugin.
Covers both APIs in detail, existing PoC analysis, and gap assessment.

---

## 1. OpenShift BuildConfig API

**API Group:** `build.openshift.io/v1`  
**Source code:** [openshift/api — build/v1/types.go](https://github.com/openshift/api/blob/master/build/v1/types.go) (~1500 lines)  
**Go import:** `github.com/openshift/api/build/v1`

**Documentation:**
- [OKD API Reference (latest)](https://docs.okd.io/latest/rest_api/workloads_apis/buildconfig-build-openshift-io-v1.html)
- [OCP Build Strategies Guide (4.16)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.16/html/builds_using_buildconfig/build-strategies)

### 1.1 BuildConfigSpec — Complete Field Inventory

`BuildConfigSpec` embeds `CommonSpec` inline. Fields marked with → are in `CommonSpec`.

#### Source fields (→ `CommonSpec.Source` — type `BuildSource`)

| Field | Type | Description |
|-------|------|-------------|
| `source.type` | `BuildSourceType` | `Git`, `Dockerfile`, `Binary`, `Images`, `None` |
| `source.git.uri` | `string` | Git repository URL |
| `source.git.ref` | `string` | Branch, tag, or commit |
| `source.git.httpProxy` | `string` | HTTP proxy for Git clone |
| `source.git.httpsProxy` | `string` | HTTPS proxy for Git clone |
| `source.git.noProxy` | `string` | No-proxy hosts |
| `source.contextDir` | `string` | Subdirectory within source |
| `source.sourceSecret` | `*LocalObjectReference` | Secret for source authentication |
| `source.dockerfile` | `*string` | Inline Dockerfile content |
| `source.binary.asFile` | `string` | Binary source filename |
| `source.images[]` | `[]ImageSource` | Image-based source inputs |
| `source.images[].from` | `ObjectReference` | Source image reference |
| `source.images[].as` | `[]string` | Multi-stage FROM aliases |
| `source.images[].paths[]` | `[]ImageSourcePath` | Files to copy (sourcePath → destinationDir) |
| `source.secrets[]` | `[]SecretBuildSource` | Secrets mounted into build (name + destinationDir) |
| `source.configMaps[]` | `[]ConfigMapBuildSource` | ConfigMaps mounted into build (name + destinationDir) |

#### Strategy fields (→ `CommonSpec.Strategy` — type `BuildStrategy`)

| Field | Type | Description |
|-------|------|-------------|
| `strategy.type` | `BuildStrategyType` | `Docker`, `Source`, `Custom`, `JenkinsPipeline` |

**Docker strategy** (`strategy.dockerStrategy` — type `DockerBuildStrategy`):

| Field | Type | Description |
|-------|------|-------------|
| `from` | `*ObjectReference` | Base image (optional, pointer — can be ISTag, ISImage, DockerImage) |
| `pullSecret` | `*LocalObjectReference` | Pull secret for base image |
| `noCache` | `*bool` | Disable Docker layer cache |
| `env` | `[]EnvVar` | Environment variables |
| `forcePull` | `bool` | Always pull base image |
| `dockerfilePath` | `string` | Path to Dockerfile in source |
| `buildArgs` | `[]EnvVar` | Docker ARG values |
| `imageOptimizationPolicy` | `*ImageOptimizationPolicy` | `None`, `SkipLayers`, `SkipLayersAndWarn` |
| `volumes` | `[]BuildVolume` | Build-time volumes |

**Source (S2I) strategy** (`strategy.sourceStrategy` — type `SourceBuildStrategy`):

| Field | Type | Description |
|-------|------|-------------|
| `from` | `ObjectReference` | Builder image (**required**, value type — not pointer) |
| `pullSecret` | `*LocalObjectReference` | Pull secret for builder image |
| `env` | `[]EnvVar` | Environment variables |
| `scripts` | `string` | Custom S2I scripts URL |
| `incremental` | `*bool` | Enable incremental builds |
| `forcePull` | `bool` | Always pull builder image |
| `volumes` | `[]BuildVolume` | Build-time volumes |

**Custom strategy** (`strategy.customStrategy` — type `CustomBuildStrategy`):

| Field | Type | Description |
|-------|------|-------------|
| `from` | `ObjectReference` | Custom builder image (**required**, value type) |
| `pullSecret` | `*LocalObjectReference` | Pull secret |
| `env` | `[]EnvVar` | Environment variables |
| `exposeDockerSocket` | `bool` | Expose Docker socket to builder |
| `forcePull` | `bool` | Always pull builder image |
| `secrets[]` | `[]SecretSpec` | Secrets mounted at mountPath |
| `buildAPIVersion` | `string` | Build API version injected |

**JenkinsPipeline strategy** (`strategy.jenkinsPipelineStrategy`):

| Field | Type | Description |
|-------|------|-------------|
| `jenkinsfilePath` | `string` | Path to Jenkinsfile in source |
| `jenkinsfile` | `string` | Inline Jenkinsfile content |
| `env` | `[]EnvVar` | Environment variables |

> **Note:** JenkinsPipeline is deprecated in favor of Tekton/OpenShift Pipelines.

#### Output fields (→ `CommonSpec.Output` — type `BuildOutput`)

| Field | Type | Description |
|-------|------|-------------|
| `output.to` | `*ObjectReference` | Target image (`DockerImage` or `ImageStreamTag`) |
| `output.pushSecret` | `*LocalObjectReference` | Secret for pushing |
| `output.imageLabels` | `[]ImageLabel` | Labels applied to output image (name + value) |

#### Other CommonSpec fields

| Field | Type | Description |
|-------|------|-------------|
| `resources` | `ResourceRequirements` | CPU/memory limits for build pod |
| `postCommit` | `BuildPostCommitSpec` | Post-build test hook (command, args, script) |
| `completionDeadlineSeconds` | `*int64` | Build timeout |
| `nodeSelector` | `map[string]string` | Node scheduling |
| `mountTrueVFS` | `bool` | Mount /dev/true VFS |

#### BuildConfigSpec-only fields (not in CommonSpec)

| Field | Type | Description |
|-------|------|-------------|
| `triggers[]` | `[]BuildTriggerPolicy` | Build triggers |
| `runPolicy` | `BuildRunPolicy` | `Serial`, `Parallel`, `SerialLatestOnly` |
| `successfulBuildsHistoryLimit` | `*int32` | Retention for successful builds |
| `failedBuildsHistoryLimit` | `*int32` | Retention for failed builds |

#### Trigger types (`BuildTriggerPolicy`)

| Trigger Type | Fields | Description |
|-------------|--------|-------------|
| `GitHub` | `secret` | GitHub webhook |
| `GitLab` | `secret` | GitLab webhook |
| `Bitbucket` | `secret` | Bitbucket webhook |
| `Generic` | `secret`, `allowEnv` | Generic webhook |
| `ImageChange` | `imageChange.from`, `imageChange.paused`, `imageChange.lastTriggeredImageID` | Trigger on base image update |
| `ConfigChange` | — | Trigger on BC spec change |

> **Note:** Deprecated lowercase trigger type constants (`"github"`, `"generic"`, `"imageChange"`) still exist in the API and must be handled.

### 1.2 Key Structural Notes

- `CommonSpec` is embedded inline — `source`, `strategy`, `output` are its fields
- `From` field pointer semantics differ by strategy: **optional** `*ObjectReference` in DockerBuildStrategy, **required** value `ObjectReference` in Source/Custom strategies
- `BuildVolume` is supported only in Docker and Source strategies, not Custom
- `ImageStreamTag` / `ImageStreamImage` references in `From` and `Output.To` require resolution to concrete registry URLs

---

## 2. Shipwright Build API

**API Group:** `shipwright.io/v1beta1`  
**Source code:** [shipwright-io/build — pkg/apis/build/v1beta1/](https://github.com/shipwright-io/build/tree/main/pkg/apis/build/v1beta1)  
**Go import:** `github.com/shipwright-io/build/pkg/apis/build/v1beta1`

**Documentation:**
- [Build CR](https://shipwright.io/docs/build/)
- [BuildRun CR](https://shipwright.io/docs/build/buildrun/)
- [BuildStrategies](https://shipwright.io/docs/build/buildstrategies/)
- [Authentication](https://shipwright.io/docs/build/authentication/)
- [API Reference](https://shipwright.io/docs/ref/api/build/)

> **Note:** `https://shipwright.io/docs/build/build/` returns 404. The correct URL is `https://shipwright.io/docs/build/`.

### 2.1 BuildSpec — Complete Field Inventory

**File:** `build_types.go`

| Field | Type | JSON Tag | Description |
|-------|------|----------|-------------|
| `source` | `*Source` | `json:"source"` | Source code location |
| `trigger` | `*Trigger` | `json:"trigger,omitempty"` | Event-driven triggers |
| `strategy` | `Strategy` | `json:"strategy"` | Reference to (Cluster)BuildStrategy |
| `paramValues` | `[]ParamValue` | `json:"paramValues,omitempty"` | Parameter values for strategy |
| `output` | `Image` | `json:"output"` | Target container image |
| `timeout` | `*metav1.Duration` | `json:"timeout,omitempty"` | Max build duration (default 10m) |
| `env` | `[]corev1.EnvVar` | `json:"env,omitempty"` | Environment variables |
| `retention` | `*BuildRetention` | `json:"retention,omitempty"` | BuildRun cleanup policy |
| `volumes` | `[]BuildVolume` | `json:"volumes,omitempty"` | Override strategy volumes |
| `nodeSelector` | `map[string]string` | `json:"nodeSelector,omitempty"` | Node scheduling |
| `tolerations` | `[]corev1.Toleration` | `json:"tolerations,omitempty"` | Scheduling tolerations |
| `schedulerName` | `*string` | `json:"schedulerName,omitempty"` | Custom scheduler |
| `runtimeClassName` | `*string` | `json:"runtimeClassName,omitempty"` | Alternative container runtime |

### 2.2 Source Types

**File:** `source.go`

**Source struct:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `BuildSourceType` | `"Git"`, `"OCI"`, `"Local"` |
| `contextDir` | `*string` | Subdirectory within source |
| `git` | `*Git` | Git source config |
| `ociArtifact` | `*OCIArtifact` | OCI artifact source config |
| `local` | `*Local` | Local upload source config |

**Git struct:**

| Field | Type | Description |
|-------|------|-------------|
| `url` | `string` | Repository URL (required) |
| `revision` | `*string` | Commit SHA, tag, or branch |
| `cloneSecret` | `*string` | Secret for private repos |
| `depth` | `*int` | Clone depth (default 1, 0 = full) |

**OCIArtifact struct:**

| Field | Type | Description |
|-------|------|-------------|
| `image` | `string` | OCI image reference |
| `prune` | `*PruneOption` | `"Never"` or `"AfterPull"` |
| `pullSecret` | `*string` | Pull secret |

**Local struct:**

| Field | Type | Description |
|-------|------|-------------|
| `timeout` | `*metav1.Duration` | Upload timeout |
| `name` | `string` | Source name |

### 2.3 Strategy Reference

**File:** `buildstrategy.go`

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Strategy name |
| `kind` | `*BuildStrategyKind` | `"BuildStrategy"` or `"ClusterBuildStrategy"` |
| `stepResources` | `[]StepResourceOverride` | Override resources per step |

### 2.4 Build Output (Image)

**File:** `build_types.go`

| Field | Type | Description |
|-------|------|-------------|
| `image` | `string` | Target registry URL and tag |
| `insecure` | `*bool` | Insecure registry flag |
| `pushSecret` | `*string` | Secret for registry auth |
| `annotations` | `map[string]string` | OCI image annotations |
| `labels` | `map[string]string` | OCI image labels |
| `vulnerabilityScan` | `*VulnerabilityScanOptions` | Scan config |
| `timestamp` | `*string` | `"Zero"`, `"SourceTimestamp"`, `"BuildTimestamp"`, or epoch |
| `platforms` | `[]ImagePlatform` | Multi-platform targets |

### 2.5 ParamValue

**File:** `parameter.go`

| Field | Type | Description |
|-------|------|-------------|
| `name` | `string` | Parameter name |
| `*SingleValue` | (embedded) | For string-type params — `value`, `configMapValue`, or `secretValue` |
| `values` | `[]SingleValue` | For array-type params |

`SingleValue` can be: `value *string`, `configMapValue *ObjectKeyRef`, or `secretValue *ObjectKeyRef`.

Reserved parameter names: `BUILDER_IMAGE`, `DOCKERFILE`, `CONTEXT_DIR`, anything starting with `shp-`.

### 2.6 BuildRetention

| Field | Type | Description |
|-------|------|-------------|
| `failedLimit` | `*uint` | Max failed BuildRuns to keep |
| `succeededLimit` | `*uint` | Max succeeded BuildRuns to keep |
| `ttlAfterFailed` | `*metav1.Duration` | TTL for failed BuildRuns |
| `ttlAfterSucceeded` | `*metav1.Duration` | TTL for succeeded BuildRuns |
| `atBuildDeletion` | `*bool` | Delete BuildRuns when Build is deleted |

### 2.7 Trigger Types

**File:** `trigger.go`, `trigger_when.go`

| Field | Type | Description |
|-------|------|-------------|
| `when[]` | `[]TriggerWhen` | Trigger conditions |
| `triggerSecret` | `*string` | Secret for webhook validation |

`TriggerWhen` types: `"GitHub"` (push/pull_request events), `"Image"` (image update), `"Pipeline"` (Tekton pipeline trigger).

### 2.8 BuildRun

**File:** `buildrun_types.go`

| Field | Type | Description |
|-------|------|-------------|
| `build` | `ReferencedBuild` | Reference by name OR inline spec |
| `source` | `*BuildRunSource` | Source override (Local only) |
| `serviceAccount` | `*string` | SA for build (`.generate` to auto-create) |
| `timeout` | `*metav1.Duration` | Override Build timeout |
| `paramValues` | `[]ParamValue` | Override Build params |
| `output` | `*Image` | Override Build output |
| `env` | `[]corev1.EnvVar` | Override/add env vars |
| `retention` | `*BuildRunRetention` | Cleanup policy |
| `volumes` | `[]BuildVolume` | Override volumes |
| `nodeSelector` | `map[string]string` | Node scheduling |

### 2.9 Built-in ClusterBuildStrategies

**Strategy YAML files:** `samples/v1beta1/buildstrategy/` in [shipwright-io/build](https://github.com/shipwright-io/build)

Available strategies: `buildah`, `source-to-image`, `kaniko`, `ko`, `buildpacks-v3`, `buildpacks-v3-heroku`, `BuildKit`, `multiarch-native-buildah`

#### `buildah` Strategy Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `build-args` | array | `[]` | Dockerfile ARG values (KEY=VALUE format) |
| `registries-block` | array | `[]` | Blocked registries |
| `registries-insecure` | array | `[]` | Insecure registries |
| `registries-search` | array | `["docker.io", "quay.io"]` | Search registries for short names |
| `dockerfile` | string | `"Dockerfile"` | Path to Dockerfile |
| `storage-driver` | string | `"vfs"` | Storage driver (`overlay` or `vfs`) |
| `target` | string | `""` | Multi-stage target |

Image: `quay.io/containers/buildah:v1.43.1`

> **Note:** `buildah` does NOT have a `from` or `runtime-stage-from` parameter in the upstream strategy. The PoC maps `DockerStrategy.From` to `runtime-stage-from` but this param doesn't exist in the default strategy definition. This would need a custom strategy or a different approach.

#### `source-to-image` Strategy Parameters

**Vanilla variant:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `builder-image` | string | **(required)** | S2I builder image |

Steps: (1) `s2i build --as-dockerfile` using `quay.io/openshift-pipeline/s2i:nightly`, (2) kaniko build.

**Red Hat variant (`source-to-image-redhat`):**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `builder-image` | string | **(required)** | S2I builder image |
| `registries-block` | array | `[]` | Blocked registries |
| `registries-insecure` | array | `[]` | Insecure registries |
| `registries-search` | array | `["docker.io", "quay.io"]` | Search registries |
| `storage-driver` | string | `"vfs"` | Storage driver |

Steps: (1) `s2i build --as-dockerfile` using Red Hat S2I image, (2) buildah build.

#### Parameter Comparison Across Strategies

| Parameter | buildah | s2i (vanilla) | s2i-redhat |
|-----------|:---:|:---:|:---:|
| `dockerfile` | ✓ | — | — |
| `build-args` | ✓ | — | — |
| `target` | ✓ | — | — |
| `storage-driver` | ✓ | — | ✓ |
| `registries-block` | ✓ | — | ✓ |
| `registries-insecure` | ✓ | — | ✓ |
| `registries-search` | ✓ | — | ✓ |
| `builder-image` | — | ✓ | ✓ |

---

## 3. Existing PoC Analysis: crane-lib/convert

**Location:** [migtools/crane-lib — convert/](https://github.com/migtools/crane-lib/tree/main/convert)  
**Files:** `convert.go`, `buildconfigs.go` (~1026 lines), `buildconfigs_test.go` (~2150 lines), `rfe.go`

### 3.1 Architecture

```
ConvertOptions.Convert()          # Dispatcher (convert.go)
  └→ convertBuildConfigs()        # Main orchestrator (buildconfigs.go)
       ├→ Strategy dispatch: Docker or Source
       ├→ processSource()         # Source fields mapping
       ├→ processOutput()         # Output fields mapping
       ├→ addRegistries()         # Registry config params
       ├→ writeBuild()            # Write Shipwright Build YAML to disk
       └→ writeServiceAccount()   # Write SA if pull secrets present
```

### 3.2 What the PoC Handles

**Docker strategy mapping:**

| BuildConfig Field | Shipwright Mapping | Function |
|-------------------|--------------------|----------|
| `dockerStrategy.from` | `paramValues: runtime-stage-from` | `processDockerStrategyFromField()` |
| `dockerStrategy.pullSecret` | Validated + SA generated | `getPullSecret()`, `validatePullSecret()`, `generateServiceAccountForPullSecret()` |
| `dockerStrategy.noCache` | `paramValues: no-cache = "true"` | `processDockerStrategyNoCache()` |
| `dockerStrategy.env` | `build.spec.env` | Inline copy |
| `dockerStrategy.forcePull` | `paramValues: pull = "always"` | `processDockerStrategyForcePull()` |
| `dockerStrategy.dockerfilePath` | `paramValues: dockerfile` | Inline |
| `dockerStrategy.buildArgs` | `paramValues: build-args` (multi-value) | `processBuildArgs()` |
| `dockerStrategy.imageOptimizationPolicy` | `paramValues: squash = "true"` | `processDockerStrategySquash()` |
| `dockerStrategy.volumes` | Warning with RFE link | Not converted |

**S2I strategy mapping:**

| BuildConfig Field | Shipwright Mapping | Function |
|-------------------|--------------------|----------|
| `sourceStrategy.from` | `paramValues: builder-image` | `processStrategyFromField()` |
| `sourceStrategy.pullSecret` | Validated + SA generated | Same as Docker |
| `sourceStrategy.env` | `build.spec.env` | Inline copy |
| `sourceStrategy.scripts` | Warning (RFE BUILD-1641) | Not converted |
| `sourceStrategy.incremental` | Warning (RFE BUILD-1607) | Not converted |
| `sourceStrategy.forcePull` | Warning (RFE BUILD-1606) | Not converted |
| `sourceStrategy.volumes` | Warning (RFE BUILD-1747) | Not converted |

**Source processing:**

| BuildConfig Source | Shipwright Mapping | Notes |
|--------------------|--------------------|-------|
| `git` | `source.type: Git`, `git.url` + `revision` | Full support |
| `git.httpProxy/httpsProxy/noProxy` | `env: HTTP_PROXY, HTTPS_PROXY, NO_PROXY` | Via `processGitProxyConfig()` |
| `sourceSecret` | `source.git.cloneSecret` | Direct |
| `contextDir` | `source.contextDir` | Direct |
| `binary` | `source.type: Local` | Maps to `shp build upload` |
| `images[0]` | `source.type: OCIArtifact` | Single image only |
| `dockerfile` (inline) | Error logged | Not supported |
| `configMaps` | Warning (RFE BUILD-1745) | Not converted |
| `secrets` | Warning (RFE BUILD-1744) | Not converted |

**Output processing:**

| BuildConfig Output | Shipwright Mapping |
|--------------------|--------------------|
| `output.to` (DockerImage) | `output.image` (direct passthrough) |
| `output.to` (ImageStreamTag) | Hardcoded `image-registry.openshift-image-registry.svc:5000/{ns}/{name}` |
| `output.pushSecret` | `output.pushSecret` |

**ImageStream resolution** (requires live cluster):

| Reference Kind | Resolution Method | Function |
|----------------|-------------------|----------|
| `ImageStreamTag` | Fetch ISTag, extract `Tag.From.Name` | `resolveImageStreamRef()` |
| `ImageStreamImage` | Fetch ISImage, extract `Image.DockerImageReference` | `resolveImageStreamImageRef()` |
| `DockerImage` | Direct passthrough | — |

### 3.3 Bugs Found in PoC

1. **`addRegistries()` bug:** InsecureRegistries processing uses `t.BlockRegistries` instead of `t.InsecureRegistries`:
   ```go
   // Line ~797 in buildconfigs.go
   if len(t.InsecureRegistries) != 0 {
       values := parseRegistries(t.BlockRegistries)  // BUG: should be t.InsecureRegistries
   ```

2. **`Convert()` uses `log.Fatal`** for unknown resource types instead of returning an error — kills the process.

3. **`processOutput()` nil dereference:** No nil check on `bc.Spec.Output.To` — panics on BuildConfigs with no output defined.

### 3.4 Dead Code

`processStrategyVolumes()` and `processSourceStrategyVolumes()` are defined and tested but **never called** from the main `convertBuildConfigs()` flow. The main flow only logs warnings about volumes.

### 3.5 Test Coverage

~20 test functions with ~58 subtests. Good coverage of individual mapping functions.

**Not tested:**
- Full `convertBuildConfigs()` end-to-end flow
- `processGitProxyConfig()`
- `processBuildSourceFromField()` (image source From)
- Binary source path
- `Convert()` dispatcher
- Error paths in file writing

### 3.6 RFE Tracking Constants

| Constant | RFE | Shipwright Gap |
|----------|-----|----------------|
| `ConfigMapsRFE` | BUILD-1745 | ConfigMaps in build env |
| `SecretsRFE` | BUILD-1744 | Secrets in build env |
| `DockerStrategyVolumesRFE` | BUILD-1747 | Volumes in buildah |
| `CustomScriptsRFE` | BUILD-1641 | Custom S2I scripts |
| `IncrementalBuildRFE` | BUILD-1607 | Incremental S2I builds |
| `ForcePullFlagS2iRFE` | BUILD-1606 | ForcePull in S2I |
| `PullSecretS2IRFE` | BUILD-1749 | PullSecret in S2I |

---

## 4. Gap Analysis: PoC vs. Complete Conversion

### 4.1 BuildConfig Fields NOT Handled by PoC

| BuildConfig Field | Shipwright Equivalent | Difficulty | Notes |
|-------------------|----------------------|------------|-------|
| `spec.triggers[]` | `spec.trigger` | Medium | Webhook mapping possible (GitHub→GitHub), ImageChange→Image trigger. ConfigChange has no equivalent. |
| `spec.runPolicy` | — | N/A | No Shipwright equivalent (Serial/Parallel/SerialLatestOnly) |
| `spec.successfulBuildsHistoryLimit` | `spec.retention.succeededLimit` | Easy | Direct mapping |
| `spec.failedBuildsHistoryLimit` | `spec.retention.failedLimit` | Easy | Direct mapping |
| `spec.resources` | `spec.strategy.stepResources` | Medium | Resource limits per step, not per build |
| `spec.completionDeadlineSeconds` | `spec.timeout` | Easy | Convert seconds → `metav1.Duration` |
| `spec.nodeSelector` | `spec.nodeSelector` | Easy | Direct mapping |
| `spec.postCommit` | — | N/A | No Shipwright equivalent |
| `spec.mountTrueVFS` | — | N/A | No Shipwright equivalent |
| `output.imageLabels` | `output.labels` | Easy | Direct mapping |
| Custom strategy | — | N/A | No automatic conversion possible |
| JenkinsPipeline strategy | — | N/A | Deprecated, out of scope |

### 4.2 PoC-Specific Issues to Fix in Plugin

| Issue | Impact | Fix |
|-------|--------|-----|
| Live cluster required for ImageStream resolution | Violates offline principle | Use layered approach: `--registry-mapping` flag → co-exported IS data → fallback with warning |
| Hardcoded internal registry URL | Wrong for non-OpenShift targets | Make configurable, emit warning |
| `runtime-stage-from` param used for Docker base image | This param doesn't exist in upstream buildah strategy | Use `from` param or document custom strategy requirement |
| `no-cache` param | Not in upstream buildah strategy | Verify or use `--layers=false` buildah arg |
| `pull` param for ForcePull | Not in upstream buildah strategy | Verify or use buildah CLI arg |
| `squash` param | Not in upstream buildah strategy | Verify or use `--squash` buildah arg |
| File I/O writes to `ExportDir` | Plugin should use stdin/stdout only | Redesign for plugin architecture (PluginResponse) |
| Uses `client.Client` for K8s API calls | Plugin runs offline | Remove all client usage, use flag-based input |

### 4.3 Enhancement Proposal vs. PoC Coverage

| Feature | PoC | Enhancement Proposal |
|---------|:---:|:-------------------:|
| Docker strategy | ✓ | ✓ |
| S2I strategy | ✓ | ✓ |
| Custom strategy | ✗ (ignored) | Warning + passthrough |
| JenkinsPipeline | ✗ (ignored) | Warning + passthrough (out of scope) |
| Git source | ✓ | ✓ |
| Binary source | ✓ | ✓ |
| Image source | ✓ (partial) | ✓ (single image) |
| Inline Dockerfile | Error | Warning |
| ImageStream resolution (live) | ✓ | ✗ (offline only) |
| ImageStream resolution (exported data) | ✗ | ✓ |
| Registry mapping flag | ✗ | ✓ |
| Strategy name override | ✗ | ✓ (`--strategy-mapping`) |
| Trigger conversion | ✗ | ✗ (non-goal) |
| Retention mapping | ✗ | ✗ (not mentioned) |
| Timeout mapping | ✗ | ✗ (not mentioned) |
| NodeSelector mapping | ✗ | ✗ (not mentioned) |
| Resource limits mapping | ✗ | ✗ (not mentioned) |
| Output image labels | ✗ | ✗ (not mentioned) |
| Whiteout original BC | ✗ (writes to new dir) | ✓ |
| Plugin architecture (stdin/stdout) | ✗ (file I/O + K8s client) | ✓ |
| Offline operation | ✗ | ✓ |

### 4.4 Easy Wins Not in Enhancement Proposal

These BuildConfig fields have direct Shipwright equivalents and could be added to the plugin with minimal effort:

1. **`completionDeadlineSeconds` → `timeout`** — simple seconds-to-Duration conversion
2. **`successfulBuildsHistoryLimit` → `retention.succeededLimit`** — direct uint mapping
3. **`failedBuildsHistoryLimit` → `retention.failedLimit`** — direct uint mapping
4. **`nodeSelector` → `nodeSelector`** — direct `map[string]string` copy
5. **`output.imageLabels` → `output.labels`** — direct label mapping

---

## 5. Source Code References

### OpenShift BuildConfig

| What | Location |
|------|----------|
| All type definitions | [openshift/api/build/v1/types.go](https://github.com/openshift/api/blob/master/build/v1/types.go) |
| BuildConfig struct | types.go — search `type BuildConfig struct` |
| CommonSpec (embedded in BuildConfigSpec) | types.go — search `type CommonSpec struct` |
| DockerBuildStrategy | types.go — search `type DockerBuildStrategy struct` |
| SourceBuildStrategy | types.go — search `type SourceBuildStrategy struct` |
| CustomBuildStrategy | types.go — search `type CustomBuildStrategy struct` |
| JenkinsPipelineBuildStrategy | types.go — search `type JenkinsPipelineBuildStrategy struct` |
| BuildSource | types.go — search `type BuildSource struct` |
| BuildOutput | types.go — search `type BuildOutput struct` |
| BuildTriggerPolicy | types.go — search `type BuildTriggerPolicy struct` |
| BuildVolume | types.go — search `type BuildVolume struct` |

### Shipwright Build

| What | Location |
|------|----------|
| Build, BuildSpec | [build_types.go](https://github.com/shipwright-io/build/blob/main/pkg/apis/build/v1beta1/build_types.go) |
| Source, Git, OCIArtifact, Local | [source.go](https://github.com/shipwright-io/build/blob/main/pkg/apis/build/v1beta1/source.go) |
| ParamValue, SingleValue | [parameter.go](https://github.com/shipwright-io/build/blob/main/pkg/apis/build/v1beta1/parameter.go) |
| Strategy reference | [buildstrategy.go](https://github.com/shipwright-io/build/blob/main/pkg/apis/build/v1beta1/buildstrategy.go) |
| BuildRun | [buildrun_types.go](https://github.com/shipwright-io/build/blob/main/pkg/apis/build/v1beta1/buildrun_types.go) |
| Trigger types | [trigger.go](https://github.com/shipwright-io/build/blob/main/pkg/apis/build/v1beta1/trigger.go), [trigger_when.go](https://github.com/shipwright-io/build/blob/main/pkg/apis/build/v1beta1/trigger_when.go) |
| BuildStrategy CRD | [buildstrategy_types.go](https://github.com/shipwright-io/build/blob/main/pkg/apis/build/v1beta1/buildstrategy_types.go) |
| ClusterBuildStrategy CRD | [clusterbuildstrategy_types.go](https://github.com/shipwright-io/build/blob/main/pkg/apis/build/v1beta1/clusterbuildstrategy_types.go) |
| Buildah strategy YAML | [samples/v1beta1/buildstrategy/buildah/](https://github.com/shipwright-io/build/tree/main/samples/v1beta1/buildstrategy/buildah) |
| S2I strategy YAML | [samples/v1beta1/buildstrategy/source-to-image/](https://github.com/shipwright-io/build/tree/main/samples/v1beta1/buildstrategy/source-to-image) |

### crane-lib PoC

| What | Location |
|------|----------|
| Dispatcher | [convert/convert.go](https://github.com/migtools/crane-lib/blob/main/convert/convert.go) |
| Conversion logic | [convert/buildconfigs.go](https://github.com/migtools/crane-lib/blob/main/convert/buildconfigs.go) |
| Tests | [convert/buildconfigs_test.go](https://github.com/migtools/crane-lib/blob/main/convert/buildconfigs_test.go) |
| RFE constants | [convert/rfe.go](https://github.com/migtools/crane-lib/blob/main/convert/rfe.go) |

### Enhancement Proposal

| What | Location |
|------|----------|
| Enhancement PR | [konveyor/enhancements#300](https://github.com/konveyor/enhancements/pull/300) |
| Enhancement document | `enhancements/crane-2.1/buildconfig-to-shipwright/README.md` |
| Local proposal (this repo) | `drafts/proposals-v0.11/BUILDCONFIG_TO_SHIPWRIGHT_PROPOSAL.md` |
