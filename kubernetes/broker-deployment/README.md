# Java App on Kubernetes

This project sets up a Kubernetes deployment to run a Java `.jar` application with a mounted config file and a service account that can manage roles and rolebindings across the cluster.

## Contents

- `Dockerfile` - Builds the container with OpenJDK 21 and the Java app
- `entrypoint.sh` - Launches the Java app using the provided config
- `k8s/` - Kubernetes manifests for configmap, service account, and deployment

## Instructions

### 1. Build and Push Docker Image

Replace the placeholder jar and build the image:

```bash
docker build -t your-docker-repo/java-app:latest .
docker push your-docker-repo/java-app:latest
```

### 2. Apply Kubernetes Resources

```bash
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/serviceaccount.yaml
kubectl apply -f k8s/deployment.yaml
```

### 3. Notes

- The config file is mounted from a ConfigMap.
- The service account has cluster-wide RBAC permissions to manage roles and rolebindings.
- Deployment is set to 2 replicas for availability.