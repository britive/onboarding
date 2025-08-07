# Britive Broker Kubernetes Deployment

## Files

- `deployment.yaml` - Complete Kubernetes deployment
- `deploy.sh` - One-script deployment
- `Dockerfile` - Your Docker image

## Required Files

Make sure you have these in your directory:

- `britive-broker-1.0.0.jar`
- `broker-config.yml`
- `token-generator.sh`
- `start-broker.sh`
- `supervisord.conf`
- `create-resources.py`

## Deploy

1. **Edit deploy.sh** and set your token:

   ```bash
   BRITIVE_TOKEN="your-actual-token"
   ```

2. **Run deployment**:

   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

That's it! The script will:

- Clean up any existing deployment
- Start fresh local registry on port 5055
- Build and push your image
- Deploy to Kubernetes
- Show status

## Monitor

```bash
# Check pods
kubectl get pods -l app=britive-broker

# View logs
kubectl logs -f -l app=britive-broker

# Port forward
kubectl port-forward svc/britive-broker-service 8080:8080
```

## Clean Up

```bash
# Remove everything
kubectl delete -f deployment.yaml
docker stop local-registry
docker rm local-registry
```

## What It Creates

- **2 pod replicas** with JDK 21
- **Local registry** on port 5055
- **RBAC permissions** for cluster role management
- **ConfigMap** with your scripts and config
- **Secret** for Britive token
- **Service** exposing ports 8080 and 22
