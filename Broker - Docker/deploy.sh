#!/bin/bash
set -e

# Configuration - EDIT THESE
BRITIVE_TOKEN="pBkjlzFKIgQuzpZqWnZBfp6RTPNsdaLycPXkU6fwwmA=" 

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validate token is set
if [ "$BRITIVE_TOKEN" = "your-britive-token-here" ]; then
    print_error "Please update BRITIVE_TOKEN in this script"
    exit 1
fi

print_status "Starting fresh Britive Broker deployment..."

# Clean up any existing resources
print_status "Cleaning up existing resources..."
kubectl delete deployment britive-broker --ignore-not-found=true
kubectl delete svc britive-broker-service --ignore-not-found=true
kubectl delete configmap britive-config --ignore-not-found=true
kubectl delete secret britive-secrets --ignore-not-found=true
kubectl delete sa britive-broker-sa --ignore-not-found=true
kubectl delete clusterrole britive-broker-role --ignore-not-found=true
kubectl delete clusterrolebinding britive-broker-binding --ignore-not-found=true

# Clean up registry
print_status "Setting up fresh registry..."
docker stop local-registry 2>/dev/null || true
docker rm local-registry 2>/dev/null || true

# Start registry
docker run -d --name local-registry --restart=always -p 5055:5000 registry:2
sleep 5

# Test registry
if ! curl -s http://localhost:5055/v2/_catalog > /dev/null; then
    print_error "Registry failed to start"
    exit 1
fi

# Build and push image
print_status "Building and pushing image..."
docker build -t britive-broker:latest .
docker tag britive-broker:latest localhost:5055/britive-broker:latest
docker push localhost:5055/britive-broker:latest

# Verify image in registry
if ! curl -s http://localhost:5055/v2/britive-broker/tags/list | grep -q "latest"; then
    print_error "Image not found in registry"
    exit 1
fi

# Encode token for secret
print_status "Creating Kubernetes secret..."
ENCODED_TOKEN=$(echo -n "$BRITIVE_TOKEN" | base64)
sed -i.bak "s|britive-token: \"\"|britive-token: \"$ENCODED_TOKEN\"|g" deployment.yaml

# Deploy to Kubernetes
print_status "Deploying to Kubernetes..."
kubectl apply -f deployment.yaml

# Wait for deployment
print_status "Waiting for deployment..."
kubectl rollout status deployment/britive-broker --timeout=300s

# Show status
print_status "Deployment complete!"
kubectl get pods,svc -l app=britive-broker

print_status "Monitor with:"
echo "  kubectl logs -f -l app=britive-broker"
echo "  kubectl get pods -l app=britive-broker -w"
echo "  kubectl port-forward svc/britive-broker-service 8080:8080"