# Crane Transform Step Redesign - Solution Proposal

## Main Opportunity

**Migrate Kubernetes resources from source to target cluster without cluster-admin** via three-step flow: Export → Transform → Import

This proposal addresses **Solution 2** - the **Transform step**: mutating locally stored exported data into a form that can be imported to the target cluster.

## Problem (Transform Step)

Users transforming exported resources discover incompatibilities **only at import attempt**, forcing manual trial-and-error:

1. Export resources from source ✓
2. Transform locally (blind to target constraints) ❌
3. Attempt import to target → **FAILS** (missing APIs, auth issues, capacity limits)
4. Return to step 2, manually adjust transformations
5. Repeat 3-5 times (2-4 hours average)

**Core issue:** Transform step operates without target cluster context - mutations are speculative, validation happens too late.

## Desired Outcome

**Confident, target-aware transformation** where:
- Exported data is mutated with knowledge of target constraints
- Incompatibilities surface during transform (not at import)
- Remediation guidance is actionable and deterministic
- Final manifests are import-ready on first attempt

**Target:** 60%+ reduction in iteration cycles, <2 attempts to successful import.

---

## Solution: Target-Aware Transform

**Core idea:** Integrate target validation **into** the transform step - mutate local exported data iteratively using target cluster feedback until import-ready.

### Redesigned Workflow

```bash
# 1. Analyze exported data, create initial transformation patches
crane transform-prepare --export-dir ./export --output-dir ./transforms

# 2. Apply transformations to mutate exported data → manifests
crane transform-apply --export-dir ./export --transform-dir ./transforms --output-dir ./manifests

# 3. Validate manifests against target cluster (NEW)
crane validate --target-context prod --input-dir ./manifests
# → Returns findings: missing GVKs, API mismatches, capacity issues

# 4. Adjust transformations based on findings, repeat 2-3 until exit code 0
crane transform-prepare --export-dir ./export --output-dir ./transforms \
  --enable-plugin RouteToIngress --storage-class-map gp2=gp3
```

**Result:** Final `./manifests` are validated against target **before** import attempt - mutations are informed, not speculative.

### What Gets Validated (Target Compatibility Checks)

1. **Access & Permissions** - auth, RBAC, create permissions for exported GVKs
2. **API Compatibility** - GVK existence, API versions, dry-run validation, dependencies (StorageClasses)
3. **Capacity** - storage/compute requests vs quotas/limits

### Mutation-Remediation Loop

Validation output guides **local manifest mutations**:

- **Finding:** Route GVK missing on target → **Mutation:** Enable RouteToIngress plugin, regenerate manifests
- **Finding:** StorageClass mismatch → **Mutation:** Apply storage-class-map, reapply transforms
- **Finding:** Immutable field conflict → **Mutation:** Adjust patch or flag for manual review

### Output Format
- Structured JSON with actionable findings
- Exit codes: `0` (pass) | `2` (needs mutation) | `5` (unreachable)
- Plugin/patch recommendations for next iteration

### Example Finding
```json
{
  "severity": "error",
  "resource": "routes.route.openshift.io",
  "issue": "GVK not found on target",
  "remediation": {
    "plugin": "RouteToIngress",
    "confidence": "high"
  }
}
```

---

## Assumptions to Test

1. **Users have target kubeconfig during transformation** - validate with 5 user interviews
2. **Dry-run provides sufficient compatibility signal** - test against 10 real migrations
3. **70%+ issues are auto-remediable** - analyze 50 migration failure logs
4. **Users trust validation output** - prototype UX feedback

---

## MVP Scope

**In:**
- `transform-prepare`, `transform-apply` commands
- `validate` with domains 1-2 (access + API)
- JSON output, stable exit codes

**Out:**
- Auto-orchestration
- Domain 3 (capacity sizing) - phase 2
- Plugin marketplace

**Success:** 3 pilot users, <2 iterations average, <90sec validation time

---

## Next Steps

1. Build `validate` domains 1-2 (2 weeks)
2. Test on 10 historical migrations (1 week)
3. User interviews with prototype (1 week)
4. Decide: auto-orchestration based on data
