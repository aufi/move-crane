# Finding 09 — downstream binary (mta-ops) support + contract check

**Scope:** run the exact same test-day flow against the downstream build
(`mta-ops`, not yet available) instead of upstream `crane`, and — separately —
assert the ways the downstream binary is contractually expected to differ from
upstream.

## Running the same flow against a different binary

Every crane-invoking script now takes a `CRANE_BIN` env var (default `crane`) and
calls `"${CRANE_BIN}"` instead of a bare `crane`. So the whole migration runs
against the downstream build by setting one variable:

```bash
# whole end-to-end migration against the downstream binary
CRANE_BIN=mta-ops scripts/10-run-full-migration.sh

# or individual steps
CRANE_BIN=mta-ops scripts/01-check-versions.sh
CRANE_BIN=mta-ops NAMESPACE=wordpress scripts/05-crane-export-transform-apply.sh
CRANE_BIN=mta-ops RUNS=2 scripts/07-transfer-pvc.sh
```

`10-run-full-migration.sh` exports `CRANE_BIN`, so every sub-step inherits it.
Notes on the parametrized scripts:

- `01-check-versions.sh` — checks whichever binary; the strict `v0.11.0-alpha.1`
  assertion only runs for `crane` (a downstream binary reports a different version
  string, which is just printed).
- `22-crane-buildconfig-convert.sh` — gained `SKIP_PLUGIN_BUILD=true`, which drops
  the external plugin build **and** `--plugin-dir`, so the BuildConfig→Shipwright
  conversion runs on the binary's *embedded* Builds/Shipwright plugin. Upstream
  crane has no embedded BuildConfig plugin, so its default (`false`) still builds
  and adds the external one.

## Separate downstream contract check — `scripts/30-check-downstream-binary.sh`

This does **not** migrate data (that is the same flow above). It asserts the
downstream-specific contract, read-only, no cluster:

| # | Check | Downstream expectation |
| :-- | :-- | :-- |
| A | Command surface | ONLY `export, transform, apply, validate, transfer-pvc`; `plugin-manager, convert, skopeo-sync-gen, tunnel-api` **absent** |
| B | Embedded transform plugins | `Kubernetes`, `OpenShift` **and** `Builds/Shipwright` all built in (no external plugin dir; Shipwright must **not** be added externally) |
| C | Transfer image | `transfer-pvc` default container image is a downstream image **not** on `quay.io`; its name is echoed to the log |

How each check works:

- **A** parses the `Available Commands:` block of `<bin> --help`.
- **B** runs `<bin> transform` on a throwaway one-ConfigMap export from a **clean
  temp CWD** with an empty `--plugin-dir`. `transform` otherwise auto-loads
  `./plugins` relative to the CWD, so a clean CWD is what isolates *embedded*
  plugins. It then reads the `Creating default stage for plugin: <Name>` log lines
  (crane creates one default stage per discovered plugin) and matches names
  case-insensitively against `kubernetes` / `openshift` / `shipwright|build`.
- **C** parses the `--source-image` (fallback `--destination-image`) default out of
  `<bin> transfer-pvc --help` and asserts it does not contain `quay.io`.

The script exits non-zero if any expectation is unmet.

## Validated against upstream crane (the diff, made explicit)

Running the check against the current `crane v0.11.0-alpha.1` **fails every
downstream expectation — as it should**, which is exactly the upstream/downstream
diff mta-ops has to close:

```
A) commands: extra present -> plugin-manager, convert, skopeo-sync-gen, tunnel-api
B) embedded plugins: KubernetesPlugin only  (OpenShift, Builds/Shipwright NOT embedded)
C) transfer image: quay.io/konveyor/rsync-transfer:latest  (on quay.io)
RESULT: FAIL (expected when checking upstream 'crane')
```

The required commands (`export, transform, apply, validate, transfer-pvc`) and the
Kubernetes embedded plugin are already present upstream; the check confirms only
those three deltas remain for the downstream build. When `mta-ops` is available,
`CRANE_BIN=mta-ops scripts/30-check-downstream-binary.sh` should print `RESULT:
PASS` and echo the downstream transfer image name.

## Reproduce

```bash
# contract check (against crane now; against mta-ops later)
scripts/30-check-downstream-binary.sh                 # crane  -> RESULT: FAIL (documented diff)
CRANE_BIN=mta-ops scripts/30-check-downstream-binary.sh   # later -> RESULT: PASS expected

# same migration flow, different binary
CRANE_BIN=mta-ops scripts/10-run-full-migration.sh
```
