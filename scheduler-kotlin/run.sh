#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBS="$SCRIPT_DIR/libs"
JAR="$SCRIPT_DIR/scheduler.jar"

export PATH="/home/dev/.local/jdk/bin:$PATH"

CP=$(find "$LIBS" -name "*.jar" | tr '\n' ':')

echo "🚀 Starting Kotlin Scheduler on :9000..."
java -cp "$JAR:$CP" com.polyglot.MainKt
