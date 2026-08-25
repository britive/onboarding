#!/usr/bin/env bash
# =============================================================================
# Build the Britive Bridge deployment image and push it to your ECR repository.
#
# Prerequisites:
#   - Docker running
#   - AWS CLI v2, authenticated to the target account
#   - The ECR repository already created (deploy ecr-repo.yaml first)
#
# Usage:
#   ./build-and-push.sh                                  # defaults below
#   IMAGE_TAG=v2.1.0-r2 ./build-and-push.sh              # new tag after a config change
#   BRIDGE_VERSION=v2.1.1 IMAGE_TAG=v2.1.1-r1 ./build-and-push.sh
#   PLATFORM=linux/amd64 CPU_ARCH=X86_64 ./build-and-push.sh
# =============================================================================
set -euo pipefail

BRIDGE_VERSION="${BRIDGE_VERSION:-v2.1.0}"   # upstream tag used in the FROM line
IMAGE_TAG="${IMAGE_TAG:-${BRIDGE_VERSION}-r1}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPO="${ECR_REPO:-britive/bridge}"

# MUST match the CpuArchitecture parameter on the ECS stack. Fargate refuses to
# start a task whose image architecture differs, and the failure surfaces as a
# stopped task rather than a stack error.
PLATFORM="${PLATFORM:-linux/arm64}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v docker >/dev/null 2>&1 || { echo "error: docker not found" >&2; exit 1; }
command -v aws    >/dev/null 2>&1 || { echo "error: aws CLI not found" >&2; exit 1; }
[ -f "${SCRIPT_DIR}/bridge.yaml" ] || { echo "error: bridge.yaml not found beside this script" >&2; exit 1; }

# Fail early on the mistake that otherwise crash-loops the task at startup.
if grep -qE '^\s*tenant:\s*"?your-tenant"?\s*$' "${SCRIPT_DIR}/bridge.yaml"; then
  echo "error: set server.auth.britive.tenant in bridge.yaml to your tenant subdomain" >&2
  echo "       (the Bridge validates this from the FILE and crash-loops when it is unset)" >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"

echo "==> Building ${IMAGE_URI}"
echo "    base platform : ${PLATFORM}"
echo "    bridge version: ${BRIDGE_VERSION}"

docker pull --platform "$PLATFORM" "britive/bridge:${BRIDGE_VERSION}"

docker build \
  --platform "$PLATFORM" \
  --build-arg "BRIDGE_VERSION=${BRIDGE_VERSION}" \
  -f "${SCRIPT_DIR}/Dockerfile" \
  -t "$IMAGE_URI" \
  "$SCRIPT_DIR"

echo "==> Logging in to ${REGISTRY}"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Pushing ${IMAGE_URI}"
docker push "$IMAGE_URI"

cat <<EOF

Done.

  ImageUri: ${IMAGE_URI}

Use that as the ImageUri parameter of britive_bridge_ecs_fargate.yaml.

Tags are immutable: any later change to bridge.yaml needs a NEW tag
(IMAGE_TAG=${BRIDGE_VERSION}-r2) followed by a stack update.
EOF
