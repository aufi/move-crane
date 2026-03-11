# Draft Proposal: Extend Crane Plugin Protocol (`PluginRequest` / `PluginResponse`)

This a very raw draft (and nearly fully AI generated), primary for plugin structs demonstration. 

## Goal

Define a versioned (? TBD) and Go-friendly plugin contract that:

- standardizes request/response shape,
- improves error handling and retries,
- supports observability (trace IDs, duration, warnings),
- allows safe migration from existing plugin protocol versions.

---

## Scope

This proposal covers protocol-level changes for:

- `PluginRequest`
- `PluginResponse`

It also defines implementation work split across repositories:

- `crane`
- `crane-lib`
- plugin repositories (first-party and third-party)
- optional supporting projects (docs/observability/tooling)

---

## Proposed Protocol (V2)

## `PluginRequest` (V2)

```go
type PluginRequestV2 struct {
    Version   string                 `json:"version"`   // "2"
    RequestID string                 `json:"requestId"` // correlation id
    Plugin    string                 `json:"plugin"`    // plugin name/identifier
    Action    string                 `json:"action"`    // operation/command
    Payload   json.RawMessage        `json:"payload"`   // typed by plugin handler
    Context   *PluginRequestContext  `json:"context,omitempty"`
    Meta      map[string]any         `json:"meta,omitempty"`
}

type PluginRequestContext struct {
    TraceID      string   `json:"traceId,omitempty"`
    UserID       string   `json:"userId,omitempty"`
    SessionID    string   `json:"sessionId,omitempty"`
    Locale       string   `json:"locale,omitempty"`
    TimeoutMs    int64    `json:"timeoutMs,omitempty"`
    DeadlineAt   string   `json:"deadlineAt,omitempty"` // RFC3339
    Capabilities []string `json:"capabilities,omitempty"`
}
```

Notes:

- `Version` is mandatory to support explicit protocol negotiation.
- `RequestID` is mandatory for matching responses and logs.
- `Payload` remains plugin-owned (schema is action-specific).
- If both `TimeoutMs` and `DeadlineAt` are set, the earlier limit should win.

---

## `PluginResponse` (V2)

```go
type PluginResponseV2 struct {
    Version   string                `json:"version"`   // "2"
    RequestID string                `json:"requestId"`
    Status    PluginResponseStatus  `json:"status"`    // ok | error | partial

    Data     json.RawMessage        `json:"data,omitempty"`
    Error    *PluginError           `json:"error,omitempty"`
    Warnings []PluginWarning        `json:"warnings,omitempty"`
    Metrics  *PluginResponseMetrics `json:"metrics,omitempty"`
    Meta     map[string]any         `json:"meta,omitempty"`
}

type PluginResponseStatus string

const (
    PluginStatusOK      PluginResponseStatus = "ok"
    PluginStatusError   PluginResponseStatus = "error"
    PluginStatusPartial PluginResponseStatus = "partial"
)

type PluginError struct {
    Code      string `json:"code"`                // e.g. VALIDATION_ERROR, TIMEOUT
    Message   string `json:"message"`
    Retriable bool   `json:"retriable,omitempty"`
    Details   any    `json:"details,omitempty"`
}

type PluginWarning struct {
    Code    string `json:"code"`
    Message string `json:"message"`
}

type PluginResponseMetrics struct {
    StartedAt  string `json:"startedAt,omitempty"`  // RFC3339
    FinishedAt string `json:"finishedAt,omitempty"` // RFC3339
    DurationMs int64  `json:"durationMs,omitempty"`
}
```

Notes:

- `partial` allows returning useful partial results without overloading `error` semantics.
- `Retriable` provides direct signal to `crane` retry policy.
- `Warnings` are explicit and machine-readable.

---

## Optional Extension: Progress Events

For long-running plugin operations, the transport may support progress messages:

```go
type PluginProgressEvent struct {
    Version   string         `json:"version"`   // "2"
    RequestID string         `json:"requestId"`
    Progress  int            `json:"progress"`  // 0..100
    Message   string         `json:"message,omitempty"`
    Meta      map[string]any `json:"meta,omitempty"`
}
```

Final completion is always represented by `PluginResponseV2`.

---

## Compatibility & Migration Plan

### Phase 1: Dual-stack support (if really needed))

- `crane-lib` supports both V1 and V2 models/parsers.
- `crane` sends V2 by default where plugin capability allows it.
- Fallback to V1 for legacy plugins.

### Phase 2: V2-by-default

- New plugins must implement V2.
- Existing V1 plugins run through compatibility adapter where possible.

### Phase 3: V1 deprecation

- Communicate deprecation date.
- Remove V1 parser/adapter after adoption threshold is met.

---

## Work Split by Project

## 1) `crane-lib` (highest priority)

### Responsibilities

- Define canonical Go types for V2 request/response.
- Provide encoding/decoding helpers and validation.
- Implement V1↔V2 adapter layer (best effort).
- Define shared error code taxonomy and constants.
- Add contract tests and fixtures.

### Deliverables

- `plugin/protocol/v2` package
- migration guide for plugin authors
- test suite for protocol compatibility

---

## 2) `crane` (runtime/orchestrator)

### Responsibilities

- Generate `requestId` and propagate `traceId`.
- Perform protocol negotiation per plugin (`supportedVersions`, capabilities).
- Implement retry logic based on `error.retriable` + error codes.
- Extend logging/metrics with V2 fields (`status`, warnings, duration).
- Rollout behind feature flags by environment/tenant.

### Deliverables

- runtime support for V2 + legacy fallback
- observability updates
- E2E tests for mixed V1/V2 plugin fleet

---

## 3) Plugin repositories

### Responsibilities

- Update handlers to parse `PluginRequestV2` and return `PluginResponseV2`.
- Replace ad-hoc errors with standard error codes.
- Use `partial` + `warnings` where output can degrade gracefully.
- Update plugin docs/examples.

### Deliverables

- V2-compatible plugin releases
- changelog with migration notes

---

## 4) Other projects (optional but recommended)

### Documentation project (`crane-docs` or equivalent)

- Publish protocol specification (normative + examples).
- Add migration cookbook: V1 → V2.

### Observability project (if separate)

- Dashboards: error code distribution, retriable rates, partial response rates.
- Alerts for spikes in `TIMEOUT` / `VALIDATION_ERROR`.

### CI/tooling

- Contract-test runner for plugin repos.
- Lint/check: plugin must declare supported protocol versions.

---

## Acceptance Criteria

- [ ] `crane-lib` publishes stable V2 protocol package.
- [ ] `crane` supports V2 with safe fallback to V1.
- [ ] At least 2 critical plugins run V2 in production-like environment.
- [ ] Correlation and tracing are end-to-end (`requestId`, `traceId`).
- [ ] Documentation and migration guide are available.

---

## Risks & Mitigations

### Risks

- Inconsistent implementation of error codes across plugins.
- Misinterpretation of `partial` by clients.
- Mixed-version fleet complexity during migration.

### Mitigations

- Shared constants and contract tests in `crane-lib`.
- Clear semantics in protocol spec and examples.
- Gradual rollout with feature flags and telemetry.
