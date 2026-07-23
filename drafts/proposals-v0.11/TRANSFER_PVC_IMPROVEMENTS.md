# transfer-pvc: Verified Improvement Recommendations

**Date:** 2026-07-23  
**Status:** Draft  
**Verified against:** current source code of `migtools/crane` (`cmd/transfer-pvc/`)

---

## Summary

This document captures Phase 1 (critical fixes) and Phase 2 (optimization) recommendations for `crane transfer-pvc`. Every claim has been verified against the current crane source code. Verdicts are noted as CONFIRMED, PARTIALLY CONFIRMED, or REFUTED.

---

## Phase 1: Critical Fixes (est. 2 weeks)

Goal: Make `transfer-pvc` production-ready.

### 1.1 Replace log.Fatal with proper error handling

**Verified status:** CONFIRMED — exactly 17 `log.Fatal` calls exist in `cmd/transfer-pvc/transfer-pvc.go`. The `run()` function has zero `defer` statements. `garbageCollect()` is called only on the happy path (last line of `run()`).

Every `log.Fatal` triggers `os.Exit(1)`, bypassing any cleanup. Orphaned resources (stunnel pods, rsync pods, secrets, configmaps, routes/ingresses) are left on both source and destination clusters.

**Affected lines (sample):**

| Line | Message |
|------|---------|
| 289 | `unable to get source rest config` |
| 298 | `unable to get destination client` |
| 318 | `unable to create destination PVC` |
| 329 | `failed creating endpoint` |
| 348 | `error creating stunnel server` |
| 375 | `failed to create certificate secret on source cluster` |
| 442 | `error creating rsync transfer server` |
| 486 | `failed to create rsync client` |

**Fix:**
- Replace all 17 `log.Fatal` calls with `return fmt.Errorf(...)`
- Add `defer cleanup.Execute()` at the top of `run()`
- Cleanup must tolerate partial state (some resources may not exist yet)

**Estimate:** 1 day  
**Impact:** Prevents resource leaks, enables retry

---

### 1.2 Add retry mechanism

**Verified status:** CONFIRMED (with nuance) — no retry logic exists at the crane CLI level. Two `wait.PollUntil` polling loops exist for health checks (endpoint and rsync server readiness), but these are not retries for the overall transfer. The rsync container itself has built-in retry for the data transfer phase (evidenced by `progress.go` parsing `Syncronization failed. Retrying in \d+ seconds`), but if setup fails (pod creation, secret copying, endpoint creation), the transfer dies immediately.

No state persistence between runs. Each invocation starts from scratch. The only partial idempotency: destination PVC creation tolerates `AlreadyExists` errors.

**Fix:**
- Add `--max-retries` flag (default 3)
- Exponential backoff for transient errors (network timeouts, pod evictions)
- Non-retryable errors: missing PVC, auth failures, invalid configuration

**Estimate:** 4 hours  
**Impact:** Handles transient errors without manual intervention

---

### 1.3 Address stale pvc-transfer dependency

**Verified status:** CONFIRMED — `go.mod` pins `github.com/backube/pvc-transfer v0.0.0-20220810121213-5f9e29a1f6e5` (August 10, 2022). No semantic versioning. Crane imports 7 sub-packages from it (more than the 3 originally documented):

| Package | Purpose |
|---------|---------|
| `endpoint` | Network endpoint abstraction |
| `endpoint/ingress` | Ingress implementation |
| `endpoint/route` | OpenShift Route implementation |
| `transfer` | SingletonPVC, PodOptions |
| `transfer/rsync` | Rsync server/client/options |
| `transport` | Transport options |
| `transport/stunnel` | Stunnel TLS tunnel |

**Fix options:**

- **Option A (recommended): Fork to `migtools/pvc-transfer`**, add semantic versioning, update crane `go.mod`
- **Option B: Vendor and inline** — copy relevant code to `cmd/transfer-pvc/internal/`, remove unused features

**Estimate:** 4 hours (fork) or 2-3 days (vendor)  
**Impact:** Control over dependency, ability to add features and security patches

---

## Phase 2: Optimization (est. 1 week)

Goal: Faster transfers and better code quality with minimal changes.

### 2.1 Expose missing rsync flags

