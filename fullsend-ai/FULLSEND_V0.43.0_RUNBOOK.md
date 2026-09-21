# Fullsend v0.43.0 for aufi/move-crane

## Purpose

This runbook describes how to install Fullsend `v0.43.0` in the public
`aufi/move-crane` repository. It enables issue triage, pull request review,
development from issues, and fixes based on review feedback. Fullsend is
installed for one repository. It must not merge changes or bypass protection
on the `main` branch.

The `move-crane` repository contains plans, documentation, research, and POCs.
It is not a production implementation repository for Crane. The code and fix
agents may create only corresponding documentation, proposals, test scenarios,
and POCs here. Production changes belong in the relevant `migtools/crane*`
repositories.

This procedure was verified against upstream tag `v0.43.0`, released on
September 9, 2026. Before using another version, review its release notes,
workflows, GitHub App permissions, and pinned OpenShell version.

## Scope

Enabled installation roles:

- `triage` analyzes issues and writes comments and labels.
- `coder` provides the `code` and `fix` agents and can create branches,
  commits, and pull requests.
- `review` reviews pull requests.

Do not enable `retro` or `prioritize`. A per-repository installation does not
need the `fullsend-ai-fullsend` dispatch App.

Available commands:

| Command | Location | Result |
| --- | --- | --- |
| `/fs-triage` | Issue | Runs triage. |
| `/fs-code` | Issue | Creates an implementation and pull request. |
| `/fs-review` | Pull request | Runs a review. |
| `/fs-fix [instruction]` | Pull request | Fixes the pull request and pushes a commit. |
| `/fs-fix-stop` | Pull request | Stops automatic fix runs for the pull request. |

Only users with write permission or higher can run `/fs-code` and `/fs-fix`.
`/fs-review` requires at least triage permission.

## Security boundaries

1. Restrict the GitHub Apps to `aufi/move-crane`.
2. Do not grant Fullsend permission to merge, administer the repository, access
   packages, or access other repositories.
3. Keep required CI checks, human review, and `main` branch protection in
   place, with no bot bypass.
4. Pin workflows and remote resources to `v0.43.0`, a commit SHA, or a digest.
5. Keep credentials, tokens, local environment files, and sandbox output out
   of the checkout, issues, and pull requests.
6. `.github/workflows/fullsend.yaml` may use `pull_request_target` only as a
   static shim. It must not check out or execute pull request code.
7. The code agent must not change protected paths without human review. Protect
   at least `.github/workflows/**`, `.fullsend/**`, `CODEOWNERS`, and
   `AGENTS.md`.
8. Do not enable `CODE_AUTO_MERGE`.

By default, the review agent runs when a pull request is opened, updated, or
moved out of draft. It may apply `ready-for-merge`, request changes, mark a pull
request as `requires-manual-review`, or close it as `rejected`. The fix agent
automatically responds to requested changes on pull requests created by the
code agent. Automatic fixes on human-authored pull requests require the
`fullsend-fix` label. A manual `/fs-fix` works without that label.

## 1. Prepare a clean checkout

Do not run the installation from the current worktree while it contains
unreviewed files. Use a new clone or a separate clean worktree.

```bash
git status --short
git check-ignore -v test-day-june2026/sample-apps/wordpress/.env
```

The `.env` file must remain ignored and must never be committed. Before setup,
also confirm that the checkout contains no cloud credentials, personal access
tokens, or output from previous agent runs.

## 2. Install the native Fullsend CLI

The Fullsend CLI can run directly on Linux. The runner container is optional.
OpenShell uses Podman for agent sandboxes, so Podman remains required when
running agents locally.

Download the release and checksum with GitHub CLI:

```bash
mkdir -p /tmp/fullsend-0.43.0
gh release download v0.43.0 \
  --repo fullsend-ai/fullsend \
  --pattern fullsend_0.43.0_linux_amd64.tar.gz \
  --pattern checksums.txt \
  --dir /tmp/fullsend-0.43.0
cd /tmp/fullsend-0.43.0
sha256sum -c checksums.txt --ignore-missing
tar -xzf fullsend_0.43.0_linux_amd64.tar.gz
install -m 0755 fullsend_0.43.0_linux_amd64/fullsend "$HOME/.local/bin/fullsend"
fullsend --version
```

The expected SHA-256 for the Linux amd64 archive is:

```text
e56be72bb2af7210418307e784d65a8ead4ff736540c077f75d258865e595f10
```

For another architecture, use the corresponding archive and value from the
signed `checksums.txt` file in release `v0.43.0`.

## 3. Install the local runtime

Fullsend `v0.43.0` pins OpenShell to version `0.0.116`, commit
`d1155aa70042d3e2ee49dbfa15346b108b7c1d92`.

1. Install Podman.
2. Install OpenShell `0.0.116` according to its upstream documentation.
3. Start the OpenShell gateway.
4. Verify the versions and runtime availability:

```bash
podman version
openshell --version
fullsend --version
```

