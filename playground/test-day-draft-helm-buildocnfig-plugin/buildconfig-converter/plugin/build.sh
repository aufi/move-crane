#!/bin/bash
set -e

echo "Building BuildConfigConverter plugin..."

# Get directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Download dependencies
echo "Downloading Go dependencies..."
go mod download
go mod tidy

# Build plugin
echo "Building binary..."
go build -o buildconfig-converter main.go

# Make executable
chmod +x buildconfig-converter

echo "✓ Plugin built successfully: $SCRIPT_DIR/buildconfig-converter"
echo ""
echo "To install:"
echo "  mkdir -p ~/.local/share/crane/plugins/"
echo "  cp buildconfig-converter ~/.local/share/crane/plugins/"
echo ""
echo "To test:"
echo "  ./buildconfig-converter --test ../samples/buildconfig-docker.yaml"
