# Britive Access Broker - Deployment Options

The Britive Access Broker is a lightweight Java service that runs inside your infrastructure and enables
the Britive platform to manage just-in-time access to your Kubernetes clusters and other resources. The
broker establishes an outbound connection to Britive — no inbound firewall rules or public endpoints
are required.

## How It Works

```
  Your Infrastructure                    Britive Platform
  ─────────────────                      ────────────────
  ┌─────────────────────┐   outbound     ┌──────────────────┐
  │  Access Broker      │ ────HTTPS───▶  │  Britive SaaS    │
  │  (this repo)        │                │  (your-tenant    │
  │                     │                │  .britive-app    │
  │  Manages:           │                │  .com)           │
  │  • Kubernetes RBAC  │                └──────────────────┘
  │  • Role bindings    │
  │  • Service accounts │
  └─────────────────────┘
```

The broker reads its configuration from `broker-config.yml` at startup:

```yaml
config:
  bootstrap:
    tenant_subdomain: mycompany          # your Britive tenant
    authentication_token: "<token>"      # broker pool token from Britive console
```

---

## Prerequisites (All Deployment Options)

Before deploying, you need two values from the Britive console:

| What | Where to Find It |
|------|-----------------|
| **Tenant subdomain** | The part before `.britive-app.com` in your Britive URL (e.g. `mycompany`). Find it under System Administration > Settings. |
| **Broker pool token** | System Administration > Broker Pools > Create or select a pool > copy the token. |

You also need the **`britive-broker-2.0.0.jar`** file placed in the deployment directory before running any deployment script.

---

## Deployment Options

| Option | Platform | Kubernetes Required | Secret Storage | Best For |
|--------|----------|-------------------|----------------|----------|
| [ECS Fargate](#ecs-fargate-aws-recommended) | AWS | No | AWS Secrets Manager | AWS-native, serverless |
| [EKS](#eks-aws-kubernetes) | AWS | Yes (EKS) | Kubernetes Secrets | Existing EKS clusters |
| [AKS](#aks-azure-kubernetes) | Azure | Yes (AKS) | Kubernetes Secrets | Existing AKS clusters |
| [GKE](#gke-google-kubernetes) | Google Cloud | Yes (GKE) | Kubernetes Secrets | Existing GKE clusters |

---

### ECS Fargate (AWS) — Recommended

**Directory:** [`ecs-fargate-deployment/`](ecs-fargate-deployment/)

Runs the broker as a serverless container on AWS ECS Fargate. No Kubernetes cluster needed.
Secrets are stored in AWS Secrets Manager and injected into the task at runtime.

**Additional prerequisites:** AWS CLI, Docker, jq

**Highlights:**
- Fully automated single-script deployment (`deploy.sh`)
- Secrets managed via `secrets.json` → AWS Secrets Manager
- `manage-secrets.sh` CLI for day-2 secret operations (add, rotate, sync)
- Auto-generates `broker-config.yml` at container startup from secrets
- CloudWatch logging, health checks, and auto-restart included

**Quick start:**
```bash
cd ecs-fargate-deployment
# 1. Place britive-broker-2.0.0.jar here
# 2. Edit secrets.json — set BRITIVE_TENANT and BRITIVE_TOKEN
chmod +x deploy.sh manage-secrets.sh
./deploy.sh
```

See [`ecs-fargate-deployment/README.md`](ecs-fargate-deployment/README.md) for full documentation.

---

### EKS (AWS Kubernetes)

**Directory:** [`eks-deployment/`](eks-deployment/)

Deploys the broker as a Kubernetes Deployment on an existing AWS EKS cluster.
Uses ECR for the container image. Configuration is provided via a Kubernetes ConfigMap.

**Additional prerequisites:** AWS CLI, Docker, kubectl (configured for your EKS cluster)

**Quick start:**
```bash
cd eks-deployment
# 1. Place britive-broker-2.0.0.jar here
# 2. Edit deploy.sh — set BRITIVE_TOKEN and AWS_REGION
# 3. Edit deployment.yaml — set tenant_subdomain and authentication_token in the ConfigMap
chmod +x deploy.sh
./deploy.sh
```

See [`eks-deployment/README.md`](eks-deployment/README.md) for full documentation.

---

### AKS (Azure Kubernetes)

**Directory:** [`aks-deployment/`](aks-deployment/)

Deploys the broker as a Kubernetes Deployment on an existing Azure AKS cluster.
Uses Azure Container Registry (ACR) for the container image.

**Additional prerequisites:** Azure CLI (`az`), Docker, kubectl (configured for your AKS cluster)

**Quick start:**
```bash
cd aks-deployment
# 1. Place britive-broker-2.0.0.jar here
# 2. Edit deploy.sh — set BRITIVE_TOKEN, ACR_NAME, RESOURCE_GROUP
# 3. Edit deployment.yaml — set tenant_subdomain and authentication_token in the ConfigMap
chmod +x deploy.sh
./deploy.sh
```

See [`aks-deployment/README.md`](aks-deployment/README.md) for full documentation.

---

### GKE (Google Kubernetes)

**Directory:** [`gke-deployment/`](gke-deployment/)

Deploys the broker as a Kubernetes Deployment on an existing Google GKE cluster.
Uses Google Container Registry for the container image.

**Additional prerequisites:** gcloud CLI, Docker, kubectl (configured for your GKE cluster)

**Quick start:**
```bash
cd gke-deployment
# 1. Place britive-broker-2.0.0.jar here
# 2. Edit deploy.sh — set BRITIVE_TOKEN
# 3. Edit deployment.yaml — set tenant_subdomain and authentication_token in the ConfigMap
chmod +x deploy.sh
./deploy.sh
```

See [`gke-deployment/README.md`](gke-deployment/README.md) for full documentation.

---

## Choosing a Deployment Option

```
Do you already have a Kubernetes cluster?
│
├─ No  ──▶  Use ECS Fargate (serverless, no cluster to manage)
│
└─ Yes
   │
   ├─ AWS EKS    ──▶  Use EKS deployment
   ├─ Azure AKS  ──▶  Use AKS deployment
   └─ Google GKE ──▶  Use GKE deployment
```

Use **ECS Fargate** if:
- You are deploying to AWS and don't want to manage a Kubernetes cluster
- You want secrets managed in AWS Secrets Manager with audit logging
- You want a fully serverless, auto-scaling setup

Use a **Kubernetes deployment** (EKS / AKS / GKE) if:
- You already have a Kubernetes cluster in that cloud
- You want the broker to run alongside your workloads in the same cluster
- You prefer Kubernetes-native secret and config management

---

## Common Architecture Notes

All deployment options share the same broker container image and startup sequence:

1. Container starts under `supervisord` (auto-restarts on crash)
2. `start-broker.sh` runs: sets up secrets directory, configures kubectl if needed, generates `broker-config.yml`
3. Java broker starts and connects outbound to `<tenant_subdomain>.britive-app.com` over HTTPS (port 443)
4. Broker registers with the Britive platform using the broker pool token
5. Britive can now orchestrate just-in-time access via the broker

**Network requirement:** Outbound HTTPS (port 443) to `*.britive-app.com`. No inbound rules needed.
