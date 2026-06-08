# BuildConfig to Shipwright Converter - File Index

## 📚 Documentation

### Quick Reference
- **[QUICK-START.md](QUICK-START.md)** - ⚡ Fast setup guide (START HERE!)
- **[README.md](README.md)** - 📖 Complete documentation
- **[samples/test-stage/TEST.md](samples/test-stage/TEST.md)** - 🧪 Testing guide

### Topic-Specific
- **[samples/test-stage/README.md](samples/test-stage/README.md)** - Runtime generation concept

## 🔧 Implementation Files

### Core Components
- **[scripts/converter.sh](scripts/converter.sh)** - Main conversion script
- **[helm-chart/buildconfig-to-shipwright/](helm-chart/buildconfig-to-shipwright/)** - Helm templates
  - `Chart.yaml` - Chart metadata
  - `values.yaml` - Default values
  - `templates/build.yaml` - Build template

### Configuration Examples
- **[samples/test-stage/kustomization.yaml](samples/test-stage/kustomization.yaml)** - Runtime generation config
- **[samples/test-stage/generator-config.yaml](samples/test-stage/generator-config.yaml)** - Generator plugin config

### Sample Data
- **[samples/buildconfig-docker.yaml](samples/buildconfig-docker.yaml)** - Docker strategy example
- **[samples/buildconfig-source.yaml](samples/buildconfig-source.yaml)** - Source strategy example

## 🎯 Quick Navigation

### I want to...

**Understand the concept**
→ Start with [QUICK-START.md](QUICK-START.md) "Key Concept" section

**See working example**
→ Look at [samples/test-stage/](samples/test-stage/)

**Test it locally**
→ Follow [samples/test-stage/TEST.md](samples/test-stage/TEST.md)

**Use in crane migration**
→ See [QUICK-START.md](QUICK-START.md) "TL;DR" section

**Understand field mappings**
→ Check [README.md](README.md) "Field Mapping" table

**Modify conversion logic**
→ Edit [helm-chart/buildconfig-to-shipwright/templates/build.yaml](helm-chart/buildconfig-to-shipwright/templates/build.yaml)

**Debug converter script**
→ Run [scripts/converter.sh](scripts/converter.sh) manually with sample

**Extend to new strategy**
→ See [README.md](README.md) "Extending the Converter" section

## 🔍 Key Concepts by File

### Runtime Generation
- **Definition:** [README.md](README.md#runtime-generation-flow)
- **Config:** [samples/test-stage/generator-config.yaml](samples/test-stage/generator-config.yaml)
- **Example:** [samples/test-stage/kustomization.yaml](samples/test-stage/kustomization.yaml)
- **Testing:** [samples/test-stage/TEST.md](samples/test-stage/TEST.md#test-3-verify-fresh-generation)

### Conversion Logic
- **Script:** [scripts/converter.sh](scripts/converter.sh)
- **Template:** [helm-chart/buildconfig-to-shipwright/templates/build.yaml](helm-chart/buildconfig-to-shipwright/templates/build.yaml)
- **Values:** [helm-chart/buildconfig-to-shipwright/values.yaml](helm-chart/buildconfig-to-shipwright/values.yaml)
- **Mappings:** [README.md](README.md#field-mapping)

### Integration
- **Crane workflow:** [QUICK-START.md](QUICK-START.md#-tldr)
- **Stage structure:** [README.md](README.md#integration-with-crane)
- **Testing:** [samples/test-stage/TEST.md](samples/test-stage/TEST.md#test-5-crane-apply-integration)

## 📊 File Types

### Executable
- `scripts/converter.sh` - Main conversion script

### Configuration
- `samples/test-stage/kustomization.yaml` - Kustomize config
- `samples/test-stage/generator-config.yaml` - Generator plugin config
- `helm-chart/buildconfig-to-shipwright/Chart.yaml` - Helm chart metadata
- `helm-chart/buildconfig-to-shipwright/values.yaml` - Helm default values

### Templates
- `helm-chart/buildconfig-to-shipwright/templates/build.yaml` - Helm template

### Sample Data
- `samples/buildconfig-docker.yaml` - Docker BuildConfig example
- `samples/buildconfig-source.yaml` - Source BuildConfig example

### Documentation
- `README.md` - Main documentation
- `QUICK-START.md` - Quick reference
- `INDEX.md` - This file
- `samples/test-stage/README.md` - Runtime generation explanation
- `samples/test-stage/TEST.md` - Testing procedures

## 🚀 Getting Started Path

1. **Read:** [QUICK-START.md](QUICK-START.md) (5 min)
2. **Understand:** [samples/test-stage/README.md](samples/test-stage/README.md) (5 min)
3. **Test:** [samples/test-stage/TEST.md](samples/test-stage/TEST.md) - Test 1 & 2 (10 min)
4. **Try:** Follow [QUICK-START.md](QUICK-START.md) TL;DR section (20 min)
5. **Deep dive:** [README.md](README.md) for complete reference

## 🔗 Related Resources

- **Scenario 06:** [../../test-day-june2026/scenario-06-buildconfig-kustomize-conversion.md](../../test-day-june2026/scenario-06-buildconfig-kustomize-conversion.md)
- **Playground README:** [../README.md](../README.md)
- **Plugin approach:** [../crane-plugin-agent-instructions.md](../crane-plugin-agent-instructions.md)

---

**Total files:** 12 (4 docs, 5 config/templates, 2 samples, 1 script)
