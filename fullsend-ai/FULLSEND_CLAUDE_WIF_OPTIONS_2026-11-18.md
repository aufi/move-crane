# Claude inference without an EnMaaS token on GitHub

Research date: November 18, 2026.

## Conclusion

Use GitHub Actions OIDC with GCP Workload Identity Federation to invoke Claude
on Vertex AI. This is a supported Fullsend path in the pilot's existing
v0.55.0 release. It needs no Anthropic API key, EnMaaS key, or service-account
private key on GitHub. Either the Claude Code runtime or pi can use it.

For the requested return to Claude, prefer `runtime: claude`. Keeping pi and
changing only inference is also supported. WIF is the authentication choice;
the runtime choice is independent.

This recommendation replaces the API-key credential recommendation in the
[EnMaaS plan](FULLSEND_ENMAAS_PLAN.md). The November 13 deployment and validation
documents remain records of the earlier experiment.

## Observed pilot state

The public default-branch files were read on November 18:

- Repository: `aufi/crane-fullsend-pilot`.
- The shim calls Fullsend `v0.55.0` and already grants `id-token: write`.
- Triage, review, code, and fix use pi and
  `gateway/rits/deepseek-ai/DeepSeek-V4.1-Flash-1017`.
- `inference.gateway` selects EnMaaS with `auth: api-key`.
- Review has explicit gateway overrides for its personas. Code and fix also
  have gateway subagent defaults.
- The shim already forwards `FULLSEND_GCP_PROJECT_ID` and
  `FULLSEND_GCP_WIF_PROVIDER`, alongside the gateway and OpenAI secrets.
- Local triage and review harnesses wrap pinned fleet harnesses. They preserve
  manual triage, `TRIAGE_AUTO_CODE: "off"`, and the medium review threshold.

The [deployment record](FULLSEND_ENMAAS_DEPLOYMENT_2026-11-13.md) says the EnMaaS
key was provisioned as `FULLSEND_INFERENCE_GATEWAY_API_KEY`. Its current
existence was not checked. Authenticated GitHub reads failed with HTTP 401;
public files were retrieved over HTTPS instead. No GCP project, IAM policy,
model entitlement, or live inference was inspected.

GitHub reports v0.56.1, released November 14, as the latest Fullsend release.
WIF migration does not require that upgrade. A later upgrade needs its own
review of CLI, workflows, harnesses, and sandbox pins.

## Supported options

| Option | GitHub stores a reusable inference key | Required infrastructure | Assessment |
| --- | --- | --- | --- |
| Claude Code with Vertex WIF | No | GCP project, billing, enabled Claude models, repo-scoped WIF | Recommended for the requested Claude setup. |
| pi with Claude on Vertex WIF | No | Same GCP setup | Supported way to retain the current runtime. Use `anthropic-vertex/<model-id>` or a Claude alias. |
| Claude or pi through an OIDC gateway | No | Gateway that validates GitHub OIDC and holds upstream credentials or uses its own cloud identity | Useful if an approved shared gateway already exists, or direct sandbox credentials are disallowed. |
| Existing EnMaaS gateway changed to `auth: oidc` | No, if supported by EnMaaS | EnMaaS must explicitly trust GitHub's issuer, audience, and allowed repository | Conditional. No such support was verified. An SSO login does not establish it. |

The last option preserves access to EnMaaS models; it does not establish that
EnMaaS serves Claude. Fullsend's gateway OIDC route validates the GitHub token
directly. It has no generic exchange from GitHub OIDC to an EnMaaS/SSO token.

Bedrock or another Claude backend is not a documented drop-in route for the
Fullsend Claude runtime in the inspected release. Its documented routes are
Vertex and an Anthropic-compatible inference gateway. Claude Code's standalone
provider support does not establish Fullsend integration support.

## What direct Vertex WIF does

1. The Actions job requests a short-lived GitHub OIDC token.
2. Fullsend supplies an `external_account` credential configuration and the
   actual OIDC token to the sandbox.
3. Google's authentication library exchanges that token with GCP STS for
   access to Vertex. The federated principal has `roles/aiplatform.user`.
4. Fullsend refreshes the GitHub OIDC token every four minutes during the run.

The standard provisioner uses direct federated access. It does not require
creating a service-account JSON key or a separate service account.

This path removes long-lived inference keys. It does not remove actual
short-lived credentials from the sandbox. The OIDC gateway path differs:
the runner keeps the actual token behind OpenShell, and the sandbox gets a
placeholder. If the policy also prohibits actual tokens in the sandbox, use
the gateway path rather than direct Vertex WIF.

GitHub API access is separate. The existing token mint issues GitHub App
installation tokens for comments and PRs. Configuring Vertex WIF does not
replace that mint or require moving App private keys into GitHub.

