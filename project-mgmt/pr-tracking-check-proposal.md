# PR tracking check proposal

## Goal

Add one stable pull request check named `verify-pr-tracking` to `migtools/crane`.

The check enforces:

- a pull request to `main` references at least one GitHub issue or Jira issue;
- a pull request to `release-*` references tracked work assigned to the corresponding release line;
- the check result explains which references were found and why they passed or failed.

The check validates planning metadata only. It does not change issues, Jira records, milestones, or Project 24.

## Baseline impact

The current open PR queue has 25 PRs, all targeting `main`:

- 10 have at least one GitHub closing issue reference;
- 8 contain at least one Jira key matching `MTA-[0-9][0-9][0-9]+`;
- 13 satisfy at least one of those conditions;
- 12 satisfy neither condition and would fail immediately.

Among the latest 100 merged PRs, 28 of 85 PRs to `main` and 3 of 15 PRs to a `release-*` branch have neither form of tracking reference. This check needs an audit-only rollout before becoming required.

## Tracking sources

### GitHub issues

Use the GraphQL `closingIssuesReferences` connection for the PR. This recognizes actual closing links created by text such as:

```markdown
Fixes #123
Closes migtools/crane#123
Resolves https://github.com/migtools/crane/issues/123
```

Do not treat every `#123` mention as tracking. PR descriptions commonly mention dependency PRs and test artifacts. A free-form number is not an issue relationship.

A closing reference is suitable when the PR completes the issue. If partial PRs must link without closing the issue, define a second explicit footer before implementation:

```text
Tracking-Issue: migtools/crane#123
```

The first version should support only `closingIssuesReferences` unless the team commits to maintaining this footer convention.

### Jira issues

Search the PR title and body, but not comments, with this exact case-sensitive pattern:

```regex
MTA-[0-9][0-9][0-9]+
```

Deduplicate repeated keys before querying Jira. The equivalent shorter expression is `MTA-[0-9]{3,}`, but the configured value should preserve the requested pattern.

For `main`, the regex match is enough to satisfy the initial policy. The action should still query Jira when credentials are available and report whether the ticket exists.

For a release branch, validate the Jira issue against:

- `Target Version`, currently Jira field `customfield_10855`;
- `fixVersions` as a fallback.

The Red Hat Jira issue endpoint is currently accessible at:

```text
https://issues.redhat.com/rest/api/2/issue/MTA-123?fields=customfield_10855,fixVersions
```

The field identifier must remain a workflow input rather than a hard-coded constant because Jira administrators can migrate or replace custom fields.

## Validation rules

### Pull requests to main

Pass when at least one condition is true:

1. `closingIssuesReferences` contains at least one GitHub issue.
2. The PR title or body contains at least one key matching `MTA-[0-9][0-9][0-9]+`.

Fail when neither condition is true.

Milestone and Jira Target Version are not required for `main`. Assignment to a release may happen later during planning.

### Pull requests to release branches

First parse the base branch:

| Branch form | Expected release |
| --- | --- |
| `release-X.Y` | `X.Y` release line; accept `vX.Y`, `vX.Y.Z`, or `release-X.Y` |
| `release-X.Y.Z` | exact `X.Y.Z`; accept `vX.Y.Z` or `release-X.Y.Z` |

Examples:

| Base branch | Matching GitHub milestone |
| --- | --- |
| `release-0.11` | `v0.11.0`, `v0.11.1`, `v0.11.2`, `release-0.11` |
| `release-0.10` | `v0.10.0`, `v0.10.1`, `release-0.10` |
| `release-1.7.3` | `v1.7.3`, `release-1.7.3` |

Apply these rules:

1. Require at least one GitHub or Jira tracking reference.
2. Require every linked GitHub issue to have a milestone.
3. Require every linked GitHub milestone to match the base release branch.
4. Require every Jira issue to exist and have a matching `Target Version` or `fixVersions` value.
5. Fail on an unknown `release-*` branch format rather than guessing its release line.

Validating every declared reference is stricter than accepting one matching reference. It prevents a PR from passing with one correctly targeted issue while also claiming unrelated work from another release.

Closed GitHub issues are valid references for backports. Their milestone still records the release assignment. Jira status should also be informational; target version, not open or closed status, determines release compatibility.

## Suggested output

Write a concise job summary and GitHub error annotations.

Successful `main` example:

```text
Base branch: main
GitHub issues: migtools/crane#933
Jira issues: MTA-819
Result: pass, tracking reference found
```

Failed release example:

```text
Base branch: release-0.11
Expected release: 0.11
GitHub issue: migtools/crane#1028, milestone: none
Jira issue: MTA-907, Target Version: none, Fix versions: none
Result: fail

Assign #1028 to v0.11.x or set MTA-907 Target Version to 0.11, then rerun the check.
```

The summary should link every GitHub issue, Jira ticket, and mismatched milestone. Avoid a generic `tracking check failed` message.

## Workflow design

The validation reads metadata and may use a Jira credential. It must not execute code from the pull request.

