#!/bin/bash
set -e

# Crane Test Day - Automated Agent Runner
# This script runs the DevOps agent through all test day scenarios automatically

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_RUNNER="${SCRIPT_DIR}/run-agent.sh"
SAMPLE_APPS="${SCRIPT_DIR}/sample-apps"
AGENT_WORKSPACE="${SCRIPT_DIR}/agent-workspace"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
AUTO_SESSION_DIR="${AGENT_WORKSPACE}/auto_session_${TIMESTAMP}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
VERBOSE=${VERBOSE:-false}
SKIP_DEPLOY=${SKIP_DEPLOY:-false}
CLEANUP_AFTER=${CLEANUP_AFTER:-true}

# Create auto session directory
mkdir -p "${AUTO_SESSION_DIR}"/{logs,issues,notes}

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Crane Test Day - Automated Agent Runner                  ║${NC}"
echo -e "${CYAN}║  Agent: Alex Chen (Automated Mode)                        ║${NC}"
echo -e "${CYAN}║  Session: ${TIMESTAMP}                             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[$(date +%H:%M:%S)] INFO: $1" >> "${AUTO_SESSION_DIR}/logs/auto-run.log"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    echo "[$(date +%H:%M:%S)] SUCCESS: $1" >> "${AUTO_SESSION_DIR}/logs/auto-run.log"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    echo "[$(date +%H:%M:%S)] WARNING: $1" >> "${AUTO_SESSION_DIR}/logs/auto-run.log"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    echo "[$(date +%H:%M:%S)] ERROR: $1" >> "${AUTO_SESSION_DIR}/logs/auto-run.log"
}

log_agent_thought() {
    echo -e "${YELLOW}[Alex thinks]${NC} $1"
    echo "$1" >> "${AUTO_SESSION_DIR}/notes/thoughts.md"
}

log_agent_question() {
    echo -e "${YELLOW}[Alex asks]${NC} $1"
    echo "- $1" >> "${AUTO_SESSION_DIR}/notes/questions.md"
}

log_agent_issue() {
    local severity="$1"
    local issue="$2"
    local issue_file="${AUTO_SESSION_DIR}/issues/${severity}_$(date +%s).md"

    cat > "${issue_file}" << EOF
# ${severity} Issue

**Timestamp:** $(date)
**Scenario:** ${CURRENT_SCENARIO}

## Description
${issue}

## Auto-detected by Agent
This issue was automatically detected during agent auto-run.
EOF

    echo -e "${RED}[Issue ${severity}]${NC} ${issue}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check crane is available
    if ! command -v crane &> /dev/null; then
        log_error "crane command not found. Please install crane first."
        exit 1
    fi
    log_success "crane found: $(crane version 2>&1 | head -1 || echo 'unknown version')"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    log_success "kubectl found"

    # Check cluster contexts
    if ! kubectl config get-contexts &> /dev/null; then
        log_warning "Cannot access Kubernetes contexts"
    else
        log_success "Kubernetes contexts available"
    fi

    # Check yq if available (helpful but not required)
    if command -v yq &> /dev/null; then
        log_success "yq found (helpful for YAML parsing)"
    fi

    echo ""
}

