#!/usr/bin/env bash
# Checks the backend from inside the cluster and, when possible, through
# CloudFront (the same path a browser uses).
#
# Usage: scripts/health-check.sh [cloudfront-domain]
# Optional env: RETRIES (default 10), DELAY (seconds, default 6)

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

RETRIES="${RETRIES:-10}"
DELAY="${DELAY:-6}"
DOMAIN="${1:-${CLOUDFRONT_DOMAIN:-}}"

require kubectl curl

log "Deployment status"
kubectl get deployment "$DEPLOYMENT_NAME" -n "$K8S_NAMESPACE" -o wide

READY="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$K8S_NAMESPACE" -o jsonpath='{.status.readyReplicas}')"
WANTED="$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$K8S_NAMESPACE" -o jsonpath='{.spec.replicas}')"
[[ "${READY:-0}" -ge 1 ]] || die "No ready replicas (${READY:-0}/${WANTED})"
log "Ready replicas: ${READY}/${WANTED}"

# In-cluster check through the Service, from a short-lived pod.
log "Checking /api/v1/health through the Service"
kubectl run "health-check-$RANDOM" -n "$K8S_NAMESPACE" --rm -i --restart=Never --quiet \
  --image=curlimages/curl:8.10.1 -- \
  curl -fsS --max-time 5 "http://${DEPLOYMENT_NAME}.${K8S_NAMESPACE}.svc.cluster.local/api/v1/health" \
  || die "In-cluster health check failed"
echo

if [[ -z "$DOMAIN" ]] && command -v aws >/dev/null 2>&1; then
  BUCKET="$(discover_frontend_bucket 2>/dev/null || true)"
  if ! is_empty "${BUCKET:-}"; then
    DIST_ID="$(discover_distribution_id "$BUCKET" 2>/dev/null || true)"
    is_empty "${DIST_ID:-}" || DOMAIN="$(discover_distribution_domain "$DIST_ID")"
  fi
fi

if is_empty "${DOMAIN:-}"; then
  warn "CloudFront domain unknown; skipping the end-to-end check"
  exit 0
fi

URL="https://${DOMAIN}/api/v1/health"
log "Checking ${URL}"
for ((i = 1; i <= RETRIES; i++)); do
  CODE="$(curl -s -o /tmp/health.json -w '%{http_code}' --max-time 10 "$URL" || true)"
  if [[ "$CODE" == "200" ]] && grep -q '"database":"ok"' /tmp/health.json; then
    log "Healthy: $(cat /tmp/health.json)"
    exit 0
  fi
  warn "Attempt ${i}/${RETRIES}: HTTP ${CODE}"
  sleep "$DELAY"
done
die "End-to-end health check failed for ${URL}"
