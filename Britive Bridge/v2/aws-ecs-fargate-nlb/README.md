# Britive Bridge on ECS Fargate

Deploy the [Britive Bridge](https://learn.britive.com/bridge/) as an ECS Fargate
service behind a Network Load Balancer, using a container image you build and
host in your own ECR registry.

## Templates

| File | Purpose |
| ---- | ------- |
| `ecr-repo.yaml` | ECR repository for your Bridge image (deploy once) |
| [`../../custom-image/`](../../custom-image/) | Shared image builder — bakes your config and adds the broker runtime |
| [`../../custom-image/bridge.yaml`](../../custom-image/bridge.yaml) | The Bridge configuration baked into that image |
| `ecs-fargate-nlb.yaml` | ECS Fargate service, NLB, EFS, security groups, IAM, secrets |
| `params.example.json` | Parameter file for the ECS stack |

## When to Use These Templates

**Use this when you want:**

- Recorded, brokered SSH / RDP / database / Kubernetes sessions through Britive
- The Bridge running as a managed container service with no EC2 hosts to patch
- A reproducible image, versioned in ECR, that carries your exact configuration

**Do not use this when:**

- You only need Britive's AWS SAML integration — see
  [cloudformation/aws/](../../../cloudformation/aws/) instead. The Bridge is a
  separate product from the AWS account integration.
- You are running **Bridge v1.x** — use [../../v1/](../../v1/), whose templates
  match that version. v1 has no datastore or encryption-key parameters, and this
  template will not work with a v1 image.
- You cannot expose an internet-facing load balancer. The Bridge needs to be
  reachable by the browsers and native clients of the people using it.

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Step 1: Create the ECR Repository](#step-1-create-the-ecr-repository)
- [Step 2: Configure the Bridge](#step-2-configure-the-bridge)
- [Step 3: Build and Push the Image](#step-3-build-and-push-the-image)
- [Step 4: Prepare Stack Prerequisites](#step-4-prepare-stack-prerequisites)
- [Step 5: Deploy the ECS Stack](#step-5-deploy-the-ecs-stack)
- [Step 6: Point DNS at the Load Balancer](#step-6-point-dns-at-the-load-balancer)
- [Step 7: Verify](#step-7-verify)
- [Updating the Deployment](#updating-the-deployment)
- [Parameter Reference](#parameter-reference)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

---

## Architecture

```md
                    Internet
                        |
        +---------------+----------------+
        |   Network Load Balancer (NLB)  |   ingress gated by a managed
        |   TLS 443  ->  web tier :8080  |   prefix list of your client IPs
        |   TCP 2222 ->  SSH             |
        |   TCP 3389 ->  RDP             |
        |   TCP 3306 ->  MySQL           |
        |   TCP 5432 ->  PostgreSQL      |
        +---------------+----------------+
                        |
              +---------+---------+
              |  ECS Fargate task |  your ECR image
              |  britive/bridge   |  (config baked in)
              +----+---------+----+
                   |         |
        +----------+         +-----------+
        |                                |
   +----+-----+                    +-----+------+
   |   EFS    |  recordings        | PostgreSQL |  datastore
   |  /data   |  + certs           |  (yours)   |  (you supply)
   +----------+                    +------------+
```

**One hostname does everything.** A single NLB fronts the web UI and every
native protocol listener, so users reach `bridge.example.com` for a browser
session and the same name on port 2222 for `ssh`.

**Why the odd ports.** Fargate cannot bind privileged ports (below 1024)
without the `NET_BIND_SERVICE` capability, which Fargate does not allow adding.
The container serves the web tier on 8080 and SSH on 2222; the NLB does the
443 → 8080 translation, and SSH clients connect to 2222 directly.

**The 5-registration ceiling.** ECS caps a single service at **five**
load-balancer registrations. One is spent on the web tier, leaving four for
native listeners — used here by SSH, RDP, MySQL and PostgreSQL. Every other
protocol is browser-only, which costs no registration because those sessions
ride the existing 443 listener. This is why `mssql` is browser-only in the
supplied `bridge.yaml`: enabling a native listener the NLB does not forward
produces a connect command that looks valid and never works.

---

## Prerequisites

### Tooling

| Tool | Why |
| ---- | --- |
| Docker | Builds the image. Must support `--platform` (Docker 20.10+) |
| AWS CLI v2 | ECR login, CloudFormation deployment |
| `openssl` | Generates the encryption key |

### AWS resources you must have or create first

| Resource | Notes |
| -------- | ----- |
| VPC with two **public** subnets in different AZs | The NLB, the Fargate task and the EFS mount targets all live here |
| **PostgreSQL** instance reachable from the VPC | Mandatory in Bridge v2. RDS, Aurora or self-managed |
| Secrets Manager secret with the DB password | Must be JSON containing a `password` key |
| **ACM certificate** for your Bridge hostname | Must be in the **same region** as the NLB |
| **Managed prefix list** of client public IPs | Gates the NLB. See [Step 4](#4-create-a-managed-prefix-list) |

### Required IAM permissions

The deploying principal needs to create and manage: ECR repositories, ECS
clusters/services/task definitions, EC2 security groups, Elastic Load Balancing
v2 resources, EFS file systems, IAM roles (`CAPABILITY_NAMED_IAM`), Secrets
Manager secrets, and CloudWatch log groups.

### Britive information needed

| Value | Where to find it |
| ----- | ---------------- |
| Tenant subdomain | Your Britive URL, without `.britive-app.com` |
| Broker pool token | Britive console: **Admin → Access Broker → Broker Pools** |

---

## Step 1: Create the ECR Repository

Tags are **immutable** in this repository by design: a given tag can never be
overwritten, so what a task pulls on restart cannot silently change.

```bash
aws cloudformation create-stack \
  --stack-name britive-bridge-ecr \
  --template-body file://ecr-repo.yaml \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete \
  --stack-name britive-bridge-ecr

aws cloudformation describe-stacks \
  --stack-name britive-bridge-ecr \
  --query 'Stacks[0].Outputs[?OutputKey==`RepositoryUri`].OutputValue' \
  --output text
```

---

## Step 2: Configure the Bridge

Edit [`../../custom-image/bridge.yaml`](../../custom-image/bridge.yaml). It is baked
into the image, so this is where your
deployment is defined — **not** in the CloudFormation stack.

**Required change:**

```yaml
server:
  auth:
    britive:
      tenant: "your-tenant" # <- your subdomain, without .britive-app.com
```

The Bridge validates this from the **file** before environment overrides are
applied. Leaving it unset crash-loops the task at startup, so
the image build refuses to proceed until you change it.

**Recommended changes:**

```yaml
server:
  trusted_proxies:
    - "10.0.0.0/16" # <- your VPC CIDR, so recordings log real client IPs
```

**Protocols.** Every protocol is off by default and the Bridge refuses to start
unless at least one is enabled. The supplied file enables SSH, RDP, MySQL and
PostgreSQL in both native and browser mode, and everything else in browser mode
only. Keep native mode limited to those four unless you also add NLB listeners —
see [the 5-registration ceiling](#architecture).

**Secrets belong nowhere in this file.** The stack injects them at runtime from
Secrets Manager. Anything you put here is baked into an image layer permanently.

Full option list:
[bridge.reference.yaml](https://learn.britive.com/bridge-files/bridge.reference.yaml).

---

## Step 3: Build and Push the Image

The shared builder in [`../../custom-image/`](../../custom-image/) produces the
image. `BAKE_CONFIG=true` is **required** for v2 — every protocol is off by
default and the Bridge refuses to start unless at least one is enabled.
`WITH_RDS_CA=true` trusts the AWS RDS certificate authorities so database
checkouts using `target_tls=true` verify successfully.

```bash
cd ../../custom-image

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
IMAGE_URI="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/britive/bridge:v2.1.0-r1"

docker build \
  --platform linux/arm64 \
  --build-arg BASE_IMAGE=britive/bridge:v2.1.0 \
  --build-arg BAKE_CONFIG=true \
  --build-arg WITH_RDS_CA=true \
  -t "$IMAGE_URI" .

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

docker push "$IMAGE_URI"
```

Use `$IMAGE_URI` as the `ImageUri` parameter in Step 5.

The build fails if the tenant is still the `your-tenant` placeholder, and
asserts that the RDS certificates actually landed in the trust store — so
neither mistake reaches a running task.

> **Pin `BASE_IMAGE` to a specific tag; do not use `britive/bridge:latest`.**
> That tag tracks whatever was published most recently — it points at v2.1.0
> today and will move on the next release, so two builds of the "same" image
> can differ. Worse, `latest` is shared across major versions, so it will
> eventually point at a v3 image that this template does not support. The
> Dockerfile's own `BASE_IMAGE` default is `latest` for backwards
> compatibility, which is why every command here passes it explicitly.

> **`PLATFORM` must match the `CpuArchitecture` stack parameter.** Fargate will
> not run an image built for the other architecture, and the failure shows up as
> a task that starts and immediately stops — not as a stack error. The defaults
> here are `linux/arm64` and `ARM64`, which is cheaper per vCPU-hour.

To build for Intel/AMD instead:

```bash
docker build --platform linux/amd64 \
  --build-arg BASE_IMAGE=britive/bridge:v2.1.0 \
  --build-arg BAKE_CONFIG=true --build-arg WITH_RDS_CA=true \
  -t "$IMAGE_URI" .
# and set CpuArchitecture=X86_64 on the ECS stack
```

---

## Step 4: Prepare Stack Prerequisites

### 1. Generate the encryption key

```bash
openssl rand -base64 32
```

This key encrypts checkout payloads in the datastore.

> **This value is permanent.** Rotating it after go-live makes every previously
> stored checkout payload undecryptable. Generate it once, store it somewhere
> durable, and keep it for the life of the deployment.

### 2. Create the database password secret

The stack expects a Secrets Manager secret whose JSON contains a `password`
key:

```bash
aws secretsmanager create-secret \
  --name britive-bridge/datastore \
  --secret-string '{"username":"bridge","password":"REPLACE_ME"}' \
  --query ARN --output text
```

Create the `bridge` database and role on your PostgreSQL instance, and allow
inbound 5432 from the Bridge task's security group.

### 3. Request an ACM certificate

For the hostname clients will use, **in the same region as the NLB**:

```bash
aws acm request-certificate \
  --domain-name bridge.example.com \
  --validation-method DNS \
  --query CertificateArn --output text
```

Complete DNS validation before deploying.

### 4. Create a managed prefix list

This gates **all** NLB ingress — the web UI and every native listener. Native
protocols can carry cleartext credentials, so keep the list tight.

```bash
aws ec2 create-managed-prefix-list \
  --prefix-list-name britive-bridge-clients \
  --address-family IPv4 \
  --max-entries 50 \
  --entries 'Cidr=203.0.113.10/32,Description=office-egress' \
  --query 'PrefixList.PrefixListId' --output text
```

Entries can be changed later with `aws ec2 modify-managed-prefix-list` — no
stack update required.

---

## Step 5: Deploy the ECS Stack

### Via AWS CLI

Copy `params.example.json`, fill it in, then:

```bash
aws cloudformation create-stack \
  --stack-name britive-bridge \
  --template-body file://ecs-fargate-nlb.yaml \
  --parameters file://params.example.json \
  --capabilities CAPABILITY_NAMED_IAM

aws cloudformation wait stack-create-complete --stack-name britive-bridge
```

Monitor progress:

```bash
aws cloudformation describe-stack-events \
  --stack-name britive-bridge \
  --query 'StackEvents[0:10].[Timestamp,ResourceStatus,ResourceType,ResourceStatusReason]' \
  --output table
```

### Via AWS Console

1. **CloudFormation → Create stack → With new resources**
2. **Upload a template file** → select `ecs-fargate-nlb.yaml`
3. Enter a stack name and fill in the parameters
4. Acknowledge **"may create IAM resources with custom names"**
5. **Submit**

---

## Step 6: Point DNS at the Load Balancer

```bash
aws cloudformation describe-stacks \
  --stack-name britive-bridge \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDnsName`].OutputValue' \
  --output text
```

Create a CNAME (or a Route 53 alias) from your Bridge hostname to that value.
The name **must match the ACM certificate**, or browsers reject the TLS
handshake on 443.

---

## Step 7: Verify

### The service is running

```bash
aws ecs describe-services \
  --cluster britive-bridge-cluster \
  --services britive-bridge-service \
  --query 'services[0].{running:runningCount,desired:desiredCount}'
```

### Startup looks healthy

```bash
aws logs tail /ecs/britive-bridge --since 10m --follow
```

A healthy start ends with a line naming the enabled protocols:

```md
msg="SSH proxy listening" addr=:2222
msg="MySQL proxy listening" addr=:3306
msg="Britive Bridge started" api=:8080 ssh_browser_enabled=true ...
```

### The web tier answers

```bash
curl -sI https://bridge.example.com/readyz
```

### The broker registered

In the Britive console under **Admin → Access Broker → Broker Pools**, the
broker appears in the pool matching `BrokerAuthToken`.

---

## Updating the Deployment

### Changing Bridge configuration

`bridge.yaml` lives inside the image, so a config change is an image change:

```bash
cd ../../custom-image
# edit bridge.yaml, then rebuild with a NEW tag - tags are immutable
docker build --platform linux/arm64 \
  --build-arg BASE_IMAGE=britive/bridge:v2.1.0 \
  --build-arg BAKE_CONFIG=true --build-arg WITH_RDS_CA=true \
  -t "<registry>/britive/bridge:v2.1.0-r2" .
docker push "<registry>/britive/bridge:v2.1.0-r2"
```

Then update **only** `ImageUri`:

```bash
aws cloudformation update-stack \
  --stack-name britive-bridge \
  --use-previous-template \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters \
      ParameterKey=ImageUri,ParameterValue=<new-image-uri> \
      ParameterKey=VpcId,UsePreviousValue=true \
      ParameterKey=PublicSubnetIds,UsePreviousValue=true \
      ParameterKey=NativeAccessCidr,UsePreviousValue=true \
      ParameterKey=NativeClientPrefixListId,UsePreviousValue=true \
      ParameterKey=CpuArchitecture,UsePreviousValue=true \
      ParameterKey=TaskCpu,UsePreviousValue=true \
      ParameterKey=TaskMemory,UsePreviousValue=true \
      ParameterKey=DbHost,UsePreviousValue=true \
      ParameterKey=DbPort,UsePreviousValue=true \
      ParameterKey=DbSecretArn,UsePreviousValue=true \
      ParameterKey=BrokerTenantSubdomain,UsePreviousValue=true \
      ParameterKey=BrokerAuthToken,UsePreviousValue=true \
      ParameterKey=EncryptionKeyB64,UsePreviousValue=true \
      ParameterKey=BrokerSSHPrivateKey,UsePreviousValue=true \
      ParameterKey=AcmCertificateArn,UsePreviousValue=true \
      ParameterKey=StackNamePrefix,UsePreviousValue=true
```

> **Always pass `UsePreviousValue=true` for every parameter you are not
> changing.** Re-submitting the parameter file sends whatever is in that file,
> including empty strings for the `NoEcho` secrets — which replaces the stored
> encryption key, broker token and SSH key with blanks. The encryption key in
> particular cannot be recovered.

### Upgrading the Bridge version

```bash
cd ../../custom-image
docker build --platform linux/arm64 \
  --build-arg BASE_IMAGE=britive/bridge:v2.1.1 \
  --build-arg BAKE_CONFIG=true --build-arg WITH_RDS_CA=true \
  -t "<registry>/britive/bridge:v2.1.1-r1" .
```

Then update `ImageUri` as above. Check the
[release notes](https://learn.britive.com/releases/) first — a new version may
apply one-way schema migrations to the datastore, so take a database snapshot
if you need a rollback path.

### During a deployment

ECS starts the new task before draining the old one, so **both brokers stay
registered with your tenant for several minutes** and Britive load-balances
across them. A checkout routed to the draining task runs the old image. Wait for
`runningCount: 1` before judging a test result.

---

## Parameter Reference

| Parameter | Required | Default | Description |
| --------- | -------- | ------- | ----------- |
| `VpcId` | Yes | — | VPC for the task, NLB and EFS mount targets |
| `PublicSubnetIds` | Yes | — | Two public subnets in different AZs |
| `NativeClientPrefixListId` | Yes | — | Managed prefix list (`pl-…`) of allowed **public** client IPs |
| `ImageUri` | Yes | — | Your ECR image from Step 3 |
| `AcmCertificateArn` | Yes | — | ACM cert for the Bridge hostname, same region as the NLB |
| `DbHost` | Yes | — | PostgreSQL endpoint |
| `DbSecretArn` | Yes | — | Secrets Manager secret containing a `password` key |
| `BrokerTenantSubdomain` | Yes | — | Britive tenant subdomain |
| `BrokerAuthToken` | Yes | — | Broker pool token (`NoEcho`) |
| `EncryptionKeyB64` | Yes | — | `openssl rand -base64 32` (`NoEcho`, **permanent**) |
| `NativeAccessCidr` | No | `10.0.0.0/8` | In-VPC CIDR allowed to reach task ports; set to your VPC CIDR |
| `CpuArchitecture` | No | `ARM64` | Must match the image `PLATFORM` |
| `TaskCpu` / `TaskMemory` | No | `1024` / `2048` | Fargate task size |
| `DbPort` | No | `5432` | PostgreSQL port |
| `BrokerSSHPrivateKey` | No | `""` | Broker SSH key for SSH checkouts (`NoEcho`) |
| `StackNamePrefix` | No | `britive-bridge-v2` | Prefix for named resources |

### Outputs

| Output | Use |
| ------ | --- |
| `LoadBalancerDnsName` | CNAME target for your Bridge hostname |
| `BridgeUrl` | Base URL of the deployment |
| `ClusterName` / `ServiceName` | For `aws ecs` commands |
| `DataFileSystemId` | EFS holding recordings and generated certs |
| `EncryptionKeySecretArn` | Where the encryption key is stored |
| `BrokerSSHKeySecretArn` | Where the broker SSH key is stored |

---

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Task starts then stops repeatedly | `tenant` empty in `bridge.yaml` | Set it, rebuild with a new tag, update `ImageUri` |
| `at least one protocol must be enabled` | All protocols off in `bridge.yaml` | Enable at least one, rebuild |
| Task stops immediately, no app logs | Image architecture ≠ `CpuArchitecture` | Rebuild with the matching `PLATFORM`, or flip the parameter |
| `failed to apply schema migrations` | Postgres unreachable or credentials wrong | Check the DB security group allows the task SG on 5432; confirm the secret has a `password` key |
| Target group unhealthy | Health check failing | Check `/readyz` in the task logs; confirm `NativeAccessCidr` covers the NLB ENIs |
| Browser TLS error on 443 | Hostname does not match the ACM cert | Use the certificate's domain, or reissue for the name in use |
| Native client times out, browser works | Client IP absent from the prefix list | Add it with `aws ec2 modify-managed-prefix-list` |
| `denied` pushing to ECR | Tag already exists (immutable) | Push a new tag; never reuse |
| Recordings lost after redeploy | Writing outside `/data` | `recording.output_dir` must stay under `/data` (EFS) |

---

## Cleanup

```bash
aws cloudformation delete-stack --stack-name britive-bridge
aws cloudformation wait stack-delete-complete --stack-name britive-bridge
```

The ECR repository is a separate stack and must be emptied before deletion:

```bash
aws ecr batch-delete-image \
  --repository-name britive/bridge \
  --image-ids "$(aws ecr list-images --repository-name britive/bridge --query 'imageIds[*]' --output json)"

aws cloudformation delete-stack --stack-name britive-bridge-ecr
```

The database, ACM certificate and prefix list were created outside these
templates and are not removed.

---

## Further Reading

- [Britive Bridge documentation](https://learn.britive.com/bridge/)
- [Deploying on AWS ECS](https://learn.britive.com/bridge/deploy/aws-ecs/)
- [Configuration reference](https://learn.britive.com/bridge-files/bridge.reference.yaml)
- [Access Broker examples](https://github.com/britive/access-broker-examples)
- [Bridge v1.x deployment options](../../v1/) — for older Bridge releases
- [Platform setup](../../platform-setup/) — run first; creates the broker pool and token
