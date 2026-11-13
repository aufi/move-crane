# EnMaaS review, code, and fix validation, November 13, 2026

## Activation

Review, code, and manual fix verification all passed on the live GitHub Actions
path. The resulting implementation PR remains open for human review.

[PR #18](https://github.com/aufi/crane-fullsend-pilot/pull/18) enabled review,
code, and fix after the successful triage test in the
[deployment record](FULLSEND_ENMAAS_DEPLOYMENT_2026-11-13.md). It passed its CI
checks and was merged by the operator at 14:55:28 UTC as
`a50a572fb7cd7f1de3edc137a933ba56a8b479ac`.

All four agents use Fullsend v0.55.0, pi, and
`gateway/rits/deepseek-ai/DeepSeek-V4.1-Flash-1017` through EnMaaS. Harnesses and
review-persona model overrides retain their existing v0.55.0 pins. Triage stays
manual with automatic code promotion off; retro and prioritize remain disabled.
Review, code, and fix use the fleet triggers, including automatic PR review and
eligible review-triggered fixes.

After these lifecycle checks, [PR #23](https://github.com/aufi/crane-fullsend-pilot/pull/23)
raised the review finding threshold to `medium` in both runner and sandbox
environments. It passed Fullsend lint and required CI and was merged as
`7977fbb01054a43733b3956519b733675f14a93b`. The registered local review harness
and both threshold values were verified on `main`. The persona roster and
model overrides were preserved. The run measurements below predate this
reporting-threshold change.

## Review verification

- Subject: [PR #15](https://github.com/aufi/crane-fullsend-pilot/pull/15), a small
  existing fix for Kustomize path separators.
- Trigger: human [`/fs-review`](https://github.com/aufi/crane-fullsend-pilot/pull/15#issuecomment-6856585762).
- Run: [43447504422](https://github.com/aufi/crane-fullsend-pilot/actions/runs/43447504422), successful.
- Reviewed head: `a56857c8a42f145f6b7deb10b9123cb1da1e2ce0`.
- Outcome: schema-valid `action: approve`, two low-severity advisory findings,
  and a published GitHub approval. The PR was not merged.

Bootstrap registered all ten configured review personas on the exact gateway
model. Seven personas actually ran: correctness, security, intent-coherence,
style-conventions, docs-currency, risk-assessment, and challenger. Each completed
with `isError: false` and the same gateway model in the child-usage record.
The other registered personas were not exercised by this diff.

| Measurement | Recorded value |
| --- | --- |
| Parent agent execution | 442.6 s |
| Iterations / parent turns | 1 / 29 |
| Parent tool calls / tool errors | 49 / 3 |
| Unanswered tool calls | 0 |
| Input / cache-read tokens, including children | 147,392 / 2,227,008 |
| Output tokens, including children | 48,439 |
| Runtime-reported estimated cost, including children | USD 0.117933456 |

The final structured result, submitted approval, child transcripts, and
`per_model_usage` establish the review lifecycle and gateway delegation. Merely
registering a persona would not establish that it executed.

## Code verification

- Task: [issue #19](https://github.com/aufi/crane-fullsend-pilot/issues/19), a
  real defect in the E2E `HasFilesRecursively` helper. A filename containing the
  display marker `(no files)` could incorrectly indicate an empty directory.
- Trigger: human [`/fs-code`](https://github.com/aufi/crane-fullsend-pilot/issues/19#issuecomment-6856727362).
- Run: [43448317571](https://github.com/aufi/crane-fullsend-pilot/actions/runs/43448317571), successful.
- Published change: [PR #20](https://github.com/aufi/crane-fullsend-pilot/pull/20),
  initial head `0865fb688a3efa04bdb98bbabac881d45a3b7be2`.

The agent changed only `e2e-tests/utils/utils.go` and its test file, deriving
presence from discovered files and sharing the listing renderer. The transcript
shows the new regression failing on the old implementation with `false, want
true`, and passing after the fix. It also covers ordinary files, an empty
directory, and a missing-directory error.

The agent ran the focused utility tests, build, selected cluster-free unit
packages, E2E package compilation, and targeted vet. Sandbox execution through
`make` failed with `Operation not permitted`, so the agent used the underlying
commands and disclosed that in the PR. Its repository-wide formatting check
reported existing unrelated issues. No live Kubernetes test was performed.

| Measurement | Recorded value |
| --- | --- |
| Agent execution | 370.2 s |
| Iterations / turns | 1 / 31 |
| Tool calls / tool errors | 38 / 0 |
| Input / cache-read tokens | 60,293 / 1,672,128 |
| Output / reported reasoning tokens | 11,693 / 5,064 |
| Runtime-reported estimated cost | USD 0.043824396 |

Build/unit CI and lint passed on the initial PR. The title-convention check
failed because the generated title had no required emoji-code prefix. This
became the real CI failure used by the fix verification below; code-agent
success did not mean all PR checks were already green.

## Fix verification

- Subject: PR #20.
- Trigger: human [`/fs-fix` with a narrow instruction](https://github.com/aufi/crane-fullsend-pilot/pull/20#issuecomment-6857298685).
- Run: [43452131447](https://github.com/aufi/crane-fullsend-pilot/actions/runs/43452131447), successful.
- Requested work: inspect the failed title check, add the required `:bug:`
  prefix, and extend the existing helper test with a marker-like nested
  directory containing a real file and an entirely empty nested directory tree.

The agent inspected the failing title-check log and classified it as
`pr-related` in `ci_inspections`. Its schema-valid result proposed the corrected
title through `pr_title` with a hash of the previous title. The post-script
applied the proposal, changing the title to
`:bug: fix(#19): derive HasFilesRecursively presence from files`.

Commit `5a0475e2701fea18e5687e32c3572bf9ebb8bc04` adds the two requested cases,
changing only `e2e-tests/utils/utils_test.go`, with 28 added lines. The helper
implementation was left unchanged. The agent reported passing focused utility
tests, vet, build, selected cluster-free unit packages, and compile-only E2E
checks. It again disclosed pre-existing formatting failures outside its new
lines.

All required checks on the updated PR passed:

- [Build and unit test](https://github.com/aufi/crane-fullsend-pilot/actions/runs/43453521760).
- [golangci-lint](https://github.com/aufi/crane-fullsend-pilot/actions/runs/43453521856).
- [Verify PR contents](https://github.com/aufi/crane-fullsend-pilot/actions/runs/43453526872).

| Measurement | Recorded value |
| --- | --- |
| Fix job duration, including setup | 8 min 17 s |
| Agent execution | 361.0 s |
| Iterations / turns | 1 / 26 |
| Tool calls / tool errors | 36 / 3 |
| Unanswered tool calls | 0 |
| Input / cache-read tokens | 51,508 / 1,104,960 |
| Output / reported reasoning tokens | 9,943 / 4,305 |
| Runtime-reported estimated cost | USD 0.035118720 |

The new commit, applied PR-title update, successful post-script, and passing
required CI establish the manual fix lifecycle. The implementation PR remains
open and unmerged. Automatic review-triggered fixes were not required for this
verification.

## Result and follow-up

The explicitly triggered review, code, and fix runs all served the selected
DeepSeek model on pi. Their combined runtime-reported estimated cost was
USD 0.196876572, excluding triage and automatic or operator-triggered runs
outside these three verification runs. Reconcile actual charges with EnMaaS.

Review delegation, regression-driven implementation, PR creation, CI
inspection, PR metadata updates, and publication of a follow-up commit have
been exercised. The active configuration can now be used for further pilot
tasks. The next infrastructure milestone is live-cluster E2E execution under
the assignment below, rather than additional inference setup.

## Observed limitations

- A secondary PR-label event on the older PR #15 failed harness dispatch in
  [run 43447672347](https://github.com/aufi/crane-fullsend-pilot/actions/runs/43447672347).
  Its configuration load encountered the removed `create_issues` key in an
  older PR revision. The explicitly triggered review succeeded with the current
  default-branch config. Older PR revisions need configuration/base alignment
  before assuming every event path works after the schema upgrade.
- Review prefetch warned that review-thread data was invalid or truncated, so
  human dismissals could not be fully verified in that run.
- Sandbox `make` subprocess failures and catalog-based cost estimates remain
  distinct from inference compatibility. Cost figures above are runtime
  estimates, not reconciled EnMaaS charges.

These lifecycle checks use an existing small PR and cluster-free E2E helper
tests. They do not establish live minikube, OpenShift, or CRC test execution;
that remains under the [E2E assignment](FULLSEND_E2E_IMPLEMENTATION_ASSIGNMENT.md).
