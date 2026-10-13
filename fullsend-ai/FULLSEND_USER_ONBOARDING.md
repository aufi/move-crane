# Fullsend User Onboarding

## Purpose

This guide is for developers and QE engineers using Fullsend in the
`aufi/crane-fullsend-pilot` repository. It explains how to request agent work
and how to review its results. It does not cover installation, credentials, or
repository administration.

Fullsend is an experimental pilot. Agents assist with routine development work;
they do not replace engineering judgment, code review, testing, or branch
protection.

## What Fullsend Can Do

| Agent | Where to use it | What it does |
| --- | --- | --- |
| Triage | GitHub issue | Assesses completeness, asks questions, applies workflow labels. |
| Review | Pull request | Reviews correctness, security, tests, and intent. |
| Code | GitHub issue | Creates a branch and pull request implementing a well-scoped issue. |
| Fix | Pull request | Updates a Fullsend code-agent pull request in response to a specific request. |

Fullsend is configured with the experimental Codex runtime. Treat every output
as a proposal that requires normal human review.

## Before You Start

- Use only the pilot repository, not an upstream `migtools` repository.
- Do not include credentials, customer data, security reports, access tokens,
  kubeconfigs, or private cluster information in issues, pull requests, logs,
  or comments.
- Use a small, focused task. A good first task has clear expected behavior and
  a practical test or acceptance criterion.
- Do not ask an agent to change `.github/workflows/`, `.fullsend/`,
  `CODEOWNERS`, `AGENTS.md`, or `PILOT.md`.
- Never merge agent output solely because the agent created it. The existing
  required checks and human approval remain mandatory.

## Commands

Post these commands as separate GitHub comments. A command must be issued by a
user with the repository permission required by GitHub and Fullsend.

| Command | Target | Use it when |
| --- | --- | --- |
| `/fs-triage` | Issue | You need the issue classified or want to know what information is missing. |
| `/fs-review` | Pull request | You want an additional agent review of an existing pull request. |
| `/fs-code` | Issue | The issue is small, unambiguous, and ready for an implementation pull request. |
| `/fs-fix <specific instruction>` | Pull request | A Fullsend code-agent pull request needs a narrowly defined correction. |
| `/fs-fix-stop` | Pull request | Stop automatic fix activity for that pull request. |

`/fs-code` and `/fs-fix` require write permission or higher. `/fs-review`
requires at least triage permission.

## Recommended Workflow

### 1. Triage an Issue

Create a clear issue and use `/fs-triage` when needed. The agent may:

- ask clarifying questions and apply `needs-info`;
- label an issue `triaged` when a human must prioritize it;
- apply `ready-to-code` when it considers an issue suitable for implementation.

Because `ready-to-code` can trigger the code agent, do not use it for an
unfinished design discussion or a task that is not safe to implement. Add the
missing constraints first, or ask a maintainer to remove the label.

### 2. Request a Review

Open a normal pull request and use `/fs-review`. Read the review as another
engineering signal, not an approval to merge.

For each finding:

1. Confirm that it is correct in the repository context.
2. Check whether the suggested change preserves intended behavior.
3. Run or extend relevant tests.
4. Resolve the discussion through the normal review process.

### 3. Request an Implementation

Use `/fs-code` only for a well-defined issue. The code agent creates a branch
and a pull request; it must not commit to `main`.

Review the generated pull request as carefully as a human-authored change:

- verify its target is `aufi/crane-fullsend-pilot`;
- inspect the diff for unrelated changes;
- confirm tests cover the requested behavior;
- confirm required GitHub checks pass;
- ensure protected files were not changed;
- provide the required human approval before merge.

### 4. Request a Fix

Use `/fs-fix` on a pull request created by the code agent. Give one specific,
testable instruction, for example:

```text
/fs-fix Add a regression test for an empty storage-class value and return an error before creating the transfer job.
```

Do not assume the fix agent reads all inline comments, general discussion, or
CI logs. Put the essential context in the command. Use `/fs-fix-stop` when the
agent is making unsuitable changes or iterations are no longer wanted.

## Expected Behavior

- GitHub Actions shows the agent run and its logs.
- Agent comments and labels form the visible audit trail.
- The code agent works through a branch and pull request, never directly on
  `main`.
- Branch protection, required checks, and human approval apply equally to agent
  changes.
- Fullsend may fail or produce an incomplete result. A failed run is not a
  reason to weaken repository protection or bypass review.

## Reporting Problems

Stop using the relevant agent and notify the pilot owner if an agent:

- exposes or requests sensitive information;
- changes unrelated files or protected paths;
- targets another repository or branch unexpectedly;
- creates a loop of unsuitable fixes;
- produces repeated low-quality reviews or triage;
- causes unexpected OpenAI usage or cost.

For a single pull request, use `/fs-fix-stop` to stop automatic fix activity.
Do not delete Actions logs, agent comments, or labels; they are needed for the
pilot evaluation.
