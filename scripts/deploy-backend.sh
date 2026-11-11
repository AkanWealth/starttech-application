#!/usr/bin/env bash
# Builds, scans and pushes the backend image, then deploys it to EKS.
#
# Usage: scripts/deploy-backend.sh [image-tag]
#   image-tag defaults to the current git SHA.
# Required env: MONGO_URI, JWT_SECRET_KEY
# Optional env: AWS_REGION, REDIS_HOST, CLOUDFRONT_DOMAIN, SKIP_BUILD=true

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${1:-$(git -C "$ROOT_DIR" rev-parse HEAD)}"

require aws docker kubectl git

: "${MONGO_URI:?MONGO_URI must be set}"
: "${JWT_SECRET_KEY:?JWT_SECRET_KEY must be set}"

ACCOUNT_ID="$(aws_account_id)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
  log "Running Go tests"
  (cd "${ROOT_DIR}/backend" && go test ./...)

  log "Building ${IMAGE}"
  docker build --build-arg VERSION="$IMAGE_TAG" -t "$IMAGE" "${ROOT_DIR}/backend"

  if command -v trivy >/dev/null 2>&1; then
    log "Scanning image with Trivy"
    trivy image --exit-code 1 --severity CRITICAL,HIGH --ignore-unfixed "$IMAGE"
  else
    warn "trivy not installed; skipping local scan (ECR scan-on-push still runs)"
  fi

  log "Logging in to ECR"
  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"
  log "Pushing image"
  docker push "$IMAGE"
fi

ensure_kubeconfig

REDIS_ENDPOINT="$(discover_redis_host)"
is_empty "$REDIS_ENDPOINT" && die "Could not find Redis endpoint for ${REDIS_CLUSTER_ID}"

if [[ -z "${CLOUDFRONT_DOMAIN:-}" ]]; then
  BUCKET="$(discover_frontend_bucket)"
  DIST_ID="$(discover_distribution_id "$BUCKET")"
  CLOUDFRONT_DOMAIN="$(discover_distribution_domain "$DIST_ID")"
fi

log "Applying namespace, config and secrets"
kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$K8S_NAMESPACE" create configmap backend-config \
  --from-literal=REDIS_HOST="$REDIS_ENDPOINT" \
  --from-literal=COOKIE_DOMAINS="$CLOUDFRONT_DOMAIN" \
  --from-literal=ALLOWED_ORIGINS="https://${CLOUDFRONT_DOMAIN}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$K8S_NAMESPACE" create secret generic backend-secrets \
  --from-literal=MONGO_URI="$MONGO_URI" \
  --from-literal=JWT_SECRET_KEY="$JWT_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Setting image in k8s/deployment.yaml to ${IMAGE}"
# Portable in-place edit (GNU and BSD sed).
sed -i.bak -E "s|^([[:space:]]*image:[[:space:]]*).*/${ECR_REPOSITORY}:.*$|\1${IMAGE}|" "${ROOT_DIR}/k8s/deployment.yaml"
rm -f "${ROOT_DIR}/k8s/deployment.yaml.bak"
grep -q "image: ${IMAGE}" "${ROOT_DIR}/k8s/deployment.yaml" || die "Image tag was not written to deployment.yaml"

log "Applying manifests"
kubectl apply -f "${ROOT_DIR}/k8s/"

log "Waiting for rollout"
if ! kubectl rollout status "deployment/${DEPLOYMENT_NAME}" -n "$K8S_NAMESPACE" --timeout=300s; then
  warn "Rollout failed; rolling back"
  "${ROOT_DIR}/scripts/rollback.sh"
  exit 1
fi

"${ROOT_DIR}/scripts/health-check.sh"
log "Backend deployed: ${IMAGE}"
