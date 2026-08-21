---
name: writing-enhancements
description: Use when writing a Konveyor enhancement proposal to formalize a feature plan into the standard enhancement document format, following the Konveyor enhancements repo template and conventions
---

# Writing Konveyor Enhancement Proposals

Formalize a feature plan into a Konveyor enhancement document following the project's template and conventions from https://github.com/konveyor/enhancements/.

## When to Use

- You have a clear feature plan and need to write the formal enhancement doc
- You need to create a new enhancement proposal in the Konveyor enhancements repo

## When NOT to Use

- The idea is vague and needs brainstorming first — use brainstorming skill instead
- You're writing a bug fix, test addition, or small refactor — enhancements are for significant features

## Required Input

The user provides:
1. **Feature description** — what the feature does, why it's needed, how it works
2. **Target domain** — the subdirectory under `enhancements/` (e.g., `crane-2.0`, `kantra`, `kai`, `common`)

If domain is not provided, ask for it. List existing domains by running: `ls enhancements/` in the current directory.

## Process

### 1. Validate working directory

Confirm the current directory is a clone/fork of the enhancements repo by checking that `enhancements/` and `guidelines/` directories exist. If not, stop and tell the user to run this skill from their enhancements repo fork.

### 2. Derive metadata

- **Slug:** derive a kebab-case slug from the feature description (e.g., `multi-stage-kustomize-transforms`)
- **Author:** read from `git config user.name` and `git config user.email` to construct the `@handle` or name
- **Date:** use today's date in `yyyy-mm-dd` format
- **Status:** always start as `provisional`

### 3. Generate the enhancement document

Create `enhancements/<domain>/<slug>/README.md` with the content below, filling every section from the user's feature description. Do not leave any section as TBD or TODO — if the user's input doesn't cover a section, make a reasonable inference and mark it with a `<!-- REVIEW: inferred, please verify -->` HTML comment.

### 4. Completeness check

After writing, verify:
- All required sections are present
- YAML frontmatter is valid
- No unintentional TBD/TODO placeholders remain
- Directory name matches the `title` field in frontmatter

Report the file path and any sections marked for review.

## Enhancement Template

The generated document MUST follow this exact structure:

```markdown
---
title: <slug>
authors:
  - "<author>"
reviewers:
  - TBD
approvers:
  - TBD
creation-date: <yyyy-mm-dd>
last-updated: <yyyy-mm-dd>
status: provisional
see-also: []
replaces: []
superseded-by: []
---

# <Title in Natural Case>

## Release Signoff Checklist

- [ ] Enhancement is `implementable`
- [ ] Design details are appropriately documented from clear requirements
- [ ] Test plan is defined
- [ ] User-facing documentation is created

## Open Questions [optional]

> List any open questions here that need resolution before the enhancement
> can move to `implementable`.

## Summary

A paragraph or two summarizing the enhancement. This should be usable as
release notes.

## Motivation

Why is this change important? What benefits does it provide to users?
What problems does it solve?

### Goals

- Specific, measurable goals for this enhancement

### Non-Goals

- What is explicitly out of scope

## Proposal

Detailed description of the proposed change.

### User Stories [optional]

#### Story 1

As a <role>, I want <feature> so that <benefit>.

### Implementation Details/Notes/Constraints [optional]

Technical details, constraints, and implementation notes.

### Security, Risks, and Mitigations

What security implications does this have? What risks? How are they mitigated?

## Design Details

### Test Plan

How will this be tested? Cover unit, integration, and e2e testing strategy.

### Upgrade / Downgrade Strategy

If applicable, how does this affect upgrades and downgrades?

## Implementation History

- `yyyy-mm-dd`: Enhancement proposed as `provisional`

## Drawbacks

The best argument against implementing this enhancement.

## Alternatives

What other approaches were considered and why were they not chosen?

## Infrastructure Needed [optional]

New repos, subprojects, testing infrastructure, or CI changes needed.
```

## Conventions

- Directory names: lowercase kebab-case (e.g., `validate-api-compatibility`)
- Each enhancement lives in its own directory: `enhancements/<domain>/<slug>/`
- The proposal file is always named `README.md`
- Images or supporting assets go alongside README.md in the same directory
- The YAML `title` field matches the directory name (the slug)
- Status always starts as `provisional` for new proposals
