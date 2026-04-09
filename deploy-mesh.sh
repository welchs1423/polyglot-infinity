#!/usr/bin/env bash
set -euo pipefail

echo "Creating namespace polyglot"
kubectl create namespace polyglot --dry-run=client -o yaml | kubectl apply -f -

echo "Enabling Istio sidecar injection on namespace polyglot"
kubectl label namespace polyglot istio-injection=enabled --overwrite

echo "Applying manifests from k8s/ to namespace polyglot"
kubectl apply -f k8s/ -n polyglot

echo "Deployment complete"
echo "All 28 services submitted to namespace polyglot"

# ---------------------------------------------------------------------------
# Kiali dashboard port-forward (run in a separate terminal or background)
#
#   kubectl port-forward svc/kiali 20001:20001 -n istio-system &
#
# Then open: http://localhost:20001/kiali
#
# To stop the port-forward:
#   kill %1   (if started with &)
#   or:
#   pkill -f "kubectl port-forward svc/kiali"
# ---------------------------------------------------------------------------
