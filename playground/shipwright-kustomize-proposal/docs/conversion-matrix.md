# Conversion matrix: BuildConfig -> Shipwright Build (Kustomize-only)

| BuildConfig field | Shipwright mapping | Status | Notes |
|---|---|---|---|
| `metadata.name` | `Build.metadata.name` | Supported | Set in overlay patch |
| `metadata.namespace` | `Build.metadata.namespace` | Supported | Set in overlay patch |
| `spec.source.git.uri` | `Build.spec.source.git.url` | Supported | Manual mapping |
| `spec.strategy.type=Docker` | `Build.spec.strategy.name=buildah` | Supported | Manual mapping |
| `spec.strategy.type=Source` | `Build.spec.strategy.name=source-to-image` | Supported | Manual mapping |
| `spec.strategy.*.from` | `paramValues[builder-image]` | Supported (manual) | Explicitly map image ref |
| `spec.strategy.dockerStrategy.dockerfilePath` | `paramValues[dockerfile]` | Supported (manual) | Explicitly map path |
| `spec.output.to.name` | `Build.spec.output.image` | Supported (manual) | Explicitly map image output |
| `spec.output.pushSecret.name` | `Build.spec.output.pushSecret` | Supported (manual) | Optional |
| `spec.strategy.*.env` | `Build.spec.env` | Partial | Add manually in patch |
| Build args | `paramValues` | Partial | Depends on strategy params |
| NoCache | N/A | Unsupported | Requires strategy support |
| ForcePull | N/A | Unsupported | Requires strategy support |
| Incremental S2I | N/A | Unsupported | Requires strategy support |
| Custom scripts | N/A | Unsupported | Requires strategy support |
| Strategy volumes | N/A | Unsupported | Requires strategy support |

## Recommendation
Use this Kustomize-only approach for repetitive, known BuildConfig patterns.
For heterogeneous estates, combine with a pre-processing step (still Git-reviewed) or a converter tool.
