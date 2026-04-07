#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/home/dev/.local/swift/usr/bin:$PATH"

echo "🔨 Compiling Swift Actor Server..."
swiftc -O -whole-module-optimization \
  "$SCRIPT_DIR/main.swift" \
  -o "$SCRIPT_DIR/server" \
  2>&1
echo "✅ Build complete: $SCRIPT_DIR/server"
