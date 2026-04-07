#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "🌙 Starting Lua ${LUA_VERSION:-5.4} Coroutine Stream Server on :8007..."
exec lua5.4 "$SCRIPT_DIR/server.lua"
