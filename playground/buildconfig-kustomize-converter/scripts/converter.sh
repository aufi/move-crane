#!/bin/bash
set -e

# converter.sh - Convert BuildConfig to Shipwright Build using Helm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_CHART="${SCRIPT_DIR}/../helm-chart/buildconfig-to-shipwright"

# Check dependencies
command -v yq >/dev/null 2>&1 || { echo "Error: yq not found" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "Error: helm not found" >&2; exit 1; }

if [ ! -d "$HELM_CHART" ]; then
    echo "Error: Helm chart not found at $HELM_CHART" >&2
    exit 1
fi

process_buildconfig() {
    local bc_file="$1"

    if [ ! -f "$bc_file" ]; then
        echo "Warning: File not found: $bc_file" >&2
        return 1
    fi

    local kind=$(yq eval '.kind' "$bc_file" 2>/dev/null)
    if [ "$kind" != "BuildConfig" ]; then
        echo "Skipping non-BuildConfig: $bc_file" >&2
        return 0
    fi

    local name=$(yq eval '.metadata.name' "$bc_file")
    local namespace=$(yq eval '.metadata.namespace' "$bc_file")

    echo "# Processing: $namespace/$name" >&2

    # Generate values file properly
    local values_file=$(mktemp /tmp/bc-values-XXXXXX.yaml)

    yq eval '{
      "name": .metadata.name,
      "namespace": .metadata.namespace,
      "labels": (.metadata.labels // {}),
      "strategy": {
        "type": .spec.strategy.type,
        "dockerStrategy": {
          "dockerfilePath": (.spec.strategy.dockerStrategy.dockerfilePath // "Dockerfile"),
          "env": (.spec.strategy.dockerStrategy.env // []),
          "buildArgs": (.spec.strategy.dockerStrategy.buildArgs // [])
        },
        "sourceStrategy": {
          "from": {
            "kind": (.spec.strategy.sourceStrategy.from.kind // ""),
            "name": (.spec.strategy.sourceStrategy.from.name // ""),
            "namespace": (.spec.strategy.sourceStrategy.from.namespace // "")
          },
          "env": (.spec.strategy.sourceStrategy.env // [])
        }
      },
      "source": {
        "type": (.spec.source.type // ""),
        "git": {
          "uri": (.spec.source.git.uri // ""),
          "ref": (.spec.source.git.ref // "")
        },
        "sourceSecret": (.spec.source.sourceSecret.name // "")
      },
      "output": {
        "to": {
          "kind": (.spec.output.to.kind // ""),
          "name": (.spec.output.to.name // "")
        },
        "pushSecret": (.spec.output.pushSecret.name // "")
      }
    }' "$bc_file" > "$values_file"

    # Run Helm template
    helm template "$name" "$HELM_CHART" -f "$values_file" 2>&1 | grep -v "^#" || {
        echo "Error: Helm template failed" >&2
        cat "$values_file" >&2
        rm -f "$values_file"
        return 1
    }

    rm -f "$values_file"
}

# Main
if [ $# -eq 0 ]; then
    echo "Usage: $0 <buildconfig.yaml> [...]" >&2
    exit 1
fi

first=true
for bc_file in "$@"; do
    if [ "$first" = false ]; then
        echo "---"
    fi

    if process_buildconfig "$bc_file"; then
        first=false
    fi
done

echo "# Done. Processed $# file(s)." >&2
