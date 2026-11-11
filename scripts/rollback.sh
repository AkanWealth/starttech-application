#!/usr/bin/env bash
# Rolls the backend deployment back to the previous revision, or to a
# specific revision.
#
# Usage: scripts/rollback.sh [revision]
#   scripts/rollback.sh          # previous revision
#   scripts/rollback.sh 4        # revision 4 (see: kubectl rollout history)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

REVISION="${1:-}"
require kubectl

if [[ "${SKIP_KUBECONFIG:-false}" != "true" ]] && command -v aws >/dev/null 2>&1; then
  ensure_kubeconfig || warn "Could not update kubeconfig; using current context"
fi

log "Rollout history for ${DEPLOYMENT_NAME}"
kubectl rollout history "deployment/${DEPLOYMENT_NAME}" -n "$K8S_NAMESPACE"

CURRENT_IMAGE="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$K8S_NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')"
log "Current image: ${CURRENT_IMAGE}"

if [[ -n "$REVISION" ]]; then
  log "Rolling back to revision ${REVISION}"
  kubectl rollout undo "deployment/${DEPLOYMENT_NAME}" -n "$K8S_NAMESPACE" --to-revision="$REVISION"
else
  log "Rolling back to the previous revision"
  kubectl rollout undo "deployment/${DEPLOYMENT_NAME}" -n "$K8S_NAMESPACE"
fi

kubectl rollout status "deployment/${DEPLOYMENT_NAME}" -n "$K8S_NAMESPACE" --timeout=300s

NEW_IMAGE="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$K8S_NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')"
log "Rolled back: ${CURRENT_IMAGE} -> ${NEW_IMAGE}"