# Scenario 1: Real-World Application Migration
run_scenario_01() {
    CURRENT_SCENARIO="Scenario 1: Real-World Application Migration"
    local scenario_dir="${AUTO_SESSION_DIR}/scenario-01"
    mkdir -p "${scenario_dir}"/{migration,observations}

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  ${CURRENT_SCENARIO}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    log_info "Starting Scenario 1: WordPress Application Migration"

    # Agent thoughts
    log_agent_thought "This is a real-world WordPress app with MySQL. Good test for multi-container pods, PVCs, Jobs, ConfigMaps."
    log_agent_question "Will all resource types be exported correctly?"

    # Deploy WordPress if not skipped
    if [ "${SKIP_DEPLOY}" = "false" ]; then
        log_info "Deploying WordPress sample application..."

        if [ ! -d "${SAMPLE_APPS}/wordpress" ]; then
            log_error "WordPress sample app not found at ${SAMPLE_APPS}/wordpress"
            log_agent_issue "BLOCKING" "WordPress sample app directory not found"
            return 1
        fi

        cd "${SAMPLE_APPS}/wordpress"

        log_agent_thought "Running deploy.sh to set up WordPress and MySQL..."

        if ./deploy.sh > "${scenario_dir}/deploy.log" 2>&1; then
            log_success "WordPress deployed successfully"

            # Verify deployment
            local pod_count=$(kubectl get pods -l app=wordpress --no-headers 2>/dev/null | wc -l)
            echo "Deployed pods: ${pod_count}" >> "${scenario_dir}/observations/deploy.md"

            log_agent_thought "Deployment shows ${pod_count} pods. Expected 2 (mysql + wordpress)"

            if [ "${pod_count}" -lt 2 ]; then
                log_warning "Expected 2 pods, found ${pod_count}"
                log_agent_question "Why are there fewer pods than expected?"
            fi
        else
            log_error "WordPress deployment failed"
            log_agent_issue "BLOCKING" "WordPress deployment failed. See ${scenario_dir}/deploy.log for details"
            cat "${scenario_dir}/deploy.log"
            return 1
        fi
    else
        log_info "Skipping WordPress deployment (SKIP_DEPLOY=true)"
    fi

    # Create migration workspace
    cd "${scenario_dir}/migration"
    log_info "Working directory: ${PWD}"

    # Step 1: Export
    log_info "Step 1: Export resources"
    log_agent_thought "Exporting default namespace. Should get Deployments, Services, PVCs, ConfigMaps, Secrets, Job..."

    if crane export > "${scenario_dir}/export.log" 2>&1; then
        log_success "Export completed"

        # Count exported resources
        local resource_count=$(find export/resources/default/ -type f 2>/dev/null | wc -l)
        echo "Exported ${resource_count} resource files" >> "${scenario_dir}/observations/export.md"

        log_agent_thought "Export created ${resource_count} files"

        # List resource types
        if [ -d "export/resources/default/" ]; then
            local resource_types=$(ls export/resources/default/ | cut -d'_' -f1 | sort -u | tr '\n' ', ')
            echo "Resource types: ${resource_types}" >> "${scenario_dir}/observations/export.md"
            log_agent_thought "Resource types found: ${resource_types}"
        fi

        # Check for expected resources
        if ! ls export/resources/default/Deployment_* &> /dev/null; then
            log_warning "No Deployments found in export"
            log_agent_issue "BLOCKING" "Expected Deployments not found in export"
        fi

        if ! ls export/resources/default/Job_* &> /dev/null; then
            log_warning "No Jobs found in export"
            log_agent_question "Should the wordpress-install Job be exported?"
        fi

        if ! ls export/resources/default/ConfigMap_*nginx-config* &> /dev/null; then
            log_warning "NGINX ConfigMap not found"
            log_agent_issue "MEDIUM" "nginx-config ConfigMap might be missing from export"
        fi
    else
        log_error "Export failed"
        log_agent_issue "BLOCKING" "crane export failed. See ${scenario_dir}/export.log"
        cat "${scenario_dir}/export.log"
        return 1
    fi

    # Step 2: Transform
    log_info "Step 2: Transform with KubernetesPlugin"
    log_agent_thought "Transform should clean server-managed metadata..."

    if crane transform > "${scenario_dir}/transform.log" 2>&1; then
        log_success "Transform completed"

        # Count patches
        local patch_count=$(find transform/10_KubernetesPlugin/patches/ -type f 2>/dev/null | wc -l)
        echo "Generated ${patch_count} patch files" >> "${scenario_dir}/observations/transform.md"

        log_agent_thought "Transform created ${patch_count} patches"

        # Verify patch count matches resource count
        if [ "${patch_count}" -ne "${resource_count}" ]; then
            log_warning "Patch count (${patch_count}) doesn't match resource count (${resource_count})"
            log_agent_question "Why don't patch count and resource count match?"
        fi

        # Sample patch inspection
        if [ -f "transform/10_KubernetesPlugin/patches/default--apps-v1--Deployment--wordpress.patch.yaml" ]; then
            local removes_uid=$(grep -c "metadata/uid" transform/10_KubernetesPlugin/patches/default--apps-v1--Deployment--wordpress.patch.yaml || echo 0)
            if [ "${removes_uid}" -gt 0 ]; then
                log_agent_thought "Patches correctly remove metadata/uid"
            else
                log_warning "Patch doesn't remove metadata/uid"
                log_agent_issue "MEDIUM" "Deployment patch missing uid removal"
            fi
        fi
    else
        log_error "Transform failed"
        log_agent_issue "BLOCKING" "crane transform failed. See ${scenario_dir}/transform.log"
        cat "${scenario_dir}/transform.log"
        return 1
    fi

    # Step 3: Apply
    log_info "Step 3: Generate final output"
    log_agent_thought "Running crane apply to generate output/output.yaml..."

    if crane apply > "${scenario_dir}/apply.log" 2>&1; then
        log_success "Apply completed"

        # Verify output exists
        if [ -f "output/output.yaml" ]; then
            local output_resources=$(grep "^kind:" output/output.yaml | wc -l)
            echo "Output contains ${output_resources} resources" >> "${scenario_dir}/observations/apply.md"
            log_agent_thought "Final output has ${output_resources} resources"

            # List resource kinds
            grep "^kind:" output/output.yaml | sort | uniq -c >> "${scenario_dir}/observations/apply.md"
        else
            log_error "output/output.yaml not created"
            log_agent_issue "BLOCKING" "crane apply didn't create output/output.yaml"
        fi
    else
        log_error "Apply failed"
        log_agent_issue "BLOCKING" "crane apply failed. See ${scenario_dir}/apply.log"
        cat "${scenario_dir}/apply.log"
        return 1
    fi

    # Validation
    log_info "Step 4: Validation"
    log_agent_thought "Testing dry-run validation before real deployment..."
    log_agent_question "Should crane have built-in validation command?"

    if kubectl apply --dry-run=client -f output/output.yaml > "${scenario_dir}/validation.log" 2>&1; then
        log_success "Validation passed (dry-run)"
    else
        log_error "Validation failed"
        log_agent_issue "MEDIUM" "kubectl dry-run validation failed. See ${scenario_dir}/validation.log"
        cat "${scenario_dir}/validation.log" | head -20
    fi

    log_success "Scenario 1 completed"
    echo ""

    return 0
}

