# Fullsend v0.44.0 for aufi/crane-fullsend-pilot

## Purpose

This runbook describes how to install Fullsend `v0.44.0` in the public
`aufi/crane-fullsend-pilot` repository. It enables issue triage, pull request
review, development from issues, and fixes based on review feedback. Fullsend
is installed for one repository. It must not merge changes or bypass protection
on the `main` branch.

This procedure was verified against upstream tag `v0.44.0`, released on
October 2, 2026. Before using another
version, review its release notes, workflows, GitHub App permissions, and
pinned OpenShell version.

## v0.44.0 Upgrade Requirements

This GitHub pilot is unaffected by the release's GitLab identity migration and
`repos.yaml` `config_base` rename. It must, however, upgrade its local
OpenShell installation before using Fullsend `v0.44.0`:

1. Install OpenShell `0.1.2` and migrate the local gateway configuration to
   schema v2 before any local run.
2. Declare credentials in every custom OpenShell provider. Do not rely on the
   pre-`0.1.2` implicit provider credential behavior.
3. Re-run the local smoke test after the OpenShell migration. Fullsend waits
   for OpenShell's initial settings poll before enabling sandbox networking;
   a policy or provider error is a failed test, not a warning.
4. Use OpenAI-only inference. Store the API key only as the
   `FULLSEND_OPENAI_API_KEY` GitHub Actions secret; do not add GCP or Vertex
   configuration to this pilot.

`fullsend agent new` is available for a later custom design agent, but is not
part of the initial triage, review, code, and fix pilot.

## Target repository

The pilot runs in <https://github.com/aufi/crane-fullsend-pilot>: a public,
disposable content copy of `migtools/crane` taken on September 21, 2026. It is
not a fork and has no upstream relationship.

An earlier revision of this runbook targeted `aufi/move-crane`. That target was
rejected for three reasons:

1. `move-crane` is a planning repository whose `AGENTS.md` prohibits production
   code, so the `coder` and `fix` agents could only ever produce documentation.
   That yields a weak signal for the decision recorded in
   `FULLSEND_MIGTOOLS_EVALUATION.md`, which proposes `migtools/crane` as the
   eventual candidate.
2. The `move-crane` working copy carries a large volume of unreviewed local
   artifacts (cluster dumps, exports, test-day output).
3. A Go repository with tests and CI gives the `review` and `fix` agents real
   material to work on.

The obvious alternative, the existing `aufi/crane` fork, was also rejected:
issues are disabled on it by default, it inherits 22 upstream workflows that
would fire on every agent branch, it holds roughly twenty personal working
branches, and pull requests created in a fork default to targeting
`migtools/crane`.

## Preconditions already satisfied

Completed on September 21, 2026. Re-verify before installation rather than
assuming.

| Item | State |
| --- | --- |
| Repository created, public, not a fork | Done |
| Issues enabled | Done |
| Wiki, Projects, Discussions disabled | Done |
| Workflows pruned to `go.yml`, `lint.yml`, `pr-title-check.yml` | Done |
| `main` branch protection | Done |
| Required status checks | `Build and unit test`, `golangci-lint`, `Verify PR contents`, strict |
| Required review | 1 approval, CODEOWNERS review, dismiss stale reviews |
| Force push and branch deletion on `main` | Blocked |
| `.github/CODEOWNERS` | Done, owner `@aufi` |
| `PILOT.md` and `AGENTS.md` banner | Done |
| Merge gate verified end to end | Done, throwaway PR #1, closed |

Verify with:

```bash
gh repo view aufi/crane-fullsend-pilot --json visibility,isFork,hasIssuesEnabled
gh api repos/aufi/crane-fullsend-pilot/branches/main/protection \
  -q '"reviews=\(.required_pull_request_reviews.required_approving_review_count) codeowners=\(.required_pull_request_reviews.require_code_owner_reviews) checks=\(.required_status_checks.contexts)"'
```

Two known properties of this setup:

- `enforce_admins` is deliberately **false**. A single-maintainer repository
  cannot self-approve, so the administrator needs a path to perform
  maintenance. The Fullsend Apps are not administrators and therefore cannot
  bypass protection. Do not grant them admin.
