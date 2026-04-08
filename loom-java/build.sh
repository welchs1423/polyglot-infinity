#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export PATH="/home/dev/.local/jdk/bin:$PATH"

LIBS="$SCRIPT_DIR/libs"
CP="$LIBS/jedis-5.2.0.jar:$LIBS/commons-pool2-2.12.0.jar:$LIBS/slf4j-api.jar"

echo "Compiling Java 21 Virtual Thread Server..."
mkdir -p "$SCRIPT_DIR/out"
javac -cp "$CP" "$SCRIPT_DIR/VirtualServer.java" -d "$SCRIPT_DIR/out"
echo "Build complete"
