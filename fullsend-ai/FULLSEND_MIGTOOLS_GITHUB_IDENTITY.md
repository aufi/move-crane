# GitHub identity setup for all Fullsend agents in migtools/crane

## Selected configuration

The user requested all six standard Fullsend agents: triage, review, code,
fix, retro, and prioritize. This replaces the earlier triage-only rollout
recommendation for this installation.

The user selected the upstream managed token mint, `https://mint.fullsend.sh`.
The repository variable `FULLSEND_MINT_URL` was set to that value and read back
successfully on November 19, 2026. No provider API key or App private key was
created or stored on GitHub.

Inference remains separate: `migtools/crane` has verified access through the
central ITPC WIF provider to `claude-sonnet-5-5` in `global`, billed to
`mta-ops-fs-agents`. See the
[live WIF validation](FULLSEND_WIF_ALLOWLIST_MR.md#live-wif-validation-on-november-19).

## Required GitHub Apps

Public App metadata was read from GitHub on November 19. Permissions below
exclude the common read-only Metadata permission.

| App | App ID | Agents | Declared permissions |
| --- | --- | --- | --- |
| `fullsend-ai-triage` | `3478490` | triage | Contents read; Issues, Organization projects, and Repository projects write |
| `fullsend-ai-review` | `3478501` | review | Checks and Contents read; Issues and Pull requests write |
| `fullsend-ai-coder` | `3478495` | code and fix | Checks and Packages read; Contents, Issues, and Pull requests write |
| `fullsend-ai-retro` | `3689659` | retro | Actions and Contents read; Issues and Pull requests write |
| `fullsend-ai-prioritize` | `3689657` | prioritize | Contents read; Issues and Organization projects write |

Install or configure all five in the `migtools` organization. For each, select
**Only select repositories** and include **crane**:

- [Install triage](https://github.com/apps/fullsend-ai-triage/installations/new?target_id=55251026)
- [Install review](https://github.com/apps/fullsend-ai-review/installations/new?target_id=55251026)
- [Install coder](https://github.com/apps/fullsend-ai-coder/installations/new?target_id=55251026)
- [Install retro](https://github.com/apps/fullsend-ai-retro/installations/new?target_id=55251026)
- [Install prioritize](https://github.com/apps/fullsend-ai-prioritize/installations/new?target_id=55251026)

GitHub organization ID `55251026` was verified to be `migtools`. If GitHub
offers an installation request instead of installation, an organization owner
must approve it. If an App is already installed, its existing installation
must include `crane` and accept any required permission update.

Code and fix share the coder App. Per-repository installation does not require
the `fullsend-ai-fullsend` dispatch App.

## Verified state and installation dependency

- GitHub account `aufi` reports `MAINTAIN` on `migtools/crane` and `member`
  membership in the organization.
- Listing organization App installations returned HTTP 404 with a missing
  `admin:org` scope notice. Installation state and repository selection could
  not be verified with this credential. An inaccessible list does not establish
  that the Apps are absent.
- The hosted mint `/health` endpoint returned `status: ok`. That proves health,
  not permission to mint role tokens for `migtools/crane`.
- According to the v0.56.1 upstream guide, the managed public mint needs no
  separate repo enrollment when using the shared public Apps.

The remaining identity-setup dependency is confirmation that all five Apps
are installed and have access to `migtools/crane`. App installation requires
GitHub's interactive organization installation flow; Git repository write
access alone does not provide it.

## Next setup stage

After App installation is confirmed, prepare the Fullsend installation with
all six standard agents, the selected managed mint, and the already verified
Vertex WIF route. Ensure all parent and child model selections use models
enabled in the GCP project, initially Sonnet 5.5.

The existing `VERTEX_PROJECT_ID` and `VERTEX_WIF_PROVIDER` variables belong to
the smoke-test workflow. The Fullsend scaffold must receive its own expected
inference identifiers and region. Neither successful App installation nor the
mint URL variable activates agents without the Fullsend workflows and config.

## Sources

- [Fullsend v0.56.1 GitHub setup](https://github.com/fullsend-ai/fullsend/blob/v0.56.1/docs/guides/getting-started/configuring-github.md)
- [Managed mint and enrollment](https://github.com/fullsend-ai/fullsend/blob/v0.56.1/docs/guides/infrastructure/mint-administration.md#hosted-mint)
- Public App metadata from GitHub `GET /apps/{slug}` for the five Apps above.
