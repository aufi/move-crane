# Fullsend update review, November 13, 2026

## Findings

The latest stable release is Fullsend **v0.55.0**, published November 11,
2026, with a matching `fullsend-ai/agents` v0.55.0 release. Our November 10
[EnMaaS plan](FULLSEND_ENMAAS_PLAN.md) targets v0.54.0. Use v0.55.0 as the
candidate for the next pilot upgrade, with the configuration migration below.

This is an upstream documentation and release review. The pilot's installed
state and EnMaaS connectivity were not checked, and no deployment was performed.
The DeepSeek choice and pending connection details remain as recorded in the plan.

## Released changes affecting the pilot

### Issue target configuration must migrate

v0.55.0 removes top-level `create_issues` and scalar `tracker` values.
Configuration loading rejects the old keys, including in `config.base.yaml`.
For the GitHub pilot, migrate the existing policy as follows:

```yaml
# Before
create_issues:
  allow_targets:
    repos:
      - aufi/crane-fullsend-pilot
      - fullsend-ai/fullsend
```

```yaml
# After
tracker:
  github:
    allowed_targets:
      repos:
        - aufi/crane-fullsend-pilot
        - fullsend-ai/fullsend
```

This preserves the recorded targets. Adding `aufi/crane-lib-pilot` remains a
separate cross-repository policy change. The GitHub App installation and target's
FOREIGN grant described in the [cross-repository plan](FULLSEND_CROSS_REPOSITORY_PILOT.md)
are still needed; changing YAML grants no token access.

`fullsend repos install` migrates legacy managed `config:` blocks in
`repos.yaml` and regenerates managed repository configuration. Its `--dry-run`
reports the migration without writing. Unmanaged, markerless configuration and
presets require manual edits. A `tracker` mapping replaces the whole inherited
mapping, so preserve the full intended provider and target policy in each layer.

Retro and triage post-scripts currently read target policy from the overlay,
not the preset. Put the needed targets in `.fullsend/config.yaml`, or the
repository's managed `config:` block, rather than only in `config.base.yaml`.

### Runtime and gateway versions

| Component | v0.54.0 sandbox | v0.55.0 sandbox |
| --- | --- | --- |
| pi | 1.3.0 | 1.5.0 |
| pi-inference-gateway | 0.1.4 | 0.2.0 |
| pi-anthropic-vertex | 0.1.1 | 0.2.1 |
| pi-xai-vertex | 0.2.1 | 0.3.1 |
| Codex | 0.159.3 | 0.166.0 |
| OpenShell pin | 0.1.4 | 0.1.4 |

The gateway extension v0.2.0 requires pi >= 1.3.0. Upgrade the runner,
workflow references, harness content, and sandbox images together and record
their pins or digests. `self-update` alone does not update those components.

pi transcripts now include tool-call IDs, arguments, and results. Calls cut
off before completion are reported as unanswered. This improves the evidence
available when investigating a failed DeepSeek tool sequence.

The inference gateway route still supports an explicit model catalog, API-key
or OIDC authentication, and the existing API dialects. The v0.55.0 gateway guide
does not introduce a new EnMaaS setup contract. The extension's v0.2.0 release
is a pi compatibility update; it does not establish that EnMaaS preserves
DeepSeek `reasoning_content`. Streaming, thinking mode, and multi-turn tool calls
still need live validation.

Codex gateway parents still require Responses API and have no native
sub-agents. Keep pi as the pilot's preferred runtime pending the EnMaaS API
details.

### Review model routing needs explicit persona overrides

The v0.55.0 pi documentation confirms a detail the existing plan should make
explicit. A persona's model resolves in this order:

1. `agents[].subagents.<persona>`.
2. The persona's frontmatter model.
3. `agents[].subagents.default`, when the persona has no model.
4. The parent model.

Setting the review parent to DeepSeek and `subagents.default` to DeepSeek does
not replace frontmatter choices such as `opus`, `sonnet`, or `haiku`. Inspect
the actual pinned roster and explicitly override every persona that must run
on EnMaaS. Check the Bootstrap model table and generated `personas.json` against
the expected roster before accepting a review result. This is a confirmed
configuration rule, not a new feature introduced by v0.55.0.

The agents release also runs the review challenger in the foreground and
writes a provisional review result before final synthesis. A provisional
result should not be counted as a completed review in pilot measurements.
The fix agent can now update a stale PR/MR title and body.

### CLI and harness compatibility

- `fullsend self-update` installs the latest or a selected release after
  Sigstore signature and checksum verification. It first appears in v0.55.0,
  so install that release through the existing download or container route.
  Later binary upgrades can use `self-update --dry-run` and `--version`.
- `fullsend lint --format json` now emits schema version 2 and a required
  `diagnostics[].code`. Update any scripts consuming that JSON.
- Harness `schema_version` is an integer, currently `1`. Omitting it remains
  valid. Malformed or unsupported values fail loading before composition.
