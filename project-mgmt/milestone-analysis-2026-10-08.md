# Crane milestone analysis

Snapshot date: 2026-10-08

## Scope

This analysis covers the repositories listed in `repositories.yaml`. It uses GitHub's current open-milestone, issue, pull request, and release data. Counts shown by GitHub for a milestone include both issues and pull requests.

## Current state

Only `migtools/crane` and `migtools/crane-lib` have open milestones. The four remaining configured repositories have no release milestones:

- `migtools/crane-plugin-buildconfig-to-builds`
- `migtools/crane-plugin-openshift`
- `migtools/rsync-transfer`
- `migtools/mta-crane`

`migtools/crane` has eight open milestones. Six have no due date, two are empty, and 43 currently open issues have no milestone. All eight milestone descriptions are empty or unset.

| Milestone | Open issues | Open PRs | Closed items | Due date | Assessment |
| --- | ---: | ---: | ---: | --- | --- |
| [`v0.11.0`](https://github.com/migtools/crane/milestone/1) | 24 | 1 | 156 | None | Release was published; milestone should be reconciled. |
| [`v0.11.1`](https://github.com/migtools/crane/milestone/6) | 4 | 0 | 5 | 2026-10-13 | Near-term patch release. |
| [`v0.11.2`](https://github.com/migtools/crane/milestone/7) | 10 | 0 | 1 | 2026-10-27 | Planned patch release. |
| [`v0.11.3`](https://github.com/migtools/crane/milestone/8) | 5 | 0 | 0 | None | Release intent exists without schedule. |
| [`v0.12.0`](https://github.com/migtools/crane/milestone/2) | 6 | 0 | 0 | None | Next minor release without schedule. |
| [`future`](https://github.com/migtools/crane/milestone/5) | 5 | 1 | 2 | None | Backlog bucket; define its entry and exit rules. |
| [`v0.10.0`](https://github.com/migtools/crane/milestone/3) | 0 | 0 | 169 | None | Empty open milestone for a released version. |
| [`release-0.10`](https://github.com/migtools/crane/milestone/4) | 0 | 0 | 0 | None | Empty open milestone. |

`migtools/crane-lib` has one empty open [`v0.11`](https://github.com/migtools/crane-lib/milestone/1) milestone with one closed item and no due date. Its 17 open issues are unassigned to a milestone.

## Release mismatch

The latest published Crane release is [`v0.11.0`](https://github.com/migtools/crane/releases/tag/v0.11.0), published on 2026-10-02. Its corresponding milestone remains open with 25 items.

This does not necessarily mean every item must be closed. It does mean release completion is not being reflected in milestone state. Before closing the milestone, maintainers should move deferred work to a later milestone or the backlog and verify that remaining open pull requests are intentional.

The `v0.11.0` milestone is dominated by test and automation work. It contains 24 issues and one pull request. Several items were last updated in July, including `crane#709` through `crane#721`. They need an explicit decision rather than being silently carried into a closed release milestone.

## Upcoming releases

`v0.11.1` is due on 2026-10-13. Its four open issues cover OpenShift 5 compatibility, indirect cloud-storage documentation, and transfer failure reporting:

- [`crane#408`](https://github.com/migtools/crane/issues/408)
- [`crane#980`](https://github.com/migtools/crane/issues/980)
- [`crane#1001`](https://github.com/migtools/crane/issues/1001)
- [`crane#1030`](https://github.com/migtools/crane/issues/1030)

`v0.11.2` is due on 2026-10-27 and has ten open issues. The scope combines transfer-pvc reliability, plugin-manager behavior, Kustomize instructions, and CLI progress summaries. It has no recorded effort estimates in Project 24, so schedule feasibility cannot be derived from the current fields.

Neither `v0.11.3` nor `v0.12.0` has a due date. They should remain unscheduled backlog containers unless the team sets an expected release date and uses the milestone as an actual delivery commitment.

## Cross-repository planning gap

The planned Crane implementation spans several repositories, but only the main `crane` repository has active release milestones. The BuildConfig plugin, OpenShift plugin, rsync transfer component, and MTA integration repository cannot express release assignment in their local issue trackers.

Project 24 can show cross-repository priority and sprint work. It does not replace repository milestones because a GitHub milestone belongs to one repository. For work that must ship together, use a parent issue or Project 24 item as the cross-repository release record, and assign matching local milestones only where they exist.

## Recommended workflow

1. Treat a repository milestone as a release scope, not a generic bucket.
2. Give every release milestone a description, due date, and explicit exit rule.
3. Before publishing a release, review every open milestone item. Close it, move it to the next release, or move it to the backlog.
4. After publication, close the milestone once no intentionally deferred items remain.
5. Close empty milestones for already released versions, including `v0.10.0` and `release-0.10`, after confirming they have no external reporting dependency.
6. Keep `future` only if its role is documented. Otherwise use no milestone for unscheduled work.
7. Require a milestone when an issue is committed to a release, but do not require one for untriaged or exploratory work.
8. Add matching release milestones to dependent repositories only when those repositories release independently. Otherwise track their contribution through the parent release issue in Project 24.
9. Add a read-only weekly check that reports open milestones without due dates, empty open milestones, released versions with open milestones, and open release issues without a milestone.

The generated `backlog-status.md` now includes an Open milestones table and a Milestone hygiene table. Run `python3 project-mgmt/update_backlog.py` to refresh those values.
