#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "🧠 Starting SWI-Prolog 8.4 Constraint Solver on :8011..."
exec swipl "$SCRIPT_DIR/server.pl"
