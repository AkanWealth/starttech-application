#!/usr/bin/env bash
# Rolls the backend back to the previous revision, or to a given revision.
# Usage: scripts/rollback.sh [revision]
set -euo pipefail

if [[ -n "${1:-}" ]]; then
  kubectl rollout undo deployment/backend-api -n starttech --to-revision="$1"
else
  kubectl rollout undo deployment/backend-api -n starttech
fi
kubectl rollout status deployment/backend-api -n starttech --timeout=300s
