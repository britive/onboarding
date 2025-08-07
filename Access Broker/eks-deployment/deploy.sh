#!/bin/bash
set -e

# Configuration - EDIT THESE
BRITIVE_TOKEN="your-britive-token-here" # Replace with your Britive Access Broker Pool token
AWS_REGION="us-west-2"  # Replace with your AWS region
ECR_REPO_NAME="britive-broker"

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

print_header "Britive Broker Deployment for AWS EKS"

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

# Check AWS setup
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install AWS CLI v2"
    exit 1
fi

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    print_error "Cannot get AWS account ID. Please run: aws configure"
    exit 1
fi

print_status "Using AWS account: $AWS_ACCOUNT_ID"
print_status "Using AWS region: $AWS_REGION"

# Check kubectl context for EKS
KUBE_CONTEXT=$(kubectl config current-context)
if [[ ! $KUBE_CONTEXT == *"eks"* ]]; then
    print_warning "Current kubectl context doesn't appear to be EKS: $KUBE_CONTEXT"
    print_warning "Make sure you're connected to your EKS cluster"
fi

# Clean up existing resources
print_status "Cleaning up existing resources..."
kubectl delete deployment britive-broker --ignore-not-found=true
kubectl delete svc britive-broker-service --ignore-not-found=true
kubectl delete configmap britive-config --ignore-not-found=true
kubectl delete secret britive-secrets --ignore-not-found=true
kubectl delete sa britive-broker-sa --ignore-not-found=true
kubectl delete clusterrole britive-broker-role --ignore-not-found=true
kubectl delete clusterrolebinding britive-broker-binding --ignore-not-found=true

# Create ECR repository if it doesn't exist
print_status "Creating ECR repository if needed..."
aws ecr describe-repositories --repository-names $ECR_REPO_NAME --region $AWS_REGION >/dev/null 2>&1 || {
    print_status "Creating ECR repository: $ECR_REPO_NAME"
    aws ecr create-repository --repository-name $ECR_REPO_NAME --region $AWS_REGION
}

# Configure Docker for ECR
print_status "Configuring Docker authentication for ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build image for AMD64 (EKS compatible)
print_status "Building Docker image for AMD64 architecture..."
DOCKER_DEFAULT_PLATFORM=linux/amd64 docker build --platform linux/amd64 -t britive-broker:latest .

# Verify architecture
ARCH=$(docker inspect britive-broker:latest --format='{{.Architecture}}')
if [ "$ARCH" != "amd64" ]; then
    print_error "Built image architecture is $ARCH, should be amd64 for EKS"
    exit 1
fi
print_status "✅ Image architecture: $ARCH (EKS compatible)"

# Test image locally
print_status "Testing image locally..."
if ! docker run --rm britive-broker:latest /bin/echo "Local test successful" > /dev/null; then
    print_error "Image failed local test"
    exit 1
fi
print_status "✅ Image works locally"

# Tag and push to ECR
ECR_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO_NAME:latest"
print_status "Pushing to ECR: $ECR_IMAGE"
docker tag britive-broker:latest $ECR_IMAGE
docker push $ECR_IMAGE

# Update deployment with correct image - FIXED TOKEN REPLACEMENT
print_status "Updating deployment with ECR image..."

# Fix 1: Ensure no line wrapping in base64 output
if base64 --help 2>&1 | grep -q "\-w"; then
    # Linux base64 with -w flag
    ENCODED_TOKEN=$(echo -n "$BRITIVE_TOKEN" | base64 -w 0)
else
    # macOS base64 without -w flag - use tr to remove newlines
    ENCODED_TOKEN=$(echo -n "$BRITIVE_TOKEN" | base64 | tr -d '\n')
fi

# Fix 2: Use line-by-line replacement to avoid sed issues
cp deployment.yaml deployment.yaml.bak

# Update image and token using safe line-by-line approach
while IFS= read -r line; do
    if [[ $line == *'YOUR_AWS_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com/britive-broker:latest'* ]]; then
        echo "$line" | sed "s|YOUR_AWS_ACCOUNT_ID|$AWS_ACCOUNT_ID|g; s|YOUR_REGION|$AWS_REGION|g"
    elif [[ $line == *'britive-token: ""'* ]]; then
        echo "  britive-token: \"$ENCODED_TOKEN\""
    else
        echo "$line"
    fi
done < deployment.yaml.bak > deployment.yaml

print_status "✅ Deployment updated with ECR image and encoded token"

# Deploy to Kubernetes
print_status "Deploying to EKS..."
kubectl apply -f deployment.yaml

# Wait for deployment
print_status "Waiting for deployment to be ready..."
kubectl rollout status deployment/britive-broker --timeout=300s

# Show status
print_header "EKS Deployment Complete! 🎉"
print_status "Deployment status:"
kubectl get pods,svc -l app=britive-broker

print_status "Monitor with:"
echo "  kubectl logs -f -l app=britive-broker"
echo "  kubectl get pods -l app=britive-broker -w"
echo
print_status "Access Java logs:"
echo "  kubectl exec <pod-name> -- tail -f /var/log/britive-broker.log"
echo
print_status "Access via SSH:"
echo "  kubectl port-forward svc/britive-broker-service 2222:22"
echo "  ssh root@localhost -p 2222  # password: root"
echo
print_status "Image location: $ECR_IMAGE"
print_status "View in AWS Console: https://$AWS_REGION.console.aws.amazon.com/ecr/repositories/private/$AWS_ACCOUNT_ID/$ECR_REPO_NAME"