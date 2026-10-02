# Crane development backlog analysis

Snapshot date: 2026-09-30

## Purpose

This document records the current state of open issues, pull requests, repository metadata, and GitHub Project 24. It provides a baseline for deciding which planning and development processes should be automated.

No project items, issues, pull requests, labels, milestones, or repository settings were changed during this analysis.

## Scope and method

The analysis covers the repositories listed in `repositories.yaml`:

- `migtools/crane`
- `migtools/crane-lib`
- `migtools/crane-plugin-buildconfig-to-builds`
- `migtools/crane-plugin-openshift`
- `migtools/rsync-transfer`

Data was read with GitHub REST and GraphQL APIs through `gh`. Open issue counts exclude pull requests. Project membership was matched by issue or pull request URL. Label and theme counts can overlap because one item can have several labels or match several title patterns.

GitHub Project 24 changed while data was being collected. Its auto-add workflow added `crane#1035`, increasing the selected-repository item count from 528 to 529. Counts in this document use the later joined backlog snapshot where possible. This also demonstrates why future reports should record a collection timestamp and tolerate live changes.

## Executive findings

- The five repositories have 124 open issues and 23 open pull requests.
- `migtools/crane` contains 102 of 124 open issues and 20 of 23 open pull requests.
- Project 24 contains 99 of 124 open issues, 79.8%, but only 2 of 23 open pull requests, 8.7%.
- Every open item from `crane-lib`, `crane-plugin-buildconfig-to-builds`, and `rsync-transfer` is absent from Project 24. `crane-plugin-openshift` currently has no open work.
- The active project backlog has 98 items. Priority is set on 52, Size on 2, and Sprint on 40. Estimate, Start date, and Target date have no observed values.
- Twenty-four open items still belong to Sprint 9, which ended on 2026-09-20. Sixteen open items belong to Sprint 10.
- Three open items are marked `Done` in Project 24.
- `crane-lib` has 17 open issues, all created and last updated in 2021. It has no open pull request and none of its open issues is in Project 24.
- The `crane` pull request queue has substantial review and CI pressure: 8 of 20 PRs have failing checks, 10 are pending, 15 require review, and 3 have requested changes.
- Repository label catalogs are inconsistent. Four repositories carry a large Prow-style catalog, while the BuildConfig plugin has only 12 mostly default GitHub labels.
- Release assignment is incomplete. Forty-one of 102 open `crane` issues have no milestone; all open issues in `crane-lib` and the BuildConfig plugin have no milestone.

## Repository overview