# Scenario 2: Multi-Stage Transformation
run_scenario_02() {
    CURRENT_SCENARIO="Scenario 2: Multi-Stage Transformation"
    local scenario_dir="${AUTO_SESSION_DIR}/scenario-02"
    mkdir -p "${scenario_dir}"/{migration,observations}

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  ${CURRENT_SCENARIO}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    log_info "Starting Scenario 2: Multi-Stage Transformation"
    log_agent_thought "Testing multi-stage workflow and iteration. This is the key question from test-day-notes.md"
    log_agent_question "Does it make sense to work stage-by-stage or regenerate all?"

    # Use existing export from scenario 1 or create simple test
    cd "${scenario_dir}/migration"

    # Create simple test resources
    mkdir -p export/resources/test
    cat > export/resources/test/test-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: test
  uid: fake-uid-12345
  resourceVersion: "12345"
  creationTimestamp: "2026-01-01T00:00:00Z"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: app
        image: nginx:1.25
EOF

    # Stage 1: KubernetesPlugin
    log_info "Creating Stage 1: KubernetesPlugin"
    log_agent_thought "First stage for basic cleanup..."

    if crane transform KubernetesPlugin > "${scenario_dir}/stage1.log" 2>&1; then
        log_success "Stage 1 created"

        if [ -d "transform/10_KubernetesPlugin" ]; then
            log_agent_thought "Stage 10_KubernetesPlugin created successfully"
        fi
    else
        log_error "Stage 1 creation failed"
        log_agent_issue "BLOCKING" "KubernetesPlugin stage creation failed"
        cat "${scenario_dir}/stage1.log"
        return 1
    fi

    # Stage 2: Custom stage for environment
    log_info "Creating Stage 2: EnvironmentCustomization"
    log_agent_thought "Adding custom stage for namespace and label changes..."

    if crane transform EnvironmentCustomization > "${scenario_dir}/stage2.log" 2>&1; then
        log_success "Stage 2 created"

        # Verify it used Stage 1 output
        if [ -d "transform/20_EnvironmentCustomization" ]; then
            log_agent_thought "Stage 20_EnvironmentCustomization created"
            log_agent_question "Did Stage 2 receive input from Stage 1 output, or from export?"

            # Check .work directory
            if [ -d "transform/.work/20_EnvironmentCustomization/input" ]; then
                log_agent_thought "Found .work/20_EnvironmentCustomization/input - good for debugging"
            else
                log_warning ".work directory not found"
                log_agent_issue "MEDIUM" ".work directory for debugging not created"
            fi
        fi
    else
        log_error "Stage 2 creation failed"
        log_agent_issue "BLOCKING" "EnvironmentCustomization stage creation failed"
        cat "${scenario_dir}/stage2.log"
        return 1
    fi

    # Test iteration workflow - KEY TEST
    log_info "Testing iteration workflow (KEY QUESTION)"
    log_agent_thought "Now testing what happens when I modify and re-run stages..."

    # Modify Stage 2 kustomization
    if [ -f "transform/20_EnvironmentCustomization/kustomization.yaml" ]; then
        echo "namespace: production" >> transform/20_EnvironmentCustomization/kustomization.yaml
        log_agent_thought "Modified Stage 2 kustomization - added namespace: production"
    fi

    # Test: Re-run just Stage 2
    log_agent_question "If I re-run just Stage 2, will it pick up changes and use Stage 1 output?"

    if crane transform EnvironmentCustomization > "${scenario_dir}/stage2-rerun.log" 2>&1; then
        log_success "Stage 2 re-run succeeded"
        log_agent_thought "Stage 2 re-ran successfully"

        # Check if changes were preserved
        if grep -q "namespace: production" transform/20_EnvironmentCustomization/kustomization.yaml; then
            log_agent_thought "Changes preserved after re-run"
        else
            log_warning "Changes were lost after re-run!"
            log_agent_issue "BLOCKING" "Stage changes lost when re-running - this breaks iteration workflow"
        fi
    else
        log_error "Stage 2 re-run failed"
        cat "${scenario_dir}/stage2-rerun.log"
    fi

    # Test: Re-run all stages
    log_agent_question "What happens if I run 'crane transform' without arguments?"

    if crane transform > "${scenario_dir}/transform-all.log" 2>&1; then
        log_success "Transform all stages succeeded"
        log_agent_thought "Running all stages works"
    else
        log_error "Transform all failed"
        cat "${scenario_dir}/transform-all.log"
    fi

    # Test: Force regenerate
    log_agent_question "What does --force do? Will it overwrite my custom changes?"
    log_agent_thought "Testing --force flag - this might be dangerous..."

    # Backup current state
    cp -r transform transform-backup

    if crane transform --force > "${scenario_dir}/transform-force.log" 2>&1; then
        log_success "Transform --force succeeded"

        # Check if custom changes were lost
        if ! grep -q "namespace: production" transform/20_EnvironmentCustomization/kustomization.yaml; then
            log_warning "--force lost custom changes!"
            log_agent_issue "BLOCKING" "--force flag overwrites custom stages without warning - lost my changes!"
            log_agent_thought "This is dangerous. Need clear documentation about --force behavior"
        fi
    else
        log_error "Transform --force failed"
        cat "${scenario_dir}/transform-force.log"
    fi

    # Document findings
    cat > "${scenario_dir}/observations/iteration-workflow.md" << EOF
# Iteration Workflow Testing

## Question
Does it make sense to work stage-by-stage or regenerate all?

## Tests Performed
1. Created Stage 1 (KubernetesPlugin)
2. Created Stage 2 (EnvironmentCustomization)
3. Modified Stage 2
4. Re-ran Stage 2 only
5. Re-ran all stages
6. Tested --force flag

## Findings
- Stage re-run behavior: (see logs)
- --force flag behavior: (see logs)
- .work directory presence: $([ -d transform/.work ] && echo "yes" || echo "no")

## Recommendations
(Based on test results)
EOF

    log_success "Scenario 2 completed"
    echo ""

    return 0
}

