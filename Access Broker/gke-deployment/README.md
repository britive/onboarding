# Britive Broker Kubernetes Deployment

## Files

- `deployment.yaml` - Complete Kubernetes deployment
- `deploy.sh` - One-script deployment
- `Dockerfile` - The access broker Docker image

## Required Files

Make sure you have these in your directory:

- `britive-broker-1.0.0.jar`
- `supervisord.conf`

## Deploy

1. **Edit deploy.sh** and set your broker pool token:

   ```bash
   BRITIVE_TOKEN="your-actual-token"
   ```

2. **Edit deployment.yaml** and set your Britive tenant subdomain and broker pool token.

   You will find this broker-config yaml settings under ConfigMap

   ```yaml
   data:
   broker-config.yml: |
      config:
         bootstrap:
            tenant_subdomain: <YOUR_TENANT_SUBDOMAIN_HERE> # Replace with your Britive tenant subdomain
            authentication_token: "<YOUR_TOKEN_HERE>" # Replace with your Britive Access Broker Pool token
   ```

3. **Login to gcloud cli** as an administrator and set project.

   ```bash
   gcloud auth login

   gcloud config set project <PROJECT_NAME>
   ```

4. **Run deployment**:

   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

That's it! The script will:

- Clean up any existing deployment
- Build and push your image to GCP registry
- Deploy to Kubernetes as a deployment
- Setup kubeconfig for the broker to use for checkout and check-ins
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
```

## What It Creates

- **2 pod replicas** with JDK 21
- **Local registry** on port 5055
- **RBAC permissions** for cluster role management
- **ConfigMap** with your scripts and config
- **Secret** for Britive token
- **Service** exposing ports 8080 and 22
