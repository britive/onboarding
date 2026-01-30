# Britive Access Broker - Azure AKS Deployment

This directory contains everything needed to deploy the Britive Access Broker on Azure Kubernetes Service (AKS).

## Overview

The Britive Access Broker enables secure, just-in-time access to your Kubernetes clusters through the Britive platform. This deployment uses Azure Container Registry (ACR) to store the container image and AKS for orchestration.

## Prerequisites

Before deploying, ensure you have:

1. **Azure CLI** installed and configured
   ```bash
   # Install Azure CLI
   # macOS
   brew install azure-cli

   # Linux
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

   # Login to Azure
   az login
   ```

2. **Docker** installed and running
   ```bash
   # Verify Docker is running
   docker info
   ```

3. **kubectl** installed and configured for your AKS cluster
   ```bash
   # Install kubectl
   az aks install-cli

   # Get credentials for your AKS cluster
   az aks get-credentials --resource-group <RESOURCE_GROUP> --name <CLUSTER_NAME>

   # Verify connection
   kubectl cluster-info
   ```

4. **AKS Cluster** running in Azure

5. **Britive Broker Pool Token** from the Britive console
   - Navigate to: System Administration > Broker Pools
   - Create a new pool or select an existing one
   - Copy the broker pool token

6. **britive-broker-1.0.0.jar** file in this directory

## Quick Start

### Option 1: Automated Deployment (Recommended)

1. Copy the broker JAR file to this directory:
   ```bash
   cp /path/to/britive-broker-1.0.0.jar .
   ```

2. Edit `deploy.sh` and set your configuration:
   ```bash
   BRITIVE_TOKEN="your-britive-token-here"
   ACR_NAME="britivebroker"           # Your ACR name
   RESOURCE_GROUP="your-rg-name"      # Your Azure resource group
   ```

3. Run the deployment script:
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

The script will:
- Validate all prerequisites
- Create ACR if it doesn't exist
- Attach ACR to your AKS cluster
- Build and push the Docker image
- Deploy the broker to AKS
- Wait for deployment completion

### Option 2: Manual Deployment

1. **Create Azure Container Registry** (if needed):
   ```bash
   az acr create --resource-group <RG_NAME> --name <ACR_NAME> --sku Basic
   ```

2. **Attach ACR to AKS**:
   ```bash
   az aks update --name <AKS_NAME> --resource-group <RG_NAME> --attach-acr <ACR_NAME>
   ```

3. **Build and push the Docker image**:
   ```bash
   # Login to ACR
   az acr login --name <ACR_NAME>

   # Build image
   docker build --platform linux/amd64 -t britive-broker:latest .

   # Tag and push
   docker tag britive-broker:latest <ACR_NAME>.azurecr.io/britive-broker:latest
   docker push <ACR_NAME>.azurecr.io/britive-broker:latest
   ```

4. **Update deployment.yaml**:
   - Replace `YOUR_ACR_NAME.azurecr.io` with your actual ACR login server
   - Replace `REPLACE_WITH_BASE64_TOKEN` with your base64-encoded token:
     ```bash
     echo -n "your-token" | base64
     ```

5. **Apply the deployment**:
   ```bash
   kubectl apply -f deployment.yaml
   ```

## Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `BRITIVE_TOKEN` | Broker pool authentication token | Yes |
| `KUBECONFIG` | Path to kubeconfig (auto-configured) | No |

### Resource Limits

| Resource | Request | Limit |
|----------|---------|-------|
| Memory | 512Mi | 1Gi |
| CPU | 250m | 500m |

### Replicas

The default deployment creates 2 replicas for high availability. Modify `spec.replicas` in `deployment.yaml` to change this.

## Files

| File | Description |
|------|-------------|
| `deploy.sh` | Automated deployment script |
| `deployment.yaml` | Kubernetes manifests (ServiceAccount, RBAC, ConfigMap, Secret, Deployment, Service) |
| `Dockerfile` | Container image definition |
| `supervisord.conf` | Process supervisor configuration |
| `README.md` | This documentation |

## Kubernetes Resources Created

1. **ServiceAccount** (`britive-broker-sa`) - Identity for the broker pods
2. **Secret** (`britive-broker-sa-token`) - Auto-generated service account token
3. **ClusterRole** (`britive-broker-role`) - RBAC permissions for the broker
4. **ClusterRoleBinding** (`britive-broker-binding`) - Binds role to service account
5. **ConfigMap** (`britive-config`) - Configuration files and scripts
6. **Secret** (`britive-secrets`) - Britive authentication token
7. **Deployment** (`britive-broker`) - The broker pods
8. **Service** (`britive-broker-service`) - Internal cluster service

## RBAC Permissions

The broker requires the following Kubernetes permissions:

| API Group | Resources | Verbs |
|-----------|-----------|-------|
| rbac.authorization.k8s.io | roles, rolebindings, clusterroles, clusterrolebindings | get, list, watch, create, update, patch, delete |
| "" (core) | serviceaccounts, namespaces | get, list, watch, create, update, patch, delete |

These permissions enable the broker to manage access control for just-in-time access.

## Monitoring & Troubleshooting

### Check Deployment Status
```bash
kubectl get pods -l app=britive-broker
kubectl get deployment britive-broker
```

### View Logs
```bash
# All broker pods
kubectl logs -l app=britive-broker -f

# Specific pod
kubectl logs <pod-name> -f

# Previous container (if crashed)
kubectl logs <pod-name> --previous
```

### Describe Pod (for troubleshooting)
```bash
kubectl describe pod -l app=britive-broker
```

### Check Events
```bash
kubectl get events --sort-by='.lastTimestamp' | grep britive
```

### Verify ACR Access
```bash
# Check if AKS can pull from ACR
az aks check-acr --name <AKS_NAME> --resource-group <RG_NAME> --acr <ACR_NAME>
```

### Common Issues

1. **ImagePullBackOff**: ACR not attached to AKS
   ```bash
   az aks update --name <AKS_NAME> --resource-group <RG_NAME> --attach-acr <ACR_NAME>
   ```

2. **CrashLoopBackOff**: Check logs for Java errors
   ```bash
   kubectl logs -l app=britive-broker --previous
   ```

3. **Pending Pods**: Check resource quotas and node capacity
   ```bash
   kubectl describe pod -l app=britive-broker
   ```

## Cleanup

To remove the deployment:

```bash
kubectl delete -f deployment.yaml

# Or delete individual resources
kubectl delete deployment britive-broker
kubectl delete service britive-broker-service
kubectl delete configmap britive-config
kubectl delete secret britive-secrets britive-broker-sa-token
kubectl delete clusterrolebinding britive-broker-binding
kubectl delete clusterrole britive-broker-role
kubectl delete serviceaccount britive-broker-sa
```

To also remove the ACR repository:
```bash
az acr repository delete --name <ACR_NAME> --repository britive-broker --yes
```

## Security Considerations

1. **Token Security**: The Britive token is stored as a Kubernetes Secret. Ensure your cluster has appropriate RBAC policies.

2. **Network Policies**: Consider implementing network policies to restrict broker communication.

3. **ACR Security**: Use Azure Private Link for ACR if your AKS cluster uses private networking.

4. **Pod Security**: The broker runs as root for kubectl access. Consider pod security policies for additional hardening.

## Support

For issues with:
- **Britive Platform**: Contact Britive support
- **AKS/Azure**: Check Azure documentation or contact Azure support
- **This deployment**: Check the troubleshooting section above
