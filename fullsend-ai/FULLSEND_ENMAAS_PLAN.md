# Fullsend v0.57.0 plan for migtools/crane with Vertex AI

Updated November 20, 2026.

## Status and scope

The target repository is `migtools/crane`. The current AI backend is Google
Vertex AI with Claude Sonnet 5.5, model ID `claude-sonnet-5-5`, in `global`.
GitHub Actions authenticates through the central ITPC Workload Identity
Federation provider. The selected Fullsend release is `v0.57.0`, published
November 20, with the matching `fullsend-ai/agents` release.

This replaces the earlier v0.54.0 EnMaaS/DeepSeek plan for
`aufi/crane-fullsend-pilot`. The filename is retained for existing links.
The [November 13 deployment](FULLSEND_ENMAAS_DEPLOYMENT_2026-11-13.md) and
[agent validation](FULLSEND_ENMAAS_AGENT_VALIDATION_2026-11-13.md) describe
the earlier personal pilot. Their successful agent runs do not validate the
new repository, runtime, or model.

## Verified state

Public workflow files and repository variables were read on November 20.

| Item | Current state or selected target |
| --- | --- |
| Repository | `migtools/crane` |
| Fullsend and fleet agents target | `v0.57.0` |
| Runtime target | `claude`, the stable Claude Code runtime, for all six agents |
| Inference backend and model | Google Vertex AI, `claude-sonnet-5-5` |
| GCP project | `mta-ops-fs-agents`, project number `500881529329` |
| Inference location | `global` |
| WIF provider | `projects/21066242673/locations/global/workloadIdentityPools/itpc-identity-pool/providers/github-com` |
| Runtime IAM | Repo-scoped `roles/aiplatform.user` for `attribute.repository/migtools/crane`, verified November 19 |
| Live inference | GitHub Actions WIF exchange and Sonnet 5.5 request passed November 19 |
| GitHub token mint | `https://mint.fullsend.sh`, already set as `FULLSEND_MINT_URL` |
| Selected agents | triage, review, code, fix, retro, prioritize |
| Fullsend installation | No `.fullsend` directory or Fullsend shim in the current default-branch workflow listing |
| GitHub Apps | Access for all five Apps still needs confirmation |
| OpenShell | `0.1.4`, pinned by Fullsend v0.57.0 |

