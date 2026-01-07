#!/bin/bash
# Baut die Flutter Web App und kopiert sie nach server/webapp
# Usage: ./scripts/build-webapp.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$SERVER_DIR")"

echo "=== Building Flutter Web App ==="
echo "Project: $PROJECT_DIR"
echo ""

cd "$PROJECT_DIR"

# Flutter Web Build
echo "1. Building Flutter Web..."
flutter build web --release

# Kopieren nach server/webapp
echo ""
echo "2. Copying to server/webapp..."
rm -rf "$SERVER_DIR/webapp"
cp -r "$PROJECT_DIR/build/web" "$SERVER_DIR/webapp"

# Größe anzeigen
echo ""
echo "3. Build complete!"
du -sh "$SERVER_DIR/webapp"
ls -la "$SERVER_DIR/webapp"

echo ""
echo "Done! Ready for docker build."
