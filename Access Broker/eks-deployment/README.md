# Britive Broker AWS EKS Deployment

Same deployment as GKE version, adapted for AWS EKS with ECR.

## Files

- `deployment.yaml` - Complete Kubernetes deployment for EKS
- `deploy.sh` - One-script deployment to EKS with ECR
- `Dockerfile` - The access broker Docker image

## Prerequisites

### AWS Setup

```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Configure AWS credentials
aws configure
```

### EKS Cluster Setup

```bash
# Update kubectl context for your EKS cluster
aws eks update-kubeconfig --region YOUR_REGION --name YOUR_CLUSTER_NAME

# Verify connection
kubectl get nodes
```

## Required Files

Make sure you have these in your directory:

- `britive-broker-1.0.0.jar`
- `supervisord.conf`

## Deploy

### 1. Configure the Script

Edit `deploy.sh` and set:

```bash
BRITIVE_TOKEN="your-actual-token"  # Your Britive Access Broker Pool token
AWS_REGION="us-west-2"            # Your AWS region
ECR_REPO_NAME="britive-broker"    # ECR repository name
```

### 2. Configure the Deployment

Edit `deployment.yaml` and set your Britive tenant subdomain:

```yaml
data:
  broker-config.yml: |
    config:
      bootstrap:
        tenant_subdomain: YOUR_TENANT_HERE  # Replace with your Britive tenant
        authentication_token: "Broker Pool Token"
```

### 3. Run Deployment

```bash
chmod +x deploy.sh
./deploy.sh
```

## What the Script Does

1. ✅ **Validates** AWS CLI and EKS connection
2. ✅ **Creates ECR repository** (if needed)
3. ✅ **Builds AMD64 image** (EKS compatible)
4. ✅ **Pushes to ECR** with automatic authentication
5. ✅ **Updates deployment** with ECR image URL and encoded token
6. ✅ **Deploys to EKS** with kubectl support

## What Gets Deployed

- **2 pod replicas** with JDK 21
- **ECR private registry** integration
- **RBAC permissions** for cluster role management
- **kubectl support** in pods with auto-generated kubeconfig
- **ConfigMap** with scripts and config
- **Secret** for Britive token
- **SSH access** only (port 22)
- **Java logs** written to `/var/log/britive-broker.log`

## Monitor

```bash
# Check pods
kubectl get pods -l app=britive-broker

# View container logs
kubectl logs -f -l app=britive-broker

# View Java application logs
kubectl exec <pod-name> -- tail -f /var/log/britive-broker.log

# Watch pod status
kubectl get pods -l app=britive-broker -w
```

## Access

### kubectl in Pods

The pods have kubectl pre-configured with the service account permissions:

  ```bash
  kubectl exec -it <pod-name> -- kubectl get nodes
  kubectl exec -it <pod-name> -- kubectl auth can-i create roles
  ```

## AWS Resources Created

- **ECR Repository**: `britive-broker` in your specified region
- **Container Image**: `ACCOUNT.dkr.ecr.REGION.amazonaws.com/britive-broker:latest`

## Cleanup

```bash
# Remove Kubernetes resources
kubectl delete -f deployment.yaml

# Remove ECR repository (optional)
aws ecr delete-repository --repository-name britive-broker --region $AWS_REGION --force
```

## Differences from GKE Version

### What's the Same

- ✅ All Kubernetes manifests (ServiceAccount, RBAC, ConfigMap, etc.)
- ✅ kubectl support in pods
- ✅ Java logging to `/var/log/britive-broker.log`
- ✅ Architecture compatibility (AMD64)

### What's Different

- 🔄 **Registry**: ECR instead of GCR
- 🔄 **Authentication**: AWS CLI
- 🔄 **Image URLs**: `ACCOUNT.dkr.ecr.REGION.amazonaws.com/` format
- 🔄 **Cluster**: EKS

## Troubleshooting

### ECR Authentication Issues

  ```bash
  # Re-authenticate with ECR
  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
  ```

### EKS Connection Issues

  ```bash
  # Update kubeconfig
  aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

  # Verify connection
  kubectl get nodes
  ```

### Image Pull Issues

  ```bash
  # Check if image exists in ECR
  aws ecr describe-images --repository-name britive-broker --region $AWS_REGION

  # Check EKS node permissions to pull from ECR (should be automatic)
  kubectl describe pod <pod-name>
  ```
  