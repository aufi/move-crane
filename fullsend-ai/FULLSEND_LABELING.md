# Fullsend issue and pull request labeling

Verified against Fullsend and fleet agents v0.55.0 on November 13, 2026.

Fullsend separates contextual label recommendations from labels managed by
the agent pipeline. Both can be customized, but through different mechanisms.

## Contextual labels

Triage and review use the `issue-labels` skill to recommend labels describing
the affected area, kind of work, platform, or other repository conventions.
The default GitHub skill:

1. Lists existing repository labels and their descriptions.
2. Checks issue types when processing an issue. It avoids recommending type
   labels that duplicate a GitHub issue type. Issue types do not apply to PRs.
3. Examines recent issues to infer labeling conventions.
4. Recommends appropriate additions and removals in the agent's result JSON.

Example:

```json
{
  "label_actions": {
    "reason": "The change fixes an E2E test helper.",
    "actions": [
      {"action": "add", "label": "kind/bug"},
      {"action": "add", "label": "area/testing"}
    ]
  }
}
```

The host-side post-script validates and applies the recommendations. Contextual
label additions require an existing repository label; the post-script skips
unknown labels instead of creating them. It also rejects attempts to change
reserved pipeline labels through `label_actions`.

The skill can recommend removing stale contextual labels. Protecting labels
assigned by a human therefore requires an explicit policy if that distinction
matters to the team.

## Pipeline-managed labels

These labels describe workflow state or influence agent dispatch. The
post-scripts manage them according to the agent's structured result.

| Label | Meaning |
| --- | --- |
| `needs-info` | Triage needs more information and has asked questions. |
| `triaged` | The issue is sufficiently specified but awaits a decision to implement it. |
| `ready-to-code` | Triggers the code agent. |
| `pr-open` | An open PR already addresses the issue. |
| `ready-for-review` | Code published a PR ready for review; applying it can trigger review. |
| `ready-for-merge` | Review approved the current change. It does not itself merge the PR. |
| `requires-manual-review` | Review needs human judgment or an approval was downgraded. |
| `rejected` | Review rejected and closed the PR. |
| `risk/low` through `risk/critical` | Review's risk assessment, from score 1 through 5. |
| `fullsend-no-fix` | Prevents automatic fix runs for the PR. Manual `/fs-fix` remains available. |
| `fullsend-fix-budget/2` | Example maintainer-set label lowering the automatic fix cap to two attempts, when below the configured cap. |
| `needs-human` | The fix loop needs human intervention as it approaches its cap. |

Triage also manages classification labels such as `bug`, `documentation`,
`feature`, and `question`. Its terminal actions include duplicate, not-planned,
and completed outcomes, which can close issues.

Post-scripts remove stale state labels as the workflow progresses. A new
review run removes `ready-for-merge` and restores it only if the run approves
the current head. A changes-requested review triggers eligible fix processing
through the review event rather than a separate changes-requested label.

Some system labels are created automatically. The label-management helper
ensures `ready-for-review`, `ready-to-code`, and `ready-for-triage` exist and
can overwrite their descriptions and colors with Fullsend's defaults. The
review post-script also creates or updates its `risk/*` labels.

## Customization options

### Maintain the repository label catalog

The simplest change is to create the desired contextual labels and provide
clear descriptions. A possible Crane catalog could include:

| Proposed label | Intended use |
| --- | --- |
| `area/testing` | Tests and test framework changes. |
| `area/transfer-pvc` | PVC and persistent-data transfer. |
| `platform/openshift` | OpenShift-specific behavior. |
| `kind/bug` | Defects in existing behavior. |
| `kind/flake` | Demonstrated intermittent test failures. |

These are policy examples, not a record that all listed labels already exist.
Create any missing labels before expecting contextual recommendations to apply.

The default skill will use the catalog, but its choices still depend partly on
inferred repository history.

### Define an explicit labeling skill

Replace `issue-labels` when the team needs predictable rules instead of
history-based inference. Example policy:

```text
- Changes under e2e-tests/ receive area/testing.
- PVC data-transfer changes receive area/transfer-pvc.
- OpenShift-specific API or platform behavior receives platform/openshift.
- Use kind/flake only for demonstrated intermittent failures.
- Do not change priority labels assigned by a human.
- Recommend only existing labels.
- Leave pipeline-managed labels to the post-scripts.
```

