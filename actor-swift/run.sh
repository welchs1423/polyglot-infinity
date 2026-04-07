#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/home/dev/.local/swift/usr/bin:$PATH"

if [[ ! -f "$SCRIPT_DIR/server" ]]; then
    bash "$SCRIPT_DIR/build.sh"
fi
echo "🚀 Starting Swift Actor Server on :8008..."
exec "$SCRIPT_DIR/server"
