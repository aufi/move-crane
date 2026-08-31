# Finding 04 — Minor considerations (nice-to-have, non-blocking)

**Scope:** cosmetic / documentation-level observations from the stateful
migration run. Nothing here affected the result — captured only for
consideration.

## 4a. `transfer-pvc` prints a controller-runtime stack trace

During the rsync copy phase, `crane transfer-pvc` emits a noisy Go stack trace:

```
[controller-runtime] log.SetLogger(...) was never called; logs will not be displayed.
Detected at:
	>  goroutine 1 [running]:
	>  runtime/debug.Stack()
	...
	>  github.com/migtools/pvc-transfer/transfer/rsync.(*client).reconcilePod(...)
	>  github.com/konveyor/crane/cmd/transfer-pvc/transfer-pvc.go:624
```

**Assessment:** cosmetic. It is the controller-runtime library warning that
`log.SetLogger()` was never called; the transfer completes successfully. It looks
alarming in the output (resembles a crash/panic) and could confuse users.

**Consider:** call `log.SetLogger(...)` (e.g. a no-op/zap logger) early in the
`transfer-pvc` command so the trace is suppressed.

## 4b. `transfer-pvc` requires a single kubeconfig with both contexts

`transfer-pvc` reads `--source-context` and `--destination-context` from the
*current* kubeconfig, so both clusters must live in one kubeconfig file. A
common setup (separate per-cluster kubeconfigs, or one active login at a time via
`oc login`) does not work directly; the files must be merged first
(`KUBECONFIG=a:b oc config view --flatten`).

**Assessment:** works as designed, but it is an easy-to-miss prerequisite.

**Consider:** document the merge step in the crane `transfer-pvc` docs, and/or
accept `--source-kubeconfig` / `--destination-kubeconfig` flags so two separate
files can be used without a manual merge.
