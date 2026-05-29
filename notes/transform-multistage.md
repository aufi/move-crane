# Multi-Stage Transform Pipelines

This guide covers advanced multi-stage transformation workflows, showing you when and how to use multiple stages to handle complex migration scenarios.

## What Are Multi-Stage Pipelines?

A multi-stage pipeline processes resources through a **sequence of transformation stages**, where each stage:

1. Reads the **fully materialized output** from the previous stage
2. Applies its own transformations
3. Writes output for the next stage

```
export/              Stage 1             Stage 2             Stage 3
resources/    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
              │ 10_Kubernetes   │  │ 20_Openshift    │  │ 50_CustomEdits  │
─────────────▶│ Plugin          │─▶│ Plugin          │─▶│                 │─▶ output/
              │                 │  │                 │  │                 │
              │ - Clean metadata│  │ - Convert Routes│  │ - Manual tweaks │
              └─────────────────┘  └─────────────────┘  └─────────────────┘
```

## When to Use Multi-Stage Pipelines

### Single Stage Is Sufficient When:
- ✅ Migrating between similar Kubernetes clusters
- ✅ Only need basic cleanup (remove UIDs, status, etc.)
- ✅ No platform-specific resources (OpenShift, etc.)
- ✅ No manual customization needed

### Multi-Stage Is Better When:
- ✅ Cross-platform migration (OpenShift to Kubernetes, or vice versa)
- ✅ Multiple transformation concerns (cleanup, conversion, customization)
- ✅ Need to inspect intermediate results
- ✅ Want to separate automated and manual changes
- ✅ Complex transformations that benefit from separation of concerns

## Stage Types

### Plugin-Based Stages (Auto-Regenerate)

Stage names ending with `Plugin` use a corresponding plugin:

```bash
crane transform 10_KubernetesPlugin   # Uses KubernetesPlugin
crane transform 20_OpenshiftPlugin    # Uses OpenshiftPlugin
```

**Behavior:**
- Automatically run plugin on each transform
- Always regenerate (no `--force` needed)
- Cannot manually edit (changes will be overwritten)

**Best for:**
- Automated transformations
- Repeatable processing
- Plugin-driven cleanup/conversion

### Pass-Through Stages (Manual Edit Protection)

Stage names **NOT** ending with `Plugin` create pass-through stages:

```bash
crane transform 50_CustomEdits    # No plugin - pass-through
crane transform 90_FinalTweaks    # No plugin - pass-through
```

**Behavior:**
- Resources copied unchanged from previous stage
- No patches generated automatically
- Protected from accidental overwrite (requires `--force`)
- Perfect for manual editing

**Best for:**
- Manual customizations
- Hand-crafted patches
- Environment-specific changes

## Stage Selection

Crane supports flexible stage selection using **positional arguments**:

### By Stage Directory Name
```bash
crane transform 10_KubernetesPlugin
crane transform 10_KubernetesPlugin 20_OpenshiftPlugin
```

### By Plugin Name
```bash
crane transform KubernetesPlugin
crane transform KubernetesPlugin OpenshiftPlugin
```

### By Base Name (Without Priority Prefix)
```bash
crane transform CustomEdits         # Creates or finds stage with base name "CustomEdits"
crane transform MyStage FinalTweaks # Creates multiple custom stages
```

**How base names work:**
- **Existing stage:** If a stage like `50_CustomEdits` exists, `crane transform CustomEdits` will find and use it
- **New stage:** If no matching stage exists, creates one with automatic priority (e.g., `20_CustomEdits` if max priority is 10)
- **Multiple stages:** Each new stage gets an incrementing priority (+10 for each)

**Note:** Base names only work for custom stages (non-plugin names). Plugin names must end with `Plugin`.

### Mixed Format
```bash
crane transform 10_KubernetesPlugin OpenshiftPlugin CustomEdits
```

### All Stages (Default)
```bash
crane transform    # Runs all discovered stages
```

**Key Points:**
- Stages execute in **priority order** (by numeric prefix), regardless of argument order
- Plugin names (ending with `Plugin`) are automatically resolved to stage directories
- Base names (without prefix) find existing stages or create new ones with automatic priority
- If a plugin name matches multiple stages, you must use the exact stage directory name
- Full stage names (like `50_CustomEdits`) create pass-through stages if they don't exist

## Example: Basic Two-Stage Pipeline

**Scenario:** Cleaning resources and then adding custom labels

### Step 1: Export Resources

```bash
crane export
```

### Step 2: Run Default Transformations

```bash
crane transform
```

This creates stages for all installed plugins (typically starting with KubernetesPlugin).

**Result:**
```
transform/10_KubernetesPlugin/
├── resources/          # Exported resources
├── patches/            # Auto-generated cleanup patches
└── kustomization.yaml

transform/15_OpenshiftPlugin/    # If OpenshiftPlugin is installed
├── resources/
├── patches/
└── kustomization.yaml
```

