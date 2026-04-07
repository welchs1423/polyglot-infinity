#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLOJURE_JAR="/usr/share/java/clojure.jar"

echo "🟣 Starting Clojure $(java -cp $CLOJURE_JAR clojure.main -e '(print (clojure-version))' 2>/dev/null) STM Ledger on :8009..."
exec java -cp "$CLOJURE_JAR" clojure.main "$SCRIPT_DIR/server.clj"
