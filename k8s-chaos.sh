#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="polyglot"
INTERVAL=10

while true; do
  PODS=($(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Running \
    -o jsonpath='{.items[*].metadata.name}'))

  if [[ ${#PODS[@]} -eq 0 ]]; then
    echo "$(date -u '+%Y-%m-%d %H:%M:%S') [chaos] no running pods in namespace '$NAMESPACE', skipping"
  else
    TARGET="${PODS[$((RANDOM % ${#PODS[@]}))]}"
    echo "$(date -u '+%Y-%m-%d %H:%M:%S') [chaos] deleting pod: $TARGET"
    kubectl delete pod "$TARGET" -n "$NAMESPACE" --grace-period=0 --force
  fi

  sleep "$INTERVAL"
done
