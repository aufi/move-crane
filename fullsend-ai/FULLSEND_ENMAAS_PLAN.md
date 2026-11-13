# Fullsend v0.54.0 and EnMaaS DeepSeek pilot plan

Deployment and validation are now recorded in the
[November 13 deployment record](FULLSEND_ENMAAS_DEPLOYMENT_2026-11-13.md).
The v0.55.0 configuration PR is merged, and triage, review, code, and fix have
passed live GitHub Actions verification with EnMaaS/DeepSeek. See the
[agent validation record](FULLSEND_ENMAAS_AGENT_VALIDATION_2026-11-13.md) for
review delegation and the code/fix PR lifecycle. The pending connection details
below describe the original November 10 plan; use the deployment and validation
records for current values and remaining live-cluster E2E work.

For the subsequent v0.55.0 release, required tracker migration, and confirmed
review-persona routing rules, see the
[November 13 update review](FULLSEND_UPDATES_2026-11-13.md).

## Status and scope

Updated on November 10, 2026. The selected inference service is EnMaaS and the
selected model is DeepSeek-V4.1-Flash-1017. Connection details will be supplied
later.
This is the current upgrade plan for `aufi/crane-fullsend-pilot`; deployment
and a successful DeepSeek run have not been verified.

DeepSeek-V4.1-Flash-1017 replaces GLM-5.3 as the primary model. Both are
available to the pilot at the same price. The choice follows the published
coding and agentic results for the 1017 update, not a completed Crane
evaluation. GLM-5.3 remains a comparison candidate for selected review tasks.

This plan supersedes the version, runtime, inference, credential, and cost
instructions in [the v0.44.0 runbook](FULLSEND_V0.44.0_RUNBOOK.md). That runbook
remains the historical record of the OpenAI/Codex setup. Its repository
boundaries, GitHub App setup, branch protection, and triage/review/code/fix
validation sequence remain the basis for this pilot.

The separate [migtools evaluation](FULLSEND_MIGTOOLS_EVALUATION.md) describes
an earlier organization-adoption proposal. This plan applies to the disposable
personal pilot and does not record a provider decision for `migtools`.

## Decisions and details to supply

| Item | Planned value or open detail |
| --- | --- |
| Repository | `aufi/crane-fullsend-pilot` |
| Fullsend | `v0.54.0`, released November 3, 2026 |
| Local OpenShell | `0.1.4`, the version pinned by Fullsend v0.54.0 |
| Inference service | EnMaaS |
| Primary model | DeepSeek-V4.1-Flash-1017, the October 17, 2026 update |
| Comparison model | GLM-5.3 for selected side-by-side review tasks |
| Exact gateway model ID | Pending. Use the ID supplied by EnMaaS, including any prefix, and confirm that it resolves to the 1017 update. |
| Gateway URL | Pending. HTTPS origin or path prefix, without trailing `/v1`. |
| Runtime | Pending API confirmation; prefer `pi` for Chat Completions or Messages. |
| Model API | Pending. Confirm `openai-completions` or `anthropic-messages` and streaming tool calls. |
| Authentication | Pending. Confirm API key or direct trust of GitHub Actions OIDC. |
| Messages key header | Pending if using Messages with an API key. Confirm Bearer or `x-api-key`. |
| Runner connectivity | Pending. Confirm access from both the intended CI runner and local OpenShell host. |
| Limits | Pending. Context/output limits, reasoning settings, quotas, and concurrency. |
| Accounting | Pending. EnMaaS usage source, budget owner, and pilot cost ceiling. |

Do not infer an exact model ID or API dialect from the display name DeepSeek
V4.1 Flash. The official DeepSeek API currently maps `deepseek-flash` to the
1017 update, but that does not establish EnMaaS alias behavior. Confirm the
served version with the EnMaaS operator or catalog. Do not silently substitute
the original V4.1 Flash or GLM-5.3 if the selected version is unavailable.

## Runtime and gateway route

Use Fullsend's `inference.gateway` route with a model named
`gateway/<exact-enmaas-model-id>`. It is available from v0.47.0 on pi, Claude
Code, and Codex; v0.48.1 adds `x-api-key` for Messages requests.

