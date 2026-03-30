#!/bin/bash

# Britive Access Broker - Azure AKS Deployment Script
# This script automates the deployment of Britive Access Broker to Azure Kubernetes Service
#
# Prerequisites:
# 1. Azure CLI installed and configured (az login)
# 2. Docker installed and running
# 3. kubectl installed and configured for your AKS cluster
# 4. AKS cluster running
# 5. britive-broker-<VERSION>.jar in current directory
#
# Usage:
# 1. Set BRITIVE_TOKEN below with your broker pool token from Britive console
# 2. Run: ./deploy.sh [--broker-version <version>]
#
# Options:
#   --broker-version, -v    Broker JAR version to use (default: 2.0.0)
#                           Example: ./deploy.sh --broker-version 1.5.0

set -e

#==============================================================================
# CONFIGURATION - MODIFY THESE VALUES
#==============================================================================

# Broker version (can also be overridden via --broker-version flag)
BROKER_VERSION="2.0.0"

# Your Britive broker pool token (required)
# Get this from: Britive Console > System Administration > Broker Pools > Create/Select Pool > Token
BRITIVE_TOKEN="your-britive-token-here"

# Azure Container Registry name (will be created if it doesn't exist)
ACR_NAME="britivebroker"

# Resource group for ACR (should match your AKS resource group or be accessible)
RESOURCE_GROUP=""

# Image name
IMAGE_NAME="britive-broker"
IMAGE_TAG="latest"

#==============================================================================
# DO NOT MODIFY BELOW THIS LINE
#==============================================================================

# Parse command-line arguments (override CONFIGURATION defaults)
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --broker-version|-v)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo "ERROR: --broker-version requires a value (e.g. --broker-version 2.0.0)"
                exit 1
            fi
            BROKER_VERSION="$2"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./deploy.sh [--broker-version <version>]"
            exit 1
            ;;
    esac
    shift
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if token is configured
if [ "$BRITIVE_TOKEN" == "your-britive-token-here" ]; then
    log_error "Please set BRITIVE_TOKEN in this script before running"
    log_info "Get your token from: Britive Console > System Administration > Broker Pools"
    exit 1
fi

# Check for required files
log_info "Checking required files..."
log_info "Using broker version: $BROKER_VERSION"
if [ ! -f "britive-broker-${BROKER_VERSION}.jar" ]; then
    log_error "britive-broker-${BROKER_VERSION}.jar not found in current directory"
    log_info "Please copy the broker JAR file to this directory"
    exit 1
fi

if [ ! -f "supervisord.conf" ]; then
    log_error "supervisord.conf not found in current directory"
    exit 1
fi

log_success "Required files found"

# Check Azure CLI
log_info "Checking Azure CLI..."
if ! command -v az &> /dev/null; then
    log_error "Azure CLI not found. Please install it:"
    log_info "  macOS: brew install azure-cli"
    log_info "  Linux: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    log_info "  Windows: Download from https://aka.ms/installazurecliwindows"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    log_error "Not logged in to Azure. Please run: az login"
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
log_success "Azure CLI configured - Subscription: $SUBSCRIPTION_NAME"

# Check Docker
log_info "Checking Docker..."
if ! command -v docker &> /dev/null; then
    log_error "Docker not found. Please install Docker Desktop"
    exit 1
fi

if ! docker info &> /dev/null; then
    log_error "Docker daemon not running. Please start Docker Desktop"
    exit 1
fi
log_success "Docker is running"

# Check kubectl
log_info "Checking kubectl..."
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl not found. Please install kubectl"
    exit 1
fi

# Verify kubectl context is AKS
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
log_info "Current kubectl context: $CURRENT_CONTEXT"

if [[ ! "$CURRENT_CONTEXT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    log_warning "Could not determine kubectl context"
fi

# Try to get cluster info
if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster. Please configure kubectl for your AKS cluster:"
    log_info "  az aks get-credentials --resource-group <RG_NAME> --name <CLUSTER_NAME>"
    exit 1
fi
log_success "kubectl connected to cluster"

# Get or set resource group
if [ -z "$RESOURCE_GROUP" ]; then
    log_info "Attempting to detect resource group from AKS cluster..."
    # Try to get resource group from current context
    if [[ "$CURRENT_CONTEXT" =~ ^([a-zA-Z0-9_-]+)$ ]]; then
        # List AKS clusters to find matching one
        AKS_INFO=$(az aks list --query "[?name=='$CURRENT_CONTEXT'] | [0]" -o json 2>/dev/null || echo "{}")
        if [ "$AKS_INFO" != "{}" ] && [ "$AKS_INFO" != "null" ] && [ -n "$AKS_INFO" ]; then
            RESOURCE_GROUP=$(echo "$AKS_INFO" | jq -r '.resourceGroup')
        fi
    fi

    if [ -z "$RESOURCE_GROUP" ] || [ "$RESOURCE_GROUP" == "null" ]; then
        log_warning "Could not auto-detect resource group"
        echo ""
        echo "Available resource groups:"
        az group list --query "[].name" -o tsv
        echo ""
        read -p "Enter the resource group name for ACR: " RESOURCE_GROUP
    fi
fi

log_info "Using resource group: $RESOURCE_GROUP"

# Check/Create ACR
log_info "Checking Azure Container Registry..."
ACR_EXISTS=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query name -o tsv 2>/dev/null || echo "")

if [ -z "$ACR_EXISTS" ]; then
    log_info "Creating Azure Container Registry: $ACR_NAME"
    az acr create --resource-group "$RESOURCE_GROUP" --name "$ACR_NAME" --sku Basic
    log_success "ACR created: $ACR_NAME"
else
    log_success "ACR exists: $ACR_NAME"
fi

# Get ACR login server
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query loginServer -o tsv)
log_info "ACR Login Server: $ACR_LOGIN_SERVER"