A local smoke test is recommended but not required for the GitHub installation.
Use a clean clone, separate environment files, and `--no-post-script` so the
agent cannot comment, change labels, or push changes.

## 4. Prepare inference in GCP

1. Use a dedicated GCP project with a billing alert and monthly spending limit.
2. Enable the required APIs:

```bash
gcloud services enable \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  aiplatform.googleapis.com \
  --project="$GCP_PROJECT"
```

3. Enable the Anthropic Opus and Sonnet models used by the selected runtime in
   Vertex AI.
4. The identity running the provisioning command needs
   `roles/iam.workloadIdentityPoolAdmin` and
   `roles/resourcemanager.projectIamAdmin`.
5. Create repository-scoped Workload Identity Federation:

```bash
fullsend inference provision aufi/move-crane --project "$GCP_PROJECT"
```

6. Store the reported resource name in a shell variable:

```bash
WIF_PROVIDER='projects/<number>/locations/global/workloadIdentityPools/fullsend-inference/providers/gh-aufi-move-crane'
```

The WIF provider name is not a secret, but it must be scoped to this repository.
GitHub Actions obtains short-lived credentials through WIF. No service-account
JSON file or model API key is stored in the repository.

## 5. Choose a token mint

A personal pilot may use the upstream community mint after the administrator
accepts its trust model. In that case, omit `--mint-url`; enrollment is
automatic.

For stronger isolation, deploy a private mint, allow only `aufi/move-crane`,
and pass its HTTPS URL through `--mint-url`. A private mint requires dedicated
GitHub App credentials, Secret Manager, Cloud Functions, and additional GCP
permissions.

Record this decision before installation. The coder token has `contents: write`
and can create branches, commits, and pull requests.

## 6. Install the GitHub Apps

On each installation page, select `Only select repositories` and choose only
`aufi/move-crane`:

