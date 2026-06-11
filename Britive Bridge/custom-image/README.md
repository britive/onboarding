# Britive Bridge — Custom Image (extend the broker with utilities)

The stock `britive/bridge` image ships the **broker** (and `bridge.sh`). The
broker runs your **checkout/checkin scripts** to create and destroy ephemeral
credentials. Those scripts call command-line tools — `ssh`, `mysql`, `aws`,
`jq`, `python3`, … — that aren't all present in the stock image.

This directory shows how to build a **custom image** that layers those tools on
top of `britive/bridge`, then deploy it anywhere the stock image goes
(**ECS** or **Kubernetes**) by simply pointing at your image instead.

Two worked examples are included:

1. **Linux SSH** — JIT SSH access by provisioning a one-time `ed25519` key on a
   target host and registering a proxied bridge session.
2. **Aurora MySQL** — JIT database access by creating/dropping a temporary MySQL
   user (or granting/revoking a role), using master creds from AWS Secrets Manager.

---

## How it fits together

```
            build & push                     deploy (ECS or K8s)
 Dockerfile ─────────────►  your-registry/   ──────────────►  broker container
 (FROM britive/bridge       britive-bridge-                    runs checkout/checkin
  + ssh/mysql/aws/jq...)    custom:latest                      scripts that now have
                                                               all the tools they need
```

- The broker still pulls the **actual scripts from the Britive platform** at
  checkout time (uploaded during profile setup). You do **not** have to bake
  scripts into the image — you bake in the **utilities** they depend on.
- The example scripts live under [`scripts/`](scripts/) for reference and local
  testing, and can optionally be baked in (see the commented `COPY` in the
  `Dockerfile`).

---

## What the examples need (and the Dockerfile installs)

| Utility | Linux SSH | Aurora MySQL | Notes |
|---------|:---------:|:------------:|-------|
| `ssh`, `ssh-keygen` | ✓ | | provision the one-time key on the target |
| `python3` | ✓ | | JSON-encode the private key in the payload |
| `base64`, `tr`, `head` | ✓ | ✓ | coreutils — present in most bases, installed to be safe |
| `mysql` (client) | | ✓ | run `CREATE/DROP USER`, `GRANT/REVOKE` |
| `aws` (CLI v2) | | ✓ | read DB master creds from Secrets Manager |
| `jq` | | ✓ | parse the secret JSON |
| `bridge.sh` | ✓ | | already in the base image (`/opt/britive-broker/scripts/bridge.sh`) |

The `Dockerfile` is **base-distro agnostic** (detects apt / apk / dnf) and
**arch-aware** for the AWS CLI (x86_64 + arm64), so the resulting image runs on
both Fargate ARM64 and mixed Kubernetes nodes.

---

## Prerequisites

- Docker with **buildx** (for multi-arch builds) — `docker buildx version`
- A container registry you can push to: **Docker Hub** (to keep images and the
  planned Helm chart in one place — see the [k8s option](../kubernetes/)) or
  **Amazon ECR**
- Completed [platform setup](../platform-setup/) and a working Bridge deployment
  pattern ([ECS](../aws-ecs-fargate-alb/) or [Kubernetes](../kubernetes/))

---

## 1. Build & push

```bash
# Docker Hub (run `docker login` first)
REGISTRY=docker.io/yourorg ./build-and-push.sh

# Amazon ECR (script auto-creates the repo and logs in)
REGISTRY=<account-id>.dkr.ecr.us-west-2.amazonaws.com ./build-and-push.sh
```

Override the base, tag, or platforms as needed:

```bash
REGISTRY=docker.io/yourorg TAG=v1 \
  BASE_IMAGE=britive/bridge:latest \
  PLATFORMS=linux/amd64,linux/arm64 \
  ./build-and-push.sh
```

Local single-arch build (no push) for testing:

```bash
docker build -t britive-bridge-custom:latest .
docker run --rm britive-bridge-custom:latest \
  sh -c 'for c in ssh ssh-keygen mysql aws jq python3; do command -v $c || exit 1; done'
```

---

## 2. Deploy the custom image

### ECS (Fargate)

Use any of the AWS ECS options in this repo and set the image to yours. With the
CloudFormation templates, that's the `ImageUri` parameter:

```jsonc
// params.json
{ "ParameterKey": "ImageUri",
  "ParameterValue": "docker.io/yourorg/britive-bridge-custom:latest" }
```

For the **SSH example**, the broker needs its provisioning private key. The
[ALB + SSH template](../aws-ecs-fargate-alb-ssh/) already injects a key from
Secrets Manager to `/home/bridge/.ssh/id_ed25519` — use that template with your
custom `ImageUri`.

