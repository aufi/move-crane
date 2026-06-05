# DevOps Persona Agent - Usage Guide

## What is it?

The "Alex Chen" agent simulates an experienced DevOps engineer testing crane. It helps capture:
- Realistic user workflows
- Questions a real user would ask
- Problems they would encounter
- Feedback from practical usage perspective

## Where is data stored?

The agent stores all data in:

```
test-day-june2026/agent-workspace/
└── session_YYYYMMDD_HHMMSS/          # Each session has its own directory
    ├── logs/
    │   ├── actions.log               # What Alex did
    │   ├── thoughts.log              # What Alex thought/questioned
    │   ├── commands.log              # Commands executed
    │   └── last_output.txt           # Last command output
    ├── notes/
    │   └── questions.md              # Questions Alex asked
    ├── issues/
    │   ├── BLOCKING_*.md             # Blocking issues
    │   ├── MEDIUM_*.md               # Medium priority issues
    │   └── ENHANCEMENT_*.md          # Enhancement requests
    ├── scenario-01/                  # For each scenario
    │   ├── migration/                # Crane workspace for migration
    │   ├── observations/             # Observations during scenario
    │   └── README.md                 # Scenario notes
    ├── scenario-02/
    └── SESSION_REPORT.md             # Final session report
```

## How to use the agent?

### 1. Interactive Mode (Recommended)

```bash
cd test-day-june2026/
./run-agent.sh interactive

# Or simply:
./run-agent.sh
```

**Available commands in interactive mode:**

```bash
# Start a scenario
alex> scenario 1 "Real-World Application Migration"

# Execute command as Alex
alex> exec "crane export -n wordpress"

# Record an observation
alex> observe "Export created 15 files, some look auto-generated"

# Record a thought/question
alex> think "Why are there so many files? Which ones are important?"

# Ask a question
alex> ask "How do I know if the generated patches are correct?"

# Log an issue
alex> issue BLOCKING "Export missed ConfigMap with nginx configuration"
alex> issue MEDIUM "Multi-stage iteration workflow unclear"
alex> issue ENHANCEMENT "Add progress bar during export"

# Generate report
alex> report

# Show session info
alex> info

# Exit
alex> quit
```

### 2. Initialize Specific Scenario

```bash
# Prepare workspace for scenario 1
./run-agent.sh scenario-01

# This creates:
# - agent-workspace/session_YYYYMMDD_HHMMSS/scenario-01/
# - Prepares structure for testing
# - Returns workspace path
```

Then you can manually test and use interactive commands for recording.

### 3. List All Sessions

```bash
./run-agent.sh list
```

Output:
```
Available sessions:
  - session_20260605_103045
  - session_20260605_094521
  - session_20260604_162344
```

### 4. Generate Report for Existing Session

```bash
./run-agent.sh report session_20260605_103045
```

## Usage Examples

### Example 1: Test Scenario 1 (WordPress)

```bash
./run-agent.sh interactive

alex> scenario 1 "Real-World Application Migration"
alex> exec "cd sample-apps/wordpress && ./deploy.sh"
alex> observe "WordPress deployed, 2 deployments, 2 PVCs, 1 Job"
alex> ask "How long until the Job completes?"

alex> exec "cd ../../migration-wordpress && crane export"
alex> observe "Export created 12 files"
alex> think "Are these all the resources? How do I verify?"
alex> exec "ls -la export/resources/default/"

alex> exec "crane transform"
alex> observe "Created stage 10_KubernetesPlugin with patches"
alex> exec "cat transform/10_KubernetesPlugin/patches/default--apps-v1--Deployment--wordpress.patch.yaml"
alex> think "Patches remove uid, resourceVersion - looks correct"

alex> issue MEDIUM "Not clear how to verify all resources were exported"

alex> exec "crane apply"
alex> observe "Generated output/output.yaml"
alex> exec "grep '^kind:' output/output.yaml | sort | uniq -c"

alex> ask "Should I test dry-run before applying to target cluster?"
alex> exec "kubectl apply --dry-run=client -f output/output.yaml"

alex> report
alex> quit
```

After exit, find complete report in:
`agent-workspace/session_YYYYMMDD_HHMMSS/SESSION_REPORT.md`

### Example 2: Test Multi-Stage Iteration (Key Question)

