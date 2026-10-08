# Crane pull request checks analysis

Snapshot date: 2026-10-08

## Scope and limitation

This analysis covers GitHub Actions and current open pull request check runs in [`migtools/crane`](https://github.com/migtools/crane). It also reviews the repository's workflow definitions and `OWNERS` file.

The GitHub REST endpoints returned no repository rulesets and no visible branch rule or branch-protection configuration for `main`. This does not prove that no merge rule exists. Organization-level rules may not be visible to the current token. The analysis therefore distinguishes checks that run from checks that are confirmed as merge requirements.

## Current check inventory

The repository has 30 workflows. Twenty-eight are active. Two issue-management workflows are manually disabled:

- [`Needs Triage`](https://github.com/migtools/crane/blob/main/.github/workflows/needs-triage.yaml)
- [`Reconcile GitHub Issue`](https://github.com/migtools/crane/blob/main/.github/workflows/reconcile_gh_issue.yaml)

The active workflows fall into four groups.

| Group | Workflows and checks | What they do |
| --- | --- | --- |
| Fast PR quality | [`Go build and unit tests`](https://github.com/migtools/crane/blob/main/.github/workflows/go.yml), [`Lint`](https://github.com/migtools/crane/blob/main/.github/workflows/lint.yml), [`PR Conventions Checks`](https://github.com/migtools/crane/blob/main/.github/workflows/pr-title-check.yml) | Build all Go packages and the CLI, run unit tests with coverage, lint new findings, and validate PR title conventions. |
| Functional PR validation | [`E2E Tests PR Tester`](https://github.com/migtools/crane/blob/main/.github/workflows/e2e-pr-tester.yaml), [`E2E Tests PR Tester (Indirect Migration)`](https://github.com/migtools/crane/blob/main/.github/workflows/e2e-indirect-pr-tester.yaml), [`Test Compliance`](https://github.com/migtools/crane/blob/main/.github/workflows/test-compliance.yml) | Run selective direct and indirect migration tests and enforce the non-admin E2E test convention. |
| Release confidence | [release-0.11 Tier0](https://github.com/migtools/crane/blob/main/.github/workflows/nightly-release-0.11-e2e-tier0.yml), [release-0.11 Tier1](https://github.com/migtools/crane/blob/main/.github/workflows/nightly-release-0.11-e2e-tier1.yml), [release workflow](https://github.com/migtools/crane/blob/main/.github/workflows/release.yml), [cherry-pick workflow](https://github.com/migtools/crane/blob/main/.github/workflows/pr-closed.yaml) | Exercise release branches nightly, publish releases, and create backport PRs from `cherry-pick/*` labels. |
| Workflow visibility | [coverage comments](https://github.com/migtools/crane/blob/main/.github/workflows/coverage-comment.yml), [ready-for-review notification](https://github.com/migtools/crane/blob/main/.github/workflows/pr-ready-for-review-slack.yml), [daily digest](https://github.com/migtools/crane/blob/main/.github/workflows/pr-ready-for-review-digest-slack.yml), [Documentation Assistant](https://github.com/migtools/crane/blob/main/.github/workflows/docs-assistant.yml) | Publish code coverage to PRs, route review-ready PRs to Slack, summarize the review queue, and produce requested documentation assistance. |

## What the checks do

### Build, unit test, and coverage

[`Go build and unit tests`](https://github.com/migtools/crane/blob/main/.github/workflows/go.yml) runs on pushes and pull requests. It:

- builds all Go packages and the `crane` binary with Go 1.25;
- runs unit tests with an atomic coverage profile, excluding cluster-dependent E2E packages;
- uploads the CLI binary for 30 days;
- publishes total and per-package coverage in the workflow summary;
- enforces a 5% total coverage floor;
- uploads PR coverage data used by the [coverage comment workflow](https://github.com/migtools/crane/blob/main/.github/workflows/coverage-comment.yml).

The coverage comment updates one PR comment with total, package, and function-level coverage. This is a useful durable review artifact, but the 5% floor is a smoke threshold rather than a meaningful regression guard. It detects a broken or nearly empty test run, not a small loss of coverage caused by one PR.

### Lint

[`Lint`](https://github.com/migtools/crane/blob/main/.github/workflows/lint.yml) runs `golangci-lint` on new findings only. Its job uses `continue-on-error: true`. Consequently, a lint failure remains visible in checks but does not fail the workflow. This is appropriate only if lint is intentionally advisory. If the team expects lint fixes before merge, it must become a blocking check after existing findings are resolved or explicitly baselined.

### PR conventions

[`PR Conventions Checks`](https://github.com/migtools/crane/blob/main/.github/workflows/pr-title-check.yml) invokes `konveyor/release-tools/cmd/verify-pr`. The action accepts a title only when it identifies a supported type, such as feature, bugfix, documentation, infrastructure, breaking change, no-release-note, or test. The same title taxonomy drives the Slack review digest.

This connects release-note categorization to visible PR metadata. It helps release preparation and backlog reporting, but only when title failures are promptly fixed and the title taxonomy is documented for contributors.

### Selective direct and indirect E2E

The direct and indirect PR test workflows both begin with `detect-changes`:

- code changes outside `e2e-tests`, except CI, documentation, and README paths, run the full Tier0 and Tier1 suite;
- a change to one E2E test runs a focused subset;
- documentation-only E2E changes skip execution;
- suite, framework, utility, configuration, or test-data changes run the full suite;
- indirect tests provision MinIO and pass rclone configuration to test cloud-storage transfer.

Both workflows publish an aggregator check, `run-changed-e2e-tests` or `run-indirect-e2e-tests`, to give a stable result for the path selected by `detect-changes`. This is good check design. It exposes both the decision and the final result, limits unnecessary E2E cost, and preserves a stable merge-gate name if branch protection later requires it.

[`Test Compliance`](https://github.com/migtools/crane/blob/main/.github/workflows/test-compliance.yml) applies only when files under `e2e-tests/tests/**` change. It rejects test patterns that bypass the intended `RUN_AS_ADMIN` behavior. This is a narrow but valuable policy check because it preserves a shared test contract rather than merely checking syntax.

### Release and review visibility

The release-0.11 Tier0 and Tier1 jobs ran daily from 2026-10-04 through 2026-10-08. Each suite passed on two of the last five runs and failed on three. The latest runs on 2026-10-08 passed, but the five-run history is unstable and should be reported as reliability work, not treated as a simple green/red release signal.

The ready-for-review workflow accepts `/ready-for-review` or `/rfr` from the PR author, posts a Slack notification, and applies `ready-for-review-notified`. Its weekday digest lists non-draft PRs with that label, excludes current-head change requests, classifies them by title type, and reports their age. This is already a useful review-queue mechanism.

The `OWNERS` file lists ten reviewers and seven approvers. It supplies a known reviewer pool but does not itself show whether review requests are made or whether all required approval rules are satisfied.

## Current open PR signals

The open PR check data contains repeated observations because every synchronize event can rerun a workflow. It must not be interpreted as a count of distinct PRs.

| Check | Observed runs | Passing | Failing | Skipped or pending | Interpretation |
| --- | ---: | ---: | ---: | ---: | --- |
| `Build and unit test` | 25 | 25 | 0 | 0 | Fast baseline is green in the current set. |
| `golangci-lint` | 24 | 24 | 0 | 0 | Current lint executions are green; they remain advisory by configuration. |
| `Verify PR contents` | 46 | 38 | 7 | 1 | PR title and convention failures are a visible source of queue friction. |
| `run-changed-e2e-tests` | 22 | 15 | 3 | 4 | Direct E2E has failures and expected skips. |
| `run-indirect-e2e-tests` | 20 | 13 | 5 | 2 | Indirect transfer E2E is the largest active failing check category. |
| `e2e-tier1 / run-e2e` | 15 | 11 | 3 | 1 | Tier1 direct E2E has intermittent or unresolved failures. |
| `e2e-indirect-tier0` | 22 | 10 | 4 | 8 | Indirect Tier0 includes both failures and path-based skips. |
| `e2e-indirect-tier1` | 22 | 13 | 2 | 7 | Indirect Tier1 has failures and path-based skips. |

At collection time, failed checks affected PRs [`#663`](https://github.com/migtools/crane/pull/663), [`#885`](https://github.com/migtools/crane/pull/885), [`#1005`](https://github.com/migtools/crane/pull/1005), [`#1014`](https://github.com/migtools/crane/pull/1014), [`#1042`](https://github.com/migtools/crane/pull/1042), [`#1059`](https://github.com/migtools/crane/pull/1059), [`#1063`](https://github.com/migtools/crane/pull/1063), and [`#1068`](https://github.com/migtools/crane/pull/1068). Some are old failures rather than failures on the newest commit. A report must always show check URL, commit SHA, and completion time before assigning work.

## Gaps

- `Needs Triage` is disabled, even though it can send a scheduled digest of issues carrying `needs-triage`.
- `Reconcile GitHub Issue` is disabled. When enabled, it adds and enforces `needs-triage`, `needs-kind`, and `needs-priority`, synchronizes issue data with Jira, and adds a `community` label.
- No repository branch protection or ruleset requirement was visible to the current API token. Required checks, required approvals, merge queue use, and bypass permissions should be confirmed in GitHub settings.
- Lint failures do not block the workflow because `continue-on-error` is enabled.
- The PR check list can be noisy: `detect-changes` appears twice because the direct and indirect workflows each use a job with that name. GitHub check names should include their workflow context or use distinct job names.
- Automated checks do not connect PR readiness to Project 24 status, priority, milestone, or sprint metadata.

## Recommendations

1. Publish a single merge-policy page that names required checks, required approvals, allowed bypasses, and the conditions for applying a cherry-pick label.
2. Confirm or configure branch protection or organization rulesets with stable aggregator checks, not individual E2E jobs. Require `Build and unit test`, `Verify PR contents`, `run-changed-e2e-tests`, and `run-indirect-e2e-tests` only where the selected test scope applies.
3. Rename the direct and indirect `detect-changes` jobs, for example `detect-direct-e2e-changes` and `detect-indirect-e2e-changes`, to make PR status and dashboard aggregation unambiguous.
4. Keep the selective E2E policy, but report skip reason, selected mode, workflow duration, and failure rate in the project dashboard. This turns E2E activity into a transparent capacity and reliability signal.
5. Make lint blocking only after deciding its ownership and remediating the baseline. Until then, label it clearly as advisory in the merge policy and dashboard.
6. Re-enable issue reconciliation in dry-run or notification mode first. Its label taxonomy must match Project 24 priority policy before it modifies issues automatically.
7. Feed the ready-for-review label, check state, requested reviewers, and time since the latest author update into the weekly project report. Use it to identify review bottlenecks without adding PRs as duplicate Project 24 work items.
8. Track nightly Tier0 and Tier1 pass rate separately from PR checks. The last five runs show 40% passing for each suite, so release confidence needs trend visibility and an owner for repeated failures.
9. Attach a merged PR to its issue and update the linked Project 24 item only after acceptance criteria are complete. A green PR proves a change passed selected checks; it does not prove the planned issue is done.

The generated `backlog-status.md` includes a `migtools/crane check results` table. Run `python3 project-mgmt/update_backlog.py` to refresh it.
