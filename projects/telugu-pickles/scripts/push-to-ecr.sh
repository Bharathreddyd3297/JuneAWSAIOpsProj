#!/usr/bin/env bash
# Build all 7 images for linux/amd64 and push them to Amazon ECR.
#   ./scripts/push-to-ecr.sh            # tag = 1.0.0
#   ./scripts/push-to-ecr.sh 1.0.1      # custom tag
# Prereqs: AWS CLI logged in, Docker running, ECR repos created by Terraform
#          (terraform apply -target=module.ecr  in projects/Infrastructure)
set -euo pipefail
TAG="${1:-1.0.0}"
REGION="${AWS_REGION:-us-east-1}"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Registry: $REGISTRY   Tag: $TAG"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for svc in frontend gateway auth-service catalog-service cart-service order-service payment-service; do
  if [ "$svc" = frontend ]; then ctx="$ROOT/frontend"; else ctx="$ROOT/services"; fi
  image="$REGISTRY/telugu-pickles/$svc:$TAG"
  echo "==> $svc"
  docker build --platform linux/amd64 --build-arg SERVICE="$svc" -t "$image" "$ctx" >/dev/null
  docker push "$image" | tail -1
done

echo
echo "Pushed. Scan results:  aws ecr describe-image-scan-findings --repository-name telugu-pickles/gateway --image-id imageTag=$TAG --region $REGION"
