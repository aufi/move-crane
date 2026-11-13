# EnMaaS pilot deployment and triage validation, November 13, 2026

## Status

Configuration PR: [aufi/crane-fullsend-pilot#16](https://github.com/aufi/crane-fullsend-pilot/pull/16).
Candidate commit: `37400a8ff2f2405d642c8e73c49a0e47ebeae275`.

The PR's build/unit, lint, PR conventions, and ticket-guard checks passed.
It was merged on November 13 at 14:36:52 UTC as
`737eadd00499192af93b5d98045c5d36a90b05a3`. The EnMaaS configuration is active on
the default branch. The first complete GitHub Actions triage smoke test passed.

Subsequently, [PR #18](https://github.com/aufi/crane-fullsend-pilot/pull/18)
enabled review, code, and fix. All three completed live verification; see the
[agent validation record](FULLSEND_ENMAAS_AGENT_VALIDATION_2026-11-13.md).

`FULLSEND_INFERENCE_GATEWAY_API_KEY` has been provisioned on the pilot repository
from the operator's existing `ENMAAS_KEY` environment variable. No credential
value was written to these documents or committed to the pilot.

## Confirmed connection and deployed configuration

| Setting | Deployed value |
| --- | --- |
| Pilot repository | `aufi/crane-fullsend-pilot` |
| Gateway | `https://api.enmaas.devshift.net` |
| Exact model ID | `rits/deepseek-ai/DeepSeek-V4.1-Flash-1017` |
| Fullsend model | `gateway/rits/deepseek-ai/DeepSeek-V4.1-Flash-1017` |
| API and authentication | Chat Completions, API key in Authorization Bearer |
| Fullsend workflow and CLI | v0.55.0 |
| Agents revision | `3b40ac718d29c3190b71e68447b9f4e938f19974`, agents v0.55.0 |
| Runtime | pi 1.5.0 in the pinned fleet sandbox images |
| Gateway extension | pi-inference-gateway 0.2.0 |
| CI OpenShell | 0.1.4, confirmed in the triage run |

The gateway URL came from EnMaaS's production operations configuration. The
authenticated live model catalog confirmed the exact selected model ID.

The PR migrates the old tracker schema to `tracker.github.allowed_targets`,
preserving the pilot's actual explicit issue target, `fullsend-ai/fullsend`.
It pins harness content by commit and integrity hash and explicitly routes all
ten review personas to the selected gateway model.

Only manually triggered triage is enabled initially. Triage-to-code promotion
is off. Review, code, fix, retro, and prioritize are disabled pending staged
validation. The old OpenAI secret is retained for rollback during migration.

This describes the initial PR #16 rollout. PR #18 subsequently enabled review,
code, and fix while keeping automatic triage promotion off and retro/prioritize
disabled.

## Verification completed

- The authenticated `/v1/models` request returned HTTP 200 and the selected ID.
- Direct streaming Chat Completions succeeded with high reasoning effort,
  function-call arguments, a tool result, and a subsequent user turn. Responses
  identified the selected model and a reasoning field was observed.
- An isolated pi 1.5.0 run with gateway extension 0.2.0 successfully invoked
  a read-only file tool and returned the expected result.
- Fullsend v0.55.0 lint resolved all four configured agent harnesses with zero
  errors and nine fleet harness warnings. The final triage-only activation
  configuration has zero errors and three fleet harness warnings.
- Gateway status resolved the intended config and local credential presence.
  In API-key mode this command does not send an inference request.
- Actionlint, diff whitespace checks, and a scan for literal values of the
  available EnMaaS and GitHub credentials passed.
- All PR checks passed. The old workflow skipped agent dispatch for the
  `fullsend/scaffold-install` branch, as intended.

The isolated runtime test did not exercise OpenShell. The subsequent GitHub
Actions run below closes that gap for triage. Local OpenShell remains 0.1.2;
the CI run installed and used the pinned 0.1.4 release independently.

## Complete GitHub Actions triage smoke test

- Trigger: human [`/fs-triage` comment on issue #10](https://github.com/aufi/crane-fullsend-pilot/issues/10#issuecomment-6856077949).
- Run: [43444515213](https://github.com/aufi/crane-fullsend-pilot/actions/runs/43444515213), successful.
- Tested configuration: merged commit `737eadd00499192af93b5d98045c5d36a90b05a3`.
- Result: `action: question`; output passed the triage JSON schema on the first
  iteration, and the post-script published the answer on the issue.

The job confirmed Fullsend 0.55.0, OpenShell 0.1.4, runtime pi, effort high, and
served model `rits/deepseek-ai/DeepSeek-V4.1-Flash-1017`. It created the run-scoped
inference gateway provider, successfully performed inference and GitHub tool
operations from the sandbox, and deleted the provider during cleanup. The
OpenAI provider declared by the inherited harness was explicitly skipped as
unnecessary for this gateway run.

| Measurement | Recorded value |
| --- | --- |
| Triage job duration | 2 min 41 s, including environment setup |
| Agent execution | 48.8 s |
| Agent iterations / turns | 1 / 8 |
| Tool calls | 7 |
| Tool errors / unanswered calls | 1 / 0 |
| Input tokens | 21,225 |
| Cache-read tokens | 122,048 |
| Output tokens | 3,708 |
| Reported reasoning tokens | 1,855, included in pi output accounting |
| Runtime-reported estimated cost | USD 0.011671436 |

The recoverable tool error came from an unsupported `gh` JSON field, `type`.
The agent continued and produced a valid result. No inference or authentication
failure was reported. The transcript records gateway-served reasoning and
multiple tool-result turns.

The cost is pi's catalog-based estimate, with `totalFromProvider: false` in the
transcript, not a confirmed EnMaaS charge. Check EnMaaS accounting before using
it as a billing result.

Code, fix, review, retro, and prioritize jobs were skipped. The issue event
generated by triage's post-script produced a routing-only follow-up run,
[43444971259](https://github.com/aufi/crane-fullsend-pilot/actions/runs/43444971259),
with every agent job skipped. No automatic code promotion occurred.

## Next step

Review, code, and fix are now enabled and their lifecycle checks passed, as
recorded in the [agent validation results](FULLSEND_ENMAAS_AGENT_VALIDATION_2026-11-13.md).
Proceed with pilot development tasks and the planned live-cluster E2E setup.

The pilot's [activation guide](https://github.com/aufi/crane-fullsend-pilot/blob/737eadd00499192af93b5d98045c5d36a90b05a3/FULLSEND_ENMAAS.md)
contains the detailed sequence and rollback procedure. Provider-side quotas,
context/output limits, and the pilot cost ceiling still need confirmation.

E2E cluster provisioning remains a follow-up under the
[E2E implementation assignment](FULLSEND_E2E_IMPLEMENTATION_ASSIGNMENT.md).