# Attach ACR to AKS (if not already attached)
log_info "Ensuring ACR is attached to AKS cluster..."
AKS_NAME=$(kubectl config current-context)
az aks update --name "$AKS_NAME" --resource-group "$RESOURCE_GROUP" --attach-acr "$ACR_NAME" 2>/dev/null || \
    log_warning "Could not attach ACR to AKS. You may need to do this manually or ensure proper permissions."

# Clean up existing resources
log_info "Cleaning up existing Kubernetes resources..."
kubectl delete deployment britive-broker --ignore-not-found=true
kubectl delete service britive-broker-service --ignore-not-found=true
kubectl delete configmap britive-config --ignore-not-found=true
kubectl delete secret britive-secrets --ignore-not-found=true
kubectl delete secret britive-broker-sa-token --ignore-not-found=true
kubectl delete clusterrolebinding britive-broker-binding --ignore-not-found=true
kubectl delete clusterrole britive-broker-role --ignore-not-found=true
kubectl delete serviceaccount britive-broker-sa --ignore-not-found=true
log_success "Cleanup complete"

# Authenticate Docker with ACR
log_info "Authenticating Docker with ACR..."
az acr login --name "$ACR_NAME"
log_success "Docker authenticated with ACR"

# Build Docker image
log_info "Building Docker image (AMD64 architecture, broker version: $BROKER_VERSION)..."
docker build --platform linux/amd64 --build-arg BROKER_VERSION="$BROKER_VERSION" -t "$IMAGE_NAME:$IMAGE_TAG" .

# Verify architecture
ARCH=$(docker inspect "$IMAGE_NAME:$IMAGE_TAG" --format '{{.Architecture}}')
log_info "Image architecture: $ARCH"

if [ "$ARCH" != "amd64" ]; then
    log_error "Image architecture is not amd64. AKS requires amd64 images."
    exit 1
fi
log_success "Image built successfully"

# Test image locally
log_info "Testing image locally..."
CONTAINER_ID=$(docker run -d --name test-broker -e BRITIVE_TOKEN="test" "$IMAGE_NAME:$IMAGE_TAG")
sleep 5

if docker ps | grep -q test-broker; then
    log_success "Container started successfully"
    docker logs test-broker 2>&1 | head -20 || true
else
    log_error "Container failed to start"
    docker logs test-broker 2>&1 || true
fi

docker stop test-broker 2>/dev/null || true
docker rm test-broker 2>/dev/null || true

# Tag and push image
FULL_IMAGE_NAME="$ACR_LOGIN_SERVER/$IMAGE_NAME:$IMAGE_TAG"
log_info "Tagging image as: $FULL_IMAGE_NAME"
docker tag "$IMAGE_NAME:$IMAGE_TAG" "$FULL_IMAGE_NAME"

log_info "Pushing image to ACR..."
docker push "$FULL_IMAGE_NAME"
log_success "Image pushed to ACR"

# Update deployment.yaml with correct values
log_info "Updating deployment.yaml..."
ENCODED_TOKEN=$(echo -n "$BRITIVE_TOKEN" | base64)

# Create a temporary deployment file
cp deployment.yaml deployment-temp.yaml

# Update image URL
sed -i.bak "s|YOUR_ACR_NAME.azurecr.io/britive-broker:latest|$FULL_IMAGE_NAME|g" deployment-temp.yaml

# Update token
sed -i.bak "s|REPLACE_WITH_BASE64_TOKEN|$ENCODED_TOKEN|g" deployment-temp.yaml

# Clean up backup files
rm -f deployment-temp.yaml.bak

log_success "Deployment manifest updated"

# Apply deployment
log_info "Applying Kubernetes deployment..."
kubectl apply -f deployment-temp.yaml

# Clean up temp file
rm -f deployment-temp.yaml

# Wait for rollout
log_info "Waiting for deployment rollout..."
kubectl rollout status deployment/britive-broker --timeout=300s

log_success "Deployment complete!"

# Show status
echo ""
echo "=============================================="
echo "         DEPLOYMENT STATUS"
echo "=============================================="
echo ""
kubectl get pods -l app=britive-broker
echo ""
kubectl get deployment britive-broker
echo ""
kubectl get service britive-broker-service
echo ""
echo "=============================================="
echo ""
log_info "To view logs: kubectl logs -l app=britive-broker -f"
log_info "To check status: kubectl get pods -l app=britive-broker"
log_info "To describe pod: kubectl describe pod -l app=britive-broker"
echo ""
log_success "Britive Access Broker deployed to AKS!"
