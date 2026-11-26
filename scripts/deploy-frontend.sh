#!/usr/bin/env bash
# Builds the React app, uploads it to S3 and invalidates CloudFront.
# Usage: S3_BUCKET=... CLOUDFRONT_DISTRIBUTION_ID=... scripts/deploy-frontend.sh
set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET must be set}"
: "${CLOUDFRONT_DISTRIBUTION_ID:?CLOUDFRONT_DISTRIBUTION_ID must be set}"

cd "$(dirname "$0")/../frontend"
npm ci
npm audit --audit-level=high
npm run build

aws s3 sync dist/ "s3://${S3_BUCKET}/" --delete
aws cloudfront create-invalidation --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" --paths "/*"
