#!/usr/bin/env bash
# Checks the backend health endpoint through CloudFront.
# Usage: scripts/health-check.sh <cloudfront-domain>
set -euo pipefail

DOMAIN="${1:?Usage: $0 <cloudfront-domain>}"

kubectl rollout status deployment/backend-api -n starttech --timeout=60s
curl -fsS "https://${DOMAIN}/api/v1/health"
echo
