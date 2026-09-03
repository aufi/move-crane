# Fullsend Pilot Runbook for aufi/move-crane

## Purpose

Run a small, reversible Fullsend pilot on the public repository <https://github.com/aufi/move-crane>. The initial scope is manual issue triage only. It must not create pull requests, modify repository content, merge changes, or be installed on any `migtools` repository.

This runbook targets Fullsend `v0.40.0`, verified on September 3, 2026. Review the upstream release notes before using a newer version.

## Pilot Boundaries

- Enable only `triage`.
- Install only the `fullsend-ai-triage` GitHub App and restrict it to `aufi/move-crane`.
- Use `/fs-triage` as the only trigger during the initial evaluation. Do not rely on automatic triage until the manual flow is accepted.
- Do not install `coder`, `fix`, `review`, `retro`, or `prioritize`.
- Do not grant a bot, workflow, or GitHub App permission to merge, administer the repository, access packages, or read unrelated repositories.
- Keep all API keys, service-account credentials, and personal access tokens outside the checkout and out of GitHub issue content.

## Current Repository Preconditions

- Remote repository: `aufi/move-crane`.
- Default branch: `main`.
- Visibility: public.
- The current local worktree has many untracked files, including `test-day-june2026/sample-apps/wordpress/.env`.

Before running any Fullsend setup command, work from a clean checkout or a dedicated branch with reviewed changes. Do not let the installer, a local sandbox, or a test agent process unreviewed `.env` files or other sensitive local artifacts. Verify this before every setup or test run:

```bash
git status --short
git check-ignore -v test-day-june2026/sample-apps/wordpress/.env
```

If the `.env` file is not ignored, add an ignore rule before doing any Fullsend work. Never commit it.

## Phase 1: Local Read-Only Smoke Test

Perform a local run before enabling GitHub Actions. This validates the Fullsend binary, OpenShell sandbox, model access, and the triage output without adding a GitHub App or workflow to the repository.

1. Install Podman and the OpenShell version pinned by Fullsend's `v0.40.0` release. Confirm that the OpenShell gateway is running. The runner image executes the Fullsend CLI, but its sandboxes still use the host OpenShell gateway.
2. Pull the versioned Fullsend runner image. Do not use the floating `latest` tag:

```bash
podman pull ghcr.io/fullsend-ai/fullsend-runner:0.40.0
```

3. Record the image digest reported by Podman and use that digest in later runs if the pilot needs repeatable provenance.
4. Create or select a dedicated GCP project. Enable `iam.googleapis.com`, `cloudresourcemanager.googleapis.com`, and `aiplatform.googleapis.com`, and enable the required Vertex AI Anthropic models.
5. Create a least-privileged service account with `roles/aiplatform.user` only for this local test. Store its JSON credential outside this repository with restrictive filesystem permissions.
6. Create a fine-grained GitHub token limited to `aufi/move-crane`. For the first local triage test, grant read-only repository metadata/content access and the least issue permission required by the upstream triage harness. Do not reuse a personal broad-scope token.
7. Create a dedicated test issue containing only non-sensitive sample text.
8. Clone `fullsend-ai/agents` outside this repository at the commit used by `v0.40.0`. Create GCP and triage environment files outside this repository, then run the triage agent with `--no-post-script` so it cannot post a comment, change labels, or close issues.
9. Inspect the generated JSON output, transcript, sandbox log, and `metrics.json`. Delete the local credential files after the test if they are not needed for the CI setup.

Example container command, with paths and secrets intentionally external to the checkout. The OpenShell client configuration is mounted read-only; the host gateway and Podman remain prerequisites.

```bash
podman run --rm --network=host \
  -v "$HOME/.config/openshell:/root/.config/openshell:ro" \
  -v /secure/path/fullsend-agents:/work/fullsend-agents:ro \
  -v /secure/path/move-crane-clean:/work/move-crane \
  -v /secure/path/fullsend-env:/work/env:ro \
  -v /secure/path/fullsend-output:/work/output \
  ghcr.io/fullsend-ai/fullsend-runner:0.40.0 \
  run triage \
    --fullsend-dir /work/fullsend-agents \
    --target-repo /work/move-crane \
    --env-file /work/env/fullsend-gcp.env \
    --env-file /work/env/fullsend-triage.env \
    --no-post-script \
    --output-dir /work/output
```

Success criteria: the run completes, identifies whether the test issue has enough information, produces no repository mutation, and makes no denied outbound request beyond the configured inference/provider endpoints.

## Phase 2: Provision CI Identity and Inference

This phase creates cloud identity resources and must be performed only after the local smoke test succeeds.

1. Use a dedicated GCP project for this pilot, with a budget alert and a small monthly spending limit.
2. Authenticate `gcloud` as an identity allowed to administer WIF in that project.
3. Provision repo-scoped WIF for `aufi/move-crane`:

