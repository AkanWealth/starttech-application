#!/usr/bin/env bash
# Shared helpers for the deploy scripts. Values come from environment
# variables when set; otherwise they are looked up in AWS using the
# StartTech naming conventions.

set -euo pipefail

export AWS_REGION="${AWS_REGION:-us-east-1}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-starttech-cluster}"
export ECR_REPOSITORY="${ECR_REPOSITORY:-starttech-backend-api}"
export K8S_NAMESPACE="${K8S_NAMESPACE:-starttech}"
export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-backend-api}"
export REDIS_CLUSTER_ID="${REDIS_CLUSTER_ID:-starttech-redis}"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not installed"
  done
}

aws_account_id() {
  aws sts get-caller-identity --query Account --output text
}

# The bucket name is "starttech-frontend-bucket-<account id>".
discover_frontend_bucket() {
  if [[ -n "${S3_BUCKET:-}" ]]; then echo "$S3_BUCKET"; return; fi
  aws s3api list-buckets \
    --query "Buckets[?starts_with(Name, 'starttech-frontend-bucket')].Name | [0]" \
    --output text
}

# Finds the distribution whose origins include the S3-Frontend origin ID
# and point at the frontend bucket.
discover_distribution_id() {
  if [[ -n "${CLOUDFRONT_DISTRIBUTION_ID:-}" ]]; then echo "$CLOUDFRONT_DISTRIBUTION_ID"; return; fi
  local bucket="$1"
  aws cloudfront list-distributions \
    --query "DistributionList.Items[?Origins.Items[?Id=='S3-Frontend' && starts_with(DomainName, '${bucket}.')]].Id | [0]" \
    --output text
}

discover_distribution_domain() {
  local id="$1"
  aws cloudfront list-distributions \
    --query "DistributionList.Items[?Id=='${id}'].DomainName | [0]" \
    --output text
}

discover_redis_host() {
  if [[ -n "${REDIS_HOST:-}" ]]; then echo "$REDIS_HOST"; return; fi
  aws elasticache describe-cache-clusters \
    --cache-cluster-id "$REDIS_CLUSTER_ID" \
    --show-cache-node-info \
    --query "CacheClusters[0].CacheNodes[0].Endpoint.Address" \
    --output text
}

ensure_kubeconfig() {
  log "Updating kubeconfig for cluster ${EKS_CLUSTER_NAME}"
  aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
}

is_empty() { [[ -z "$1" || "$1" == "None" || "$1" == "null" ]]; }
