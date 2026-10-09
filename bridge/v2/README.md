# Britive Bridge v2.x — Deployment Options

Deployment templates for **Bridge v2.x**, the current release line. Every
image reference pins `britive/bridge:v2.3.1`; bump it deliberately after
reading the [release notes](https://learn.britive.com/releases/).

> Do not build against `britive/bridge:latest`. It tracks the newest release
> and moves without notice, so two builds of the "same" image can differ.

## What v2 requires

| Requirement | Why it matters |
| ----------- | -------------- |
| **PostgreSQL datastore** | Checkouts, sessions and the audit index live in the database. The process will not start without one. |
| **Encryption key** | `BRIDGE_ENCRYPTION_KEY_B64` encrypts checkout payloads at rest. It is **permanent** — rotating it after go-live makes stored payloads undecryptable. |
| **A configuration file with at least one protocol enabled** | Every protocol is off by default and the Bridge refuses to start otherwise. Environment variables are applied after the file is read and before it is validated, so they can complete a partial file — but they cannot replace it. |

Where the configuration file comes from differs per option: Docker Compose
bind-mounts [`../custom-image/bridge.yaml`](../custom-image/bridge.yaml);
ECS Fargate has no volume to mount it from, so the
[custom image builder](../custom-image/) bakes it into the image
(`--build-arg BAKE_CONFIG=true`), and a config change becomes an image change;
the Helm chart renders it from values into a ConfigMap.

## Options

| Option | Where it runs | TLS / external access | Persistence |
| ------ | ------------- | --------------------- | ----------- |
| [**AWS ECS Fargate + NLB**](aws-ecs-fargate-nlb/) | AWS ECS Fargate | NLB:443 terminates TLS with an ACM certificate; TCP listeners for native SSH, RDP, MySQL and PostgreSQL | EFS for recordings; RDS PostgreSQL from the included `rds-postgres.yaml` |
| [**Docker Compose**](docker-compose/) | Any Docker host / VM | The container's own TLS (self-signed by default); every native port published | Docker volumes for Bridge data and PostgreSQL |
| [**Kubernetes (Helm)**](kubernetes/) | Any cluster | L4 load balancer from the chart's proxy Service; TLS at the LB (ACM on an NLB) or in the pods | ReadWriteMany PVC for recordings (EFS, Azure Files, NFS); your managed PostgreSQL. Britive's official chart `oci://registry-1.docker.io/britive/bridge-chart`, with a production values file and External Secrets manifest here |

## Before you start

Run the [platform setup](../platform-setup/) first — it creates the broker pool
and token every deployment needs.

## Directory layout

```
v2/
├── aws-ecs-fargate-nlb/
│   ├── ecr-repo.yaml            # ECR repository (immutable tags)
│   ├── rds-postgres.yaml        # RDS PostgreSQL datastore, deployed once
│   ├── ecs-fargate-nlb.yaml     # ECS service, NLB, EFS, IAM, secrets
│   ├── params.example.json      # every ECS stack parameter
│   └── README.md                # prerequisites through cleanup
├── kubernetes/
│   ├── values.example.yaml      # production values for Britive's official chart
│   ├── external-secret.example.yaml
│   └── README.md
└── docker-compose/
    ├── docker-compose.yaml      # PostgreSQL + Bridge on one host
    ├── .env.example
    └── README.md
```
