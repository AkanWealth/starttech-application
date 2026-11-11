#!/usr/bin/env bash
# Builds the React app and publishes it to S3 behind CloudFront.
#
# Usage: scripts/deploy-frontend.sh [--skip-build]
# Optional env: S3_BUCKET, CLOUDFRONT_DISTRIBUTION_ID, AWS_REGION

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="${ROOT_DIR}/frontend"
SKIP_BUILD=false
[[ "${1:-}" == "--skip-build" ]] && SKIP_BUILD=true

require aws npm

BUCKET="$(discover_frontend_bucket)"
is_empty "$BUCKET" && die "Frontend bucket not found. Set S3_BUCKET or run the infrastructure pipeline first."
DISTRIBUTION_ID="$(discover_distribution_id "$BUCKET")"
is_empty "$DISTRIBUTION_ID" && die "CloudFront distribution not found. Set CLOUDFRONT_DISTRIBUTION_ID."

log "Bucket: ${BUCKET}  Distribution: ${DISTRIBUTION_ID}"

if [[ "$SKIP_BUILD" == false ]]; then
  log "Installing dependencies"
  (cd "$FRONTEND_DIR" && npm ci)
  log "Running npm audit (fails on high or critical findings)"
  (cd "$FRONTEND_DIR" && npm audit --audit-level=high)
  log "Building"
  (cd "$FRONTEND_DIR" && npm run build)
fi

[[ -f "${FRONTEND_DIR}/dist/index.html" ]] || die "dist/index.html not found. Did the build succeed?"

# Hashed assets are immutable and can be cached for a year.
log "Uploading hashed assets"
aws s3 sync "${FRONTEND_DIR}/dist/" "s3://${BUCKET}/" \
  --delete \
  --exclude "index.html" \
  --cache-control "public, max-age=31536000, immutable"

# index.html must always be revalidated so users pick up new releases.
log "Uploading index.html"
aws s3 cp "${FRONTEND_DIR}/dist/index.html" "s3://${BUCKET}/index.html" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "text/html"

log "Invalidating CloudFront cache"
INVALIDATION_ID="$(aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" \
  --query Invalidation.Id --output text)"

if [[ "${WAIT_FOR_INVALIDATION:-false}" == "true" ]]; then
  log "Waiting for invalidation ${INVALIDATION_ID}"
  aws cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION_ID" --id "$INVALIDATION_ID"
fi

DOMAIN="$(discover_distribution_domain "$DISTRIBUTION_ID")"
log "Frontend deployed: https://${DOMAIN}"
