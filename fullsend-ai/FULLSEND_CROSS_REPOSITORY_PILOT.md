# Fullsend Cross-Repository Pilot: Crane and Crane Library

## Status

`aufi/crane-lib-pilot` is a prepared source copy for a future cross-repository
experiment. It is not yet a Fullsend installation and must not receive agent
work until its pilot controls are configured and reviewed.

## Purpose

The existing Fullsend pilot at
[`aufi/crane-fullsend-pilot`](https://github.com/aufi/crane-fullsend-pilot)
exercises the Crane application repository. The library copy at
[`aufi/crane-lib-pilot`](https://github.com/aufi/crane-lib-pilot) adds a
dependency repository to test a realistic change sequence:

1. A Crane issue identifies a required library change.
2. A linked issue and pull request implement that change in `crane-lib-pilot`.
3. A separate Crane pull request updates the dependency and verifies the
   integration.

This tests coordination across repositories without writing to any upstream
`migtools` repository.

## Verified Repository State

| Property | Value |
| --- | --- |
| Repository | <https://github.com/aufi/crane-lib-pilot> |
| Description | `Pilot copy of migtools/crane-lib for evaluating Fullsend and cross-repository development.` |
| Visibility | Public |
| Fork | No; independent repository |
| Default branch | `main` |
| GitHub Issues | Enabled |
| GitHub Actions | Disabled |
| Baseline commit | `926a5ffd044f510bb8175ed8ed4b07e052057b16` |
| Upstream baseline | Matches `migtools/crane-lib` `main` at the same commit |

The library repository contains only the copied upstream source at this stage.
No source changes, pilot commits, builds, tests, GitHub Apps, branch protection,
Fullsend configuration, or agent runs have been added.

## Why a Separate Repository

The repository is a copy, not a GitHub fork. This mirrors the Crane pilot and
avoids the common fork workflow error where a pull request targets the upstream
repository by default. All pilot pull requests must target either
`aufi/crane-lib-pilot` or `aufi/crane-fullsend-pilot`, never `migtools`.

## Fullsend Limitation

A standard Fullsend code-agent run has one target repository. It can read an
issue and create a pull request in that repository, but it does not coordinate
an end-to-end change across a dependent repository by itself.

The experiment must therefore use explicit linked issues and pull requests, or
a later custom orchestration agent. It must not assume that a Crane code-agent
run will automatically create and merge a library pull request, update the
Crane dependency, and validate the combined result.

## Required Preparation

Before the first Fullsend run in `crane-lib-pilot`:

1. Enable only the Actions workflows required for the library pilot.
2. Configure branch protection, required checks, CODEOWNERS, and pilot
   instructions before enabling write-capable agents.
3. Install Fullsend Apps only for `aufi/crane-lib-pilot`.
4. Configure the same reviewed Fullsend version, runtime, model, community
   mint decision, and OpenAI secret policy used by the Crane pilot.
5. Add a separate `FULLSEND_OPENAI_API_KEY` secret to the library repository;
   GitHub repository secrets are not shared between repositories.
6. Run triage and review validation in the library repository before enabling
   code and fix workflows there.
7. Confirm that every new branch and pull request targets the pilot repository.

## Dependency Decision Required

Copying the repository does not make Crane consume the library pilot. The Go
module path and dependency references remain upstream values.

Before the integration phase, choose and document one dependency strategy:

- a local-only `replace` directive for a developer experiment;
- an explicit, CI-reproducible module-path or dependency change in the Crane
  pilot; or
- a dedicated integration workflow that checks out both repositories and uses
  a temporary local replacement outside committed production-like manifests.

Do not commit a local filesystem `replace` directive as the integration result.
It would not work in GitHub Actions or for another contributor. The selected
strategy must be reproducible in the Crane pilot's pull request and test
workflow.

## Proposed Experiment Workflow

### 1. Create Linked Issues

Create a Crane issue in `aufi/crane-fullsend-pilot` that describes the user
visible need and explicitly records:

- the required library behavior;
- a link to the library issue once created;
- acceptance criteria for the eventual Crane integration;
- that work must remain within the two pilot repositories.

Create a library issue in `aufi/crane-lib-pilot` that links back to the Crane
issue and records the API or behavior change, compatibility expectations, and
library-level tests.

### 2. Implement the Library Change

Run Fullsend or a human implementation against the library issue only. Review
the resulting library pull request under the library repository's branch
protection and test policy. Do not merge it until the API contract and tests
are acceptable.

### 3. Integrate in Crane

After the library pull request merges, create a linked Crane integration issue
or update the original Crane issue. The Crane pull request must:

- use the previously selected reproducible dependency strategy;
- update only the dependency and the required consuming code or tests;
- link to both the Crane and library pull requests;
- run Crane's required checks and integration tests;
- target `aufi/crane-fullsend-pilot`.

### 4. Record the Outcome

Record the linked issue and pull request URLs, the dependency mechanism, test
results, Fullsend runs, OpenAI cost, manual intervention, and failures. The
result should determine whether cross-repository orchestration merits a custom
agent or remains a human-coordinated workflow.

## Non-Goals

- Automatically merging library or Crane pull requests.
- Updating upstream `migtools` repositories.
- Assuming Fullsend provides built-in multi-repository transaction semantics.
- Publishing a new public Go module path before the dependency strategy is
  reviewed.
- Sharing secrets, GitHub App installations, or branch-protection exceptions
  across the pilot repositories.