```bash
fullsend inference provision aufi/move-crane --project "$GCP_PROJECT"
```

4. Record the printed WIF provider resource name. Treat it as configuration data, not as a secret.
5. Install [fullsend-ai-triage](https://github.com/apps/fullsend-ai-triage/installations/new) from GitHub's App installation page. Select **Only select repositories** and select only `aufi/move-crane`.
6. Do not install the Fullsend dispatch App. Per-repository installation does not require it.
7. For the simplest personal pilot, use the upstream-hosted community mint only after accepting its documented trust model. For a stronger isolation boundary, deploy a dedicated tight mint and allow only `aufi/move-crane`; this requires separate GitHub App credentials and GCP Secret Manager administration.

## Phase 3: Install the Triage-Only Repository Configuration

The following command modifies GitHub configuration, creates repository secrets/variables, and generates Fullsend scaffold files. Run it only from the clean branch prepared above.

```bash
fullsend github setup aufi/move-crane \
  --inference-project "$GCP_PROJECT" \
  --inference-wif-provider "$WIF_PROVIDER" \
  --agents triage
```

Before merging any installer-created pull request or pushing its changes, review all generated files and GitHub settings:

1. Confirm `.fullsend/config.yaml` enables only `triage`.
2. Confirm every upstream action, reusable workflow, container image, and remote harness is pinned to `v0.40.0` or a commit SHA. Do not accept a floating `main` or `latest` reference for CI.
3. Confirm `.github/workflows/fullsend.yaml` does not check out, build, or execute pull-request code under `pull_request_target`.
4. Protect `.github/workflows/fullsend.yaml` and `.fullsend/**` with `CODEOWNERS` or branch rules requiring your review.
5. Confirm the only repository secrets are `FULLSEND_GCP_PROJECT_ID` and `FULLSEND_GCP_WIF_PROVIDER`, and that the expected variables are `FULLSEND_MINT_URL` and `FULLSEND_GCP_REGION`.
6. Confirm that no local `.env`, GCP JSON credential, token, or generated sandbox output is included in the change.

## Phase 4: Controlled GitHub Validation

1. Create a new non-sensitive test issue with a deliberately incomplete description.
2. Add the comment `/fs-triage`.
3. Review the GitHub Actions run, the agent comment, and its labels. Expected outcome: a clarification request and `needs-info`, not an implementation action.
4. Add the requested information and run `/fs-triage` again.
5. Verify that the result is `triaged` for a feature/design request. Do not apply `ready-to-code` during this pilot.
6. Check GCP billing and GitHub Actions usage after each run.
7. Repeat with two to five representative documentation, research, and planning issues from this repository. Never use a security report or issue containing credentials.

## Optional Phase 5: Design Gate

After manual triage is accepted, configure a repository-specific `needs-design` label and add a triage skill that applies it when the desired outcome is clear but the implementation approach is not. The skill must prohibit `ready-to-code` whenever it recommends `needs-design`.

Do not create a custom design agent in the first pilot. A custom agent needs a defined harness, output schema, CEL trigger, policy, test plan, and an identity/permission review. First establish that triage reliably routes design work for this planning repository.

## Evaluation and Exit Criteria

Keep the pilot for two weeks or ten manually triggered triage runs, whichever is later. Continue only if all conditions hold:

- No secret exposure, unauthorized mutation, or unexpected workflow trigger occurs.
- At least 60% of triage outputs are judged useful after review.
- No output causes a human to treat an insufficiently specified issue as ready to implement.
- Actual spending remains within the predefined budget.
- The setup and audit process remains understandable and maintainable by one repository administrator.

Otherwise, remove the installation as described below.

## Rollback

1. Remove the `fullsend-ai-triage` App from `aufi/move-crane` in GitHub App settings.
2. Remove `.github/workflows/fullsend.yaml` and `.fullsend/` through a reviewed pull request.
3. Delete `FULLSEND_GCP_PROJECT_ID`, `FULLSEND_GCP_WIF_PROVIDER`, `FULLSEND_MINT_URL`, and other `FULLSEND_*` repository configuration entries created by the installer.
4. Remove WIF access:

```bash
fullsend inference deprovision aufi/move-crane
```

5. Revoke any local fine-grained GitHub token and delete local service-account keys used for smoke testing.
6. Review Actions logs, agent comments, labels, and cloud billing before closing the pilot.

## Sources

- [Fullsend GitHub setup](https://fullsend.sh/docs/guides/getting-started/configuring-github)
- [Fullsend inference setup](https://fullsend.sh/docs/guides/getting-started/getting-inference)
- [Running agents locally](https://fullsend.sh/docs/guides/user/running-agents-locally)
- [Triage agent](https://fullsend.sh/docs/agents/triage)
- [Fullsend operations](https://fullsend.sh/docs/guides/getting-started/operations)
