# Britive Bridge — Custom Image

The stock `britive/bridge` image ships the Bridge and the **broker** (with
`bridge.sh`). The broker runs your **checkout/checkin scripts** to create and
destroy ephemeral credentials, and those scripts call command-line tools —
`ssh`, `mysql`, `aws`, `jq`, `python3`, … — that are not all present in the
stock image.

This directory builds a **custom image** that layers those tools on top of
`britive/bridge`, and does two more things a v2 deployment needs:

- **Bakes `bridge.yaml` into the image** (`BAKE_CONFIG=true`). Required on ECS
  Fargate, which has no volume to mount a config file from. Docker Compose and
  Kubernetes bind-mount the file instead and can skip this.
- **Trusts the AWS RDS certificate authorities** (`WITH_RDS_CA=true`), so
  database checkouts with `target_tls=true` and a `verify-full` datastore
  connection succeed.

Two worked examples are included under [`scripts/`](scripts/):

1. **Linux SSH** — JIT SSH access by provisioning a one-time `ed25519` key on a
   target host and registering a proxied Bridge session.
2. **Aurora MySQL** — JIT database access by creating/dropping a temporary MySQL
   user (or granting/revoking a role), using master credentials from AWS
   Secrets Manager.

---

## How it fits together

```
            build & push                      deploy (ECS / Compose / Helm)
 Dockerfile ─────────────►  your-registry/    ─────────────────►  bridge container
 (FROM britive/bridge        britive/bridge:                       runs checkout/checkin
  + ssh/mysql/aws/jq          v2.3.1-r1                            scripts that now have
  + baked bridge.yaml)                                             all the tools they need
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
| ------- | :-------: | :----------: | ----- |
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
- A container registry you can push to: **Amazon ECR** (create it with
  [`../v2/aws-ecs-fargate-nlb/ecr-repo.yaml`](../v2/aws-ecs-fargate-nlb/ecr-repo.yaml))
  or **Docker Hub**
- Completed [platform setup](../platform-setup/)

---

## 1. Configure

Edit [`bridge.yaml`](bridge.yaml). At minimum set
`server.auth.britive.tenant` to your tenant subdomain; the build refuses to
bake the file while it is still `your-tenant`. The supplied file enables SSH,
RDP, MySQL and PostgreSQL in native and browser mode and everything else in
browser mode only — exactly what the ECS template wires. Secrets never go in
this file; the deployment injects them at runtime.

---

## 2. Build & push

```bash
# Amazon ECR (script logs in; creates the repo with immutable tags if missing)
REGISTRY=<account>.dkr.ecr.<region>.amazonaws.com \
  BAKE_CONFIG=true WITH_RDS_CA=true \
  ./build-and-push.sh

# Docker Hub (run `docker login` first)
REGISTRY=docker.io/yourorg ./build-and-push.sh
```

Defaults: `BASE_IMAGE=britive/bridge:v2.3.1`, `IMAGE_NAME=britive/bridge`,
`TAG=<base tag>-r1` (so `v2.3.1-r1`). Bump the `-rN` suffix on every rebuild —
ECR tags are immutable and `latest` is refused.

### Pick the base image deliberately

**Never set `BASE_IMAGE` to `britive/bridge:latest`** — that tag tracks the
newest release and moves without notice. Check what is published before
bumping:

```bash
curl -s 'https://hub.docker.com/v2/repositories/britive/bridge/tags?page_size=100' \
  | python3 -c 'import json,sys; print(*[t["name"] for t in json.load(sys.stdin)["results"]])'
```

Local single-arch build (no push) for testing:

```bash
docker build --build-arg BAKE_CONFIG=true -t britive-bridge-custom:local .
docker run --rm --entrypoint sh britive-bridge-custom:local \
  -c 'for c in ssh ssh-keygen mysql aws jq python3; do command -v $c || exit 1; done; cat /etc/britive-bridge/config.yaml | head -5'
