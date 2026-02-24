#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${BLUE}[GCP]${NC} $1"; }

print_header "GCP Registry Setup for GKE"
echo

# Get current GCP project
if command -v gcloud &> /dev/null; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        print_error "No GCP project set. Run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    print_status "Using GCP project: $PROJECT_ID"
else
    print_error "gcloud CLI not found. Please install Google Cloud SDK"
    exit 1
fi

echo
print_status "Choose your registry option:"
echo "1) Google Container Registry (GCR) - gcr.io"
echo "2) Artifact Registry - <region>-docker.pkg.dev"
echo

read -p "Enter your choice (1-2): " choice

case $choice in
    1)
        # Google Container Registry
        REGISTRY_URL="gcr.io/$PROJECT_ID"
        IMAGE_URL="$REGISTRY_URL/britive-broker:latest"
        
        print_header "Setting up Google Container Registry"
        echo
        
        # Configure Docker for GCR
        print_status "Configuring Docker authentication for GCR..."
        gcloud auth configure-docker --quiet
        
        # Build and tag image
        print_status "Building and tagging image..."
        docker build -t britive-broker:latest .
        docker tag britive-broker:latest $IMAGE_URL
        
        # Push to GCR
        print_status "Pushing to GCR: $IMAGE_URL"
        docker push $IMAGE_URL
        
        if [ $? -eq 0 ]; then
            print_status "✅ Image pushed successfully!"
        else
            print_error "❌ Failed to push image"
            exit 1
        fi
        ;;
        
    2)
        # Artifact Registry
        print_status "Available regions for Artifact Registry:"
        echo "  us-central1, us-east1, us-west1, us-west2"
        echo "  europe-west1, europe-west4, asia-east1, etc."
        echo
        read -p "Enter region (e.g., us-central1): " region
        
        if [ -z "$region" ]; then
            print_error "Region required"
            exit 1
        fi
        
        REPO_NAME="britive-repo"
        REGISTRY_URL="$region-docker.pkg.dev/$PROJECT_ID/$REPO_NAME"
        IMAGE_URL="$REGISTRY_URL/britive-broker:latest"
        
        print_header "Setting up Artifact Registry"
        echo
        
        # Create repository if it doesn't exist
        print_status "Creating Artifact Registry repository..."
        gcloud artifacts repositories create $REPO_NAME \
            --repository-format=docker \
            --location=$region \
            --quiet 2>/dev/null || print_warning "Repository may already exist"
        
        # Configure Docker for Artifact Registry
        print_status "Configuring Docker authentication..."
        gcloud auth configure-docker $region-docker.pkg.dev --quiet
        
        # Build and tag image
        print_status "Building and tagging image..."
        docker build -t britive-broker:latest .
        docker tag britive-broker:latest $IMAGE_URL
        
        # Push to Artifact Registry
        print_status "Pushing to Artifact Registry: $IMAGE_URL"
        docker push $IMAGE_URL
        
        if [ $? -eq 0 ]; then
            print_status "✅ Image pushed successfully!"
        else
            print_error "❌ Failed to push image"
            exit 1
        fi
        ;;
        
    *)
        print_error "Invalid choice"
        exit 1
        ;;
esac

# Update deployment.yaml
print_status "Updating deployment.yaml..."
sed -i.bak "s|localhost:5055/britive-broker:latest|$IMAGE_URL|g" deployment.yaml
sed -i.bak "s|imagePullPolicy: Always|imagePullPolicy: Always|g" deployment.yaml

# Verify the change
if grep -q "$IMAGE_URL" deployment.yaml; then
    print_status "✅ Deployment updated to use: $IMAGE_URL"
else
    print_error "❌ Failed to update deployment"
    exit 1
fi

# Clean up existing deployment and redeploy
print_status "Redeploying to GKE..."
kubectl delete deployment britive-broker --ignore-not-found=true
sleep 5

# Apply deployment
kubectl apply -f deployment.yaml

# Wait for rollout
print_status "Waiting for deployment..."
kubectl rollout status deployment/britive-broker --timeout=300s

# Show status
print_status "Deployment complete!"
kubectl get pods,svc -l app=britive-broker

echo
print_header "Success! 🎉"
print_status "Image location: $IMAGE_URL"
print_status "Registry: $REGISTRY_URL"
print_status "GKE cluster can now pull the image"
echo
print_status "Monitor with:"
echo "  kubectl logs -f -l app=britive-broker"
echo "  kubectl get pods -l app=britive-broker -w"
echo
print_status "View in GCP Console:"
if [ $choice -eq 1 ]; then
    echo "  https://console.cloud.google.com/gcr/images/$PROJECT_ID"
else
    echo "  https://console.cloud.google.com/artifacts/docker/$PROJECT_ID/$region/$REPO_NAME"
fi