### Step 3: Create Custom Stage

You can create a custom stage using either a full stage name or a base name:

```bash
# Option 1: Use base name (automatic priority)
crane transform CustomLabels        # Creates 20_CustomLabels

# Option 2: Use full stage name (explicit priority)
crane transform 50_CustomLabels     # Creates 50_CustomLabels
```

**Result:**
```
transform/20_CustomLabels/          # Or 50_CustomLabels if you used explicit priority
├── resources/          # Copied from previous stage OUTPUT
├── patches/            # Empty - ready for manual patches
└── kustomization.yaml
```

**Important:** The `resources/` directory contains the **cleaned output** from the previous stage, not the raw export!

### Step 4: Add Custom Labels, Namespace, and Images

Edit `kustomization.yaml` to add common labels, set target namespace, and update container images:

```bash
# Adjust the path based on which option you chose in Step 3
cat >> transform/20_CustomLabels/kustomization.yaml <<EOF
namespace: migrated-app
commonLabels:
  migrated-with: crane
images:
- name: mysql:8.0
  newName: registry.redhat.io/rhel8/mysql-80
  newTag: latest
EOF
```

This demonstrates:
- **namespace**: Changes all resources to `migrated-app` namespace
- **commonLabels**: Adds `migrated-with: crane` label to all resources
- **images**: Updates MySQL container image to use [Red Hat MySQL 8.0](https://catalog.redhat.com/software/containers/rhel8/mysql-80/5ba0ad4cdd19c70b45cbf48c)

### Step 5: Apply All Stages

```bash
crane apply
```

Crane automatically applies **all stages sequentially**, producing final output.

## Sequential Consistency Deep Dive

**Critical concept:** Each stage sees the **fully applied output** of the previous stage.

### What This Means

```
Stage 1: Export → [Apply transforms] → Materialized Output
                                              ↓
Stage 2: Materialized Output → [Apply transforms] → Materialized Output
                                                            ↓
Stage 3: Materialized Output → [Apply transforms] → Final Output
```

### Example: Resource Deletion

**Stage 1:** Removes a Deployment (via whiteout)

`transform/10_KubernetesPlugin/`
- `resources/Deployment_apps_v1_default_myapp.yaml` exists
- Plugin marks it for whiteout (not in `kustomization.yaml` resources list)

**Stage 2:** Sees the materialized output from Stage 1

`transform/20_OpenshiftPlugin/`
- `resources/` directory **does not contain** the whitelisted Deployment
- Stage 2 never sees it
- Transformations cannot reference it

**Why it matters:**
- Stages don't see patches, they see results
- Deleted resources don't propagate
- Structural changes are visible to later stages

## Working Directory Structure

When running multi-stage transforms, Crane creates a `.work/` directory:

```
transform/
├── 10_KubernetesPlugin/
│   ├── resources/
│   ├── patches/
│   └── kustomization.yaml
├── 20_OpenshiftPlugin/
│   ├── resources/
│   ├── patches/
│   └── kustomization.yaml
└── .work/                      # Intermediate artifacts (debugging)
    ├── 10_KubernetesPlugin/
    │   ├── input/              # What stage 1 read (from export)
    │   └── output/             # What stage 1 produced (materialized)
    └── 20_OpenshiftPlugin/
        ├── input/              # What stage 2 read (stage 1 output)
        └── output/             # What stage 2 produced (materialized)
```

**Use `.work/` for debugging:**

```bash
# See what Stage 1 read
ls transform/.work/10_KubernetesPlugin/input/

# See what Stage 1 produced (input for Stage 2)
ls transform/.work/10_KubernetesPlugin/output/

# Compare input vs output
diff -r transform/.work/10_KubernetesPlugin/input/ \
        transform/.work/10_KubernetesPlugin/output/
```

**Note:** `.work/` is regenerated on each transform run. Add to `.gitignore`:

```gitignore
transform/.work/
```

## Running Specific Stages

### Run Single Stage

```bash
# By stage directory name
crane transform 20_OpenshiftPlugin

# By plugin name
crane transform OpenshiftPlugin

# By base name (finds existing or creates new)
crane transform CustomEdits
```

**Requirement:** Previous stages must have been run and have output available.

### Run Multiple Stages

```bash
# Run specific stages in one command
crane transform KubernetesPlugin OpenshiftPlugin

# Mix directory names, plugin names, and base names
crane transform 10_KubernetesPlugin OpenshiftPlugin CustomEdits

# Create multiple custom stages with automatic priorities
crane transform FirstEdit SecondEdit FinalTweaks
```

**Execution order:** Stages always execute in priority order (10, 20, 50...), regardless of argument order.

### Run All Stages

```bash
# Default behavior: discover and run all existing stages
crane transform
```

**Note:** Plugin stages auto-regenerate; custom stages require `--force`.

### Force Re-run Everything

```bash
crane transform --force
```

**Warning:** This overwrites custom stages, including manual edits!

### Run Stages from Instructions File

For declarative stage configuration, use an instructions file:

```bash
# Create instructions file
cat > stages.yaml <<EOF
stages:
  - KubernetesPlugin
  - OpenshiftPlugin
  - CustomEdits
EOF

# Run stages from file
crane transform --instructions-file stages.yaml
```

**Note:** `--instructions-file` and positional arguments are mutually exclusive.

## Best Practices

### 1. Stage Naming Convention

Use clear, descriptive names with priority spacing:

**Good:**
```
10_KubernetesPlugin      # Core cleanup
20_OpenshiftPlugin       # Platform conversion
30_SecurityContext       # Security policies
50_CustomLabels          # Manual labels
90_FinalTweaks           # Last-minute changes
```

**Bad:**
```
1_KubernetesPlugin       # Too close together (hard to insert new stages)
2_OpenshiftPlugin
3_Custom
```

### 2. Add Manual Stages Last

**Correct:**
```
10_KubernetesPlugin     # Plugin: cleanup
20_OpenshiftPlugin      # Plugin: convert
50_CustomEdits          # Manual: tweaks (uses output from stage 20)
```

**Problem:**
```
10_KubernetesPlugin
50_CustomEdits          # Manual stage
20_OpenshiftPlugin      # Plugin added later
```

If you later re-run `20_OpenshiftPlugin`, stage 50's `resources/` directory is now stale (has old data from stage 10, not stage 20). You'd need to run all stages or use `--force` to refresh it, **losing manual edits**.

### 3. Use Short Names for Convenience

Instead of full stage directory names, use shorter alternatives:

```bash
# Instead of this:
crane transform 10_KubernetesPlugin 20_OpenshiftPlugin 50_CustomEdits

# Use this (plugin names and base names):
crane transform KubernetesPlugin OpenshiftPlugin CustomEdits
```

**Benefits:**
- More readable
- Doesn't depend on exact priority numbers
- Base names automatically find existing stages or create new ones
- Works even if you later renumber your stages

### 4. Test Incrementally

After each stage:
```bash
# Preview output
kubectl kustomize transform/<stage-name>/

# Validate syntax
kubectl apply --dry-run=client -k transform/<stage-name>/
```

## Troubleshooting Multi-Stage Pipelines

### Issue: "Stage X requires output from stage Y, but output directory does not exist"

**Cause:** You're trying to run a stage before its predecessor has been run.

**Solution:**
```bash
# Run all stages up to the one you want
crane transform

# Or run from the first missing stage onward
crane transform KubernetesPlugin OpenshiftPlugin CustomEdits
```

### Issue: "plugin 'KubernetesPlugin' found in multiple stages"

**Cause:** Multiple stages use the same plugin (e.g., `10_KubernetesPlugin` and `20_KubernetesPlugin`).

**Solution:** Use the exact stage directory name:
```bash
crane transform 10_KubernetesPlugin
```

### Issue: Custom stage has stale data

**Cause:** Previous plugin stages were updated, but custom stage still has old data.

**Solution:**
```bash
# Re-run all stages to refresh custom stage inputs
crane transform

# Or use --force to regenerate everything
crane transform --force
```

**Warning:** `--force` will overwrite manual edits in custom stages!

### Issue: Resources missing in later stages

**Cause:** Earlier stage marked resources for whiteout (deletion).

**Solution:**
```bash
# Check what was included in earlier stage
cat transform/10_KubernetesPlugin/kustomization.yaml

# Inspect intermediate output
ls transform/.work/10_KubernetesPlugin/output/
```

## Summary

Multi-stage pipelines provide:
- ✅ **Separation of concerns** - Different transformations in different stages
- ✅ **Sequential consistency** - Each stage sees materialized output
- ✅ **Flexibility** - Mix plugin and manual stages
- ✅ **Debugging** - Inspect intermediate results in `.work/`
- ✅ **GitOps-friendly** - Standard Kustomize layouts
- ✅ **Convenient selection** - Use plugin names, base names, or full stage directory names

**Key Takeaways:**
- Use positional arguments: `crane transform KubernetesPlugin CustomEdits`
- Three naming options:
  - **Full stage name:** `50_CustomEdits` (explicit priority)
  - **Plugin name:** `KubernetesPlugin` (must end with "Plugin")
  - **Base name:** `CustomEdits` (automatic priority, finds existing or creates new)
- Plugin stages auto-regenerate (no `--force` needed)
- Custom stages are protected (require `--force`)
- Base names provide flexibility: find existing stages or create new ones automatically
- Each stage processes previous stage's **materialized output**
- Run `crane apply` to generate final manifests
- Stages execute in priority order regardless of argument order
- Always add manual stages last
- Use `.work/` directory for debugging

## Next Steps

- [**Troubleshooting**](./transform-scenarios/05-troubleshooting.md) - Common issues and solutions
- [**Transform CLI Reference**](../README.md) - Detailed documentation
