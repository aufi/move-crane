# Proposal: Controlled Fullsend Pilot in the migtools Organization

## Status

Proposal pending a decision. This document is based on upstream state and documentation verified on September 3, 2026.

## Summary

[Fullsend](https://github.com/fullsend-ai/fullsend) is an open-source platform for autonomous software-development lifecycle agents: issue triage, implementation, code review, review-finding remediation, prioritization, and retrospectives. The upstream project is licensed under Apache-2.0 and its current stable release is `v0.40.0`.

Fullsend is neither a Crane runtime dependency nor part of its migration workflow. It is developer infrastructure for a GitHub organization. The upstream `fullsend-ai/fullsend` repository should therefore not be transferred to `migtools`, maintained as a long-term fork, or enabled organization-wide. The recommended approach is an isolated, reversible pilot in one repository, initially limited to the `triage` and `review` roles.

## Goals

1. Determine whether Fullsend reduces time from an issue to a useful proposal without reducing review quality.
2. Collect inference-cost, GitHub Actions consumption, and operational-effort data.
3. Validate its security model with minimal GitHub permissions and no changes to merge rules.
4. Establish a repeatable procedure for a possible expansion to other `migtools` repositories.

## Non-Goals

- Automatic merging, releases, deployments, or production-cluster changes.
- Agent access to Kubernetes, Quay, cloud-account, or CI secrets beyond inference and its short-lived GitHub identity.
- Enabling the `coder` and `fix` roles in the first phase.
- Moving ownership or maintenance of the upstream project to `migtools`.

## Findings

### Upstream State

- Repository: <https://github.com/fullsend-ai/fullsend>.
- Implementation: Go; a public, non-archived project created in March 2026.
- License: Apache-2.0, compatible with the predominant license of `migtools` repositories.
- Current release: `v0.40.0`, published on September 3, 2026; the distribution includes Linux and macOS binaries and checksums.
- The project has detailed documentation, ADRs, test workflows, and an explicit security architecture. It is young and changes actively; deployments must use a specific release or commit SHA, never the `main` branch.

### Operating Model

Each enrolled repository contains configuration in `.fullsend/` and a thin GitHub Actions workflow. An issue or pull-request event invokes a particular role, which runs in an isolated sandbox and communicates through a GitHub App.

Fullsend supports per-repository installation, which is both the preferred and upstream-supported model. Multi-repository management through a `repos.yaml` manifest is available but must remain outside the pilot scope.

The default inference model uses Google Cloud Vertex AI and Workload Identity Federation (WIF). GitHub Actions obtains a short-lived OIDC identity; no long-lived model-provider key is stored in the repository. For GitHub API access, Fullsend uses short-lived GitHub App installation tokens issued by a token-mint service. The mint can be self-hosted or use an upstream-hosted variant.

### GitHub Permissions

Roles are separate GitHub Apps. Their relevant publicly declared permissions are:

| Role | Permissions | Impact |
| --- | --- | --- |
| `triage` | `contents: read`, `issues: write`, projects: write | Reads issue context and writes labels and comments. |
| `review` | `contents: read`, `pull_requests: write`, `issues: write`, `checks: read` | Creates reviews and comments without changing source code. |
| `coder` / `fix` | `contents: write`, `pull_requests: write`, `issues: write`, `checks: read` | Can create branches, commits, and pull requests. Do not enable during the pilot. |

Fullsend uses `pull_request_target` for its shim workflow. Upstream explicitly states its security condition: the shim must not check out or execute code from an untrusted pull request. Before installation, verify that `migtools` policies permit this trigger and protect `.github/workflows/fullsend.yaml` through `CODEOWNERS` or an equivalent ruleset.

## Integration Options

| Option | Assessment | Rationale |
| --- | --- | --- |
| Transfer the repository to `migtools` | Reject | It would transfer ownership of an active external project without a Crane requirement. |
| Long-term `migtools/fullsend` fork | Not recommended | It adds synchronization, security-patching, and distribution responsibilities. |
| Consume an upstream release in one repository | Recommended | It has the smallest blast radius, retains the upstream update path, and is fully reversible. |
| Organization-wide rollout | Defer | It requires pilot results, operational ownership, a budget, and an approved threat model. |

## Recommended Pilot

### Target Repository

Choose one active public repository with a manageable set of issues and a maintained review process. `migtools/crane` is a technically suitable candidate, but its maintainers and the GitHub organization owner must confirm the final selection. The pilot must not use a repository with customer data, non-public security incidents, or secrets available to workflows.

### Scope and Limits

1. Install only the `fullsend-ai-triage` and `fullsend-ai-review` GitHub Apps, limited to a single pilot repository.
2. Configure only `triage,review`; do not enable `coder`, `fix`, `retro`, or `prioritize`.
3. Pin Fullsend to release `v0.40.0` or a verified commit SHA. Prefer a vendored installation if security review does not accept a runtime dependency on upstream reusable workflows.
4. Use a dedicated GCP project, WIF provider, and tight token mint with explicit `ALLOWED_ORGS=migtools`; do not use a public mint without separate security approval.
5. Configure a Vertex AI budget alert and a GitHub Actions limit. Define a monthly ceiling and a person authorized to stop the service beforehand.
6. Add Go/Kubernetes repository instructions in `.fullsend/`: no automatic merges, prioritize reproducible tests, respect `AGENTS.md`, and require maintainer review.
7. Keep branch protection, required checks, `CODEOWNERS`, and human approval unchanged, with no exceptions for bots.
8. Require platform-owner and repository-maintainer review for changes to `.fullsend/**` and `.github/workflows/fullsend.yaml`.

### Phases

| Phase | Duration | Activity | Continuation Criterion |
| --- | --- | --- | --- |
| Preparation | 1 week | Threat model, owner, GCP/WIF, GitHub Apps, budgets, and rollback. | Approved permissions and verified teardown. |
| Shadow triage | 2 weeks | `triage` responds only to an explicit `/fs-triage` command. | No security incident; maintainers consider at least half of outputs useful. |
| Review pilot | 2 to 4 weeks | `review` runs on opt-in pull requests or an explicit command. | No incorrect merge blocking; useful material findings; cost within budget. |
| Evaluation | 1 week | Compare metrics, incidents, and operational effort. | Decision to stop, extend, or selectively expand. |

### Metrics

- Percentage of triage/review outputs that maintainers mark as useful.
- Number of confirmed findings by severity and number of false positives.
- Time from an issue to the first useful triage and review completion time.
- Inference cost and GitHub Actions minutes per issue or pull request.
- Number of security, availability, or process incidents.
- Maintainer time spent operating and correcting the agent.

## Security and Operational Requirements

1. Install GitHub Apps only on the pilot repository, never on the whole organization.
2. Apply least privilege. Source-content write permission is prohibited during the pilot.
3. The workflow must pin a specific upstream version; each update is a separate change request subject to security review.
4. Sandbox egress configuration must allow only GitHub, the model provider, and required registries; MCP servers and additional external tools are outside the pilot.
5. No long-lived PAT, GitHub App PEM key, or model API key may exist in the repository or sandbox. Validate WIF and short-lived tokens with a practical test before deployment.
6. Instructions from issues and pull requests are untrusted input. An agent must not be able to bypass policy through issue content, a pull request description, a commit, or documentation in a pull-request branch.
7. Maintain an audit trail through Actions logs, GitHub comments and reviews, cloud-service consumption, and configuration reviews.
8. Immediate rollback must remove the Apps from the pilot repository, disable or remove the workflow, revoke WIF and token-mint access, and review open bot pull requests and comments.

## Decisions Required Before Installation

1. Who owns Fullsend operations, the GCP project, the mint service, and the cost ceiling?
2. Which repository and maintainers explicitly approve the pilot?
3. Is `pull_request_target` acceptable to `migtools` if the upstream invariant and workflow-path protections are enforced?
4. Will the organization use its own tight mint, or an upstream-hosted public mint after formal security assessment?
5. Which inference model is allowed under Red Hat/Konveyor compliance, and where may telemetry and logs be stored?
6. What monthly budget, maximum run count, and stop mechanism apply to the pilot?

## Conclusion

Fullsend can be integrated with `migtools` without coupling it to the Crane runtime and with a clearly limited risk profile. The conditions are per-repository installation, dedicated identity and inference infrastructure, a strict initial role limit of `triage` and `review`, and retained human approval. Agents with source-code write access should be considered only after the pilot demonstrates security, quality, and cost control.

## Sources

- Fullsend upstream: <https://github.com/fullsend-ai/fullsend>
- Fullsend documentation: <https://fullsend.sh/docs/>
- GitHub configuration: <https://fullsend.sh/docs/guides/getting-started/configuring-github>
- Per-repository installation management: <https://fullsend.sh/docs/guides/getting-started/repo-management>
- Architecture and identity: <https://fullsend.sh/docs/architecture>
- Token mint and WIF infrastructure: <https://fullsend.sh/docs/guides/infrastructure/infrastructure-reference>
- `pull_request_target` ADR: <https://fullsend.sh/docs/ADRs/0009-pull-request-target-in-shim-workflows>
