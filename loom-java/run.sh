#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/home/dev/.local/jdk/bin:$PATH"

LIBS="$SCRIPT_DIR/libs"
CP="$SCRIPT_DIR/out:$LIBS/jedis-5.2.0.jar:$LIBS/commons-pool2-2.12.0.jar:$LIBS/slf4j-api.jar"

if [[ ! -f "$SCRIPT_DIR/out/VirtualServer.class" ]]; then
    bash "$SCRIPT_DIR/build.sh"
fi
echo "Starting Java 21 Loom Virtual Thread Server on :8010..."
exec java -cp "$CP" VirtualServer
