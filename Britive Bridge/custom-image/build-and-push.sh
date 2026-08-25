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
#   BASE_IMAGE  base to extend               (default: britive/bridge:v2.1.0)
#               Bridge v1 deployments MUST set britive/bridge:v1.0.2
#   BAKE_CONFIG bake BRIDGE_CONFIG into the image  (default: false)
#               REQUIRED for Bridge v2 - it will not start without a config
#   BRIDGE_CONFIG  config file in this directory   (default: bridge.yaml)
#   WITH_RDS_CA trust the AWS RDS CAs          (default: false)
#               needed for database checkouts using target_tls=true
#   PLATFORMS   buildx platforms             (default: linux/amd64,linux/arm64)

set -euo pipefail

REGISTRY="${REGISTRY:?Set REGISTRY, e.g. docker.io/yourorg or <acct>.dkr.ecr.<region>.amazonaws.com}"
IMAGE_NAME="${IMAGE_NAME:-britive-bridge-custom}"
TAG="${TAG:-latest}"
BASE_IMAGE="${BASE_IMAGE:-britive/bridge:v2.1.0}"
BAKE_CONFIG="${BAKE_CONFIG:-false}"
BRIDGE_CONFIG="${BRIDGE_CONFIG:-bridge.yaml}"
WITH_RDS_CA="${WITH_RDS_CA:-false}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "==> Building ${FULL_IMAGE}"
echo "    base:      ${BASE_IMAGE}"
echo "    config:    $([ "$BAKE_CONFIG" = "true" ] && echo "${BRIDGE_CONFIG} (baked)" || echo "not baked")"
echo "    rds CAs:   ${WITH_RDS_CA}"
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
  --build-arg "BAKE_CONFIG=${BAKE_CONFIG}" \
  --build-arg "BRIDGE_CONFIG=${BRIDGE_CONFIG}" \
  --build-arg "WITH_RDS_CA=${WITH_RDS_CA}" \
  -t "$FULL_IMAGE" \
  --push \
  .

echo "==> Pushed ${FULL_IMAGE}"
echo "    Set this as the image in your ECS task definition (ImageUri) or"
echo "    Kubernetes Deployment (image:)."
