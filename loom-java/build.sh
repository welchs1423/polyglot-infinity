#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/home/dev/.local/jdk/bin:$PATH"

echo "🔨 Compiling Java 21 Virtual Thread Server..."
javac "$SCRIPT_DIR/VirtualServer.java" -d "$SCRIPT_DIR/out"
echo "✅ Build complete"
