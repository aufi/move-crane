# Proposal: Crane transform support for Ingress -> Gateway API identity conversion (migration to new GVK)

## Context
Current Crane transform is patch-first:
- plugin returns JSONPatch for the same object, or
- plugin marks object as whiteout.

This model cannot fully cover identity changes (GVK -> new GVK), e.g.:
- `networking.k8s.io/v1 Ingress` -> `gateway.networking.k8s.io/v1 HTTPRoute` (+ optional `Gateway`, `ReferenceGrant`).

`ingress2gateway` demonstrates this conversion pattern well:
- parses Ingress resources,
- applies provider-specific behavior,
- emits Gateway API resources,
- reports conflicts deterministically.

---

## Goal
Extend Crane so `transform` can:
1. whiteout an original object (optional),
2. generate replacement objects with different GVK,
3. gate this behavior by target validation (`crane validate --target-context ...`).

---

## Recommended design

## 1) Extend transform plugin response model (crane-lib)
Add generated-object support to `PluginResponse` (backward compatible):

```go
type GeneratedResource struct {
  PathHint string                 `json:"pathHint,omitempty"` // optional relative path hint
  Object   map[string]interface{} `json:"object"`             // unstructured manifest
}

type PluginResponse struct {
  Version    string              `json:"version,omitempty"`
  IsWhiteOut bool                `json:"isWhiteOut,omitempty"`
  Patches    jsonpatch.Patch     `json:"patches,omitempty"`
  Generated  []GeneratedResource `json:"generated,omitempty"`
}
```

Runner behavior:
- keeps current patch/whiteout flow,
- additionally collects `Generated` outputs per source resource.

---

## 2) Persist generated resources in transform output
In `crane transform prepare`, besides `transform-*.yaml` and `.wh.*`, write generated manifests to e.g.:

- `transform-generated/<namespace>/<name>-<kind>.yaml`

plus provenance annotation:
- `crane.transform/generated-from: <group>/<version>/<kind>/<namespace>/<name>`

This keeps generated resources explicit, reviewable, and GitOps-friendly.

---

## 3) Teach `crane transform apply` to include generated resources
`apply` should:
- continue processing export resources as today,
- copy/render generated resources from `transform-generated/` into `output/`.

If source object is whiteout and generated resources exist, output contains only replacements.

---

## 4) Add a dedicated plugin: `ingress-gateway`
Create a transform plugin inspired by ingress2gateway behavior:

Input:
- Ingress resources from export set.

Output:
- `HTTPRoute` (required)
- optional `Gateway` (configurable)
- optional `ReferenceGrant` for cross-namespace refs
- whiteout source Ingress (configurable mode)

Optional flags (examples):
- `ingress-gateway.enabled=true|false`
- `ingress-gateway.gateway-name=<name>`
- `ingress-gateway.gateway-namespace=<ns>`
- `ingress-gateway.gateway-class=<class>`
- `ingress-gateway.listener-http-port=80`
- `ingress-gateway.listener-https-port=443`
- `ingress-gateway.emit-gateway=true|false`
- `ingress-gateway.whiteout-source=true|false`
- `ingress-gateway.provider=ingress-nginx|nginx|kong|...`

Provider-specific behavior can start with a minimal subset (standard Ingress spec), then iterate.

---

## 5) Target-driven activation via `crane validate`
Use `crane validate --target-context <name>` as decision input:

- If target lacks Ingress support but has Gateway API CRDs -> suggest/enable ingress-gateway conversion.
- If target lacks required Gateway API CRDs (`Gateway`, `HTTPRoute`) -> fail with actionable message.

Suggested flow:
1. prepare (default plugins)
2. apply
3. validate
4. if validate finding: `unsupported GVK Ingress` + `Gateway API present`
   -> rerun prepare with `ingress-gateway.enabled=true`

This fits your current strategy: user-scripted orchestration with explicit reports.

---

## 6) Conflict and determinism rules (important)
Adopt deterministic processing similar to ingress2gateway:
- sort source Ingress by creationTimestamp then namespace/name,
- deterministic naming of generated HTTPRoutes,
- explicit conflict report when two Ingress rules map to conflicting matches/backends.

---

## MVP scope
1. Extend plugin response with `Generated`.
2. `prepare` writes generated resources to `transform-generated/`.
3. `apply` includes generated resources in `output/`.
4. Implement minimal `ingress-gateway` plugin for standard Ingress spec only.
5. Add validate hint rules for conversion trigger.

---

## Why this is the right fit for Crane
- Preserves existing patch-based model.
- Adds first-class identity transformation without hacks.
- Keeps outputs auditable as files.
- Integrates naturally with `validate`-driven migration decisions.
- Enables future conversions beyond Ingress (e.g. DeploymentConfig -> Deployment).
