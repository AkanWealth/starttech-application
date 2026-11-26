#!/usr/bin/env bash
# Tests, builds and pushes the backend image, then deploys it to EKS.
# Usage: REDIS_HOST=... MONGO_URI=... JWT_SECRET_KEY=... scripts/deploy-backend.sh
set -euo pipefail

: "${REDIS_HOST:?REDIS_HOST must be set}"
: "${MONGO_URI:?MONGO_URI must be set}"
: "${JWT_SECRET_KEY:?JWT_SECRET_KEY must be set}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${REGISTRY}/starttech-backend-api:$(git -C "$ROOT_DIR" rev-parse HEAD)"

(cd "${ROOT_DIR}/backend" && go test ./...)
docker build -t "$IMAGE" "${ROOT_DIR}/backend"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"
docker push "$IMAGE"

sed -i.bak -E "s|image: .*/starttech-backend-api:.*|image: ${IMAGE}|" "${ROOT_DIR}/k8s/deployment.yaml"
rm -f "${ROOT_DIR}/k8s/deployment.yaml.bak"

aws eks update-kubeconfig --name starttech-cluster --region "$AWS_REGION"
kubectl create namespace starttech --dry-run=client -o yaml | kubectl apply -f -
kubectl -n starttech create configmap backend-config \
  --from-literal=REDIS_HOST="$REDIS_HOST" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n starttech create secret generic backend-secrets \
  --from-literal=MONGO_URI="$MONGO_URI" \
  --from-literal=JWT_SECRET_KEY="$JWT_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${ROOT_DIR}/k8s/"
kubectl rollout status deployment/backend-api -n starttech --timeout=300s