## Inputs needed from the GCP owner

- A billing-enabled GCP project approved for this pilot and a spending owner.
- Enabled `iam.googleapis.com`, `cloudresourcemanager.googleapis.com`, and
  `aiplatform.googleapis.com` APIs.
- Claude model access enabled in Model Garden, including models used by
  review subagents. API enablement alone does not grant model access.
- A supported inference location. Fullsend defaults to `global`; confirm
  availability for every selected model and any location requirements.
- A repo-scoped WIF provider and its full resource name.

The person provisioning WIF needs
`roles/iam.workloadIdentityPoolAdmin` and
`roles/resourcemanager.projectIamAdmin`. These are setup permissions, not
permissions to grant to the agent. Runtime access uses `roles/aiplatform.user`.

Use the exact repository scope `aufi/crane-fullsend-pilot`, rather than all of
`aufi`. If the organization requires custom claims, an administrator can supply
an existing provider. Numeric `repository_id` and `repository_owner_id` checks
can prevent a reused repository or owner name from inheriting trust. Branch or
workflow restrictions must account for both issue-comment and PR event claims,
including reusable workflows. Do not assume a `main` ref condition covers them
all.

Budget alerts report spending; they are not a hard spending cap. Agree on
quotas, dispatch limits, and a way to stop runs separately.

## Migration outline

These are preparation commands and configuration requirements, not a record of
executed setup.

### 1. Stop using the prohibited credential

Disable Fullsend dispatch and cancel active agent jobs before the transition.
Delete `FULLSEND_INFERENCE_GATEWAY_API_KEY` from the pilot repository. Ask the
EnMaaS key owner to revoke or rotate the uploaded credential, accounting for any
other consumers of the same key. Keeping it for rollback conflicts with the new
constraint.

### 2. Provision or inspect repo-scoped WIF

With the chosen, pinned Fullsend CLI and an authenticated GCP administrator:

```bash
fullsend inference provision aufi/crane-fullsend-pilot \
  --project "$GCP_PROJECT"

fullsend inference status aufi/crane-fullsend-pilot \
  --project "$GCP_PROJECT"
```

If the provider already exists, inspect its condition and IAM grants first.
The printed provider name contains the project number, not the project ID.

### 3. Configure the pilot

The supported setup entry point for the current version is:

```bash
fullsend github setup aufi/crane-fullsend-pilot \
  --inference-project "$GCP_PROJECT" \
  --inference-wif-provider "$WIF_PROVIDER" \
  --runtime claude \
  --fullsend-ref v0.55.0
```

Review the resulting configuration before merging. Setup flags alone do not
remove old per-agent overrides or the gateway block. The desired diff must:

- Set the default and all enabled agent runtimes to `claude`, or remove the
  per-agent pi overrides so they inherit `claude`.
- Replace every `gateway/...` parent model with a Claude model available in
  the project. Sonnet is a reasonable first triage model; select code and
  review models after confirming project access and cost.
- Remove the EnMaaS `inference.gateway` block and gateway subagent overrides.
- Preserve manual triage, disabled triage-to-code promotion, the review
  threshold, and pinned harness sources.
- Keep `FULLSEND_GCP_PROJECT_ID` and `FULLSEND_GCP_WIF_PROVIDER` as the two
  repository secrets expected by the scaffold. Their values are identifiers,
  not private credentials. Set `FULLSEND_GCP_REGION` to the chosen location.
- Remove unused inference-key forwarding and any obsolete OpenAI credential
  after confirming it has no remaining consumer. Refresh managed workflow
  files through supported scaffolding rather than hand-editing them blindly.

For the pi variant, retain `runtime: pi` and use Claude Vertex models for
parents and every explicitly overridden persona. Changing only
`subagents.default` does not override personas with their own models.

### 4. Check Claude subagent model selection

Claude Code resolves native subagent aliases itself. Fullsend's parent
`models.aliases` table and its fallback chains do not control those aliases,
and the configuration reference describes `agents[].subagents` tuning for pi
and Codex. Do not assume the old pi persona map controls Claude Code.