# Scenario 3: Cluster-Level Resources (Simplified)
run_scenario_03() {
    CURRENT_SCENARIO="Scenario 3: Cluster-Level Resources"
    local scenario_dir="${AUTO_SESSION_DIR}/scenario-03"
    mkdir -p "${scenario_dir}"/{observations}

    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  ${CURRENT_SCENARIO}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    log_info "Starting Scenario 3: Cluster-Level Resources"
    log_agent_thought "Testing detection of cluster-level resource dependencies"
    log_agent_question "Does crane detect when cluster resources (CRDs, ClusterRoles) are needed?"
    log_agent_question "Should there be a --include-cluster-resources flag?"

    # This is a detection test - we can't deploy CRDs in auto mode without cluster-admin
    log_info "Testing cluster resource detection (simulation)"

    cat > "${scenario_dir}/observations/cluster-resources.md" << EOF
# Cluster-Level Resources Testing

## Questions for Testing
- Does crane detect cluster resource dependencies?
- How does crane handle missing CRDs on export?
- How does crane handle missing ClusterRoles?
- Should there be a validation step that checks cluster resources?

## Notes
This scenario requires cluster-admin permissions and cannot be fully automated
without risking cluster state changes.

Recommendation: Manual testing required for this scenario.
EOF

    log_warning "Scenario 3 requires cluster-admin and cannot be fully automated"
    log_agent_issue "MEDIUM" "Cluster-level resource testing requires manual intervention"
    log_agent_question "Could crane provide a --check-cluster-dependencies dry-run mode?"

    log_success "Scenario 3 completed (manual testing recommended)"
    echo ""

    return 0
}

