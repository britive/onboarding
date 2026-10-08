# Britive Bridge — Deployment Options

Britive Bridge is a self-hosted container that connects to the Britive platform
through the Britive Broker and brokers recorded, proxied sessions — browser or
native client — to your internal resources: SSH, RDP, databases, Kubernetes
exec and more. This directory holds **ready-to-use deployment templates** for
Bridge **v2.x**, the current release line.

> **Bridge v1.x is end-of-life.** Its templates were removed from this
> repository on 2026-10-08 and no v1 image is published on Docker Hub. If you
> still run v1, plan the move to v2 — see [v2/README.md](v2/README.md) for what
> changed.
>
> **Pin the image tag.** `britive/bridge:latest` tracks the newest release and
> moves without notice. Every template here pins `v2.3.1`. To see what is
> published:
>
> ```bash
> curl -s 'https://hub.docker.com/v2/repositories/britive/bridge/tags?page_size=100' \
>   | python3 -c 'import json,sys; print(*[t["name"] for t in json.load(sys.stdin)["results"]])'
> ```
>
> Everything here is **BETA**: validate in a non-production environment first.

Official product documentation lives at <https://learn.britive.com/bridge/>.
The templates here are examples, not supported product; they encode what we
have verified works, with the reasons recorded inline.

---

## How Bridge v2 works (the short version)

- The Bridge container connects **outbound** to the Britive platform via the
  Broker (MQTT), registering with a **broker pool token**. Nothing inbound from
  Britive is required.
- It serves one HTTP(S) endpoint (the **web tier**: API, browser sessions,
  login) and, optionally, **native listeners** per protocol (SSH 2222, RDP
  3389, MySQL 3306, PostgreSQL 5432, …) for users who prefer their own client.
- **PostgreSQL is mandatory.** Checkouts, sessions and the audit index live
  there. The process will not start without a reachable datastore.
- A **permanent encryption key** (`BRIDGE_ENCRYPTION_KEY_B64`) protects stored
  checkout payloads. Rotating it after go-live makes everything already stored
  unreadable.
- Configuration is a YAML file (`/etc/britive-bridge/config.yaml`) that
  environment variables can **complete or override** — precedence is built-in
  defaults < file < environment. Every protocol is off by default, and at
  least one must be enabled or the process refuses to start.
- Users authenticate to **Bridge** (Britive SSO in the browser; a Britive-held
  Bridge password/key for native clients). The endpoint credential is
  ephemeral, created by the broker at checkout, and the user never sees it.

Users reach Bridge at a public URL (`BRIDGE_URL`). That URL must match the TLS
certificate and must be reachable from the user's browser or native client —
which is what each option's load balancer or port mapping provides.

---

## Before you start: one-time platform setup

Every deployment needs a broker pool, a token, a Bridge resource type and an
admin profile on the Britive platform. [`platform-setup/`](platform-setup/)
contains an interactive script that creates all of them and prints the
environment variables Bridge needs.

Run it **first** — see [platform-setup/README.md](platform-setup/README.md).
You will typically run it **twice**: once before deploying (with a placeholder
Bridge URL) and once after, to set the real URL. Re-running updates the
existing resource in place.

---

## Choosing an option

| Option | Where it runs | TLS / external access | Persistence | Best for |
| ------ | ------------- | --------------------- | ----------- | -------- |
| [**AWS ECS Fargate + NLB**](v2/aws-ecs-fargate-nlb/) | AWS ECS Fargate | NLB:443 terminates TLS with an **ACM cert**; TCP listeners for native SSH/RDP/MySQL/PostgreSQL | EFS + RDS PostgreSQL (companion stack included) | Production on AWS, no hosts to patch |
| [**Docker Compose**](v2/docker-compose/) | Any Docker host / VM | Container's own TLS (self-signed by default) | Docker volumes (bridge data + PostgreSQL) | Evaluation, POCs, single-server deployments |
| **Kubernetes (Helm)** | Any cluster | Ingress of your choice | PVC + your PostgreSQL | Britive publishes an official chart: `helm install bridge oci://registry-1.docker.io/britive/bridge-chart` — see [learn.britive.com/bridge/deploy/kubernetes/](https://learn.britive.com/bridge/deploy/kubernetes/). No manifests are duplicated here. |

### Quick guidance

- **Just trying it out, or one server is enough?** → [Docker Compose](v2/docker-compose/).
- **Production on AWS?** → [ECS Fargate + NLB](v2/aws-ecs-fargate-nlb/), with
  the included `rds-postgres.yaml` for the datastore.
- **Already standardized on Kubernetes?** → the official Helm chart (link
  above). Build a [custom image](custom-image/) first if your checkout scripts
  need extra tools.
- **Need the broker to run scripts that use extra tools** (`ssh`, `mysql`,
  `aws`, `jq`, …) or want the configuration baked in for Fargate? → build a
  [custom image](custom-image/) and use it as the image in any option.
- **Need horizontal scale** (orchestrator / proxy / session roles)? → Britive's
  cluster-mode reference at
  [learn.britive.com/bridge/deploy/aws-ecs/](https://learn.britive.com/bridge/deploy/aws-ecs/).
  The single-role template here runs one task.

---

## Extending the image (custom utilities, baked config)

The broker runs your checkout/checkin scripts to mint and destroy ephemeral
credentials, and those scripts often need CLI tools not in the stock image. The
[`custom-image/`](custom-image/) builder layers them on top of `britive/bridge`,
optionally bakes `bridge.yaml` into the image (required on Fargate, which has
no volume to mount the file from) and trusts the AWS RDS certificate
authorities. Two worked examples are included: **Linux SSH** key provisioning
and **Aurora MySQL** temporary users/roles.

```bash
docker build \
  --build-arg BASE_IMAGE=britive/bridge:v2.3.1 \
  --build-arg BAKE_CONFIG=true \
  --build-arg WITH_RDS_CA=true \
  -t <account>.dkr.ecr.<region>.amazonaws.com/britive/bridge:v2.3.1-r1 .
```

---

## Directory layout

```
Britive Bridge/
├── README.md                       # you are here
├── platform-setup/                 # run FIRST — creates Britive platform objects
│   ├── quick-setup.py
│   ├── requirements.txt
│   └── README.md
├── custom-image/                   # extend britive/bridge; bake config; trust RDS CAs
│   ├── Dockerfile                  # base-distro & arch agnostic
│   ├── build-and-push.sh           # multi-arch build → Docker Hub / ECR
│   ├── bridge.yaml                 # the configuration that gets baked in
│   ├── scripts/                    # worked examples: Linux SSH + Aurora MySQL
│   └── README.md
└── v2/
    ├── README.md
    ├── aws-ecs-fargate-nlb/
    │   ├── ecr-repo.yaml           # ECR repository (immutable tags)
    │   ├── rds-postgres.yaml       # RDS PostgreSQL datastore (deploy once)
    │   ├── ecs-fargate-nlb.yaml    # ECS service, NLB, EFS, IAM, secrets
    │   ├── params.example.json
    │   └── README.md
    └── docker-compose/
        ├── docker-compose.yaml
        ├── .env.example
        └── README.md
```

---

## A note on placeholders

All templates use **placeholder values** (`your-tenant`, `vpc-EXAMPLE…`,
`bridge.example.com`, `<account>`). Replace them before deploying. **Never
commit real tokens, private keys, account IDs or certificate ARNs** — keep
parameter files local, or better, in a secret store.
