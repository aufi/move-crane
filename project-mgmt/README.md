# Crane project management

This directory will contain automation for managing work across the Crane GitHub project and its repositories.

## Current scope

- GitHub project configuration is stored in `project.yaml`.
- Participating repositories are listed in `repositories.yaml`.
- The current backlog baseline and automation assessment are documented in `backlog-analysis-2026-09-30.md`.
- Automation will be added after its requirements and workflow are defined.

## Related tooling

[konveyor/release-tools](https://github.com/konveyor/release-tools) provides shared configuration and automation for maintaining, building, and releasing Konveyor repositories. It includes:

- a central YAML inventory of repositories, labels, and milestones;
- commands that reconcile labels and milestones across repositories;
- reusable GitHub Actions for pull request checks, changelog and release creation, release branch preparation, and multi-architecture image builds;
- stale issue and pull request management;
- repository health dashboards and weekly maintainer reports.

Its current repository inventory and project conventions target the `konveyor` organization. Crane project management may reuse individual patterns or workflows, but compatibility with `migtools` repositories and GitHub Project 24 must be evaluated first.
