# Fullsend v0.54.0 and EnMaaS GLM-5.3 pilot plan

## Status and scope

Updated on November 6, 2026. The selected inference service is EnMaaS and the
selected model family is GLM-5.3. Connection details will be supplied later.
This is the current upgrade plan for `aufi/crane-fullsend-pilot`; deployment
and a successful GLM-5.3 run have not been verified.

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
| Model family | GLM-5.3 |
| Exact gateway model ID | Pending. Use the ID supplied by EnMaaS, including any prefix. |
| Gateway URL | Pending. HTTPS origin or path prefix, without trailing `/v1`. |
| Runtime | Pending API confirmation; prefer `pi` for Chat Completions or Messages. |
| Model API | Pending. Confirm `openai-completions` or `anthropic-messages` and streaming tool calls. |
| Authentication | Pending. Confirm API key or direct trust of GitHub Actions OIDC. |
| Messages key header | Pending if using Messages with an API key. Confirm Bearer or `x-api-key`. |
| Runner connectivity | Pending. Confirm access from both the intended CI runner and local OpenShell host. |
| Limits | Pending. Context/output limits, reasoning settings, quotas, and concurrency. |
| Accounting | Pending. EnMaaS usage source, budget owner, and pilot cost ceiling. |

Do not infer an exact model ID or API dialect from the display name GLM-5.3.
Do not substitute another model if it is unavailable.

## Runtime and gateway route

Use Fullsend's `inference.gateway` route with a model named
`gateway/<exact-enmaas-model-id>`. It is available from v0.47.0 on pi, Claude
Code, and Codex; v0.48.1 adds `x-api-key` for Messages requests.

The preferred runtime for this plan is pi, subject to the supplied EnMaaS API
details. It supports gateway models using Chat Completions or Messages and
requires an explicit model catalog in `inference.gateway.models` or
`models_file`. Confirm GLM-5.3 tool-call and reasoning behavior with a real run.

Do not carry the old Codex selection into this migration by default. Codex
requires `/v1/responses`, and its gateway route has no native sub-agents. Only
consider it if EnMaaS confirms Responses support for this exact model.

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
GLM-5.3-specific effort and token settings after they are supplied and tested.

## Upgrade from v0.44.0

1. Record the pilot's actual workflow refs, configuration, harness pins, runner
   image digest, and enabled agents before preparing the upgrade pull request.
2. Upgrade the local Fullsend runner to
   `ghcr.io/fullsend-ai/fullsend-runner:0.54.0` and record its digest. Upgrade
   local OpenShell to `0.1.4`. Check gateway health after the upgrade.
3. Refresh the per-repository scaffold with Fullsend v0.54.0 and
   `--fullsend-ref v0.54.0`. Review the generated pull request. Update pinned
   `fullsend-ai/agents` harnesses and images as well as the CLI/workflow ref.
4. Apply the confirmed EnMaaS gateway block and exact GLM-5.3 model settings.
   Add the gateway secret only if API-key authentication is selected.
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
   Check streaming and tool calls, not only a plain-text completion.
2. Run `fullsend lint` with v0.54.0 against the completed configuration and
   harnesses. Resolve inherited model selections and configuration errors.
3. Run `fullsend inference gateway status aufi/crane-fullsend-pilot`. In
   API-key mode this checks configuration and credential presence, not a live
   model request. Use an actual agent run to verify inference.
4. Perform a local triage smoke test on a clean pilot checkout with
   `--no-post-script`. Verify the selected runtime/model, tool execution,
   structured output, and recorded usage.
5. Run controlled GitHub triage and review cases before code and fix. Confirm
   GLM-5.3 works with delegating review skills and their final structured
   result. Retain the runbook's human review and branch/target checks.
6. Compare usefulness, failed runs, latency, token usage, and EnMaaS accounting
   with the recorded v0.44.0 pilot results, where available. Mark results by
   version, runtime, exact model ID, and date.

Gateway token metrics may be incomplete for some streaming responses. Use
EnMaaS accounting to check consumption rather than interpreting zero reported
usage as a free run.

## Cross-repository follow-up

The [Crane/library experiment](FULLSEND_CROSS_REPOSITORY_PILOT.md) uses the same
Fullsend version and confirmed EnMaaS/GLM-5.3 settings when the library pilot is
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