Recommended architecture:

1. Implement the validator as a reusable workflow or action in `konveyor/release-tools`.
2. Pin the caller to a commit SHA or immutable release tag.
3. Trigger it with `pull_request_target` so fork PRs can be validated against trusted workflow code.
4. Never check out the PR head, run PR scripts, or interpolate untrusted title or body text into a shell command.
5. Grant only `contents: read`, `pull-requests: read`, and `issues: read`.
6. Pass the Jira token only to the metadata request step.

Target caller workflow:

```yaml
name: PR Tracking Policy

on:
  pull_request_target:
    types: [opened, edited, reopened, synchronize, ready_for_review]
    branches:
      - main
      - "release-*"

permissions:
  contents: read
  pull-requests: read
  issues: read

jobs:
  verify-pr-tracking:
    name: verify-pr-tracking
    uses: konveyor/release-tools/.github/workflows/verify-pr-tracking.yml@<pinned-ref>
    with:
      jira-base-url: https://issues.redhat.com
      jira-key-regex: 'MTA-[0-9][0-9][0-9]+'
      jira-target-field: customfield_10855
      release-branch-regex: '^release-([0-9]+\.[0-9]+(?:\.[0-9]+)?)$'
    secrets:
      jira-token: ${{ secrets.JIRA_API_TOKEN }}
```

The reusable workflow does not exist yet. The snippet defines the intended interface, not an immediately usable configuration.

## Interaction with current automation

### PR conventions

Keep this check separate from `Verify PR contents` initially. Title format and work tracking are different policies with different remediation. Separate check names make failures understandable and allow independent rollout.

The implementation may later share one `release-tools` binary, but GitHub should continue to expose distinct jobs:

- `verify-pr-title`
- `verify-pr-tracking`

### Cherry-pick workflow

The existing cherry-pick workflow creates a backport PR with `gh pr create --fill`. Several historical release PRs mention only the source PR number and have neither a closing issue nor Jira key.

Before enforcing release validation, update the cherry-pick workflow to copy these values from the source PR into the backport body:

- linked GitHub issue URLs;
- Jira keys;
- source PR URL;
- target release branch.

Do not allow a source PR number by itself to satisfy tracking. It hides the actual release assignment one level away.

### Pull request template

The repository currently has no pull request template. Add one with an explicit section:

```markdown
## Tracking

<!-- Use at least one. Use a closing keyword when this PR completes a GitHub issue. -->

Fixes #
Jira: MTA-
```

This prevents avoidable check failures and documents the policy where authors create PRs.

## Jira availability and failure policy

For `main`, a Jira API outage should not block a PR that contains a syntactically valid Jira key. Report the lookup failure as a warning because the stated main-branch policy requires the regex, not target validation.

For `release-*`, fail closed when Jira target data cannot be read. A release assignment cannot be verified without it. Distinguish these outcomes:

- ticket does not exist;
- ticket exists but has no target;
- target does not match;
- Jira API is unavailable;
- Jira authentication failed.

Use retries for transient `429` and `5xx` responses. Never print credentials or complete Jira responses to logs.

## Exceptions

Prefer creating a small tracking issue over adding a broad bypass. Documentation automation, dependency updates, and CI maintenance still represent work that can be tracked.

If an exception is necessary, use one label such as `tracking-exempt` with all of these requirements:

- only repository maintainers can apply it;
- the PR body contains `Tracking-Exemption: <reason>`;
- the check summary records who applied the label and the reason;
- release PRs cannot use the exception unless an approver has approved the PR.

Do not silently exempt bot-authored PRs or particular title prefixes.

## Rollout

1. Add the PR template and update the cherry-pick workflow.
2. Run `verify-pr-tracking` in audit mode for at least two weeks.
3. Publish failures in the job summary without failing the job.
4. Fix or explicitly classify the 12 currently open PRs that have no reference.
5. Confirm the Jira Target Version policy and populate release tickets. `MTA-819`, for example, currently has neither Target Version nor Fix Version.
6. Make the check required for `main`.
7. Enable strict release validation only after active release branches have matching milestones and Jira targets.
8. Add the stable `verify-pr-tracking` context to the documented merge policy and branch ruleset.

## Test cases

The validator needs unit or integration coverage for:

- `main` with one closing GitHub issue;
- `main` with one valid Jira key;
- `main` with both forms;
- `main` with only `#123` text and no closing reference;
- `main` with malformed or lowercase Jira text;
- `release-0.11` with milestone `v0.11.2`;
- `release-0.11` with no milestone;
- `release-0.11` with milestone `v0.12.0`;
- `release-0.11` with Jira Target Version `0.11`;
- a patch branch such as `release-1.7.3` with exact target matching;
- multiple references where one target mismatches;
- a closed issue with a matching milestone;
- Jira `404`, `401`, `429`, and `5xx` responses;
- a fork PR containing shell syntax in its title or body;
- a bot-authored PR without tracking;
- a cherry-pick PR carrying references from its source PR.