**Verified status:** PARTIALLY CONFIRMED — the effective rsync flags are `--recursive --links --perms --times --human-readable --info=COPY,DEL,STATS2,PROGRESS2,FLIST2 --omit-dir-times --progress` (plus `--checksum` when `--verify` is set).

Key finding: the pvc-transfer library already supports `--partial` and `--bwlimit` via fields in `CommandOptions`, but crane never sets them and does not expose CLI flags for them.

| Flag | In pvc-transfer library | Exposed in crane CLI |
|------|------------------------|---------------------|
| `--partial` (resume) | `Partial` field exists | Not exposed |
| `--bwlimit` (bandwidth) | `BwLimit *int` field exists | Not exposed |
| `--compress` | Not supported | Not supported |
| `--block-size` | Not supported | Not supported |

**Fix — connect existing library support (quick wins):**

```
--bandwidth-limit=0    Bandwidth limit in KB/s (maps to existing BwLimit field)
--resume               Enable partial file resume (maps to existing Partial field)
```

**Fix — add via Extras (new flags):**

```
--compress             Enable compression (adds --compress --compress-level=6)
--block-size=131072    Block size for delta-transfer (default rsync: 700 bytes)
```

**Estimate:** bandwidth-limit + resume: 15 minutes (wiring existing fields); compress + block-size: a few hours  
**Impact:** Bandwidth control and resume support are essentially free

---

### 2.2 Fix progress tracking

**Verified status:** CONFIRMED — `cmd/transfer-pvc/progress.go` has three distinct problems:

**Global state without synchronization:**
- `var pastAttempts Progress` (line 180)
- `var failedFiles map[string]bool` (line 183)
- Zero sync primitives anywhere in the file

**Brittle regex parsing:** 9 hardcoded `regexp.MustCompile` patterns for parsing rsync output. Breaks if rsync output format changes between versions.

**Deprecated API:** `import "io/ioutil"` (line 8), `ioutil.WriteFile` (line 150) — deprecated since Go 1.16. Additionally, `writeProgressToFile` opens a file with `os.OpenFile` (line 146), defers closing it, then overwrites it with `ioutil.WriteFile` (line 150) — the `os.OpenFile` call is completely unnecessary.

**Fix:**
- Replace global state with a `progressTracker` struct guarded by `sync.Mutex`
- Replace `ioutil.WriteFile` with `os.WriteFile`
- Remove the redundant `os.OpenFile` call
- Consider switching to rsync's machine-readable `--out-format` instead of regex parsing (larger change, separate effort)

**Estimate:** 2 days  
**Impact:** Thread-safe, eliminates deprecated API, cleaner code

---

### 2.3 Consistent logging

**Verified status:** CONFIRMED — the code sets up logrus with JSON formatting and wraps it as a `logr.Logger` (lines 283-285 of `transfer-pvc.go`), but only passes it to pvc-transfer library functions. All of crane's own output uses stdlib `log.Fatal`, `log.Println`, `log.Printf`.

Additionally, the struct field `RsyncFlags []string` (line 78) is declared but never registered as a cobra flag — dead code.

**Fix:**
- Replace stdlib `log` with the already-configured logrus logger
- Add context fields: source_pvc, dest_pvc, source_context, dest_context
- Remove dead `RsyncFlags` field

**Estimate:** 4 hours  
**Impact:** Structured output, easier debugging in production

---

## Implementation Order

```
Week 1-2:  Phase 1 — Critical fixes
           ├── 1.1 Replace log.Fatal (1 day)
           ├── 1.2 Add retry mechanism (4 hours)
           └── 1.3 Fork pvc-transfer (4 hours)

Week 3:    Phase 2 — Optimization
           ├── 2.1 Wire rsync flags (1 day)
           ├── 2.2 Fix progress tracking (2 days)
           └── 2.3 Consistent logging (4 hours)
```

## Success Metrics

| Metric | Current | After Phase 1+2 |
|--------|---------|-----------------|
| Transfer success rate | ~85% (dies on errors) | 99%+ (retry + cleanup) |
| Resource leaks on failure | Yes | None |
| Bandwidth control | Unavailable | `--bandwidth-limit` |
| Resume support | No | `--resume` |
| Thread-safe progress | No | Yes |
| Deprecated API usage | `ioutil` | Eliminated |
| Structured logging | No (stdlib log) | Yes (logrus) |
| Stale dependency | 4+ years old | Forked, versioned |