For the **MySQL example**, the broker calls AWS Secrets Manager and reaches
Aurora. Grant the ECS **task role** (named `<StackNamePrefix>-task-role-<region>`
by the templates) `secretsmanager:GetSecretValue` via an inline policy scoped
to the DB secret's ARN, and make sure the task's security group can reach the
Aurora endpoint (3306).

### Kubernetes

Ready-to-apply overlays live in [`k8s-overlays/`](k8s-overlays/) — they patch
the base [Kubernetes deployment](../kubernetes/) with your custom image, the
SSH-key mount, and the IRSA service account. After the base manifests are up:

```bash
# 0. Generate the broker's provisioning keypair (once) and install the PUBLIC
#    key in the provisioning user's authorized_keys on each target host:
#    ssh-keygen -t ed25519 -f ./bridge_ed25519 -N ''

# 1. Broker SSH provisioning key (Linux SSH example)
kubectl -n britive-bridge create secret generic bridge-ssh-key \
  --from-file=id_ed25519=./bridge_ed25519

# 2. IRSA service account (Aurora MySQL example) — edit the role ARN first
kubectl apply -f k8s-overlays/serviceaccount-irsa.yaml

# 3. Patch the Deployment: your image + SA + SSH mount (strategic merge —
#    do not use --type merge, it wipes list fields from the base Deployment)
kubectl -n britive-bridge patch deployment britive-bridge \
  --type strategic --patch-file k8s-overlays/deployment-patch.yaml
```

Edit the placeholders first (`image:` → your build,
`eks.amazonaws.com/role-arn` → your role). Need only one example? Apply just its
pieces — see [`k8s-overlays/README.md`](k8s-overlays/README.md). The MySQL
example also needs pod egress to the Aurora endpoint on 3306.

---

## The two examples in detail

### Linux SSH — `scripts/linux-ssh/`

`checkout_remote_bridge.sh` / `checkin_remote_bridge.sh`. On checkout: derive an
OS username from the user's email, generate a one-time `ed25519` keypair, SSH to
the target (as a privileged provisioning user) to create the user + install the
public key (optionally passwordless sudo), then register the session with
`bridge.sh checkout-create` and return a browser URL. Checkin reverses it.

**Broker container needs:** `ssh`, `ssh-keygen`, `base64`, `python3`, `bridge.sh`.

**Target host needs:** a privileged provisioning account (default
`britivebroker`) reachable by the broker's key, with root or passwordless sudo.

Key script variables (set as Britive profile/permission parameters):
`BRITIVE_USER_EMAIL`, `TRX`, `BRITIVE_REMOTE_HOST`, `BRIDGE_URL`, `EXPIRATION`,
and optional `REMOTE_USER`, `PROVISION_HOST/PORT/KEY`, `BRITIVE_SUDO`.

### Aurora MySQL — `scripts/aurora-mysql/`

- `temp-user/` — create a temp MySQL user with `ALL` on a database, drop on checkin.
- `role-member/` — create a temp user and `GRANT`/`REVOKE` a named role on a
  specific `database.table`.

Both pull the master DB credentials from **AWS Secrets Manager** (`jq`-parsed),
write a short-lived `--defaults-extra-file` so the password never hits the
process args, run the SQL via the `mysql` client, then clean up.

**Broker container needs:** `bash`, `mysql`, `aws`, `jq`, `/dev/urandom`.

Script parameters (set during Britive profile setup): `user`, `host`, `dburl`,
`secret`, plus `table`, `role`, `database_name` for the role-member variant, and
optional `AWS_REGION` (default `us-west-2`).

> The example SQL targets a database literally named `systemdb` (temp-user) and
> uses `us-west-2` as the default region — change these to your environment.
> The Secrets Manager secret must be JSON: `{"username": "...", "password": "..."}`.

---

## Security notes

- **Least privilege.** The MySQL master secret can create/drop users — scope the
  broker's IAM/secret access tightly and prefer specific MySQL host patterns
  over `%`. The SSH provisioning account should be a dedicated, minimal-rights
  user, not a shared admin.
- **No secrets in the image.** Keys and DB creds are injected at runtime
  (Secrets Manager / K8s Secret), never baked into the image or committed here.
- **Ephemeral by design.** Both examples create credentials on checkout and
  destroy them on checkin; verify checkin runs (and consider the optional
  user-deletion block in the SSH checkin for full teardown).
- **Pin versions for production.** Replace `:latest` (base and your image) with
  immutable tags/digests so deployments are reproducible.

---

## Customizing for other access types

To support a new resource type, add its tools to the `Dockerfile`'s package
list (and an AWS-CLI-style block if it needs a special installer), rebuild, and
push. The deployment doesn't change — only the image does. Use the sanity-check
loop at the end of the `Dockerfile`'s `RUN` to fail the build early if a tool is
missing.
