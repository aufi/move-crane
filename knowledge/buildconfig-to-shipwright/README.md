# BuildConfig → Shipwright Conversion

Knowledge base for implementing a crane transform plugin that converts OpenShift `BuildConfig` (`build.openshift.io/v1`) to Shipwright `Build` (`shipwright.io/v1beta1`).

## Context

OpenShift BuildConfig is a platform-specific CI/CD resource with no equivalent in vanilla Kubernetes. Organizations migrating from OpenShift need to convert their build definitions to a portable alternative. Shipwright (CNCF Sandbox) is a Kubernetes-native build framework and the natural successor.

## Expected Outcome

A new crane transform plugin (`crane-plugin-buildconfig-to-shipwright`) that:

- Converts BuildConfig to Shipwright Build CR offline, within the crane export → transform → apply pipeline
- Maps Docker strategy → `buildah` ClusterBuildStrategy, S2I → `source-to-image`
- Whiteouts the original BuildConfig and generates a new Shipwright Build YAML
- Resolves ImageStream references without a live cluster (layered fallthrough: explicit mapping → exported IS data → fallback)
- Produces auditable, GitOps-friendly artifacts (patches + whiteout trail)

Prerequisite: extending the crane plugin API with `NewResources` in `PluginResponse` (crane-lib).

## Files

- [api_and_poc_comparison.md](api_and_poc_comparison.md) — complete API reference for both systems, existing PoC analysis (crane-lib/convert), gap analysis
- Enhancement PR: [konveyor/enhancements#300](https://github.com/konveyor/enhancements/pull/300)