```bash
./run-agent.sh interactive

alex> scenario 2 "Multi-Stage Transformation - Iteration Testing"

# Test iteration - key question from test-day-notes.md
alex> exec "crane transform KubernetesPlugin"
alex> exec "crane transform EnvironmentCustomization"

# Make mistake in Stage 2
alex> exec "echo 'namespace: wrong-name' >> transform/20_EnvironmentCustomization/kustomization.yaml"
alex> observe "Made mistake in namespace, need to fix"

# Question: How to iterate correctly?
alex> think "Should I re-run just Stage 2, or all stages?"

# Try Option A: Re-run just Stage 2
alex> exec "crane transform EnvironmentCustomization"
alex> observe "Stage 2 was regenerated"
alex> ask "Did Stage 2 use data from Stage 1, or do I need to re-run both?"

# Try Option B: Re-run both
alex> exec "crane transform KubernetesPlugin EnvironmentCustomization"
alex> observe "Both stages were regenerated"

# Try Option C: Force regenerate all
alex> exec "crane transform --force"
alex> observe "All stages regenerated, but I lost my custom changes!"

alex> issue BLOCKING "Not documented how to iterate stages correctly - lost changes with --force"
alex> ask "Should I use stage-by-stage approach or always regenerate everything?"

alex> report
alex> quit
```

### Example 3: Discovery Session (First Time with Crane)

```bash
./run-agent.sh interactive

alex> scenario 0 "First Time User - Discovery"

alex> think "First time using crane, starting with --help"
alex> exec "crane --help"
alex> observe "Main commands: export, transform, apply, plugin-manager"

alex> ask "What is typical workflow? Export -> Transform -> Apply?"
alex> exec "crane export --help"
alex> observe "Basic usage looks simple: crane export -n namespace"

alex> think "Try to find documentation"
alex> exec "ls -la ."
alex> exec "cat README.md"
alex> observe "Test day materials, links to scenarios"

alex> ask "Should I start with Scenario 1 or read entire README first?"
alex> observe "Scenario 1 looks like good start - real-world app"

alex> think "Need two clusters - source and target"
alex> exec "kubectl config get-contexts"
alex> observe "Have 3 contexts: dev, staging, prod"

alex> ask "Can I use same cluster as source and target for testing?"
alex> issue ENHANCEMENT "README should have requirements checklist before starting testing"

alex> report
alex> quit
```

## What to do with collected data?

### 1. Analyze Issues

```bash
# All blocking issues
find agent-workspace/session_*/issues/BLOCKING_*.md

# Read specific issue
cat agent-workspace/session_20260605_103045/issues/BLOCKING_1685962345.md
```

### 2. Review Questions

```bash
# All questions from all sessions
cat agent-workspace/session_*/notes/questions.md

# These questions indicate:
# - Missing documentation
# - Unclear workflow
# - Need for validation/helpers
```

### 3. Analyze Common Patterns

```bash
# Find most frequently asked questions
cat agent-workspace/session_*/notes/questions.md | sort | uniq -c | sort -rn

# Most common issues
ls agent-workspace/session_*/issues/ | cut -d'_' -f1 | sort | uniq -c
```

### 4. Create GitHub Issues from Agent Findings

```bash
# Template:
# Title: [From Agent Testing] <issue title>
# Labels: test-day, user-feedback, <severity>
# Body: Include relevant parts from agent issue .md file
```

## Tips for Effective Use

### 1. Think Like Alex
- Be skeptical but constructive
- Ask "why" for every unexplained behavior
- Document everything that's confusing

### 2. Test Realistically
- Make mistakes (typos, wrong commands)
- Try different approaches to same problem
- Test edge cases