| Repository | Open issues | Open PRs | Unlabeled issues | Unassigned issues | Issues without milestone | Project coverage of open work |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [`migtools/crane`](https://github.com/migtools/crane) | [102](https://github.com/migtools/crane/issues?q=is%3Aissue%20is%3Aopen) | [20](https://github.com/migtools/crane/pulls?q=is%3Apr%20is%3Aopen) | [8](https://github.com/migtools/crane/issues?q=is%3Aissue%20is%3Aopen%20no%3Alabel) | [44](https://github.com/migtools/crane/issues?q=is%3Aissue%20is%3Aopen%20no%3Aassignee) | [41](https://github.com/migtools/crane/issues?q=is%3Aissue%20is%3Aopen%20no%3Amilestone) | [101/122](https://github.com/orgs/migtools/projects/24) |
| [`migtools/crane-lib`](https://github.com/migtools/crane-lib) | [17](https://github.com/migtools/crane-lib/issues?q=is%3Aissue%20is%3Aopen) | [0](https://github.com/migtools/crane-lib/pulls?q=is%3Apr%20is%3Aopen) | [4](https://github.com/migtools/crane-lib/issues?q=is%3Aissue%20is%3Aopen%20no%3Alabel) | [11](https://github.com/migtools/crane-lib/issues?q=is%3Aissue%20is%3Aopen%20no%3Aassignee) | [17](https://github.com/migtools/crane-lib/issues?q=is%3Aissue%20is%3Aopen%20no%3Amilestone) | [0/17](https://github.com/orgs/migtools/projects/24) |
| [`migtools/crane-plugin-buildconfig-to-builds`](https://github.com/migtools/crane-plugin-buildconfig-to-builds) | [5](https://github.com/migtools/crane-plugin-buildconfig-to-builds/issues?q=is%3Aissue%20is%3Aopen) | [2](https://github.com/migtools/crane-plugin-buildconfig-to-builds/pulls?q=is%3Apr%20is%3Aopen) | [4](https://github.com/migtools/crane-plugin-buildconfig-to-builds/issues?q=is%3Aissue%20is%3Aopen%20no%3Alabel) | [3](https://github.com/migtools/crane-plugin-buildconfig-to-builds/issues?q=is%3Aissue%20is%3Aopen%20no%3Aassignee) | [5](https://github.com/migtools/crane-plugin-buildconfig-to-builds/issues?q=is%3Aissue%20is%3Aopen%20no%3Amilestone) | [0/7](https://github.com/orgs/migtools/projects/24) |
| [`migtools/crane-plugin-openshift`](https://github.com/migtools/crane-plugin-openshift) | [0](https://github.com/migtools/crane-plugin-openshift/issues?q=is%3Aissue%20is%3Aopen) | [0](https://github.com/migtools/crane-plugin-openshift/pulls?q=is%3Apr%20is%3Aopen) | 0 | 0 | 0 | [No open work](https://github.com/orgs/migtools/projects/24) |
| [`migtools/rsync-transfer`](https://github.com/migtools/rsync-transfer) | [0](https://github.com/migtools/rsync-transfer/issues?q=is%3Aissue%20is%3Aopen) | [1](https://github.com/migtools/rsync-transfer/pulls?q=is%3Apr%20is%3Aopen) | 0 | 0 | 0 | [0/1](https://github.com/orgs/migtools/projects/24) |
| Total | 124 | 23 | 16 | 58 | 63 | 101/147 |

The `crane` project coverage includes 99 issues and 2 pull requests. One included PR, `crane#885`, is open but marked `Done` in the project.

## Issue backlog

### migtools/crane

Open issue age based on creation date:

| Age | Count | Share |
| --- | ---: | ---: |
| Less than 30 days | 35 | 34.3% |
| 30 to 89 days | 29 | 28.4% |
| 90 to 179 days | 24 | 23.5% |
| 180 to 364 days | 1 | 1.0% |
| At least 365 days | 13 | 12.7% |

The oldest open issue is [`crane#28`](https://github.com/migtools/crane/issues/28), created on 2021-08-24. The newest at collection time is [`crane#1035`](https://github.com/migtools/crane/issues/1035), created on 2026-09-30.

Recent activity makes creation age alone unsuitable for automatic closure. None of the 102 issues had gone a full year without an update, and 69 were updated in the previous 30 days. A stale policy must distinguish old but active work from abandoned work.

Thematic title matches show where the backlog is concentrated:

| Theme | Matching open issues |
| --- | ---: |
| Testing, E2E, automation, or Polarion | 44 |
| PVC transfer, rsync, rclone, StorageClass, or data migration | 30 |
| Validation, export, apply, or resource handling | 18 |
| Plugins, transform, Kustomize, or patches | 15 |
| Release, CI, documentation, pipelines, or workflows | 13 |
| BuildConfig, Shipwright, or Buildah | 5 |

These categories overlap. They still show that test automation and data transfer dominate current work.

Issue label usage is sparse compared with the 93 labels available in the repository:

| Metadata | Covered issues | Coverage |
| --- | ---: | ---: |
| Any `kind/*` label | 47 | 46.1% |
| `test` or `test/infra` | 42 | 41.2% |
| Any `priority/*` label | 2 | 2.0% |
| Any `triage/*` label | 1 | 1.0% |

The most used issue labels are `test` on 39 issues, `kind/bug` on 24, `kind/feature` on 23, `jira` on 5, and `story` on 4. Eight issues have no label at all, including current release and compatibility work such as `crane#1018`, `crane#1020`, `crane#1021`, `crane#1030`, and `crane#1035`.

Assignee distribution is concentrated but incomplete. Forty-four issues are unassigned. The largest assigned queues belong to `midays` with 13, `nachandr` with 10, `msajidmansoori12` with 9, `stillalearner` with 7, and `Tamar-Dinavetsky` with 6. Assignment count is not a workload estimate because issue size is mostly unknown.

### migtools/crane-lib

All 17 open issues were created in 2021 and all 17 were last updated more than a year ago. Eleven are unassigned, four are unlabeled, and none has a release milestone or Project 24 membership.

The issues cluster around old state-transfer behavior, transform and apply APIs, validation, logging, naming limits, and error handling. Examples include:

- [`crane-lib#5`](https://github.com/migtools/crane-lib/issues/5), applying one patch to every instance of a GVK
- [`crane-lib#13`](https://github.com/migtools/crane-lib/issues/13), validating binary plugin output
- [`crane-lib#24`](https://github.com/migtools/crane-lib/issues/24), waiting for created resources to reach an expected state
- [`crane-lib#28`](https://github.com/migtools/crane-lib/issues/28), endpoint readiness validation
- [`crane-lib#49`](https://github.com/migtools/crane-lib/issues/49), a versioned `PluginRequest`
- [`crane-lib#89`](https://github.com/migtools/crane-lib/issues/89), safe version checking

This backlog should not be imported into active planning without manual validation. Some issues may already be obsolete, implemented elsewhere, or superseded by current Crane designs.

### migtools/crane-plugin-buildconfig-to-builds

The repository has five open issues, all created between 2026-08-24 and 2026-09-25:

| Issue | Topic | Labels | Assignee |
| --- | --- | --- | --- |
| [`#46`](https://github.com/migtools/crane-plugin-buildconfig-to-builds/issues/46) | Migrate BuildConfig ServiceAccount and RBAC | None | None |
| [`#72`](https://github.com/migtools/crane-plugin-buildconfig-to-builds/issues/72) | Filtered resource pipeline | None | None |
| [`#98`](https://github.com/migtools/crane-plugin-buildconfig-to-builds/issues/98) | Cluster CI strategy source | `bug` | None |
| [`#101`](https://github.com/migtools/crane-plugin-buildconfig-to-builds/issues/101) | Verify `mta-crane` after dependency changes | None | `psrvere` |
| [`#102`](https://github.com/migtools/crane-plugin-buildconfig-to-builds/issues/102) | Git proxy behavior | None | `psrvere` |

None has a milestone or Project 24 membership. Four of five are unlabeled. This is active work that is invisible in the cross-repository planning project.

### migtools/crane-plugin-openshift

There are no open issues or pull requests. Project 24 contains five historical items from this repository, all in terminal states. The lack of open items may be valid, but planned work such as DeploymentConfig conversion currently appears as issues in `migtools/crane`, not in the plugin repository.

### migtools/rsync-transfer

There are no open issues. The only open pull request is [`rsync-transfer#77`](https://github.com/migtools/rsync-transfer/pull/77), which adds a minimal README. It requires review, is blocked, has pending checks, and has no labels, assignee, milestone, or Project 24 membership.

## Pull request pipeline

### Overall

| Repository | Open PRs | Drafts | Unlabeled | Unassigned | Without milestone |
| --- | ---: | ---: | ---: | ---: | ---: |
| [`migtools/crane`](https://github.com/migtools/crane/pulls?q=is%3Apr%20is%3Aopen) | 20 | 2 | 9 | 7 | 18 |
| [`migtools/crane-lib`](https://github.com/migtools/crane-lib/pulls?q=is%3Apr%20is%3Aopen) | 0 | 0 | 0 | 0 | 0 |
| [`migtools/crane-plugin-buildconfig-to-builds`](https://github.com/migtools/crane-plugin-buildconfig-to-builds/pulls?q=is%3Apr%20is%3Aopen) | 2 | 0 | 2 | 2 | 2 |
| [`migtools/crane-plugin-openshift`](https://github.com/migtools/crane-plugin-openshift/pulls?q=is%3Apr%20is%3Aopen) | 0 | 0 | 0 | 0 | 0 |
| [`migtools/rsync-transfer`](https://github.com/migtools/rsync-transfer/pulls?q=is%3Apr%20is%3Aopen) | 1 | 0 | 1 | 1 | 1 |

### migtools/crane review state

| Signal | Distribution |
| --- | --- |
| Review decision | 15 review required, 3 changes requested, 1 approved, 1 unset |
| Checks | 8 failing, 10 pending, 1 passing, 1 without checks |
| Merge state | 11 unknown, 6 blocked, 2 dirty, 1 clean |
| Age | 10 under 30 days, 7 from 30 to 89 days, 3 at least 90 days |

The oldest open PR is [`crane#355`](https://github.com/migtools/crane/pull/355), created on 2026-05-06. It has requested changes and a dirty merge state. Three PRs had not been updated in the previous 30 days.

Only these open PRs are represented in Project 24:

- [`crane#693`](https://github.com/migtools/crane/pull/693), Project status `Todo`, Sprint 9
- [`crane#885`](https://github.com/migtools/crane/pull/885), Project status `Done` despite the PR remaining open

The other 21 open PRs across the five repositories are not project items. This appears intentional or systemic rather than accidental. Planning automation should decide whether PRs are project items or operational signals linked to issue items. Mixing both models would create duplicate work and unreliable status counts.

## Labels

| Repository | Available labels | Label model |
| --- | ---: | --- |
| [`migtools/crane`](https://github.com/migtools/crane/labels) | 93 | Prow-style plus local and legacy labels |
| [`migtools/crane-lib`](https://github.com/migtools/crane-lib/labels) | 84 | Prow-style plus library area labels |
| [`migtools/crane-plugin-buildconfig-to-builds`](https://github.com/migtools/crane-plugin-buildconfig-to-builds/labels) | 12 | Mostly GitHub defaults plus `go` and `hold` |
| [`migtools/crane-plugin-openshift`](https://github.com/migtools/crane-plugin-openshift/labels) | 80 | Prow-style |
| [`migtools/rsync-transfer`](https://github.com/migtools/rsync-transfer/labels) | 78 | Prow-style |

Material inconsistencies:

- The BuildConfig plugin uses `bug` and `enhancement`; the other repositories use `kind/bug` and `kind/feature`.
- `crane` contains overlapping priority families such as `priority/critical`, `priority/critical-urgent`, `priority/major`, `priority/important-soon`, `priority/minor`, and `priority/backlog`.
- Project 24 has a separate Priority field with `Urgent`, `High`, `Medium`, and `Low`. Repository priority labels and project priority are not synchronized.
- `crane` has both `documentation` and `kind/documentation`.
- Several workflow-oriented labels are available but rarely used on the open issue backlog.
- Large label catalogs do not imply good metadata coverage. `crane` has 93 labels, but only 46.1% of open issues have a `kind/*` label.

A central label declaration similar to `konveyor/release-tools` would help, but the desired taxonomy must be selected before synchronization. Copying all existing labels would preserve duplication rather than fix it.

## Milestones

`migtools/crane` has eight open milestones:

| Milestone | Open items reported by GitHub | Due date |
| --- | ---: | --- |
| [`v0.11.0`](https://github.com/migtools/crane/milestone/1) | 28 | None |
| [`v0.11.1`](https://github.com/migtools/crane/milestone/6) | 7 | 2026-10-13 |
| [`v0.11.2`](https://github.com/migtools/crane/milestone/7) | 10 | 2026-10-27 |
| [`v0.11.3`](https://github.com/migtools/crane/milestone/8) | 5 | None |
| [`v0.12.0`](https://github.com/migtools/crane/milestone/2) | 6 | None |
| [`future`](https://github.com/migtools/crane/milestone/5) | 7 | None |
| [`v0.10.0`](https://github.com/migtools/crane/milestone/3) | 0 | None |
| [`release-0.10`](https://github.com/migtools/crane/milestone/4) | 0 | None |

GitHub's milestone item count includes pull requests. The open issue-only distribution is 27 for `v0.11.0`, 7 for `v0.11.1`, 10 for `v0.11.2`, 5 for `v0.11.3`, 6 for `v0.12.0`, 6 for `future`, and 41 without a milestone.

Only `v0.11.1` and `v0.11.2` have due dates. Two empty `v0.10` milestones remain open. `crane-lib` has one open and empty `v0.11` milestone. The other repositories have no open milestones.

Milestones currently provide only partial release planning. They should remain distinct from Sprint, which represents a timeboxed work iteration.

## GitHub Project 24

### Project model

Project 24 is named `Crane Development`. At the initial read it reported 574 items and 19 fields. Relevant fields are:

- `Status`: Todo, In progress, In review, Done, Closed
- `Priority`: Urgent, High, Medium, Low
- `Size`: X-Large, Large, Medium, Small, Tiny
- `Estimate`: numeric field
- `Sprint`: iteration field
- `Start date` and `Target date`
- built-in repository, labels, milestone, assignees, reviewers, linked pull requests, parent issue, and sub-issue progress fields

The project has these enabled built-in workflows:

- Auto-add sub-issues to project
- Auto-add to project
- Auto-close issue
- Item added to project
- Item closed
- Pull request linked to issue
- Pull request merged

The API exposes workflow names and enabled state but not their filters and actions. Current coverage shows that the auto-add rules do not cover all five repositories or all historical open issues.

### Repository representation

The later project query found 529 historical items from the five configured repositories:

| Repository | Project items |
| --- | ---: |
| [`migtools/crane`](https://github.com/orgs/migtools/projects/24) | 518 |
| [`migtools/crane-lib`](https://github.com/orgs/migtools/projects/24) | 3 |
| [`migtools/crane-plugin-buildconfig-to-builds`](https://github.com/orgs/migtools/projects/24) | 3 |
| [`migtools/crane-plugin-openshift`](https://github.com/orgs/migtools/projects/24) | 5 |
| [`migtools/rsync-transfer`](https://github.com/orgs/migtools/projects/24) | 0 |

Historical presence does not mean current backlog coverage. All open items outside `crane` are absent.

### Open backlog coverage

| Repository | Open issues in project | Open PRs in project | Missing open issues | Missing open PRs |
| --- | ---: | ---: | ---: | ---: |
| [`migtools/crane`](https://github.com/orgs/migtools/projects/24) | 99/102 | 2/20 | 3 | 18 |
| [`migtools/crane-lib`](https://github.com/orgs/migtools/projects/24) | 0/17 | 0/0 | 17 | 0 |
| [`migtools/crane-plugin-buildconfig-to-builds`](https://github.com/orgs/migtools/projects/24) | 0/5 | 0/2 | 5 | 2 |
| [`migtools/crane-plugin-openshift`](https://github.com/orgs/migtools/projects/24) | 0/0 | 0/0 | 0 | 0 |
| [`migtools/rsync-transfer`](https://github.com/orgs/migtools/projects/24) | 0/0 | 0/1 | 0 | 1 |

The three missing `crane` issues are [`#282`](https://github.com/migtools/crane/issues/282), [`#294`](https://github.com/migtools/crane/issues/294), and [`#317`](https://github.com/migtools/crane/issues/317). All are older test automation issues.

### Active field coverage

The 98 project items with `Todo`, `In progress`, or `In review` status have this metadata coverage:

| Field | Set | Coverage |
| --- | ---: | ---: |
| Status | 98 | 100% |
| Priority | 52 | 53.1% |
| Sprint | 40 | 40.8% |
| Size | 2 | 2.0% |
| Estimate | 0 observed | 0% |
| Start date | 0 observed | 0% |
| Target date | 0 observed | 0% |

Priority coverage by active status:

| Status | Total | Without priority |
| --- | ---: | ---: |
| Todo | 65 | 24 |
| In progress | 24 | 16 |
| In review | 9 | 6 |

Size and Estimate are too sparse to support capacity planning. Sprint counts currently measure assignment, not planned capacity.

### Sprint hygiene

Among the 101 open items represented in the project:

- 61 have no Sprint.
- 24 remain in Sprint 9, which started on 2026-08-31 and ended on 2026-09-20.
- 16 are in Sprint 10, which started on 2026-09-21.

Sprint 9 still contains open work in every active status, including old Todo items, active implementation, review work, and `crane#693`. A sprint rollover process is missing or not consistently followed.

### State inconsistencies

These open items are marked `Done`:

- [`crane#347`](https://github.com/migtools/crane/issues/347), "Automate Multiple ImageStream tags"
- [`crane#399`](https://github.com/migtools/crane/issues/399), a Sync2Jira test issue
- [`crane#885`](https://github.com/migtools/crane/pull/885), E2E tests for export GK filtering

No duplicate project items were found by content URL.

## Recommended planning model

The following model should be agreed before implementation:

| Concern | Recommended source of truth |
| --- | --- |
| Work lifecycle | Project `Status` |
| Business or delivery priority | Project `Priority` |
| Relative effort | Project `Size` or `Estimate`, but not both initially |
| Iteration commitment | Project `Sprint` |
| Release assignment | Repository milestone |
| Work type | Repository `kind/*` label |
| Component or area | Repository `area/*` or a small Crane-specific area taxonomy |
| Ownership | GitHub assignee |
| Implementation linkage | Linked pull requests and sub-issues |

Priority should not be maintained independently as both repository labels and a project field unless an explicit two-way synchronization rule exists. The project field is better suited to cross-repository sorting and reporting.

Issues should be planning units. Pull requests should normally remain linked implementation artifacts rather than separate project items. A PR can move or signal the status of its linked issue, while a separate PR health report tracks review and CI. Exceptions can be allowed for standalone maintenance PRs with no issue.

## Automation recommendations

### 1. Build a read-only inventory and drift report first

Run a scheduled collector that reads the configured repositories and Project 24, then reports:

- open issues and PRs by repository;
- project inclusion and missing items;
- project status, priority, size, and sprint coverage;
- issue label, assignee, and milestone coverage;
- PR review, CI, mergeability, and inactivity state;
- open items in terminal project states;
- active items assigned to past sprints;
- duplicate project items and closed items in active states.

This should be the first automation because it is non-destructive and validates assumptions before write access is introduced.

### 2. Fix project intake rules

Configure or supplement Project 24 auto-add rules for new issues in all repositories from `repositories.yaml`. Set new items to `Todo`. Do not bulk-import the 17 old `crane-lib` issues until they have been triaged.

The existing auto-add workflow already caught `crane#1035`, but current coverage proves that its filters do not provide complete cross-repository intake.

### 3. Add metadata policy checks at lifecycle transitions

Do not require complete metadata when an issue is created. Require it when work moves to `In progress`:

- an assignee;
- Priority;
- Size or Estimate;
- current Sprint if the work is part of the sprint commitment;
- a milestone when the work targets a release.

The check should report violations before it starts changing data automatically. Sixteen of 24 current `In progress` items have no Priority, and almost all have no Size.

### 4. Add sprint rollover reporting

At sprint end, produce a list of nonterminal items and require an explicit choice: move to the next sprint, return to backlog, or close. Do not silently move every item. Automatic rollover would hide repeated carryover and make sprint metrics misleading.

The immediate cleanup set is the 24 open Sprint 9 items.

### 5. Add issue and project state reconciliation

Safe rules include:

- when an issue closes, set its project status to `Done` or `Closed` according to an agreed distinction;
- when an issue reopens, move a terminal project item back to `Todo` and flag it for triage;
- report open issues and PRs in terminal project states;
- report closed issues in active project states.

Do not infer `Done` merely because one linked PR merged. An issue may have multiple PRs or remaining acceptance criteria.

### 6. Add a separate pull request health report

Track PRs across all five repositories without requiring every PR to become a project item. Report:

- failing or missing required checks;
- review required or changes requested;
- merge conflicts and dirty branches;
- draft age;
- time since last update;
- missing linked issue;
- missing reviewers or owners;
- approved and green PRs ready to merge.

The current `crane` queue already justifies this: 18 of 20 PRs are either failing or pending, and only one is both represented as clean by GitHub and not waiting on an explicit review decision.

### 7. Define and reconcile a shared label taxonomy

Use the declarative pattern from `konveyor/release-tools`, but create a Crane-specific desired label set. Reconcile names, colors, and descriptions across repositories. Start with work type, area, lifecycle exceptions, and contribution labels.

Do not synchronize the current catalogs unchanged. Resolve `bug` versus `kind/bug`, `enhancement` versus `kind/feature`, duplicate documentation labels, and overlapping priority families first.

### 8. Add milestone hygiene checks

Report milestones that are open but empty, release milestones without due dates, items assigned to past releases, and active release work without a milestone. Closing empty `v0.10` milestones and deciding due dates for active releases are immediate manual cleanup candidates.

### 9. Triage legacy backlogs before stale automation

Review all 17 `crane-lib` issues manually and classify each as still valid, moved, duplicate, completed, or obsolete. Only after that should a stale workflow be enabled. Begin with labeling and notification; do not auto-close historical issues on the first pass.

### 10. Publish trend metrics after metadata stabilizes

Useful weekly metrics include backlog size, intake and closure rate, median issue age, sprint carryover, time in status, time to first PR review, PR cycle time, CI failure age, and metadata coverage. Baseline metrics should be segmented by repository and work type so the high-volume `crane` repository does not hide smaller components.

## Suggested implementation order

1. Read-only snapshot and drift report.
2. Manual cleanup of terminal-state mismatches and Sprint 9 carryover.
3. Decision on canonical fields, PR representation, and label taxonomy.
4. Auto-add rules for newly opened issues in all configured repositories.
5. Transition-time metadata checks.
6. PR health and review reporting.
7. State reconciliation with dry-run and audit output.
8. Declarative label and milestone reconciliation.
9. Historical backlog triage and cautious stale handling.
10. Trend dashboard and scheduled reports.

## Decisions required before write automation

- Whether `Done` and `Closed` represent different outcomes.
- Whether all issues, only accepted issues, or only scheduled issues belong in Project 24.
- Whether standalone PRs should be project items.
- Whether Priority lives only in Project 24 or is mirrored to labels.
- Whether planning uses Size or numeric Estimate.
- Which repositories share one label taxonomy and which need component-specific labels.
- Whether milestones are mandatory for `In progress` work or only release-bound work.
- Who owns sprint rollover and metadata exceptions.
- How old `crane-lib` issues should be handled before project import.

These decisions should be encoded in configuration before any automation receives write permissions.