- [fullsend-ai-triage](https://github.com/apps/fullsend-ai-triage/installations/new)
- [fullsend-ai-coder](https://github.com/apps/fullsend-ai-coder/installations/new)
- [fullsend-ai-review](https://github.com/apps/fullsend-ai-review/installations/new)

The Coder App provides both the `code` and `fix` agents. There is no separate
Fix App. Do not install the `fullsend-ai-fullsend` dispatch App for a
per-repository installation.

## 7. Prepare setup permissions

Authenticate `gh` as a repository administrator. If the current token is not
sufficient, create a fine-grained personal access token limited to
`aufi/move-crane` with these permissions:

- Contents, Workflows, Secrets, and Variables: read/write.
- Pull requests: read/write if setup creates a pull request.
- Metadata: read-only.

Use the personal access token only for setup:

```bash
export GH_TOKEN='github_pat_...'
gh auth status
```

Revoke it or remove it from the environment after installation. Agents use
short-lived GitHub App tokens from the mint.

## 8. Run per-repository setup

Use the stable Claude Code runtime. In `v0.43.0`, `pi` and `codex` remain
experimental. Review on Claude Code supports the full sub-agent roster.

```bash
fullsend github setup aufi/move-crane \
  --inference-project "$GCP_PROJECT" \
  --inference-wif-provider "$WIF_PROVIDER" \
  --agents triage,coder,review \
  --runtime claude \
  --fullsend-ref v0.43.0
```

For a private mint, add:

```bash
--mint-url 'https://<mint-host>'
```

Do not use `--direct`. Setup should create a branch and pull request so the
scaffold can be reviewed before it reaches the default branch.

## 9. Review the setup pull request

Before merging, verify that:

1. `.fullsend/config.yaml` contains only roles corresponding to
   `triage,coder,review` and uses the `claude` runtime.
2. `.github/workflows/fullsend.yaml` references `v0.43.0`, not `main`.
3. All other remote harnesses, actions, and images are pinned to a tag, commit
   SHA, or digest.
4. The `pull_request_target` shim does not check out or execute pull request
   code.
5. The workflow does not grant broader `permissions` than each role needs.
6. Setup created only the expected configuration:
   - Secrets `FULLSEND_GCP_PROJECT_ID` and `FULLSEND_GCP_WIF_PROVIDER`.
   - Variable `FULLSEND_GCP_REGION`.
   - `FULLSEND_MINT_URL` when required by the selected mint.
   - Optionally `FULLSEND_REVIEW_CLIENT_ID`, which the installer sets on a
     best-effort basis.
7. The change contains no `.env` file, personal access token, GCP JSON key,
   sandbox log, or transcript.
8. `AGENTS.md` remains authoritative and clearly prohibits production
   implementation in this repository.

Add a root `.github/CODEOWNERS` file if one does not exist. Replace `@aufi`
with the account or team that must approve these changes if necessary:

```text
/.github/workflows/fullsend.yaml @aufi
/.fullsend/ @aufi
/.github/CODEOWNERS @aufi
/AGENTS.md @aufi
```

Configure a ruleset or branch protection so these paths require human review.
The Fullsend Apps must not have bypass permission.

## 10. Run controlled validation

Test issues and pull requests must not contain secrets or security reports.
After every run, inspect the Actions log, comments, label changes, GCP cost,
and Actions usage.

### Triage

1. Create an incomplete documentation issue.
2. Run `/fs-triage`.
3. Expect a request for more information and the `needs-info` label.
4. Add the requested information and run `/fs-triage` again.
5. Verify the category and any resulting `ready-to-code` label.

Warning: `ready-to-code` automatically starts the code agent. For the first
test, use an issue where creating a pull request is intended, or immediately
remove the label before the next dispatch run.

### Code

1. Prepare a small, unambiguous issue limited to documentation or a POC.
2. Run `/fs-code` as a user with write permission.
3. Verify that the agent created a new branch and pull request, not a commit to
   `main`.
4. Review the scope, tests, secret scan, and pull request linkage to the issue.
5. Verify that the agent did not change production repositories or protected
   paths.

### Review

1. Run `/fs-review` on a test pull request.
2. Check the relevance of findings and any inline comments.
3. Check for `ready-for-merge`, `requires-manual-review`, or `rejected` labels.
4. Confirm that the review agent did not write to the branch.

Review also runs automatically when a pull request is opened or updated. If
the output is too noisy, set `REVIEW_FINDING_SEVERITY_THRESHOLD=medium` in the
review harness. Do not add this option to the workflow `env` block, which is
reserved for infrastructure configuration.

### Fix

1. Let the review agent request a change on a code-agent pull request, or run
   `/fs-fix <specific instruction>`.
2. Verify that the fix agent changed only the pull request branch and added a
   commit.
3. Verify the tests and subsequent review.
4. Confirm that the review/fix loop terminates. The default limits are five
   automatic and ten total fix iterations per pull request.
5. Use `/fs-fix-stop` if the behavior is not acceptable.

The fix agent does not read individual inline comments, general pull request
discussion, or CI logs. Include a specific inline request in the `/fs-fix`
instruction.

## 11. Acceptance criteria

Run at least ten controlled pilot executions covering all enabled functions.
Continue only if:

- No secret was exposed and no unauthorized mutation occurred.
- No agent bypassed branch protection or human review.
- Human reviewers judged at least 60% of triage and review output useful.
- Code and fix changes remained within the repository's permitted scope.
- No unbounded review/fix loop occurred.
- Costs remained within the defined budget.
- One administrator can audit and remove the installation.

## 12. Updates

Treat every Fullsend upgrade as a separate reviewed change. Read the release
notes, verify the new OpenShell pin, and rerun setup with the new
`--fullsend-ref`. A repeated setup updates managed workflows but does not
overwrite an existing `.fullsend/config.yaml` unless explicit configuration
flags are provided.

Check inference health with:

```bash
fullsend inference status aufi/move-crane
```

## 13. Rollback

1. Remove the `fullsend-ai-triage`, `fullsend-ai-coder`, and
   `fullsend-ai-review` Apps from `aufi/move-crane`.
2. Remove `.github/workflows/fullsend.yaml` and `.fullsend/` through a reviewed
   pull request.
3. Delete all repository secrets and variables with the `FULLSEND_` prefix.
4. Remove repository-scoped WIF access:

```bash
fullsend inference deprovision aufi/move-crane
```

5. For a private mint, remove the repository from its allowlist:

```bash
fullsend mint unenroll aufi/move-crane
```

6. Revoke the setup personal access token and local cloud credentials.
7. Review open bot pull requests, comments, reviews, Actions logs, and cloud
   billing.

## Sources

- [Fullsend v0.43.0 release](https://github.com/fullsend-ai/fullsend/releases/tag/v0.43.0)
- [Inference setup v0.43.0](https://github.com/fullsend-ai/fullsend/blob/v0.43.0/docs/guides/getting-started/getting-inference.md)
- [GitHub setup v0.43.0](https://github.com/fullsend-ai/fullsend/blob/v0.43.0/docs/guides/getting-started/configuring-github.md)
- [GitHub CLI reference v0.43.0](https://github.com/fullsend-ai/fullsend/blob/v0.43.0/docs/cli/github.md)
- [Runtime selection v0.43.0](https://github.com/fullsend-ai/fullsend/blob/v0.43.0/docs/guides/getting-started/choosing-a-runtime.md)
- [Code agent v0.43.0](https://github.com/fullsend-ai/fullsend/blob/v0.43.0/docs/agents/code.md)
- [Review agent v0.43.0](https://github.com/fullsend-ai/fullsend/blob/v0.43.0/docs/agents/review.md)
- [Fix agent v0.43.0](https://github.com/fullsend-ai/fullsend/blob/v0.43.0/docs/agents/fix.md)
- [`pull_request_target` ADR](https://github.com/fullsend-ai/fullsend/blob/v0.43.0/docs/ADRs/0009-pull-request-target-in-shim-workflows.md)