### 3. Record Continuously
- Don't write notes only at the end
- Capture first impressions (they're valuable)
- Note every question as it arises

### 4. Use Correct Severity
- **BLOCKING**: Cannot continue, must be fixed
- **MEDIUM**: Works with workaround, should be fixed
- **ENHANCEMENT**: Nice to have, improves UX

## Reporting

After each session:

```bash
alex> report
```

Creates `SESSION_REPORT.md` with:
- Session summary
- List of all issues
- All questions asked
- Recommendations on what to fix first

## Integration with Test Day

Agent data can be used for:

1. **Documentation Validation**
   - Questions indicate where docs are missing
   
2. **UX Problem Identification**
   - Observations show where workflow is unclear
   
3. **Bug Fix Prioritization**
   - Blocking issues are top priority
   
4. **Error Message Improvement**
   - When Alex doesn't understand error, it's a problem

5. **FAQ Creation**
   - Most frequent questions → FAQ section

## Example Output

After a session you'll find for example:

**SESSION_REPORT.md:**
```markdown
# Test Session Report

**Agent:** Alex Chen
**Date:** 2026-06-05 10:30:45
**Session:** 20260605_103045

## Summary

Total scenarios tested: 2
Total issues logged: 5
Total commands executed: 23

## Issues Summary

### Blocking Issues
- BLOCKING_1685962345.md

### Medium Priority Issues  
- MEDIUM_1685962456.md
- MEDIUM_1685962567.md

### Enhancement Requests
- ENHANCEMENT_1685962678.md
- ENHANCEMENT_1685962789.md

## Questions Raised

- How do I know patches are correct?
- Should I re-run just changed stage or all stages?
- What happens when I edit a stage and run crane transform again?

## Recommendations

Based on this test session:

1. Priority bugs to fix: Export missing cluster resources
2. Documentation improvements needed: Multi-stage iteration workflow
3. UX enhancements: Add progress indicators, validation commands
```

---

**Get Started:**
```bash
cd test-day-june2026/
./run-agent.sh interactive
```

And simulate a real user! All data is automatically saved to `agent-workspace/`.

---

## Automated Mode - Run All Scenarios

For fully automated testing, use the auto-runner:

### Quick Start

```bash
cd test-day-june2026/
./agent-auto-runner.sh
```

This will automatically:
1. ✅ Deploy WordPress sample app
2. ✅ Run Scenario 1 (Real-World App Migration)
3. ✅ Run Scenario 2 (Multi-Stage Transformation)
4. ✅ Run Scenario 3 (Cluster Resources - detection only)
5. ✅ Log all issues, questions, and observations
6. ✅ Generate comprehensive report
7. ✅ Cleanup deployed resources

### Configuration Options

```bash
# Skip WordPress deployment (use existing)
SKIP_DEPLOY=true ./agent-auto-runner.sh

# Don't cleanup after run (keep resources)
CLEANUP_AFTER=false ./agent-auto-runner.sh

# Verbose output
VERBOSE=true ./agent-auto-runner.sh

# Combine options
SKIP_DEPLOY=true VERBOSE=true ./agent-auto-runner.sh
```

### What Gets Tested Automatically

**Scenario 1: WordPress Migration**
- Deploys WordPress + MySQL
- Exports resources
- Transforms with KubernetesPlugin
- Validates output
- Checks resource counts and types
- Verifies patch generation

**Scenario 2: Multi-Stage (KEY TEST)**
- Creates KubernetesPlugin stage
- Creates custom EnvironmentCustomization stage
- Tests iteration workflow:
  - Re-running single stage
  - Re-running all stages
  - Testing --force flag
- **Answers key question:** "Stage-by-stage vs regenerate all?"

**Scenario 3: Cluster Resources**
- Simulated testing (requires cluster-admin)
- Logs questions about cluster resource handling
- Recommends manual testing

### Output Location

All data saved to:
```
agent-workspace/
└── auto_session_YYYYMMDD_HHMMSS/
    ├── logs/
    │   └── auto-run.log              # Complete run log
    ├── issues/
    │   ├── BLOCKING_*.md
    │   ├── MEDIUM_*.md
    │   └── ENHANCEMENT_*.md
    ├── notes/
    │   ├── questions.md              # All questions raised
    │   └── thoughts.md               # Agent thoughts
    ├── scenario-01/
    │   ├── migration/                # Crane workspace
    │   ├── observations/             # Findings
    │   ├── deploy.log
    │   ├── export.log
    │   ├── transform.log
    │   └── apply.log
    ├── scenario-02/
    │   ├── migration/
    │   ├── observations/
    │   │   └── iteration-workflow.md  # KEY FINDINGS
    │   ├── stage1.log
    │   ├── stage2.log
    │   └── stage2-rerun.log
    ├── scenario-03/
    │   └── observations/
    └── AUTO_RUN_REPORT.md            # FINAL REPORT
```

### View Results

```bash
# Read final report
cat agent-workspace/auto_session_*/AUTO_RUN_REPORT.md

# Check all issues
find agent-workspace/auto_session_*/issues/ -type f

# Read key findings (stage iteration)
cat agent-workspace/auto_session_*/scenario-02/observations/iteration-workflow.md

# All questions asked
cat agent-workspace/auto_session_*/notes/questions.md
```

### Example Auto-Run

```bash
$ ./agent-auto-runner.sh

╔════════════════════════════════════════════════════════════╗
║  Crane Test Day - Automated Agent Runner                  ║
║  Agent: Alex Chen (Automated Mode)                        ║
║  Session: 20260605_143022                                 ║
╚════════════════════════════════════════════════════════════╝

[INFO] Checking prerequisites...
[✓] crane found: crane version main@abcd1234
[✓] kubectl found
[✓] Kubernetes contexts available

═══════════════════════════════════════════════════════════
  Scenario 1: Real-World Application Migration
═══════════════════════════════════════════════════════════

[Alex thinks] This is a real-world WordPress app with MySQL...
[INFO] Deploying WordPress sample application...
[✓] WordPress deployed successfully
[Alex thinks] Deployment shows 2 pods. Expected 2 (mysql + wordpress)
[INFO] Step 1: Export resources
[Alex thinks] Exporting default namespace...
[✓] Export completed
[Alex thinks] Export created 12 files
[INFO] Step 2: Transform with KubernetesPlugin
[✓] Transform completed
[Alex thinks] Transform created 12 patches
[INFO] Step 3: Generate final output
[✓] Apply completed
[✓] Validation passed (dry-run)
[✓] Scenario 1 completed

═══════════════════════════════════════════════════════════
  Scenario 2: Multi-Stage Transformation
═══════════════════════════════════════════════════════════

[Alex thinks] Testing multi-stage workflow and iteration...
[Alex asks] Does it make sense to work stage-by-stage or regenerate all?
[INFO] Creating Stage 1: KubernetesPlugin
[✓] Stage 1 created
[INFO] Creating Stage 2: EnvironmentCustomization
[✓] Stage 2 created
[Alex asks] Did Stage 2 receive input from Stage 1 output?
[INFO] Testing iteration workflow (KEY QUESTION)
[Alex asks] If I re-run just Stage 2, will it use Stage 1 output?
[✓] Stage 2 re-run succeeded
[Alex thinks] Changes preserved after re-run
[Alex asks] What does --force do? Will it overwrite my changes?
[⚠] --force lost custom changes!
[Issue BLOCKING] --force flag overwrites custom stages without warning!
[✓] Scenario 2 completed

...

═══════════════════════════════════════════════════════════
  Automated Run Complete
═══════════════════════════════════════════════════════════

Report: agent-workspace/auto_session_20260605_143022/AUTO_RUN_REPORT.md
Session directory: agent-workspace/auto_session_20260605_143022

Quick stats:
  - Issues: 3
  - Questions: 8
  - Scenarios: 3/3 completed
```

### When to Use Auto vs Interactive

**Use Automated Mode (`agent-auto-runner.sh`) when:**
- Quick validation of crane functionality
- Regression testing after crane changes
- CI/CD integration
- Batch testing multiple scenarios
- Overnight test runs

**Use Interactive Mode (`run-agent.sh interactive`) when:**
- Exploring specific issues
- Manual testing edge cases
- Following along with scenario docs
- Learning crane workflow
- Detailed investigation

### CI/CD Integration

```bash
# In your CI pipeline
cd test-day-june2026/
./agent-auto-runner.sh

# Check exit code
if [ $? -eq 0 ]; then
  echo "All scenarios passed"
else
  echo "Some scenarios failed"
  cat agent-workspace/auto_session_*/AUTO_RUN_REPORT.md
  exit 1
fi
```

### Interpreting Results

The auto-runner focuses on answering key questions from `test-day-notes.md`:

1. **Resource coverage** - Does KubernetesPlugin handle all types?
   - Check: scenario-01/observations/export.md

2. **Stage iteration** - Stage-by-stage or regenerate all?
   - Check: scenario-02/observations/iteration-workflow.md

3. **Cluster resources** - How should crane handle them?
   - Check: scenario-03/observations/cluster-resources.md

---

**TL;DR:**
- Interactive mode: `./run-agent.sh interactive` - Manual control
- Automated mode: `./agent-auto-runner.sh` - Run all scenarios automatically