- `pr-title-check.yml` calls `konveyor/release-tools/cmd/verify-pr@main`, a
  floating ref inherited from upstream. Pin it to a commit SHA before enabling
  any agent that can open pull requests.

## Recorded decisions

| Decision | Value | Recorded |
| --- | --- | --- |
| Target repository | `aufi/crane-fullsend-pilot` | 2026-09-21 |
| Fullsend version | `v0.44.0` | 2026-10-02 |
| Runtime | `codex` | 2026-10-02 |
| Enabled roles | `triage,review,coder` from initial setup; controlled validation order | 2026-10-12 |
| Inference provider | OpenAI API key in GitHub Actions secret | 2026-10-02 |
| OpenAI project, budget, and key owner | **Open.** Required before section 8. | — |
| Token mint | **Open.** Community mint or private mint, see section 5. | — |
| Monthly budget and stop owner | **Open.** Required by section 11. | — |

## Scope and role phasing

Install all required roles in one setup so the pilot can exercise the complete
workflow. Still validate the roles in order: triage, review, code, then fix.
The `coder` role enables both the `code` and `fix` agents; only dedicated pilot
issues and pull requests may trigger its write capability.

| Validation order | Enabled roles | Capability exercised | Exit condition |
| --- | --- | --- | --- |
| 1 | `triage`, `review` | Comments, labels, reviews. No content write. | Triage and review checks in section 11 pass. |
| 2 | `coder` | Branches, commits, pull requests. Provides `code` and `fix`. | Code and fix checks in section 11 pass. |

Do not enable `retro` or `prioritize`. A per-repository installation does not
need the `fullsend-ai-fullsend` dispatch App; upstream confirms per-repo mode
dispatches through the repository's own shim workflow.

Available commands once the corresponding stage is enabled:

| Command | Location | Stage | Result |
| --- | --- | --- | --- |
| `/fs-triage` | Issue | A | Runs triage. |
| `/fs-review` | Pull request | A | Runs a review. |
| `/fs-code` | Issue | B | Creates an implementation and pull request. |
| `/fs-fix [instruction]` | Pull request | B | Fixes the pull request and pushes a commit. |
| `/fs-fix-stop` | Pull request | B | Stops automatic fix runs for the pull request. |

Only users with write permission or higher can run `/fs-code` and `/fs-fix`.
`/fs-review` requires at least triage permission.

## Security boundaries

1. Restrict the GitHub Apps to `aufi/crane-fullsend-pilot`.
2. Do not grant Fullsend permission to merge, administer the repository, or
   access other repositories. The Coder App requires `packages: read`; do not
   grant package write access.
3. Branch protection on `main` is a **precondition, not an assumption**. It was
   established before installation because a new repository has no protection
   by default. Re-verify it before each stage and after every Fullsend upgrade.
4. Pin workflows and remote resources to `v0.44.0`, a commit SHA, or a digest.
   This includes the inherited `verify-pr@main` reference noted above.
5. Keep credentials, tokens, local environment files, and sandbox output out of
   the checkout, issues, and pull requests.
6. `.github/workflows/fullsend.yaml` may use `pull_request_target` only as a
   static shim. It must not check out or execute pull request code.
7. The code agent must not change protected paths without human review. The
   protected set is `.github/workflows/**`, `.fullsend/**`,
   `.github/CODEOWNERS`, `AGENTS.md`, and `PILOT.md`.
8. Agents must never open a pull request against `migtools/crane` or any other
   repository. `PILOT.md` states this; verify it during write-capable
   validation.
9. Do not enable `CODE_AUTO_MERGE`.

By default, the review agent runs when a pull request is opened, updated, or
moved out of draft. It may apply `ready-for-merge`, request changes, mark a
pull request as `requires-manual-review`, or close it as `rejected`. The fix
agent automatically responds to requested changes on pull requests created by
the code agent. Automatic fixes on human-authored pull requests require the
`fullsend-fix` label. A manual `/fs-fix` works without that label.

## 1. Confirm the working environment

The pilot repository is separate from any local working copy, so a dirty
`move-crane` or `crane` worktree no longer affects installation. Still confirm
that whatever checkout you run the CLI from contains no credentials, tokens, or
previous agent output.

```bash
git -C <checkout> status --short
```

## 2. Install the Fullsend Runner Image

