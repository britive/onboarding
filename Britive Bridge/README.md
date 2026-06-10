# Britive Bridge — Deployment Options

> **Note:** This directory targets **Britive Bridge v1.x**. The deployment
> scripts, templates, and examples here are in **BETA** — validate them in a
> non-production environment first, and expect changes between releases.

Britive Bridge is a self-hosted container that connects to the Britive platform
through the Britive Broker and brokers clientless, browser-based sessions to
your internal resources. This directory collects **ready-to-use deployment
templates** for the most common environments, so you can pick the one that
matches your infrastructure and stand Bridge up quickly.

Every option deploys the same `britive/bridge` container. They differ only in
**where** it runs and **how** traffic reaches it.

---

## How Bridge works (the short version)

- The Bridge container connects **outbound** to the Britive platform via the
  Broker (MQTT). It registers using a **broker pool token**.
- It serves an HTTPS endpoint on **port 8080** (API + WebSocket + browser
  session protocols). By default it presents an **auto-generated self-signed
  certificate**; you can front it with a real certificate (ALB/ACM, Ingress +
  cert-manager, or a mounted cert).
- It persists active session/checkout state to **`/data`**, so that path should
  be backed by durable storage.
- Two environment variables are always required:
  - `BRITIVE_BROKER_TENANT_SUBDOMAIN` — e.g. `acme` for `acme.britive-app.com`
  - `BRITIVE_BROKER_AUTH_TOKEN` — the broker pool token

Users reach Bridge at an external URL (the `BRIDGE_URL`). That URL must be
reachable from the user's browser, which is what the load balancer / ingress in
each option provides.

---

## Before you start: one-time platform setup

Regardless of which deployment you choose, the Britive platform needs a broker
pool, a token, a Bridge resource, and an admin profile. The
[`platform-setup/`](platform-setup/) directory contains an interactive script
that creates all of these for you and prints the env vars Bridge needs.

Run it **first** — see [platform-setup/README.md](platform-setup/README.md).

---

## Choosing an option

| Option | Where it runs | TLS / external access | Persistence | Best for |
|--------|---------------|-----------------------|-------------|----------|
| [**Docker Compose**](docker-compose/) | Any Docker host / VM | Self-signed (8080) or mounted cert | Docker volume | Local trials, POCs, single-VM deployments |
| [**Linux VM (Docker)**](linux-vm-docker/) | A Linux server / VM | Self-signed (8080) or mounted cert | Docker volume | Standalone Linux host; on-prem or cloud VM, fully scripted |
| [**Windows VM (Docker)**](windows-vm-docker/) | A Windows server / VM (WSL 2) | Self-signed (8080) or mounted cert | Docker volume | Standalone Windows host (Linux container via WSL 2) |
| [**AWS ECS Fargate + NLB**](aws-ecs-fargate-nlb/) | AWS ECS Fargate | TLS passthrough via NLB:443 → container self-signed cert | EFS | Serverless AWS, minimal moving parts, no ACM cert needed |
| [**AWS ECS Fargate + ALB**](aws-ecs-fargate-alb/) | AWS ECS Fargate | ALB terminates TLS with an **ACM cert** on 443 | EFS | Production AWS with a real cert + custom domain |
| [**AWS ECS Fargate + ALB + SSH**](aws-ecs-fargate-alb-ssh/) | AWS ECS Fargate | Same as ALB option | EFS | ALB option **plus** broker SSH access to EC2 via a key in Secrets Manager |
| [**Kubernetes**](kubernetes/) | Any K8s cluster (EKS/AKS/GKE/on-prem) | Ingress (cert-manager / ALB) → backend HTTPS | PVC | Teams standardized on Kubernetes; Helm chart on the roadmap |

### Quick guidance

- **Just trying it out?** → Docker Compose.
- **A single Linux server (on-prem or cloud VM)?** → Linux VM (Docker) — scripted
  install with per-distro handling.
- **A single Windows server?** → Windows VM (Docker) — runs the Linux image via
  the WSL 2 backend (note the licensing/runtime caveats in that guide).
- **On AWS, want the simplest production path?** → ECS Fargate + ALB.
- **Don't have / don't want an ACM cert on AWS?** → ECS Fargate + NLB
  (TLS passthrough to the container's self-signed cert).
- **Need the broker to SSH into EC2 instances?** → ECS Fargate + ALB + SSH.
- **Run everything on Kubernetes?** → Kubernetes manifests (Helm chart coming —
  see the roadmap in that option's README).
- **Need the broker to run scripts that use extra tools** (`ssh`, `mysql`,
  `aws`, `jq`, …)? → build a [custom image](custom-image/) and use it as the
  image in any option above.

---

## Extending the image (custom utilities)

The broker runs your checkout/checkin scripts to mint and destroy ephemeral
credentials, and those scripts often need CLI tools not in the stock image. The
[`custom-image/`](custom-image/) directory shows how to layer them on top of
`britive/bridge` and deploy the result to **ECS or Kubernetes** unchanged — with
two worked examples (**Linux SSH** key provisioning and **Aurora MySQL**
temporary users/roles). This is orthogonal to the deployment options above: pick
a deployment, point its image at your custom build.

---

## Directory layout

```
Britive Bridge/
├── README.md                       # you are here
├── platform-setup/                 # run FIRST — creates Britive platform objects
│   ├── quick-setup.py
│   ├── requirements.txt
│   └── README.md
├── custom-image/                   # extend britive/bridge with extra utilities
│   ├── Dockerfile                  # base-distro & arch agnostic
│   ├── build-and-push.sh           # multi-arch build → Docker Hub / ECR
│   ├── scripts/                    # worked examples: Linux SSH + Aurora MySQL
│   ├── k8s-overlays/               # ready-to-apply: image + SSH key + IRSA SA
│   └── README.md
├── docker-compose/
│   ├── docker-compose.yaml
│   └── README.md
├── linux-vm-docker/                # standalone Linux VM via Docker
│   ├── install.sh
│   ├── bridge.env.example
│   └── README.md
├── windows-vm-docker/              # standalone Windows VM via Docker (WSL 2)
│   ├── install.ps1
│   ├── bridge.env.example
│   └── README.md
├── aws-ecs-fargate-nlb/
│   ├── ecs-fargate-nlb.yaml
│   ├── params.example.json
│   └── README.md
├── aws-ecs-fargate-alb/
│   ├── ecs-fargate-alb.yaml
│   ├── params.example.json
│   └── README.md
├── aws-ecs-fargate-alb-ssh/
│   ├── ecs-fargate-alb-ssh.yaml
│   ├── params.example.json
│   └── README.md
└── kubernetes/
    ├── manifests/
    │   ├── namespace.yaml
    │   ├── secret.example.yaml
    │   ├── pvc.yaml
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── ingress.yaml
    │   ├── external-secret.example.yaml   # optional: External Secrets Operator
    │   ├── pvc-rwm.example.yaml           # optional HA: RWX PVC (instead of pvc.yaml)
    │   └── ha-deployment-patch.example.yaml  # optional HA: replicas + rolling update
    └── README.md                   # includes the public Helm chart roadmap
```

---

## A note on placeholders

All templates use **placeholder values** (`<your-tenant-subdomain>`,
`vpc-EXAMPLE...`, `arn:aws:acm:<region>:<account-id>:...`, `bridge.example.com`,
etc.). Replace them with your real values before deploying. **Never commit real
tokens, private keys, account IDs, or certificate ARNs** to source control —
use the parameter files locally or, better, a secret store.