```

Confirm what you expect is actually in the image rather than assuming the
Dockerfile did it: the `cat` above proves the config was baked, and
`docker inspect <image> --format '{{.Architecture}}'` proves the architecture
matches the `CpuArchitecture` you will deploy with.

---

## 3. Deploy the custom image

### ECS Fargate

Set the [`../v2/aws-ecs-fargate-nlb/`](../v2/aws-ecs-fargate-nlb/) stack's
`ImageUri` parameter to the pushed image.

For the **SSH example**, the broker needs its provisioning private key. The
template injects it from Secrets Manager to `/home/bridge/.ssh/id_ed25519`
when `BrokerSSHPrivateKey` is set.

For the **MySQL example**, the broker calls AWS Secrets Manager and reaches
Aurora. Set the stack's `EnableAwsBrokerScripts=true` (grants the task role
read/write on secrets under `<StackNamePrefix>/*` plus EC2/RDS discovery), put
the DB master secret under that prefix, and make sure the task's security group
can reach the Aurora endpoint (3306).

### Docker Compose

[`../v2/docker-compose/`](../v2/docker-compose/) bind-mounts `bridge.yaml`
directly, so a custom image is only needed for the extra utilities: set
`BRIDGE_IMAGE` in `.env` to your pushed image and leave `BAKE_CONFIG=false`.

### Kubernetes

Use Britive's official Helm chart with the values file in
[`../v2/kubernetes/`](../v2/kubernetes/): set `image.repository` /
`image.tag` to your build and leave `BAKE_CONFIG=false` (the chart renders
the configuration). Provide the SSH key the Linux example needs as a Secret
mounted through `worker.customization.session.volumes`, and the cloud
identity the MySQL example needs through `worker.serviceAccount.annotations`
(IRSA / GKE Workload Identity / AKS workload identity) — both shown in that
values file.

---

## The two examples in detail

### Linux SSH — `scripts/linux-ssh/`

`checkout_remote_bridge.sh` / `checkin_remote_bridge.sh`. On checkout: derive an
OS username from the user's email, generate a one-time `ed25519` keypair, SSH to
the target (as a privileged provisioning user) to create the user + install the
public key (optionally passwordless sudo), then register the session with
`bridge.sh checkout-create` and return a browser URL. Checkin reverses it,
deleting the Bridge transaction first so a live session ends before the
credential is removed.

**Broker container needs:** `ssh`, `ssh-keygen`, `base64`, `python3`, `bridge.sh`.

**Target host needs:** a privileged provisioning account (default
`britivebroker`) reachable by the broker's key, with root or passwordless sudo.

Key script variables (set as Britive profile/permission parameters):
`BRITIVE_USER_EMAIL`, `TRX`, `BRITIVE_REMOTE_HOST`, `BRIDGE_URL`, `EXPIRATION`
(seconds), and optional `REMOTE_USER`, `PROVISION_HOST/PORT/KEY`,
`BRITIVE_SUDO`.

> The scripts use `StrictHostKeyChecking=no` for the provisioning hop because
> the container has no `known_hosts`. For production, pin the target host key
> (`-o UserKnownHostsFile=` on a mounted file, or `accept-new` on a persistent
> volume) and keep checkout and checkin on the same policy.

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
  (Secrets Manager / `.env` / Kubernetes Secret), never baked into the image or
  committed here. `bridge.yaml` is baked in, so it must not contain any either.
- **Ephemeral by design.** Both examples create credentials on checkout and
  destroy them on checkin; verify checkin runs (and consider the optional
  user-deletion block in the SSH checkin for full teardown).
- **Pin versions.** Immutable `-rN` tags on your image and a pinned
  `BASE_IMAGE` keep deployments reproducible.

---

## Customizing for other access types

To support a new resource type, add its tools to the `Dockerfile`'s package
list (and an AWS-CLI-style block if it needs a special installer), rebuild, and
push. The deployment doesn't change — only the image does. Use the sanity-check
loop at the end of the `Dockerfile`'s `RUN` to fail the build early if a tool is
missing.
