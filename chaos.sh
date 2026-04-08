#!/usr/bin/env bash
set -euo pipefail

# Containers matching this pattern are excluded from chaos targeting.
# postgres, redis, db-postgres: infrastructure databases.
# svelte-portal, terminal-elm: frontend services.
EXCLUDE_PATTERN='polyglot-infinity-(postgres|redis|db-postgres|svelte-portal|terminal-elm)-'

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Chaos monkey started. Cycle: kill -> 5s down -> start -> 10s wait."

while true; do
    sleep 10

    # Build array of running backend containers for this project.
    mapfile -t CONTAINERS < <(
        docker ps --format '{{.Names}}' \
            | grep '^polyglot-infinity-' \
            | grep -vE "$EXCLUDE_PATTERN" \
            || true
    )

    if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No eligible containers running. Skipping cycle."
        continue
    fi

    # Random index selection using the shell built-in RANDOM (0..32767).
    INDEX=$(( RANDOM % ${#CONTAINERS[@]} ))
    TARGET="${CONTAINERS[$INDEX]}"

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] KILL  -> $TARGET"
    docker kill "$TARGET"

    sleep 5

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] START -> $TARGET"
    docker start "$TARGET"
done