The preferred runtime for this plan is pi, subject to the supplied EnMaaS API
details. It supports gateway models using Chat Completions or Messages and
requires an explicit model catalog in `inference.gateway.models` or
`models_file`. Confirm DeepSeek tool-call and reasoning behavior with a real run.

Do not carry the old Codex selection into this migration by default. Codex
requires `/v1/responses`, and its gateway route has no native sub-agents. Only
consider it if EnMaaS confirms Responses support for this exact model.

Claude Code is an alternative if EnMaaS exposes a compatible Messages API.
Its native sub-agents must inherit the selected model or use an explicit
EnMaaS-served ID rather than default Anthropic model aliases. Keep pi as the
initial choice until a comparison run justifies changing it.

### Configuration outline

The following is a template, not a configuration ready to install. It shows
the API-key and Chat Completions option; neither is confirmed yet.

```yaml
inference:
  gateway:
    url: https://<enmaas-host-and-optional-prefix>
    auth: api-key
    models:
      <exact-enmaas-model-id>:
        api: openai-completions

agents:
  - name: triage
    runtime: pi
    model: gateway/<exact-enmaas-model-id>
  - name: review
    runtime: pi
    model: gateway/<exact-enmaas-model-id>
  - name: code
    runtime: pi
    model: gateway/<exact-enmaas-model-id>
  - name: fix
    runtime: pi
    model: gateway/<exact-enmaas-model-id>
```

If the supplied endpoint uses Messages, change the catalog API to
`anthropic-messages`. If that API requires an `x-api-key` header, also add
`messages_auth_header: x-api-key` under `gateway`. The default is Bearer.

For API-key authentication, store the EnMaaS key as the repository secret
`FULLSEND_INFERENCE_GATEWAY_API_KEY`. Local runs receive it in the runner's
environment. Fullsend manages the sandbox credential placeholder.

For direct GitHub OIDC trust, use `auth: oidc`, set the operator-provided
`audience`, and confirm that the repository is allowed by the gateway. Remove
the API-key-specific header setting. An EnMaaS SSO login alone does not prove
that the gateway trusts a GitHub Actions OIDC token.

Set the model on every enabled agent and any explicit sub-agent model
overrides. Inspect inherited model selections so that review and other
delegating agents do not silently keep Claude/OpenAI defaults. Record any
DeepSeek-specific effort and token settings after they are supplied and tested.

### Reasoning and multi-turn tool calls

Start with reasoning enabled for code, fix, and review. Confirm how the gateway
maps the runtime's effort levels to DeepSeek's supported settings. Evaluate
lower effort or non-thinking mode for triage after the baseline works; do not
assume the same effort label gives GLM and DeepSeek equal compute budgets.

For Chat Completions in thinking mode, DeepSeek's official API requires prior
assistant `reasoning_content` to be preserved in subsequent requests carrying
`tools`. Verify that the selected runtime and EnMaaS route preserve the required
state across multiple tool calls and subsequent user turns. A successful
single-turn completion does not establish this compatibility.

## Upgrade from v0.44.0

1. Record the pilot's actual workflow refs, configuration, harness pins, runner
   image digest, and enabled agents before preparing the upgrade pull request.
2. Upgrade the local Fullsend runner to
   `ghcr.io/fullsend-ai/fullsend-runner:0.54.0` and record its digest. Upgrade
   local OpenShell to `0.1.4`. Check gateway health after the upgrade.
3. Refresh the per-repository scaffold with Fullsend v0.54.0 and
   `--fullsend-ref v0.54.0`. Review the generated pull request. Update pinned
   `fullsend-ai/agents` harnesses and images as well as the CLI/workflow ref.
4. Apply the confirmed EnMaaS gateway block and exact
   DeepSeek-V4.1-Flash-1017 settings. Add the gateway secret only if API-key
   authentication is selected.
5. Migrate custom harnesses, if present. Use bare built-in provider names,
   remove obsolete copied provider/profile definitions, declare or inherit
   `policy:`, and check compatibility with v0.49.0 sandbox restrictions.
6. Use `agents[].enabled` to control which agents run; do not rely on legacy
   `roles`. Preserve the controlled validation order of triage, review, code,
   then fix. Inspect dispatch triggers before enabling automatic runs.