- Retro on PR close or merge now requires an actor with write access. CEL
  routing errors skip the run. CEL also gains `event.actor.is_entity_assignee`
  for Jira and GitHub custom-agent triggers.

### Jira integration, if added to this pilot

Jira connection and polling settings move under `tracker.jira`, with
`base_url` and `project` required when connection settings are used. REST calls
use the Atlassian API gateway, normally `https://api.atlassian.com`, rather
than a site-URL REST mode.

Credentials use `FULLSEND_JIRA_TOKEN` and optional `FULLSEND_JIRA_EMAIL`, or
the mutually exclusive service-account OAuth client ID/secret pair.
Legacy `JIRA_TOKEN` is no longer read by the shared client. Harness scripts
must explicitly declare needed Jira secrets under `env.runner`. Managed Jira
polling is supported through `repos install` on GitHub and GitLab.

These Jira Cloud gateway requirements do not establish compatibility with a
self-hosted Jira installation. Verify the actual deployment
and API before selecting Fullsend's Jira integration.

## Changes on main, not released in v0.55.0

Reviewed Fullsend main at `944b5430c43edfbbe163f67e08ccfd5bea2194ba` and agents
main at `a69d9b550ce89131a66cd1e565f03ec5c97f9521`. These are snapshots, not
release recommendations.

- Run artifact filtering is implemented through `fullsend prepare-artifacts`
  and `artifacts.content` / `artifacts.by_source`. Levels are `all`, `metadata`,
  and `none`. This can limit artifacts for Jira-originated runs while keeping
  full artifacts for GitHub-originated runs. `metadata` removes conversations
  and agent results, which affects retro, resumption, and follow-up workflows.
  It leaves identifiers and metrics. Source-less runs get the strictest
  configured level, and withheld files have no private Fullsend archive.
- Remote fetch checks enforce the config-level `allowed_remote_resources`
  ceiling. Custom harnesses cannot expand it by declaring their own list.
- Lock replay rejects a policy URL pinned to a different revision.
  `readonly_repo` now inherits through `base:` composition.
- Managed configuration rendering accounts for the pinned `fullsend_ref`
  schema. Manifest writes gain concurrent-modification and read-only-input
  checks. These matter when an installer and target workflows use different
  versions.
- Jira polling skips individually invalid events, fails all-invalid cycles,
  bounds transported event fields, and gains an optional run-start label.
- Agents main improves triage's inventory of existing issue content and
  post-code push retry handling.

Accepted ADRs on main also describe Vault-backed named secret connections
and a phased requirement for explicit Jira authorization. An accepted design
does not establish released implementation. Do not add those settings to the
v0.55.0 pilot based only on the ADRs.

## Next pilot steps

1. Capture the actual installed pilot state and prepare a v0.55.0 upgrade
   diff, including the tracker migration in all relevant config layers.
2. Confirm the EnMaaS URL, model ID, API dialect, authentication, connectivity,
   reasoning settings, and accounting source as listed in the existing plan.
3. Configure every required review persona for the selected gateway model,
   validate with v0.55.0 lint, and inspect the resolved roster.
4. Run the existing local smoke test and controlled triage, review, code, and
   fix sequence. Use the improved pi transcripts to inspect tool behavior.
5. Revisit artifact filtering when it appears in a stable release if the pilot
   begins consuming private tracker context.

## Sources

- [Fullsend v0.55.0 release](https://github.com/fullsend-ai/fullsend/releases/tag/v0.55.0)
- [Agents v0.55.0 release](https://github.com/fullsend-ai/agents/releases/tag/v0.55.0)
- [Configuration and migration reference](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/reference/config-reference.md#tracker)
- [pi runtime and persona routing](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/runtimes/pi.md)
- [Codex gateway limitations](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/runtimes/codex.md#models-through-an-inference-gateway-experimental)
- [Inference gateway guide](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/user/inference-gateway.md)
- [Sandbox version pins, v0.55.0](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/images/sandbox/Containerfile)
- [Sandbox version pins, v0.54.0](https://github.com/fullsend-ai/fullsend/blob/v0.54.0/images/sandbox/Containerfile)
- [OpenShell pin](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/.github/scripts/openshell-version.sh)
- [pi-inference-gateway v0.2.0](https://github.com/fullsend-ai/pi-inference-gateway/releases/tag/v0.2.0)
- [Self-update reference](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/cli/self-update.md)
- [Harness schema version](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/reference/harness-reference.md)
- [Unreleased artifact filtering guide](https://github.com/fullsend-ai/fullsend/blob/944b5430c43edfbbe163f67e08ccfd5bea2194ba/docs/guides/user/run-artifacts-and-private-data.md)
- [Fullsend changes after v0.55.0](https://github.com/fullsend-ai/fullsend/compare/v0.55.0...944b5430c43edfbbe163f67e08ccfd5bea2194ba)
- [Agents changes after v0.55.0](https://github.com/fullsend-ai/agents/compare/v0.55.0...a69d9b550ce89131a66cd1e565f03ec5c97f9521)
