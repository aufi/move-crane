# DevOps Persona Agent

## Quick Start

```bash
cd test-day-june2026/
./run-agent.sh interactive
```

## What You Get

The agent simulates **Alex Chen**, an experienced DevOps engineer testing crane. It automatically tracks:

- ✅ **Actions** - What was executed
- ✅ **Thoughts** - Questions and observations  
- ✅ **Issues** - Bugs categorized by severity
- ✅ **Reports** - Structured session summaries

## Where Data is Stored

```
agent-workspace/
└── session_YYYYMMDD_HHMMSS/
    ├── logs/           # Actions, thoughts, commands
    ├── issues/         # BLOCKING, MEDIUM, ENHANCEMENT
    ├── notes/          # Questions asked
    ├── scenario-*/     # Per-scenario workspace
    └── SESSION_REPORT.md
```

## Key Files

1. **[devops-persona-agent.md](./devops-persona-agent.md)** - Agent profile and behavior
2. **[AGENT_USAGE.md](./AGENT_USAGE.md)** - Detailed usage guide with examples
3. **[run-agent.sh](./run-agent.sh)** - Executable agent runner

## Interactive Commands

```bash
alex> scenario 1 "Real-World App"     # Start scenario
alex> exec "crane export"             # Run command
alex> observe "Export created 15 files" # Log observation
alex> think "Why so many files?"      # Log thought
alex> ask "How to validate patches?"  # Ask question
alex> issue BLOCKING "Export missed CRD" # Log issue
alex> report                          # Generate report
alex> quit                            # Exit
```

## Example Session

```bash
./run-agent.sh interactive

alex> scenario 1 "Testing WordPress Migration"
alex> exec "cd sample-apps/wordpress && ./deploy.sh"
alex> observe "WordPress deployed successfully"
alex> exec "crane export"
alex> ask "How do I know all resources were exported?"
alex> issue MEDIUM "No validation that export is complete"
alex> report
alex> quit
```

Result: Complete session report with all issues and questions in `agent-workspace/session_*/SESSION_REPORT.md`

## Why Use the Agent?

1. **Structured Testing** - Consistent approach across scenarios
2. **Automatic Documentation** - All findings logged automatically
3. **Issue Tracking** - Bugs categorized by severity
4. **Realistic Perspective** - Tests from real user viewpoint
5. **Question Collection** - Identifies documentation gaps

## Use Cases

- **Test Day Validation** - Run through scenarios capturing real user experience
- **Documentation Review** - Questions reveal documentation gaps
- **UX Testing** - Observations identify workflow issues
- **Bug Discovery** - Systematic issue tracking
- **Feature Requests** - Enhancement ideas from real usage

## Next Steps

1. Read [AGENT_USAGE.md](./AGENT_USAGE.md) for detailed examples
2. Run `./run-agent.sh interactive` to start testing
3. Review session reports in `agent-workspace/`
4. Create GitHub issues from agent findings

---

**The agent helps answer:** "What would a real DevOps engineer experience when using crane?"
