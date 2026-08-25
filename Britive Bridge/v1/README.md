# Britive Bridge v1.x — Deployment Options

Deployment templates and installers for **Bridge v1.x**. For current releases
see [`../v2/`](../v2/).

> These templates predate the v2 datastore, encryption key and baked
> configuration requirements. They will **not** start a Bridge v2 image: it
> needs a PostgreSQL datastore and an encryption key that none of these
> templates supply.

## Options

| Option | Where it runs | TLS / external access | Persistence | Best for |
|--------|---------------|-----------------------|-------------|----------|
| [**Docker Compose**](docker-compose/) | Any Docker host / VM | Self-signed (8080) or mounted cert | Docker volume | Local trials, POCs, single-VM deployments |
| [**Linux VM (Docker)**](linux-vm-docker/) | A Linux server / VM | Self-signed (8080) or mounted cert | Docker volume | Standalone Linux host; on-prem or cloud VM, fully scripted |
| [**Windows VM (Docker)**](windows-vm-docker/) | A Windows server / VM (WSL 2) | Self-signed (8080) or mounted cert | Docker volume | Standalone Windows host (Linux container via WSL 2) |
| [**AWS ECS Fargate + NLB**](aws-ecs-fargate-nlb/) | AWS ECS Fargate | TLS passthrough via NLB:443 → container self-signed cert | EFS | Serverless AWS, minimal moving parts, no ACM cert needed |
| [**AWS ECS Fargate + ALB**](aws-ecs-fargate-alb/) | AWS ECS Fargate | ALB terminates TLS with an **ACM cert** on 443 | EFS | Production AWS with a real cert + custom domain |
| [**AWS ECS Fargate + ALB + SSH**](aws-ecs-fargate-alb-ssh/) | AWS ECS Fargate | Same as ALB option | EFS | ALB option **plus** broker SSH access to EC2 via a key in Secrets Manager |
| [**Kubernetes**](kubernetes/) | Any K8s cluster (EKS/AKS/GKE/on-prem) | Ingress (cert-manager / ALB) → backend HTTPS | PVC | Teams standardized on Kubernetes |

## Before you start

Run the [platform setup](../platform-setup/) first — it creates the broker pool
and token every deployment needs.

Need extra CLI tools for your checkout scripts? Build a
[custom image](../custom-image/) and point any option above at it.
