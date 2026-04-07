#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/home/dev/.local/jdk/bin:$PATH"

if [[ ! -f "$SCRIPT_DIR/out/VirtualServer.class" ]]; then
    bash "$SCRIPT_DIR/build.sh"
fi
echo "🚀 Starting Java 21 Loom Virtual Thread Server on :8010..."
exec java -cp "$SCRIPT_DIR/out" VirtualServer
