# Britive Bridge v2.x — Deployment Options

Deployment templates for **Bridge v2.x**. For v1.x see [`../v1/`](../v1/).

## What changed from v1

v2 is not a drop-in upgrade of a v1 deployment. Three things are new and all
three are mandatory:

| Requirement | Why it matters |
| ----------- | -------------- |
| **PostgreSQL datastore** | Checkouts, sessions and the audit index live in the database. The task will not start without one. |
| **Encryption key** | Encrypts checkout payloads at rest. It is **permanent** — rotating it after go-live makes stored payloads undecryptable. |
| **Configuration baked into the image** | Every protocol is off by default and the Bridge refuses to start unless at least one is enabled. The tenant is validated from the file before environment overrides apply, so it cannot be supplied by environment variable alone. |

Because configuration lives in the image, a config change is an image change:
build a new tag, then update the stack's `ImageUri`. The
[shared image builder](../custom-image/) handles this with
`--build-arg BAKE_CONFIG=true`.

## Options

| Option | Where it runs | TLS / external access | Persistence |
| ------ | ------------- | --------------------- | ----------- |
| [**AWS ECS Fargate + NLB**](aws-ecs-fargate-nlb/) | AWS ECS Fargate | NLB:443 terminates TLS with an ACM certificate; TCP listeners for native SSH, RDP, MySQL and PostgreSQL | EFS for recordings, PostgreSQL for state |

## Before you start

Run the [platform setup](../platform-setup/) first — it creates the broker pool
and token every deployment needs.

## Directory layout

```
v2/
└── aws-ecs-fargate-nlb/
    ├── ecs-fargate-nlb.yaml     # ECS service, NLB, EFS, IAM, secrets
    ├── ecr-repo.yaml            # ECR repository (immutable tags)
    ├── params.example.json      # all 17 stack parameters
    └── README.md                # prerequisites through cleanup
```
