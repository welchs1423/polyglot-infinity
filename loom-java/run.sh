#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/home/dev/.local/jdk/bin:$PATH"

if [[ ! -f "$SCRIPT_DIR/out/VirtualServer.class" ]]; then
    bash "$SCRIPT_DIR/build.sh"
fi

# build.sh가 생성한 .classpath 파일에서 의존성 경로를 읽는다.
DEPS_CP=""
if [[ -f "$SCRIPT_DIR/.classpath" ]]; then
    DEPS_CP="$(< "$SCRIPT_DIR/.classpath")"
fi

FULL_CP="$SCRIPT_DIR/out"
if [[ -n "$DEPS_CP" ]]; then
    FULL_CP="${FULL_CP}:${DEPS_CP}"
fi

echo "Starting Java 21 Loom Virtual Thread Server on :8010..."
exec java -cp "$FULL_CP" VirtualServer