The successful [run 44555023553](https://github.com/migtools/crane/actions/runs/44555023553)
identified `claude-sonnet-5-5` and reported 15 input tokens and 5 output tokens.
See the [WIF validation record](FULLSEND_WIF_ALLOWLIST_MR.md#live-wif-validation-on-november-19).
Fullsend runtime execution, delegated model selection, and long-running
credential refresh remain to be verified.

The existing `VERTEX_PROJECT_ID` and `VERTEX_WIF_PROVIDER` variables configure
only the manual smoke-test workflow. Fullsend's own inference secrets have
not been verified. Its region, mint, App-set, and per-repo marker variables
already exist, but they do not activate agents without the scaffold.

## Release changes that affect this installation

### GitHub pull request events

Generate the v0.57.0 shim with `pull_request`. Upstream says GitHub will block
`pull_request_target` by default in public repositories from December 2, 2026.
Changing a reusable workflow's `uses:` version alone does not update the event
trigger. Inspect custom CEL expressions and harness filters for old
`pull_request_target` checks when reusing pilot configuration.

Same-repository PRs retain automatic review and retro. Fork PRs and
Dependabot PRs no longer receive automatic review or retro. A user with triage
or higher access, or an OWNERS approver or reviewer, can request review with
`/fs-review`. Use that command for a PR with a merge conflict too, because
GitHub does not run `pull_request` workflows until the conflict is resolved.

### Configuration and harness compatibility

- Install the v0.57.0 CLI before running any `fullsend repos` command. Its
  managed configuration schema is version 3. This does not change the
  `.fullsend/config.yaml` schema header, which remains `version: "1"`.
- Agent entries now accept `harness:` overrides. Inspect any copied key with
  that name, because earlier releases ignored it.
- Custom harnesses with `input_source: external` default to dry-run and need
  `allow_forge_write: true` to use forge-write providers. Review such settings
  if importing a custom harness.
- Durable credential mounts now require `allow_durable: true`. The selected
  WIF `external_account` credentials are short-lived and unaffected.
- If manifest management is adopted later, `repos install` provisions trace
  signing keys. Preserve and commit the generated per-repository
  `config.trace_context` metadata in `repos.yaml` before subsequent installs.

The matching fleet release also makes triage honor `skip-triage` and configured
skip labels, rejects `ready-for-triage` in triage label actions, and makes agents
honor repository scope conventions. Include those behaviors in validation.

## Inference and model configuration

Use native Vertex inference with `runtime: claude`. Pin every enabled agent's
parent model to `claude-sonnet-5-5`. The default review harness selects Opus,
so relying on fleet defaults would not preserve the selected Sonnet backend.

Fullsend v0.57.0 resolves its `sonnet` alias to Sonnet 5.5, with a built-in
fallback to Sonnet 4.6. Use the exact model ID for this installation so that
an unavailable model fails visibly rather than changing the selected model.
Sonnet 4.6 returned HTTP 404 in the November 19 checks.

The following configuration excerpt shows the intended provider settings.
Keep the scaffold's pinned agent sources and add the model override to each
of its six entries.

```yaml
version: "1"
runtime: claude
mint_url: https://mint.fullsend.sh
inference:
  provider: vertex
  project: mta-ops-fs-agents
  region: global
  wif_provider: projects/21066242673/locations/global/workloadIdentityPools/itpc-identity-pool/providers/github-com
tracker:
  github:
    allowed_targets:
      repos:
        - migtools/crane
```

For every generated agent entry, set `runtime: claude` and
`model: claude-sonnet-5-5`. Use `agents[].enabled` to control dispatch.
The setup role is named `coder`; its implementation agent is named `code`.

### Native subagents

Claude Code resolves native subagent model frontmatter itself.
`models.aliases` controls the parent model only, and `agents[].subagents`
is documented for pi and Codex. The old pi persona overrides cannot configure
Claude Code's native model selection.

Set the following in the harness's `env.sandbox` for each delegating agent,
using the new per-agent `harness:` override or a local composed harness:

```yaml
ANTHROPIC_DEFAULT_OPUS_MODEL: claude-sonnet-5-5
ANTHROPIC_DEFAULT_SONNET_MODEL: claude-sonnet-5-5
ANTHROPIC_DEFAULT_HAIKU_MODEL: claude-sonnet-5-5
```

Inspect persona frontmatter for explicit model IDs that bypass these tier
settings. Verify parent and child models in live review and retro runs and
their `metrics.json` usage. Fullsend does not inject these tier overrides.

## Installation sequence

1. Confirm that the triage, review, coder, retro, and prioritize GitHub Apps
   can access `migtools/crane`. Code and fix share the coder App. Follow the
   [GitHub identity setup](FULLSEND_MIGTOOLS_GITHUB_IDENTITY.md). Organization
   App installation and repository-admin access are the remaining setup
   dependencies; the current GitHub identity reports maintain access.
2. Install the Fullsend v0.57.0 CLI. Record its version and the resolved
   workflow, harness, and sandbox-image pins. For local validation, use
   OpenShell `0.1.4`, as pinned by this Fullsend release.
3. Preview the per-repository installation with the command below. Then run
   the same command without `--dry-run` to prepare the setup PR and repository
   settings. Setup writes variables and secrets before the PR is merged.
4. Review the generated `.fullsend/config.yaml` and workflows. Set all six
   parent model overrides and the native subagent tiers described above.
   Keep the selected managed mint, `global` region, and GitHub tracker target
   restricted to `migtools/crane`. Pin fleet resources to v0.57.0 and record
   their resolved integrity hashes and image digests.
5. Verify `FULLSEND_GCP_PROJECT_ID`, `FULLSEND_GCP_WIF_PROVIDER`, and
   `FULLSEND_GCP_REGION` match the table above. The project/provider values
   are identifiers stored through Fullsend's expected secret mechanism.
   The generated workflows must grant `id-token: write` for WIF.
6. Run `fullsend lint` with v0.57.0 on the completed configuration and
   harnesses. Resolve configuration errors and inherited model selections
   before merging. Inspect triggers so all six agents are configured while
   validation runs can be started in the controlled order below.

```bash
fullsend github setup migtools/crane \
  --fullsend-ref v0.57.0 \
  --runtime claude \
  --agents triage,coder,review,fix,retro,prioritize \
  --mint-url https://mint.fullsend.sh \
  --inference-provider vertex \
  --inference-project mta-ops-fs-agents \
  --inference-wif-provider projects/21066242673/locations/global/workloadIdentityPools/itpc-identity-pool/providers/github-com \
  --inference-region global \
  --dry-run
```

Do not copy the old EnMaaS `inference.gateway` block, `gateway/...` models,
or gateway-key forwarding into this installation. The November 18 restriction
on uploading an EnMaaS token to GitHub still applies. Use the existing central
WIF provider rather than attempting to provision a new pool in the billing
project.

## Validation and acceptance

1. Re-run the existing manual Vertex smoke test with explicit inputs
   `model=claude-sonnet-5-5`, `location=global`, and `invoke_model=true`.
   Its workflow default still names Sonnet 4.6, so do not rely on that default.
2. Validate triage on a small issue. Check model identity, tool execution,
   structured output, labels, and skip-label handling. Keep automatic
   triage-to-code promotion off during initial validation.
3. Validate review on a same-repository PR and through `/fs-review` on a fork
   PR. Confirm native delegation uses Sonnet 5.5 and produces a valid final
   review result. Retain the earlier pilot's medium severity threshold if
   reusing its review policy, setting runner and sandbox values consistently.
4. Validate code and fix on a scoped issue and its resulting PR. Confirm the
   branch and PR target `migtools/crane`, required CI runs, and fix updates the
   intended PR. Human review and existing merge requirements still apply.
5. Validate retro and prioritize with bounded inputs. Check delegated models
   for retro and inspect the issue changes produced by prioritize.
6. Include a run long enough to cross a credential-refresh interval. Confirm
   inference still works afterward. A successful one-shot REST call does not
   prove Fullsend's credential refresh.
7. Record run URLs, Fullsend and fleet revisions, runtime, requested and served
   models, test results, latency, retries, and token usage. Check actual Vertex
   consumption in `mta-ops-fs-agents` against the agreed budget and owner.

Installation is complete when the v0.57.0 scaffold is merged, all six agents
have successful live validation, and parent/child inference and credential
refresh are verified. Until then, report Vertex connectivity as verified and
Fullsend agent integration as pending.

## E2E and cross-repository follow-up

Use the [E2E implementation assignment](FULLSEND_E2E_IMPLEMENTATION_ASSIGNMENT.md)
for the progression through PR CI, runner-local minikube, and internal
OpenShift or CRC validation. Apply this plan's repository, release, runtime,
and model settings when using that earlier assignment.

The [cross-repository experiment](FULLSEND_CROSS_REPOSITORY_PILOT.md) remains
a separate follow-up. The personal `aufi` repositories are outside the
current ITPC allowlist. A library rollout needs its own approved repository,
repo-scoped IAM access, App access, and independent validation.

## Sources

- [Fullsend v0.57.0 release and migration notes](https://github.com/fullsend-ai/fullsend/releases/tag/v0.57.0)
- [Fleet agents v0.57.0 release](https://github.com/fullsend-ai/agents/releases/tag/v0.57.0)
- [GitHub setup CLI and re-run semantics](https://github.com/fullsend-ai/fullsend/blob/v0.57.0/docs/cli/github.md)
- [Configuration reference](https://github.com/fullsend-ai/fullsend/blob/v0.57.0/docs/reference/config-reference.md)
- [Claude runtime, model fallback, and native subagents](https://github.com/fullsend-ai/fullsend/blob/v0.57.0/docs/runtimes/claude.md)
- [Review harness default model and environment](https://github.com/fullsend-ai/agents/blob/v0.57.0/harness/review.yaml)
- [OpenShell pin](https://github.com/fullsend-ai/fullsend/blob/v0.57.0/.github/scripts/openshell-version.sh)
- [Crane manual WIF smoke-test workflow](https://github.com/migtools/crane/blob/bff861f66341b166bb9082164d7d225fc7d40d54/.github/workflows/vertex-wif-smoke-test.yml)