Use the versioned Fullsend runner image instead of installing the CLI on the
host. Podman and the OpenShell gateway remain host dependencies for local agent
runs.

```bash
export FULLSEND_RUNNER_IMAGE=ghcr.io/fullsend-ai/fullsend-runner:0.44.0
podman pull "$FULLSEND_RUNNER_IMAGE"
podman image inspect "$FULLSEND_RUNNER_IMAGE" \
  --format '{{index .RepoDigests 0}}'
```

Record the resulting digest in the pilot log. Replace the tag with that digest
for repeatable production-like runs.

Define this shell function before running the `fullsend` commands in this
runbook. It keeps the CLI in the container while allowing it to use the host
OpenShell gateway and authenticated `gh` configuration:

```bash
fullsend() {
  podman run --rm --network=host \
    -v "$HOME/.config/openshell:/root/.config/openshell:ro" \
    -v "$HOME/.local/state/openshell:/root/.local/state/openshell:ro" \
    -v "$HOME/.config/gh:/root/.config/gh:ro" \
    -e GH_TOKEN \
    -e GITHUB_TOKEN \
    "$FULLSEND_RUNNER_IMAGE" "$@"
}

fullsend --version
```

Do not mount the local checkout, environment files, cloud credentials, or an
OpenAI API key unless an individual command needs them. Use a separate clean
clone and read-only mounts for local agent smoke tests.

## 3. Install the local runtime

Fullsend `v0.44.0` pins OpenShell to version `0.1.2`, commit
`6648bd0c290efbc41ba131ee9831ee45cd431f94`, per
`.github/scripts/openshell-version.sh` at that tag.

1. Install Podman 5.x and enable its rootless user socket:

```bash
systemctl --user enable --now podman.socket
systemctl --user status podman.socket
```

2. Do not use the OpenShell Snap package with Podman: the Snap gateway requires
   Docker Engine and cannot auto-detect Podman. Remove the Snap package before
   installing the RPM-based OpenShell distribution:

```bash
sudo snap remove --purge openshell
```

3. Download the upstream installer at the exact OpenShell release tag, inspect
   it, then install the Fedora/RPM distribution:

```bash
curl -LsSf \
  https://raw.githubusercontent.com/NVIDIA/OpenShell/v0.1.2/install.sh \
  -o /tmp/openshell-v0.1.2-install.sh
less /tmp/openshell-v0.1.2-install.sh
OPENSHELL_VERSION=v0.1.2 sh /tmp/openshell-v0.1.2-install.sh
```

4. The RPM installer creates and starts a user-level gateway at
   `https://127.0.0.1:17670`. It registers the gateway automatically; do not
   run `openshell gateway add` unless `openshell gateway list` remains empty.
5. If the RPM-seeded `~/.config/openshell/gateway.toml` is a schema-v1 file,
   migrate its Podman selection before restarting the gateway:

```toml
[openshell]
version = 2

[openshell.gateway]
compute_driver = "podman"
```

Replace the schema-v1 `compute_drivers = ["podman"]` entry rather than adding
the new scalar alongside it. Validate and restart the user service:

```bash
openshell-gateway config preflight --path "$HOME/.config/openshell/gateway.toml"
systemctl --user restart openshell-gateway
```

6. Declare credentials in any custom OpenShell provider.
7. Verify:

```bash
podman version
openshell --version
systemctl --user status openshell-gateway
openshell gateway list
openshell status
fullsend --version
```

A local smoke test is recommended but not required for the GitHub installation.
Use a clean clone, separate environment files, and `--no-post-script` so the
agent cannot comment, change labels, or push changes. Skipping this step means
the first agent output you see will be on GitHub.

## 4. Prepare OpenAI Inference

This pilot uses Codex with an OpenAI API key stored as a GitHub Actions secret.
This is the documented fallback when OpenAI Workload Identity Federation is not
available. It removes the GCP and Vertex prerequisites, but a long-lived key
requires an explicit owner, a rotation procedure, and an OpenAI project budget.

1. Create or select a dedicated OpenAI project for this pilot and set its
   monthly budget and usage alerts.
2. Create a key scoped to that project. Do not save the key in a shell history,
   local environment file, repository checkout, issue, or pull request.
3. Set the repository secret interactively with the GitHub CLI. This keeps the
   key out of the Fullsend container command line and process arguments:

