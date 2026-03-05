# Migration/transformation example: Kubernetes Ingress to OpenShift Route

This document provides a technical summary of how to transform a standard Kubernetes `Ingress` resource into an OpenShift `Route` using Linux CLI tools.

## 1. Overview of Tools
* **`jsonpatch` (RFC 6902):** Best for surgical, step-by-step modifications to an existing structure.
* **`jq`:** The industry standard for rebuilding or "mapping" a JSON structure into a new format.
* **CLI Redirection (`>`):** Neither tool modifies the source file by default; use `>` to "produce" the new file.

---

## 2. Structural Mapping
The primary challenge is that `Route` is not just a different version of `Ingress`; it is a different `Kind` with a flattened specification.



| Feature | Kubernetes Ingress Path | OpenShift Route Path |
| :--- | :--- | :--- |
| **API Group** | `networking.k8s.io/v1` | `route.openshift.io/v1` |
| **Hostname** | `.spec.rules[0].host` | `.spec.host` |
| **Backend** | `.spec.rules[0].http.paths[0].backend` | `.spec.to` |
| **TLS** | `.spec.tls[0].secretName` | `.spec.tls.termination` |

---

## 3. Implementation Methods

### Method A: Using `jq` (Recommended for Readability)
This approach rebuilds the object. It includes **Edge TLS termination** and an automatic **HTTP-to-HTTPS redirect**.

```bash
jq '{
  apiVersion: "route.openshift.io/v1",
  kind: "Route",
  metadata: .metadata,
  spec: {
    host: .spec.rules[0].host,
    to: {
      kind: "Service",
      name: .spec.rules[0].http.paths[0].backend.service.name
    },
    port: {
      targetPort: (.spec.rules[0].http.paths[0].backend.service.port.number // 80)
    },
    tls: {
      termination: "edge",
      insecureEdgeTerminationPolicy: "Redirect"
    }
  }
}' ingress.json > route.json
```

# Note on existing `crane convert`

Existing `crane convert` aims to convert deprecated Kubernetes and OpenShift resource types to their modern equivalents. It primarily focuses on OpenShift BuildConfigs and ImageStreams that have been marked as deprecated and replaced by alternative solutions.

  The command functions similarly to `crane export`, but instead of merely exporting the current state, it performs direct conversion to recommended replacement types. For example, BuildConfig objects can be converted while respecting registry settings (search, insecure, block
  registries), allowing the conversion to be adapted for different environments. The output is a directory with transformed manifests (default `convert/`) that are ready for deployment to a cluster that no longer supports the deprecated types. This command is particularly
  useful when migrating from older OpenShift versions or transitioning from OpenShift-specific resource types to standard Kubernetes or cloud-native alternatives.

**It might make sense move this under transform steps.**