7. Keep the existing per-repository installation path for this upgrade. If
   moving to `repos.yaml` later, account for managed-file adoption and the
   current manifest schema rather than replaying old `repos install` flags.
8. Remove explicit OpenAI model selections and obsolete runtime overrides from
   the proposed configuration. After EnMaaS validation succeeds, remove the
   unused `FULLSEND_OPENAI_API_KEY` repository secret and revoke its key if it
   belongs only to this pilot. Record that the old configuration then requires
   fresh credentials to restore.

## Validation sequence

Connection details are the next input needed to turn this plan into an
installation procedure.

1. Verify runner connectivity and an authenticated model request using the
   exact EnMaaS URL, API dialect, model ID, and selected authentication mode.
   Confirm the served model is the 1017 update. Check streaming and multi-turn
   tool calls with reasoning enabled, not only a plain-text completion.
2. Run `fullsend lint` with v0.54.0 against the completed configuration and
   harnesses. Resolve inherited model selections and configuration errors.
3. Run `fullsend inference gateway status aufi/crane-fullsend-pilot`. In
   API-key mode this checks configuration and credential presence, not a live
   model request. Use an actual agent run to verify inference.
4. Perform a local triage smoke test on a clean pilot checkout with
   `--no-post-script`. Verify the selected runtime/model, tool execution,
   structured output, and recorded usage.
5. Run controlled GitHub triage and review cases before code and fix. Confirm
   DeepSeek works with delegating review skills and their final structured
   result. Retain the runbook's human review and branch/target checks.
6. Compare usefulness, failed runs, latency, token usage, and EnMaaS accounting
   with the recorded v0.44.0 pilot results, where available. Mark results by
   version, runtime, exact model ID, and date.

On selected pull requests, compare DeepSeek-V4.1-Flash-1017 with GLM-5.3 using
the same runtime, instructions, tool access, and task limits. Record confirmed
findings, false positives, completed fixes, test results, retries, latency, and
usage. Since token pricing is equal for this pilot, prioritize useful completed
work and total consumption rather than assuming a cheaper DeepSeek endpoint.

Gateway token metrics may be incomplete for some streaming responses. Use
EnMaaS accounting to check consumption rather than interpreting zero reported
usage as a free run.

## Cross-repository follow-up

The initial development use case is E2E test implementation. Follow the
[E2E implementation assignment](FULLSEND_E2E_IMPLEMENTATION_ASSIGNMENT.md)
for the agreed progression through PR CI, runner-local minikube validation,
and internal OpenShift or CRC execution.

The [Crane/library experiment](FULLSEND_CROSS_REPOSITORY_PILOT.md) uses the same
Fullsend version and confirmed EnMaaS/DeepSeek settings when the library pilot is
installed. If using API keys, provision its gateway secret separately in
`aufi/crane-lib-pilot`. Validate that repository independently before running
code or fix there.

## Sources

- [Fullsend v0.54.0 release](https://github.com/fullsend-ai/fullsend/releases/tag/v0.54.0)
- [Fleet agents v0.54.0](https://github.com/fullsend-ai/agents/releases/tag/v0.54.0)
- [Inference gateway guide v0.54.0](https://github.com/fullsend-ai/fullsend/blob/v0.54.0/docs/guides/user/inference-gateway.md)
- [pi runtime v0.54.0](https://github.com/fullsend-ai/fullsend/blob/v0.54.0/docs/runtimes/pi.md)
- [Codex runtime and gateway limitations v0.54.0](https://github.com/fullsend-ai/fullsend/blob/v0.54.0/docs/runtimes/codex.md)
- [OpenShell pin v0.54.0](https://github.com/fullsend-ai/fullsend/blob/v0.54.0/.github/scripts/openshell-version.sh)
- [EnMaaS operations and API smoke tests](https://github.com/redhat-et/EnMaaS-opps#smoke-test)
- [DeepSeek-V4.1-Flash-1017 model card and published results](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash-1017)
- [DeepSeek API model versions](https://api-docs.deepseek.com/quick_start/pricing)
- [DeepSeek reasoning and multi-turn tool-call requirements](https://api-docs.deepseek.com/guides/thinking_mode)
