#!/usr/bin/env bash
set -euxo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$ROOT/transform/resources/kustomize/overlays/ns-a"
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

kubectl kustomize --load-restrictor=LoadRestrictionsNone "$OVERLAY" > "$OUT"

assert_contains() {
  local pattern="$1"
  local message="$2"
  if ! grep -qE "$pattern" "$OUT"; then
    echo "FAIL: $message"
    echo "Pattern not found: $pattern"
    exit 1
  fi
}

# Build resources exist with converted names
assert_contains '^kind: Build$' "Build resources should exist"
assert_contains 'name: sample-docker-bc' "Docker build should be named sample-docker-bc"
assert_contains 'name: sample-s2i-bc' "S2I build should be named sample-s2i-bc"

# Strategy mapping checks
assert_contains 'name: buildah' "Docker strategy should map to buildah"
assert_contains 'name: source-to-image' "Source strategy should map to source-to-image"

# Source mapping checks
assert_contains 'url: https://github.com/example/sample-docker.git' "Docker source URL mapping"
assert_contains 'url: https://github.com/example/sample-s2i.git' "S2I source URL mapping"

# Output mapping checks
assert_contains 'image: quay.io/example/sample-docker:latest' "Docker output image mapping"
assert_contains 'image: quay.io/example/sample-s2i:latest' "S2I output image mapping"

# Param mapping checks
assert_contains 'name: dockerfile' "Dockerfile param should exist"
assert_contains 'value: Dockerfile.prod' "Dockerfile param value"
assert_contains 'name: builder-image' "Builder-image param should exist"
assert_contains 'value: registry.access.redhat.com/ubi8/openjdk-17:latest' "Builder-image param value"

# Original BuildConfigs are explicitly marked ignored
assert_contains 'migration.konveyor.io/ignored: "true"' "BuildConfigs should be marked ignored"

echo "PASS: All kustomize conversion checks passed"
