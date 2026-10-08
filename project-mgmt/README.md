# Crane development project

This directory will contain automation for managing work across the Crane GitHub project and its repositories.

## Current scope

- GitHub project configuration is stored in `project.yaml`.
- Participating repositories are listed in `repositories.yaml`.
- The current backlog baseline and automation assessment are documented in `backlog-analysis-2026-09-30.md`.
- The current milestone analysis is documented in `milestone-analysis-2026-10-08.md`.
- The current pull request check analysis is documented in `pr-checks-analysis-2026-10-08.md`.
- The latest generated overview with GitHub links is stored in `backlog-status.md`.
- The corresponding machine-readable snapshot is stored in `backlog-data.json`.

## Updating the backlog overview

The scripts require Python 3.11 or newer and an authenticated `gh` CLI with access to the configured repositories and GitHub Project. There are no third-party Python dependencies; this is recorded in `requirements.txt`.

Run the complete update from the repository root:

```bash
python3 project-mgmt/update_backlog.py
```

The update reads `repositories.yaml` and `project.yaml`, then atomically replaces `backlog-data.json` and `backlog-status.md`. It does not modify GitHub data.

The collection and rendering phases can also run separately:

```bash
python3 project-mgmt/collect_backlog.py --output project-mgmt/backlog-data.json
python3 project-mgmt/render_backlog.py \
  --input project-mgmt/backlog-data.json \
  --output project-mgmt/backlog-status.md
```

The scripts use only the Python standard library. `backlog-data.json` keeps the source data used by the report so that later automation can evaluate different policies without querying GitHub again.

## Related tooling

[konveyor/release-tools](https://github.com/konveyor/release-tools) provides shared configuration and automation for maintaining, building, and releasing Konveyor repositories. It includes:

- a central YAML inventory of repositories, labels, and milestones;
- commands that reconcile labels and milestones across repositories;
- reusable GitHub Actions for pull request checks, changelog and release creation, release branch preparation, and multi-architecture image builds;
- stale issue and pull request management;
- repository health dashboards and weekly maintainer reports.

Its current repository inventory and project conventions target the `konveyor` organization. Crane project management may reuse individual patterns or workflows, but compatibility with `migtools` repositories and GitHub Project 24 must be evaluated first.