The supported replacement mechanism is a derived harness using `base:`
composition and an explicit skill override. The replacement must declare
`name: issue-labels` in its `SKILL.md` frontmatter so its identity matches the
built-in skill. Relative child skill paths resolve against `.fullsend/`.

Register the derived harness through the agent's `source` in
`.fullsend/config.yaml`. Apply the policy to both triage and review for shared
behavior, or give each agent its own replacement. Preserve the existing
upstream pins, runtime/model settings, and review-persona overrides.

Simply placing a same-named skill under a project `.agents/` or `.claude/`
directory is not a reliable replacement. Fullsend's built-in skills take
precedence over colliding project skills. Some agent-specific documentation
still describes older override approaches; follow the v0.55.0 platform guide
for explicit harness composition and skill-identity matching.

### Configure promotion and review behavior

Some labeling behavior has dedicated environment settings. For example, the
pilot's triage harness sets:

```yaml
env:
  runner:
    TRIAGE_AUTO_CODE: "off"
  sandbox:
    TRIAGE_AUTO_CODE: "off"
```

With this setting, a sufficiently specified issue receives `triaged` rather
than automatic `ready-to-code` promotion. A human can still invoke `/fs-code`
or apply the trigger label. Other triage modes are `on` and `discretionary`;
`TRIAGE_AUTO_CODE_CATEGORIES` selects eligible categories.

Review's risk assessment is controlled by
`REVIEW_RISK_ASSESSMENT_ENABLED` and `REVIEW_RISK_VERDICT_THRESHOLD` in its
GitHub harness environment. The default threshold is 4. This controls risk
assessment and verdict gating, not an arbitrary renaming of risk labels.

### Rename or replace pipeline labels

v0.55.0 has no universal declarative map for renaming all system labels.
Changing `ready-to-code` to a team-specific name requires coordinating the
post-script that applies it with the dispatch logic that consumes it. A skill
override alone cannot rename pipeline labels or bypass their reserved status.

For contextual-label removal or additions, use a skill policy. For mandatory
enforcement independent of model compliance, a custom post-script or wrapper
must validate the proposed actions before applying them. Keep such changes
separate from a simple labeling-policy adjustment.

## Current pilot observations and recommendation

The pilot label catalog inspected on November 13 includes `bug` and
`kind/bug`, as well as `enhancement` and `feature`. This can produce overlapping
classification:

- Triage manages `bug` and `feature` through its action handlers.
- The contextual skill may recommend `kind/bug` based on repository conventions.

Keep Fullsend's pipeline labels and establish one explicit contextual taxonomy
for areas, platforms, and types of work. Put the policy in a shared labeling
skill used by triage and review. This reduces inference from historical label
usage and makes the distinction between workflow state and classification
clearer.

This document records behavior and customization options. It does not change
the pilot's labels, skills, harnesses, or dispatch configuration.

## References

- [GitHub issue-labels skill v0.55.0](https://github.com/fullsend-ai/agents/blob/v0.55.0/skills/issue-labels/github/SKILL.md)
- [Triage labels and promotion settings](https://github.com/fullsend-ai/agents/blob/v0.55.0/docs/triage.md)
- [Review labels and risk assessment](https://github.com/fullsend-ai/agents/blob/v0.55.0/docs/review.md)
- [Code dispatch labels](https://github.com/fullsend-ai/agents/blob/v0.55.0/docs/code.md#control-labels)
- [Fix control labels](https://github.com/fullsend-ai/agents/blob/v0.55.0/docs/fix.md#control-labels)
- [Skill precedence and overrides](https://github.com/fullsend-ai/fullsend/blob/v0.55.0/docs/guides/user/customizing-with-skills.md#overriding-built-in-skills)
- [Mandatory label management](https://github.com/fullsend-ai/agents/blob/v0.55.0/scripts/lib/labels.lib.sh)
- [Triage post-script](https://github.com/fullsend-ai/agents/blob/v0.55.0/scripts/post-triage.src.sh)
- [Review post-script](https://github.com/fullsend-ai/agents/blob/v0.55.0/scripts/post-review.src.sh)
