# BuildConfig -> Shipwright using Kustomize only (Crane-style layout)

This skeleton mirrors Crane transform conventions (`export/`, `transform/`, `output/`) while using Kustomize for BuildConfig -> Shipwright mapping.

## Structure

- `export/resources/buildconfigs/`
  - source OpenShift `BuildConfig` manifests (input)
- `transform/resources/kustomize/base/`
  - reusable Shipwright templates
- `transform/resources/kustomize/overlays/ns-a/`
  - conversion mapping patches per namespace/scope
- `output/resources/`
  - reserved for rendered output artifacts
- `docs/conversion-matrix.md`
  - supported/unsupported field mapping

## Flow (aligned with Crane semantics)

1. **Export phase**
   - place exported BuildConfigs into `export/resources/buildconfigs/`
2. **Transform phase**
   - apply Kustomize overlays from `transform/resources/kustomize/overlays/...`
3. **Output phase**
   - render manifests and store bundle under `output/resources/`

## Render

```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone transform/resources/kustomize/overlays/ns-a
```

## Render to output bundle

```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone transform/resources/kustomize/overlays/ns-a > output/resources/build-bundle.yaml
```

## Validate against target

```bash
kubectl apply --dry-run=server -f output/resources/build-bundle.yaml
```

## Apply

```bash
kubectl apply -f output/resources/build-bundle.yaml
```

## Tests (inspired by `buildconfigs_test.go` mapping checks)

A lightweight shell test validates rendered Kustomize output for key conversion invariants.

```bash
./tests/run-tests.sh
```

Test file:
- `tests/run-tests.sh`

What is validated:
- strategy mapping (`Docker -> buildah`, `Source -> source-to-image`)
- source/output mapping
- parameter mapping (`dockerfile`, `builder-image`)
- source BuildConfigs marked as ignored in output

## Notes

- This approach is declarative and reviewable, but not fully automatic for all BuildConfig variants.
- Complex BuildConfig features (custom scripts, incremental mode, strategy volumes, etc.) are documented as manual/partial in `docs/conversion-matrix.md`.