Either enable all native persona models in the project or pin the Claude Code
tiers through the harness's sandbox environment using
`ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, and
`ANTHROPIC_DEFAULT_HAIKU_MODEL`. Use model IDs supported by the pinned Claude
Code version and the selected Vertex location. Confirm the actual resolved
models in a review run, including any explicitly pinned persona frontmatter.

### 5. Verify from GitHub Actions

Run `fullsend lint`, then validate triage, review with delegation, code, and
fix in that order. A local ADC test or `inference status` does not prove that
the GitHub job can exchange its identity and invoke a model.

Check that the run uses Vertex, that parent and child models resolve as
intended, and that inference still works after a token refresh. Check actual
GCP usage separately from runtime cost estimates. Re-enable normal dispatch
after these checks.

## Outstanding decisions

1. Which GCP project and administrator can provide repo-scoped WIF and Claude
   model access?
2. Is the restriction limited to long-lived provider keys on GitHub, or does it
   also exclude actual short-lived credentials inside the sandbox?
3. Which Claude models and location are approved, and what is the pilot budget?

The first item is the practical dependency for direct WIF setup. The second
decides whether direct Vertex access or an OIDC gateway is appropriate.

## Setup attempt with mta-ops-fs-agents

Verified on November 18 after refreshing the GCP login:

| Item | Observed value |
| --- | --- |
| GCP identity | `maufart@redhat.com` |
| Project ID | `mta-ops-fs-agents` |
| Project number | `500881529329` |
| Project state and billing | Active; billing enabled |
| Required APIs | IAM, Cloud Resource Manager, and Vertex AI already enabled |
| Existing WIF pools | None returned in `global` |
| GitHub repository ID | `1380442927` |
| GitHub owner ID | `555381` |

Creating `fullsend-inference` failed with `PERMISSION_DENIED` for
`iam.workloadIdentityPools.create`. No WIF resource or GitHub setting was
changed. The account needs `roles/iam.workloadIdentityPoolAdmin` on this
project, or an administrator must create the pool and provider.

The project's existing IAM policy grants the developer group conditional
`roles/resourcemanager.projectIamAdmin` restricted to changes to
`roles/aiplatform.user`. That may permit the runtime binding below once the
pool exists; the binding has not been attempted. It does not permit granting
the missing WIF administration role.

A minimal authenticated Vertex request to `claude-sonnet-4-6` in `global`
returned HTTP 404: model not found or project access unavailable. This does not
establish which Claude models, if any, are enabled. The project owner must
confirm an enabled Claude model and supported location, or enable the intended
model in Model Garden. This request used the developer's GCP identity, not WIF.

### Commands for the GCP administrator

These commands have not succeeded or been executed beyond the failed pool
creation. They create a repository-scoped provider with numeric identity
checks, then grant Vertex invocation access to the repository principal.

```bash
gcloud iam workload-identity-pools create fullsend-inference \
  --location=global \
  --project=mta-ops-fs-agents \
  --display-name='Fullsend inference'

gcloud iam workload-identity-pools providers create-oidc gh-aufi-crane-fullsend-pilot \
  --location=global \
  --workload-identity-pool=fullsend-inference \
  --project=mta-ops-fs-agents \
  --issuer-uri='https://token.actions.githubusercontent.com' \
  --attribute-mapping='google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_id=assertion.repository_id,attribute.repository_owner_id=assertion.repository_owner_id' \
  --attribute-condition="assertion.repository == 'aufi/crane-fullsend-pilot' && assertion.repository_id == '1380442927' && assertion.repository_owner_id == '555381'"

gcloud projects add-iam-policy-binding mta-ops-fs-agents \
  --member='principalSet://iam.googleapis.com/projects/500881529329/locations/global/workloadIdentityPools/fullsend-inference/attribute.repository/aufi/crane-fullsend-pilot' \
  --role=roles/aiplatform.user \
  --condition=None
```

The resulting provider resource name will be:

```text
projects/500881529329/locations/global/workloadIdentityPools/fullsend-inference/providers/gh-aufi-crane-fullsend-pilot
```

Only configure that value on GitHub after the provider and IAM binding exist
and have been verified. A successful GitHub Actions inference test is still
required to confirm end-to-end WIF access.

## Sources

- [Pilot configuration](https://github.com/aufi/crane-fullsend-pilot/blob/main/.fullsend/config.yaml), read November 18. This link follows the current branch.
- [Pilot shim](https://github.com/aufi/crane-fullsend-pilot/blob/main/.github/workflows/fullsend.yaml), read November 18. This link follows the current branch.
- [Fullsend v0.55.0 authentication paths](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/user/how-fullsend-authenticates.md)
- [Getting Vertex inference](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/getting-started/getting-inference.md)
- [Inference CLI](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/cli/inference.md)
- [GitHub setup](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/getting-started/configuring-github.md)
- [Custom WIF and existing infrastructure](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/infrastructure/advanced-setup.md)
- [Claude runtime and native subagents](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/runtimes/claude.md)
- [pi Vertex providers and persona resolution](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/runtimes/pi.md)
- [Configuration reference](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/reference/config-reference.md)
- [OIDC gateway operator guide](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/infrastructure/inference-gateway-operator.md)
- [Claude Code on Vertex](https://code.claude.com/docs/en/google-vertex-ai)
- [Google Cloud Claude model access and invocation](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/partner-models/claude/use-claude)
- [Fullsend v0.56.1 release](https://github.com/fullsend-ai/fullsend/releases/tag/v0.56.1)
