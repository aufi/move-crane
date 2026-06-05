#!/bin/bash
set -e

# Crane Test Day - DevOps Persona Agent Runner
# This script helps simulate a DevOps user testing crane

AGENT_NAME="Alex Chen"
AGENT_WORKSPACE="./agent-workspace"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SESSION_DIR="${AGENT_WORKSPACE}/session_${TIMESTAMP}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create session directory
mkdir -p "${SESSION_DIR}"/{notes,logs,issues}

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Crane Test Day - DevOps Persona Agent                  ║${NC}"
echo -e "${BLUE}║    User: ${AGENT_NAME}                                     ║${NC}"
echo -e "${BLUE}║    Session: ${TIMESTAMP}                                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to log agent actions
log_action() {
    local action="$1"
    echo "[$(date +%H:%M:%S)] ${action}" >> "${SESSION_DIR}/logs/actions.log"
    echo -e "${GREEN}[Alex]${NC} ${action}"
}

# Function to log agent thoughts/questions
log_thought() {
    local thought="$1"
    echo "[$(date +%H:%M:%S)] THOUGHT: ${thought}" >> "${SESSION_DIR}/logs/thoughts.log"
    echo -e "${YELLOW}[Alex thinks]${NC} ${thought}"
}

# Function to log issues
log_issue() {
    local severity="$1"
    local issue="$2"
    local issue_file="${SESSION_DIR}/issues/${severity}_$(date +%s).md"

    cat > "${issue_file}" << EOF
# Issue Report

**Severity:** ${severity}
**Timestamp:** $(date)
**Reporter:** ${AGENT_NAME}

## Description
${issue}

## Context
Session: ${TIMESTAMP}
Scenario: ${CURRENT_SCENARIO}

## Next Steps
- [ ] Investigate
- [ ] Document workaround
- [ ] File GitHub issue
EOF

    echo -e "${RED}[Issue ${severity}]${NC} ${issue}"
    echo "Issue logged: ${issue_file}"
}