```bash
read -r -s -p 'OpenAI API key: ' OPENAI_API_KEY
printf '\n'
printf '%s' "$OPENAI_API_KEY" | \
  gh secret set FULLSEND_OPENAI_API_KEY --repo aufi/crane-fullsend-pilot
unset OPENAI_API_KEY
```

4. Confirm only the secret name is visible in repository settings. The value
   must never appear in Actions logs, `config.yaml`, repository variables, or
   local files.
5. Record the OpenAI project, budget owner, key owner, rotation date, and the
   person authorized to revoke the key in the pilot log.

The key is delivered to the Fullsend runner only for GitHub Actions runs. The
OpenShell provider passes a placeholder to the sandbox rather than the key
itself. For local runs, use a separately managed key in the runner environment;
never copy the repository secret to a local `.env` file.

## 5. Choose a token mint

A personal pilot may use the upstream community mint after the administrator
accepts its trust model. In that case, omit `--mint-url`; enrollment is
automatic.

For stronger isolation, deploy a private mint, allow only
`aufi/crane-fullsend-pilot`, and pass its HTTPS URL through `--mint-url`. A
private mint requires dedicated GitHub App credentials, Secret Manager, Cloud
Functions, and additional GCP permissions.

Record this decision before installation. The coder token has `contents: write`
and can create branches, commits, and pull requests.

## 6. Install the GitHub Apps

On each installation page, select `Only select repositories` and choose only
`aufi/crane-fullsend-pilot`.

