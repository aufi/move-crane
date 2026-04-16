# Kantra + Crane embedding plan

## Goal

Embed selected `crane` commands into the `kantra` binary without shelling out to an external `crane` executable.

Initial command scope:

- `export`
- `transform`
- `apply`

Recommended initial UX mapping:

- `crane export` -> `kantra crane export`
- `crane transform` -> `kantra crane transform`
- `crane apply` -> `kantra crane apply`

Possible future flattening:

- `crane export` -> `kantra export`
- `crane transform` -> `kantra transform`
- `crane apply` -> `kantra apply`

## Phase 0: create a Konveyor enhancement

Create a Konveyor enhancement that describes the user-facing change in Kantra first.

### Enhancement scope

The enhancement should explicitly define that Kantra will gain new commands for Crane-based migration workflows:

- `kantra crane export`
- `kantra crane transform`
- `kantra crane apply`

### Enhancement should include

- motivation for embedding Crane commands into Kantra
- why embedding is preferred over `os/exec` of an external binary
- explicit command mapping from Crane to Kantra
- initial scope limited to `export`, `transform`, and `apply`
- rationale for choosing a namespaced `kantra crane ...` UX first
- note that top-level Kantra commands may be considered later
- high-level dependency on reusable public Cobra APIs from Crane

### Suggested enhancement sections

- Summary
- Motivation
- Goals
- Non-Goals
- User experience / command mapping
- Proposed design
- Changes required in Crane
- Changes required in Kantra
- Risks / compatibility
- Open questions

## Phase 1: create tracking issues

Create two linked GitHub issues.

### 1. Kantra issue

Purpose: track Kantra-side integration work and user-visible command additions.

The Kantra issue should cover:

- adding a new parent `crane` command to Kantra
- attaching selected embedded Crane commands under that parent
- documenting the new commands in Kantra help/docs
- validating CLI UX, help output, and flag behavior
- defining whether Kantra adds any wrapper text or keeps native Crane help unchanged

Suggested issue title:

`Embed selected Crane commands under kantra crane`

### 2. Crane issue

Purpose: track Crane-side refactoring needed to make commands embeddable from another Go module.

The Crane issue should cover:

- moving reusable flag types/helpers out of `internal/flags` into a public package, for example `pkg/flags`
- exposing a public command factory or otherwise making command constructors depend only on public packages
- refactoring `main.go` to use the new public command factory
- preserving existing standalone Crane CLI behavior

Suggested issue title:

`Expose public reusable Cobra command API for embedding`

## Phase 2: Crane changes

Crane should be changed first, because Kantra currently cannot cleanly import its command wiring.

### Required changes in Crane

1. Move or re-export global flag support from:
   - `github.com/konveyor/crane/internal/flags`
   to a public package such as:
   - `github.com/konveyor/crane/pkg/flags`

2. Ensure these command constructors are usable from another module without `internal/...` imports:
   - `cmd/export`
   - `cmd/transform`
   - `cmd/apply`

3. Add a public reusable command factory, ideally one of:

```go
func NewRootCommand(streams genericclioptions.IOStreams) *cobra.Command
```

or

```go
func NewEmbeddedCommands(streams genericclioptions.IOStreams) []*cobra.Command
```

4. Refactor `main.go` to consume the public factory instead of assembling the CLI privately.

5. Keep command semantics unchanged for existing Crane users.

### Crane acceptance criteria

- another Go module can import reusable Crane command constructors
- no import from `github.com/konveyor/crane/internal/...` is needed
- standalone `crane` binary behavior remains unchanged
- `export`, `transform`, and `apply` are embeddable as Cobra commands

## Phase 3: Kantra changes

Once Crane exposes a reusable public API, implement Kantra integration.

### Required changes in Kantra

1. Add a new parent command:

```text
kantra crane
```

2. Attach selected embedded Crane commands:

- `kantra crane export`
- `kantra crane transform`
- `kantra crane apply`

3. Reuse Crane command implementations directly instead of shelling out.

4. Verify:

- help output
- flag parsing
- IO streams behavior
- logging behavior
- exit codes
- docs/examples

5. Document the mapping explicitly in Kantra docs.

### Kantra acceptance criteria

- Kantra embeds Crane commands directly in-process
- no external `crane` binary is required
- the new commands are visible in help and docs
- command behavior is consistent with standalone Crane behavior unless intentionally documented otherwise

## Explicit command mapping

### Recommended initial mapping

- `crane export` -> `kantra crane export`
- `crane transform` -> `kantra crane transform`
- `crane apply` -> `kantra crane apply`

### Possible future mapping

- `crane export` -> `kantra export`
- `crane transform` -> `kantra transform`
- `crane apply` -> `kantra apply`

## Why start with `kantra crane ...`

Recommended reasons:

- avoids collisions with existing or future top-level Kantra commands
- makes provenance obvious to users
- reduces migration risk
- keeps room for future promotion to top-level commands if the UX proves right

## Non-goals for the first iteration

- embedding every Crane command into Kantra
- redesigning Crane command semantics
- adding Kantra-specific wrappers around all Crane behavior
- flattening commands to top-level Kantra commands immediately

## Suggested work breakdown

### Enhancement

- [ ] Create Konveyor enhancement for embedded Crane workflows in Kantra
- [ ] Define command mapping and user-facing UX in the enhancement
- [ ] Link follow-up Kantra and Crane issues from the enhancement

### Crane

- [ ] Create Crane GitHub issue for public embeddable Cobra API
- [ ] Move `internal/flags` to a public package or add public wrapper
- [ ] Add public command factory for embedding
- [ ] Refactor `main.go` to use public command factory
- [ ] Verify standalone behavior does not change

### Kantra

- [ ] Create Kantra GitHub issue for embedding selected Crane commands
- [ ] Add `kantra crane` parent command
- [ ] Attach `export`, `transform`, and `apply`
- [ ] Add docs/help/examples
- [ ] Validate CLI behavior end-to-end

## Recommended implementation order

1. Konveyor enhancement
2. Crane issue
3. Kantra issue
4. Crane refactor
5. Kantra integration
6. Docs and follow-up UX evaluation
