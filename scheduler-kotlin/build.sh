#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBS="$SCRIPT_DIR/libs"
SRC="$SCRIPT_DIR/src/main/kotlin/com/polyglot/Main.kt"
OUT="$SCRIPT_DIR/out"
JAR="$SCRIPT_DIR/scheduler.jar"

export PATH="/home/dev/.local/kotlinc/bin:/home/dev/.local/jdk/bin:$PATH"

echo "🔨 Compiling Kotlin..."
mkdir -p "$OUT"

CP=$(find "$LIBS" -name "*.jar" | tr '\n' ':')

kotlinc "$SRC" \
  -cp "$CP" \
  -include-runtime \
  -d "$JAR" \
  2>&1

echo "✅ Build complete: $JAR"
