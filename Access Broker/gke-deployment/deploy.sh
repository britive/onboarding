#!/bin/bash
set -e

# Configuration - EDIT THIS
BRITIVE_TOKEN="your-britive-token-here" # Replace with your Britive Access Broker Pool token

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}[DEPLOY]${NC} $1"; }

print_header "Clean Britive Broker Deployment for GKE"

# Validate configuration
if [ "$BRITIVE_TOKEN" = "your-britive-token-here" ]; then
    print_error "Please update BRITIVE_TOKEN in this script"
    exit 1
fi

# Check required files
REQUIRED_FILES=("britive-broker-1.0.0.jar" "supervisord.conf")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "Missing required file: $file"
        exit 1
    fi
done

# Check GCP setup
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI not found. Please install Google Cloud SDK"
    exit 1
fi

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    print_error "No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

print_status "Using GCP project: $PROJECT_ID"

# Clean up existing resources if any
print_status "Cleaning up existing resources..."
kubectl delete deployment britive-broker --ignore-not-found=true
kubectl delete svc britive-broker-service --ignore-not-found=true
kubectl delete configmap britive-config --ignore-not-found=true
kubectl delete secret britive-secrets --ignore-not-found=true
kubectl delete sa britive-broker-sa --ignore-not-found=true
kubectl delete clusterrole britive-broker-role --ignore-not-found=true
kubectl delete clusterrolebinding britive-broker-binding --ignore-not-found=true

# Configure Docker for GCR
print_status "Configuring Docker authentication for GCR..."
gcloud auth configure-docker --quiet

# Build image for AMD64 (GKE compatible)
print_status "Building Docker image for AMD64 architecture..."
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker build --platform linux/amd64 -t britive-broker:latest .

# Verify architecture
ARCH=$(docker inspect britive-broker:latest --format='{{.Architecture}}')
if [ "$ARCH" != "amd64" ]; then
    print_error "Built image architecture is $ARCH, should be amd64 for GKE"
    exit 1
fi
print_status "✅ Image architecture: $ARCH (GKE compatible)"

# Test image locally
print_status "Testing image locally..."
if ! docker run --rm britive-broker:latest /bin/echo "Local test successful" > /dev/null; then
    print_error "Image failed local test"
    exit 1
fi
print_status "✅ Image works locally"

# Tag and push to GCR
GCR_IMAGE="gcr.io/$PROJECT_ID/britive-broker:latest"
print_status "Pushing to GCR: $GCR_IMAGE"
docker tag britive-broker:latest $GCR_IMAGE
docker push $GCR_IMAGE

# Update deployment with correct image
print_status "Updating deployment with GCR image..."
sed -i.bak "s|gcr.io/YOUR_PROJECT_ID/britive-broker:latest|$GCR_IMAGE|g" deployment.yaml

# Encode token for Kubernetes secret
print_status "Creating Kubernetes secret with Britive token..."
ENCODED_TOKEN=$(echo -n "$BRITIVE_TOKEN" | base64)
sed -i.bak "s|britive-token: \"\"|britive-token: \"$ENCODED_TOKEN\"|g" deployment.yaml

# Deploy to Kubernetes
print_status "Deploying to GKE..."
kubectl apply -f deployment.yaml

# Wait for deployment
print_status "Waiting for deployment to be ready..."
kubectl rollout status deployment/britive-broker --timeout=300s

# Show status
print_header "Deployment Complete! 🎉"
print_status "Deployment status:"
kubectl get pods,svc -l app=britive-broker

print_status "Monitor with:"
echo "  kubectl logs -f -l app=britive-broker"
echo "  kubectl get pods -l app=britive-broker -w"
echo
print_status "Image location: $GCR_IMAGE"
print_status "View in GCP Console: https://console.cloud.google.com/gcr/images/$PROJECT_ID"