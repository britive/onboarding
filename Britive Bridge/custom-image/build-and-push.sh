#!/usr/bin/env bash
#
# build-and-push.sh — Build the custom Britive Bridge image and push it to your
# container registry (Docker Hub or Amazon ECR). Multi-arch by default so the
# same tag runs on Fargate ARM64 and x86 / mixed Kubernetes nodes.
#
# Usage:
#   REGISTRY=docker.io/yourorg ./build-and-push.sh                 # Docker Hub
#   REGISTRY=<acct>.dkr.ecr.us-west-2.amazonaws.com ./build-and-push.sh   # ECR
#
# Env overrides:
#   REGISTRY    (required) target registry/namespace, no trailing slash
#   IMAGE_NAME  image repo name              (default: britive-bridge-custom)
#   TAG         image tag                    (default: latest)
#   BASE_IMAGE  base to extend               (default: britive/bridge:latest)
#   PLATFORMS   buildx platforms             (default: linux/amd64,linux/arm64)

set -euo pipefail

REGISTRY="${REGISTRY:?Set REGISTRY, e.g. docker.io/yourorg or <acct>.dkr.ecr.<region>.amazonaws.com}"
IMAGE_NAME="${IMAGE_NAME:-britive-bridge-custom}"
TAG="${TAG:-latest}"
BASE_IMAGE="${BASE_IMAGE:-britive/bridge:latest}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "==> Building ${FULL_IMAGE}"
echo "    base:      ${BASE_IMAGE}"
echo "    platforms: ${PLATFORMS}"

# ECR repos must exist before push; create on demand if this is an ECR target.
if echo "$REGISTRY" | grep -q 'dkr.ecr'; then
  REGION=$(echo "$REGISTRY" | sed -E 's/.*\.ecr\.([^.]+)\.amazonaws\.com/\1/')
  echo "==> ECR detected (region ${REGION}). Ensuring repo + login..."
  aws ecr describe-repositories --repository-names "$IMAGE_NAME" --region "$REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$IMAGE_NAME" --region "$REGION" >/dev/null
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "${REGISTRY%%/*}"
else
  echo "==> Ensure you are logged in:  docker login ${REGISTRY%%/*}"
fi

# buildx handles multi-arch + push in one step. Create a builder if missing.
docker buildx inspect bridge-builder >/dev/null 2>&1 || docker buildx create --name bridge-builder --use
docker buildx use bridge-builder

docker buildx build \
  --platform "$PLATFORMS" \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  -t "$FULL_IMAGE" \
  --push \
  .

echo "==> Pushed ${FULL_IMAGE}"
echo "    Set this as the image in your ECS task definition (ImageUri) or"
echo "    Kubernetes Deployment (image:)."