# Generate final report
generate_final_report() {
    local report_file="${AUTO_SESSION_DIR}/AUTO_RUN_REPORT.md"

    log_info "Generating final report..."

    cat > "${report_file}" << EOF
# Automated Agent Run Report

**Agent:** Alex Chen (Automated Mode)
**Date:** $(date)
**Session:** ${TIMESTAMP}

## Summary

Scenarios attempted: ${SCENARIOS_ATTEMPTED:-0}
Scenarios completed: ${SCENARIOS_COMPLETED:-0}
Total issues logged: $(find "${AUTO_SESSION_DIR}/issues" -type f 2>/dev/null | wc -l)

## Scenarios

### Scenario 1: Real-World Application Migration
Status: ${SCENARIO_01_STATUS:-Not Run}
$([ -f "${AUTO_SESSION_DIR}/scenario-01/observations/deploy.md" ] && echo "✓ Completed" || echo "✗ Failed or Skipped")

### Scenario 2: Multi-Stage Transformation
Status: ${SCENARIO_02_STATUS:-Not Run}
$([ -f "${AUTO_SESSION_DIR}/scenario-02/observations/iteration-workflow.md" ] && echo "✓ Completed" || echo "✗ Failed or Skipped")

### Scenario 3: Cluster-Level Resources
Status: ${SCENARIO_03_STATUS:-Not Run}
$([ -f "${AUTO_SESSION_DIR}/scenario-03/observations/cluster-resources.md" ] && echo "⚠ Manual testing required" || echo "✗ Not Run")

## Issues Found

### Blocking Issues
$(find "${AUTO_SESSION_DIR}/issues" -name "BLOCKING_*.md" -exec basename {} \; 2>/dev/null | sed 's/^/- /' || echo "None")

### Medium Priority
$(find "${AUTO_SESSION_DIR}/issues" -name "MEDIUM_*.md" -exec basename {} \; 2>/dev/null | sed 's/^/- /' || echo "None")

### Enhancement Requests
$(find "${AUTO_SESSION_DIR}/issues" -name "ENHANCEMENT_*.md" -exec basename {} \; 2>/dev/null | sed 's/^/- /' || echo "None")

## Questions Raised

$(cat "${AUTO_SESSION_DIR}/notes/questions.md" 2>/dev/null || echo "No questions logged")

## Key Findings

### Scenario 1 (WordPress Migration)
$(cat "${AUTO_SESSION_DIR}/scenario-01/observations/"*.md 2>/dev/null | head -20 || echo "No observations")

### Scenario 2 (Multi-Stage Iteration)
$(cat "${AUTO_SESSION_DIR}/scenario-02/observations/iteration-workflow.md" 2>/dev/null || echo "No findings")

## Recommendations

1. **Priority Fixes**: Review BLOCKING issues
2. **Documentation**: Address questions in questions.md
3. **UX Improvements**: Review ENHANCEMENT issues

## Session Files

- Main log: ${AUTO_SESSION_DIR}/logs/auto-run.log
- Issues: ${AUTO_SESSION_DIR}/issues/
- Observations: ${AUTO_SESSION_DIR}/scenario-*/observations/
- Full report: ${report_file}

---
Generated: $(date)
EOF

    log_success "Report generated: ${report_file}"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Automated Run Complete${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Report: ${report_file}"
    echo "Session directory: ${AUTO_SESSION_DIR}"
    echo ""
    echo "Quick stats:"
    echo "  - Issues: $(find "${AUTO_SESSION_DIR}/issues" -type f 2>/dev/null | wc -l)"
    echo "  - Questions: $(wc -l < "${AUTO_SESSION_DIR}/notes/questions.md" 2>/dev/null || echo 0)"
    echo "  - Scenarios: ${SCENARIOS_COMPLETED:-0}/${SCENARIOS_ATTEMPTED:-0} completed"
    echo ""
}

# Cleanup function
cleanup() {
    if [ "${CLEANUP_AFTER}" = "true" ] && [ "${SKIP_DEPLOY}" = "false" ]; then
        log_info "Cleaning up deployed resources..."

        if [ -d "${SAMPLE_APPS}/wordpress" ]; then
            cd "${SAMPLE_APPS}/wordpress"
            if [ -f "./destroy.sh" ]; then
                ./destroy.sh > /dev/null 2>&1 || log_warning "Cleanup had errors"
                log_success "WordPress cleaned up"
            fi
        fi
    fi
}

# Main execution
main() {
    SCENARIOS_ATTEMPTED=0
    SCENARIOS_COMPLETED=0

    check_prerequisites

    # Run scenarios
    log_info "Starting automated scenario execution..."
    echo ""

    # Scenario 1
    SCENARIOS_ATTEMPTED=$((SCENARIOS_ATTEMPTED + 1))
    if run_scenario_01; then
        SCENARIO_01_STATUS="✓ PASSED"
        SCENARIOS_COMPLETED=$((SCENARIOS_COMPLETED + 1))
    else
        SCENARIO_01_STATUS="✗ FAILED"
    fi

    # Scenario 2
    SCENARIOS_ATTEMPTED=$((SCENARIOS_ATTEMPTED + 1))
    if run_scenario_02; then
        SCENARIO_02_STATUS="✓ PASSED"
        SCENARIOS_COMPLETED=$((SCENARIOS_COMPLETED + 1))
    else
        SCENARIO_02_STATUS="✗ FAILED"
    fi

    # Scenario 3
    SCENARIOS_ATTEMPTED=$((SCENARIOS_ATTEMPTED + 1))
    if run_scenario_03; then
        SCENARIO_03_STATUS="⚠ MANUAL REQUIRED"
        SCENARIOS_COMPLETED=$((SCENARIOS_COMPLETED + 1))
    else
        SCENARIO_03_STATUS="✗ FAILED"
    fi

    # Generate report
    generate_final_report

    # Cleanup
    cleanup

    # Exit code based on completion
    if [ "${SCENARIOS_COMPLETED}" -eq "${SCENARIOS_ATTEMPTED}" ]; then
        exit 0
    else
        exit 1
    fi
}

# Help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << 'HELP'
Usage: ./agent-auto-runner.sh [options]

Automatically runs the DevOps agent through test day scenarios.

Options:
  SKIP_DEPLOY=true          Skip WordPress deployment
  CLEANUP_AFTER=false       Don't cleanup after run
  VERBOSE=true              More detailed output

Examples:
  ./agent-auto-runner.sh                    # Full auto run
  SKIP_DEPLOY=true ./agent-auto-runner.sh   # Skip deployment
  VERBOSE=true ./agent-auto-runner.sh       # Verbose mode

The agent will:
1. Deploy WordPress sample app
2. Run crane export/transform/apply
3. Test multi-stage iteration workflow
4. Log all issues and questions
5. Generate comprehensive report

Output saved to: agent-workspace/auto_session_<timestamp>/
HELP
    exit 0
fi

# Run main
main "$@"
