#!/usr/bin/env bash
#
# build-and-push.sh — build the Britive Access Broker image and push it to a
# container registry. Multi-arch by default (linux/amd64 + linux/arm64) so the
# same tag runs on Fargate ARM64, Graviton nodes and x86 nodes.
#
# Usage:
#   REGISTRY=<acct>.dkr.ecr.us-west-2.amazonaws.com ./build-and-push.sh    # Amazon ECR
#   REGISTRY=myregistry.azurecr.io ./build-and-push.sh                      # Azure ACR
#   REGISTRY=us-docker.pkg.dev/my-project/britive ./build-and-push.sh       # Google Artifact Registry
#   REGISTRY=docker.io/yourorg ./build-and-push.sh                          # Docker Hub
#
# Env overrides:
#   REGISTRY        (required) registry/namespace, no trailing slash
#   IMAGE_NAME      repository name                  (default: britive-broker)
#   BROKER_VERSION  tarball version next to the Dockerfile (default: 3.0.2)
#   TAG             image tag                        (default: <BROKER_VERSION>-r1)
#   PLATFORMS       buildx platforms                 (default: linux/amd64,linux/arm64)
#   WITH_AWS_CLI, WITH_KUBECTL, WITH_PYWINRM, WITH_DB_CLIENTS  (default: false)
#
# Log in to the registry first (aws ecr get-login-password | docker login …,
# az acr login, gcloud auth configure-docker, docker login). ECR repositories
# are created on demand with immutable tags and scan-on-push.

set -euo pipefail
cd "$(dirname "$0")"

REGISTRY="${REGISTRY:?Set REGISTRY, e.g. <acct>.dkr.ecr.<region>.amazonaws.com or docker.io/yourorg}"
IMAGE_NAME="${IMAGE_NAME:-britive-broker}"
BROKER_VERSION="${BROKER_VERSION:-3.0.2}"
TAG="${TAG:-${BROKER_VERSION}-r1}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

if [ "$TAG" = "latest" ]; then
  echo "ERROR: TAG=latest is not allowed; use an immutable tag such as ${BROKER_VERSION}-r1" >&2
  exit 1
fi

for p in ${PLATFORMS//,/ }; do
  arch="${p#linux/}"
  f="britive-broker-${BROKER_VERSION}-linux-${arch}.tar.gz"
  [ -f "$f" ] || { echo "ERROR: $f not found. Download it from the Britive console (System Administration > Brokers and Broker Pools > Download Brokers) and place it here." >&2; exit 1; }
done

FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "==> Building ${FULL_IMAGE}"
echo "    broker:    ${BROKER_VERSION}"
echo "    platforms: ${PLATFORMS}"
echo "    tools:     aws-cli=${WITH_AWS_CLI:-false} kubectl=${WITH_KUBECTL:-false} pywinrm=${WITH_PYWINRM:-false} db-clients=${WITH_DB_CLIENTS:-false}"

if echo "$REGISTRY" | grep -q 'dkr.ecr'; then
  REGION=$(echo "$REGISTRY" | sed -E 's/.*\.ecr\.([^.]+)\.amazonaws\.com/\1/')
  echo "==> ECR detected (region ${REGION}). Ensuring repository + login..."
  aws ecr describe-repositories --repository-names "$IMAGE_NAME" --region "$REGION" >/dev/null 2>&1 \
    || aws ecr create-repository \
         --repository-name "$IMAGE_NAME" \
         --region "$REGION" \
         --image-tag-mutability IMMUTABLE \
         --image-scanning-configuration scanOnPush=true >/dev/null
  aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "${REGISTRY%%/*}"
fi

docker buildx inspect broker-builder >/dev/null 2>&1 || docker buildx create --name broker-builder --use
docker buildx use broker-builder

docker buildx build \
  --platform "$PLATFORMS" \
  --build-arg "BROKER_VERSION=${BROKER_VERSION}" \
  --build-arg "WITH_AWS_CLI=${WITH_AWS_CLI:-false}" \
  --build-arg "WITH_KUBECTL=${WITH_KUBECTL:-false}" \
  --build-arg "WITH_PYWINRM=${WITH_PYWINRM:-false}" \
  --build-arg "WITH_DB_CLIENTS=${WITH_DB_CLIENTS:-false}" \
  -t "$FULL_IMAGE" \
  --push \
  .

echo "==> Pushed ${FULL_IMAGE}"
echo "    ECS:  ImageUri=${FULL_IMAGE}"
echo "    Helm: --set image.repository=${REGISTRY}/${IMAGE_NAME} --set image.tag=${TAG}"