# Function to start scenario
start_scenario() {
    local scenario_num="$1"
    local scenario_name="$2"

    CURRENT_SCENARIO="${scenario_num}: ${scenario_name}"

    local scenario_dir="${SESSION_DIR}/scenario-${scenario_num}"
    mkdir -p "${scenario_dir}"/{migration,observations}

    cat > "${scenario_dir}/README.md" << EOF
# Scenario ${scenario_num}: ${scenario_name}

**Started:** $(date)
**Agent:** ${AGENT_NAME}

## Objective
Testing crane with scenario ${scenario_num}

## Progress
- [ ] Setup complete
- [ ] Export tested
- [ ] Transform tested
- [ ] Apply tested
- [ ] Validation complete

## Time Tracking
Start: $(date +%H:%M:%S)

## Observations
(See observations/ directory)

## Issues
(See issues/ directory)
EOF

    log_action "Starting scenario ${scenario_num}: ${scenario_name}"
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Scenario ${scenario_num}: ${scenario_name}${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    # Export scenario directory for use in functions
    export CURRENT_SCENARIO_DIR="${scenario_dir}"
}

# Function to observe and document
observe() {
    local observation="$1"
    local obs_file="${CURRENT_SCENARIO_DIR}/observations/$(date +%H%M%S).md"

    cat > "${obs_file}" << EOF
# Observation - $(date +%H:%M:%S)

${observation}
EOF

    echo -e "${BLUE}[Observes]${NC} ${observation}"
}

# Function to execute command as Alex would
alex_execute() {
    local cmd="$1"
    local description="${2:-Executing command}"

    log_thought "${description}"
    echo -e "${GREEN}$ ${cmd}${NC}"

    # Log command
    echo "[$(date +%H:%M:%S)] COMMAND: ${cmd}" >> "${SESSION_DIR}/logs/commands.log"

    # Execute and capture output
    if eval "${cmd}" > "${SESSION_DIR}/logs/last_output.txt" 2>&1; then
        log_action "✓ Command succeeded"
        cat "${SESSION_DIR}/logs/last_output.txt"
        return 0
    else
        log_issue "ERROR" "Command failed: ${cmd}"
        cat "${SESSION_DIR}/logs/last_output.txt"
        return 1
    fi
}

# Function to ask question (simulates Alex asking)
alex_asks() {
    local question="$1"
    echo ""
    echo -e "${YELLOW}❓ [Alex asks]${NC} ${question}"
    echo "${question}" >> "${SESSION_DIR}/notes/questions.md"
    echo ""
}

# Function to generate session report
generate_report() {
    local report_file="${SESSION_DIR}/SESSION_REPORT.md"

    cat > "${report_file}" << EOF
# Test Session Report

**Agent:** ${AGENT_NAME}
**Date:** $(date)
**Session:** ${TIMESTAMP}

## Summary

Total scenarios tested: $(find "${SESSION_DIR}" -type d -name "scenario-*" | wc -l)
Total issues logged: $(find "${SESSION_DIR}/issues" -type f | wc -l)
Total commands executed: $(wc -l < "${SESSION_DIR}/logs/commands.log" 2>/dev/null || echo 0)

## Issues Summary

### Blocking Issues
$(find "${SESSION_DIR}/issues" -name "BLOCKING_*" -exec basename {} \; 2>/dev/null || echo "None")

### Medium Priority Issues
$(find "${SESSION_DIR}/issues" -name "MEDIUM_*" -exec basename {} \; 2>/dev/null || echo "None")

### Enhancement Requests
$(find "${SESSION_DIR}/issues" -name "ENHANCEMENT_*" -exec basename {} \; 2>/dev/null || echo "None")

## Questions Raised

$(cat "${SESSION_DIR}/notes/questions.md" 2>/dev/null || echo "No questions logged")

## Observations

$(find "${SESSION_DIR}" -path "*/observations/*" -type f -exec echo "- {}" \; 2>/dev/null | head -20)

## Session Files

- Actions log: ${SESSION_DIR}/logs/actions.log
- Thoughts log: ${SESSION_DIR}/logs/thoughts.log
- Commands log: ${SESSION_DIR}/logs/commands.log
- Issues directory: ${SESSION_DIR}/issues/
- Observations: ${SESSION_DIR}/scenario-*/observations/

## Recommendations

Based on this test session:

1. Priority bugs to fix: (see BLOCKING issues)
2. Documentation improvements needed: (see questions.md)
3. UX enhancements: (see ENHANCEMENT issues)

---
Generated: $(date)
EOF

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Session Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Session report: ${report_file}"
    echo "Session directory: ${SESSION_DIR}"
    echo ""
    echo "Quick stats:"
    echo "  - Issues logged: $(find "${SESSION_DIR}/issues" -type f | wc -l)"
    echo "  - Commands run: $(wc -l < "${SESSION_DIR}/logs/commands.log" 2>/dev/null || echo 0)"
    echo "  - Questions asked: $(wc -l < "${SESSION_DIR}/notes/questions.md" 2>/dev/null || echo 0)"
    echo ""
}

# Interactive mode function
interactive_mode() {
    echo "Interactive mode - type 'help' for commands"
    echo ""

    while true; do
        echo -n -e "${GREEN}alex>${NC} "
        read -r input

        case "${input}" in
            help)
                cat << 'HELP'
Available commands:
  scenario <num> <name>  - Start new scenario
  exec <command>         - Execute command as Alex
  observe <text>         - Log observation
  think <text>           - Log thought/question
  ask <question>         - Ask question
  issue <severity> <text> - Log issue (BLOCKING/MEDIUM/ENHANCEMENT)
  report                 - Generate session report
  info                   - Show session info
  quit/exit              - Exit interactive mode

Examples:
  scenario 1 "Real-World App Migration"
  exec "crane export -n wordpress"
  observe "Export created 15 files"
  think "Why are there so many files?"
  ask "How do I validate these patches are correct?"
  issue MEDIUM "Multi-stage iteration unclear"
  report
HELP
                ;;
            scenario*)
                args=(${input})
                if [ ${#args[@]} -lt 3 ]; then
                    echo "Usage: scenario <num> <name>"
                else
                    start_scenario "${args[1]}" "${input#scenario ${args[1]} }"
                fi
                ;;
            exec*)
                cmd="${input#exec }"
                alex_execute "${cmd}" "Running user command"
                ;;
            observe*)
                obs="${input#observe }"
                observe "${obs}"
                ;;
            think*)
                thought="${input#think }"
                log_thought "${thought}"
                ;;
            ask*)
                question="${input#ask }"
                alex_asks "${question}"
                ;;
            issue*)
                args=(${input})
                if [ ${#args[@]} -lt 3 ]; then
                    echo "Usage: issue <BLOCKING|MEDIUM|ENHANCEMENT> <description>"
                else
                    severity="${args[1]}"
                    issue_text="${input#issue ${severity} }"
                    log_issue "${severity}" "${issue_text}"
                fi
                ;;
            report)
                generate_report
                ;;
            info)
                echo "Session: ${TIMESTAMP}"
                echo "Workspace: ${SESSION_DIR}"
                echo "Current scenario: ${CURRENT_SCENARIO:-None}"
                echo ""
                ;;
            quit|exit)
                echo "Generating final report..."
                generate_report
                break
                ;;
            "")
                # Empty input, continue
                ;;
            *)
                echo "Unknown command: ${input}"
                echo "Type 'help' for available commands"
                ;;
        esac
    done
}