- [fullsend-ai-triage](https://github.com/apps/fullsend-ai-triage/installations/new)
- [fullsend-ai-review](https://github.com/apps/fullsend-ai-review/installations/new)
- [fullsend-ai-coder](https://github.com/apps/fullsend-ai-coder/installations/new)

The Coder App provides both the `code` and `fix` agents. There is no separate
Fix App. Do not install the `fullsend-ai-fullsend` dispatch App.

## 7. Prepare setup permissions

`fullsend github setup` in per-repo mode requires repository admin access. A
classic token needs the **`repo`** and **`workflow`** scopes. Fullsend `v0.44.0`
also supports a fine-grained token scoped to the pilot repository with
read/write access to Contents, Workflows, Secrets, Variables, and Pull requests,
plus read-only Metadata.

The current `gh` session is authenticated as `aufi` and reports `repo` and
`workflow` scopes. Re-check immediately before setup. `GH_TOKEN` takes
precedence over `GITHUB_TOKEN`, which takes precedence over the stored `gh`
credential:

```bash
gh auth status
```

Use a token only for setup, keep it out of logs, and remove it from the
environment afterwards. Agents use short-lived GitHub App tokens from the mint.

## 8. Run per-repository setup

Use the Codex runtime with an explicit OpenAI model. Codex is experimental and
does not have the Claude review/retro sub-agent roster; evaluate review quality
before running write-capable validation.

```bash
fullsend github setup aufi/crane-fullsend-pilot \
  --agents triage,review,coder \
  --runtime codex \
  --fullsend-ref v0.44.0
```

Before merging the setup pull request, edit `.fullsend/config.yaml` in that
pull request so every enabled agent has an explicit Codex runtime and OpenAI
model. Codex refuses the fleet's default Claude model aliases.

```yaml
agents:
  - name: triage
    runtime: codex
    model: openai/gpt-5.6-luna
  - name: review
    runtime: codex
    model: openai/gpt-5.6-luna
  - name: code
    runtime: codex
    model: openai/gpt-5.6-luna
  - name: fix
    runtime: codex
    model: openai/gpt-5.6-luna
```

The installed roles may all run, but validate them only in the order defined in
this document and use dedicated pilot issues and pull requests for `code` and
`fix`. A later re-run refreshes managed workflow files and, because `--agents`
targets a config key, updates that key while keeping the rest. Note that
passing such a flag re-serializes the file and does not preserve hand-written
comments.

For a private mint, add:

```bash
--mint-url 'https://<mint-host>'
```

Do not use `--direct`. Setup should create a branch and pull request so the
scaffold can be reviewed before it reaches the default branch.

## 9. Review the setup pull request

Before merging, verify that:

1. `.fullsend/config.yaml` contains only the roles for the current stage and
   uses `codex` with an explicit `openai/...` model for every enabled agent.
2. `.github/workflows/fullsend.yaml` references `v0.44.0`, not `main`.
3. All other remote harnesses, actions, and images are pinned to a tag, commit
   SHA, or digest.
4. The `pull_request_target` shim does not check out or execute pull request
   code.
5. The workflow does not grant broader `permissions` than each role needs.
6. Setup created only the expected configuration:
    - Secret `FULLSEND_OPENAI_API_KEY`, added separately in section 4.
    - `FULLSEND_MINT_URL` when required by the selected mint.
    - Optionally `FULLSEND_REVIEW_CLIENT_ID`, which the installer sets on a
      best-effort basis.
7. The change contains no `.env` file, personal access token, OpenAI API key,
   sandbox log, or transcript.
8. `PILOT.md` and the `AGENTS.md` banner are unchanged and still state that
   this repository is not upstream Crane.
9. `.github/CODEOWNERS` still covers `.fullsend/`, so the new directory is
   protected from the moment it exists.

Setup adds a workflow file, so the merge will require the three existing status
checks to pass. Confirm the new workflow does not itself become a required
check until it has demonstrated a green run.

## 9.1 Post-Merge Readiness Check

After the setup pull request is merged, verify these repository-level facts
before triggering an agent:

1. `main` contains `.fullsend/config.yaml` with roles `triage`, `review`, and
   `coder`, and every enabled agent uses `codex` with an explicit
   `openai/gpt-5.6-luna` model.
2. The repository secret `FULLSEND_OPENAI_API_KEY` exists. Never retrieve,
   print, or commit its value.
3. Repository variables include `FULLSEND_MINT_URL=https://mint.fullsend.sh`
   and `FULLSEND_PER_REPO_INSTALL=true`.
4. The `fullsend` workflow is active. `Prioritize` may also appear as a
   scaffolded workflow, but the `prioritize` role remains disabled because it
   is absent from `.fullsend/config.yaml`.
5. Branch protection and required checks on `main` are unchanged.

## 10. Run controlled validation

Test issues and pull requests must not contain secrets or security reports.
Source realistic material by paraphrasing open upstream issues from
`migtools/crane`; never copy a security report. After every run, inspect the
Actions log, comments, label changes, OpenAI project cost, and Actions usage.

### Triage, validation order 1

1. Create an intentionally incomplete, non-production pilot issue.
2. Run `/fs-triage`.
3. Expect a request for more information and the `needs-info` label.
4. Add the requested information and run `/fs-triage` again.
5. Verify the category and any resulting `ready-to-code` label.

Warning: `ready-to-code` automatically starts the code agent. Test triage only
with deliberately small, approved pilot issues after the initial smoke test.

### Review, validation order 1

1. Open a small human-authored, documentation-only pull request and run
   `/fs-review`.
2. Check the relevance of findings and any inline comments.
3. Check for `ready-for-merge`, `requires-manual-review`, or `rejected` labels.
4. Confirm the review agent did not write to the branch.

Review also runs automatically when a pull request is opened or updated. If the
output is too noisy, set `REVIEW_FINDING_SEVERITY_THRESHOLD=medium` in the
review harness. Do not add this option to the workflow `env` block, which is
reserved for infrastructure configuration.

### Code, validation order 2

1. Prepare a small, unambiguous issue, for example a unit test or a contained
   bug fix.
2. Run `/fs-code` as a user with write permission only after triage and review
   checks are acceptable.
3. Verify that the agent created a new branch and pull request, not a commit to
   `main`.
4. Verify the pull request targets `aufi/crane-fullsend-pilot` and no other
   repository.
5. Review the scope, tests, secret scan, and pull request linkage to the issue.
6. Verify that the agent did not change protected paths.
7. Verify that `go.yml`, `lint.yml`, and `pr-title-check.yml` ran and that the
   merge remained blocked pending your approval.

### Fix, validation order 2

1. Let the review agent request a change on a code-agent pull request, or run
   `/fs-fix <specific instruction>` only after the code-agent pull request is
   reviewed.
2. Verify that the fix agent changed only the pull request branch and added a
   commit.
3. Verify the tests and subsequent review.
4. Confirm that the review/fix loop terminates. The default limits are five
   automatic and ten total fix iterations per pull request.
5. Use `/fs-fix-stop` if the behavior is not acceptable.

The fix agent does not read individual inline comments, general pull request
discussion, or CI logs. Include a specific inline request in the `/fs-fix`
instruction.

After every validation run, inspect the GitHub Actions log, the agent's
comments and labels, branch/commit ownership, and OpenAI project usage before
continuing to the next validation order.

## 11. Acceptance criteria

Run at least ten controlled executions per stage covering every function that
stage enables. Continue only if:

- No secret was exposed and no unauthorized mutation occurred.
- No agent bypassed branch protection or human review.
- No agent opened a pull request against another repository.
- Human reviewers judged at least 60% of triage and review output useful.
- Code and fix changes remained within the repository's permitted scope.
- No unbounded review/fix loop occurred.
- Codex review quality is accepted despite its lack of the Claude sub-agent roster.
- Costs remained within the defined budget.
- One administrator can audit and remove the installation.

Record results separately for the read-only and write-capable roles so they can
feed the decision in `FULLSEND_MIGTOOLS_EVALUATION.md`.

## 12. Updates

Treat every Fullsend upgrade as a separate reviewed change. Read the release
notes, verify the new OpenShell pin, and rerun setup with the new
`--fullsend-ref`. A repeated setup updates managed workflows but does not
overwrite an existing `.fullsend/config.yaml` unless configuration flags are
provided.

Check the OpenAI inference configuration with:

```bash
fullsend inference openai status aufi/crane-fullsend-pilot
```

## 13. Rollback

Because the pilot repository is disposable, full rollback is deletion. Remove
the OpenAI key and App side first so nothing is left holding credentials.

1. Remove the `fullsend-ai-triage`, `fullsend-ai-review`, and, if installed,
   `fullsend-ai-coder` Apps from `aufi/crane-fullsend-pilot`.
2. Delete all repository secrets and variables with the `FULLSEND_` prefix.
3. Revoke the OpenAI API key in the OpenAI project; deleting the GitHub secret
   does not invalidate a copied or exposed key.
4. For a private mint, remove the repository from its allowlist:

```bash
fullsend mint unenroll aufi/crane-fullsend-pilot
```

5. Revoke the setup personal access token and any locally used OpenAI key.
6. Review open bot pull requests, comments, reviews, Actions logs, and OpenAI
   billing, and export anything needed for the evaluation.
7. Delete the repository.

To keep the repository but stop the agents, remove
`.github/workflows/fullsend.yaml` and `.fullsend/` through a reviewed pull
request instead of step 7.

## Sources

- [Fullsend v0.44.0 release](https://github.com/fullsend-ai/fullsend/releases/tag/v0.44.0)
- [OpenAI Workload Identity and static-key fallback v0.44.0](https://github.com/fullsend-ai/fullsend/blob/v0.44.0/docs/guides/infrastructure/openai-workload-identity.md)
- [GitHub setup v0.44.0](https://github.com/fullsend-ai/fullsend/blob/v0.44.0/docs/guides/getting-started/configuring-github.md)
- [GitHub CLI reference v0.44.0](https://github.com/fullsend-ai/fullsend/blob/v0.44.0/docs/cli/github.md)
- [OpenShell pin v0.44.0](https://github.com/fullsend-ai/fullsend/blob/v0.44.0/.github/scripts/openshell-version.sh)
- [Runtime selection v0.44.0](https://github.com/fullsend-ai/fullsend/blob/v0.44.0/docs/guides/getting-started/choosing-a-runtime.md)
- [Code agent v0.44.0](https://github.com/fullsend-ai/fullsend/blob/v0.44.0/docs/agents/code.md)
- [Review agent v0.44.0](https://github.com/fullsend-ai/fullsend/blob/v0.44.0/docs/agents/review.md)
- [Fix agent v0.44.0](https://github.com/fullsend-ai/fullsend/blob/v0.44.0/docs/agents/fix.md)
- [`pull_request_target` ADR](https://github.com/fullsend-ai/fullsend/blob/v0.44.0/docs/ADRs/0009-pull-request-target-in-shim-workflows.md)
- Pilot repository: <https://github.com/aufi/crane-fullsend-pilot>