# Main script logic
main() {
    case "${1:-interactive}" in
        scenario-01|1)
            start_scenario "01" "Real-World Application Migration"
            echo "Ready to test scenario 1. Use interactive commands or run scenario manually."
            echo "Workspace: ${CURRENT_SCENARIO_DIR}"
            ;;
        scenario-02|2)
            start_scenario "02" "Multi-Stage Transformation"
            echo "Ready to test scenario 2. Use interactive commands or run scenario manually."
            echo "Workspace: ${CURRENT_SCENARIO_DIR}"
            ;;
        scenario-03|3)
            start_scenario "03" "Cluster-Level Resources"
            echo "Ready to test scenario 3. Use interactive commands or run scenario manually."
            echo "Workspace: ${CURRENT_SCENARIO_DIR}"
            ;;
        scenario-04|4)
            start_scenario "04" "Validation Testing"
            echo "Ready to test scenario 4. Use interactive commands or run scenario manually."
            echo "Workspace: ${CURRENT_SCENARIO_DIR}"
            ;;
        scenario-05|5)
            start_scenario "05" "Custom Plugin Creation"
            echo "Ready to test scenario 5. Use interactive commands or run scenario manually."
            echo "Workspace: ${CURRENT_SCENARIO_DIR}"
            ;;
        interactive|i)
            interactive_mode
            ;;
        report)
            if [ -z "$2" ]; then
                echo "Usage: $0 report <session_timestamp>"
                echo "Available sessions:"
                ls -1 agent-workspace/ | grep "^session_"
                exit 1
            fi
            generate_report
            ;;
        list)
            echo "Available sessions:"
            ls -1dt agent-workspace/session_* 2>/dev/null | while read session; do
                echo "  - $(basename ${session})"
            done
            ;;
        help|--help|-h)
            cat << 'USAGE'
Usage: ./run-agent.sh [command]

Commands:
  interactive, i           - Start interactive agent session (default)
  scenario-01, 1          - Initialize scenario 1 workspace
  scenario-02, 2          - Initialize scenario 2 workspace
  scenario-03, 3          - Initialize scenario 3 workspace
  scenario-04, 4          - Initialize scenario 4 workspace
  scenario-05, 5          - Initialize scenario 5 workspace
  list                    - List all agent sessions
  report <session>        - Generate report for specific session
  help                    - Show this help

Examples:
  ./run-agent.sh                    # Start interactive mode
  ./run-agent.sh interactive        # Start interactive mode
  ./run-agent.sh scenario-01        # Initialize scenario 1
  ./run-agent.sh list               # List sessions

Interactive mode provides commands for:
  - Starting scenarios
  - Executing commands as Alex
  - Logging observations and issues
  - Asking questions
  - Generating reports

All session data is stored in: ./agent-workspace/session_<timestamp>/

Session structure:
  session_YYYYMMDD_HHMMSS/
  ├── logs/
  │   ├── actions.log      # What Alex did
  │   ├── thoughts.log     # What Alex thought/questioned
  │   ├── commands.log     # Commands executed
  │   └── last_output.txt  # Last command output
  ├── notes/
  │   └── questions.md     # Questions Alex asked
  ├── issues/
  │   ├── BLOCKING_*.md    # Blocking issues
  │   ├── MEDIUM_*.md      # Medium priority issues
  │   └── ENHANCEMENT_*.md # Enhancement requests
  ├── scenario-*/
  │   ├── migration/       # Crane migration workspace
  │   ├── observations/    # Observations during scenario
  │   └── README.md        # Scenario notes
  └── SESSION_REPORT.md    # Final report
USAGE
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run '$0 help' for usage"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
