# Access Broker on AWS ECS Fargate

Two CloudFormation stacks: an ECR repository for the image, and the broker
service itself. No deployment script to read through — what the stack creates
is what the template says.

| File | Purpose |
| ---- | ------- |
| `ecr-repo.yaml` | ECR repository, immutable tags, scan on push (deploy once) |
| `ecs-fargate.yaml` | Cluster, task definition, service, egress-only security group, Secrets Manager secret for the token, IAM roles, log group |
| `params.example.json` | Every parameter of `ecs-fargate.yaml` |

## What you get

```text
  VPC (your subnets)                               Britive
  +-----------------------------+                  +-------------------+
  |  ECS Fargate task           |  443 outbound    |  <tenant>         |
  |  image: your ECR copy of    | ---------------> |  .britive-app.com |
  |         ../image            |  via NAT or      +-------------------+
  |  env:  TENANT (plain)       |  public IP
  |        TOKEN  (from Secrets |
  |                Manager)     |
  +-----------------------------+
          |  CloudWatch Logs /ecs/<prefix>
```

- **No inbound path.** The security group has no ingress rule; there is no
  load balancer.
- **The token never appears on the task definition.** It lives in Secrets
  Manager and is injected at task start through `Secrets:`.
- **Non-root.** The image runs the broker as uid 1000 and the task definition
  pins `User: "1000"`.
- **Circuit breaker with rollback.** A new image that fails its health check
  is rolled back automatically.

## Prerequisites

- AWS CLI v2, Docker with buildx
- A VPC with subnets that reach the internet on 443: private subnets behind a
  NAT gateway (recommended, `AssignPublicIp=DISABLED`) or public subnets
  (`AssignPublicIp=ENABLED`)
- The broker tarballs from the Britive console in [`../image/`](../image/)
- A broker pool token (**System Administration → Brokers and Broker Pools**)

## Step 1: Create the ECR repository

```bash
aws cloudformation deploy \
  --stack-name britive-broker-ecr \
  --template-file ecr-repo.yaml
```

## Step 2: Build and push the image

```bash
cd ../image
REGISTRY=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(aws configure get region).amazonaws.com \
WITH_AWS_CLI=true \
./build-and-push.sh
# prints ImageUri=<account>.dkr.ecr.<region>.amazonaws.com/britive-broker:3.0.2-r1
```

Add `WITH_KUBECTL=true`, `WITH_PYWINRM=true` or `WITH_DB_CLIENTS=true` for the
scripts you run (see [`../image/README.md`](../image/README.md)).

## Step 3: Deploy the service

Copy `params.example.json` to `params.json` (gitignored), fill it in, then:

```bash
aws cloudformation deploy \
  --stack-name britive-broker \
  --template-file ecs-fargate.yaml \
  --parameter-overrides file://params.json \
  --capabilities CAPABILITY_NAMED_IAM
```

Or in the console: **CloudFormation → Create stack → Upload a template
file** → `ecs-fargate.yaml`, fill in the parameters, acknowledge IAM resource
creation.

## Step 4: Verify

```bash
aws ecs describe-services --cluster britive-broker-cluster --services britive-broker-service \
  --query 'services[0].{running:runningCount,desired:desiredCount,deployments:deployments[*].rolloutState}'

aws logs tail /ecs/britive-broker --since 10m --follow
```

Expect `Britive broker starting version=3.x.y` and no `Broker bootstrap
failed` lines after the first seconds. The broker appears as active in the
pool's **Brokers** tab, named after the task's hostname (the container ID).

To name brokers predictably, set `BRITIVE_BROKER_NAME_GENERATOR` to a script
baked into your image that prints a name — for example one that reads the
ECS task metadata endpoint.

## Operations

### Rotate the pool token

Create a new token on the pool, then update only that parameter:

```bash
aws cloudformation deploy \
  --stack-name britive-broker \
  --template-file ecs-fargate.yaml \
  --parameter-overrides BrokerAuthToken=<new-token> \
  --capabilities CAPABILITY_NAMED_IAM
```

`aws cloudformation deploy` keeps every parameter you do not pass. The task
definition does not change, so force a new deployment to pick the secret up:

```bash
aws ecs update-service --cluster britive-broker-cluster --service britive-broker-service --force-new-deployment
```

Delete the old token in the console once the new task shows active.

### Upgrade the broker

Rebuild and push with the new tarball (`BROKER_VERSION=3.x.y`), then:

```bash
aws cloudformation deploy --stack-name britive-broker --template-file ecs-fargate.yaml \
  --parameter-overrides ImageUri=<new-image-uri> --capabilities CAPABILITY_NAMED_IAM
```

During the rollout both tasks are registered with the pool for a minute or
two; that is expected.

### Scripts that call AWS

Set `EnableAwsBrokerScripts=true` to grant the task role EC2/RDS discovery,
SSM sessions and Secrets Manager read/write **scoped to secrets named
`<StackNamePrefix>/*`**. Store anything your scripts need (database master
credentials, SSH provisioning keys) under that prefix:

```bash
aws secretsmanager create-secret --name britive-broker/targets/db-master \
  --secret-string '{"username":"admin","password":"…"}'
```

### Kubernetes (EKS) checkouts

Build the image with `WITH_KUBECTL=true WITH_AWS_CLI=true`, pass the
cluster ARN in `EksClusterArns`, and create an EKS access entry for the task
role (`TaskRoleArn` output) with the Kubernetes permissions your scripts need.
The script then runs `aws eks update-kubeconfig --name <cluster>` before
`kubectl`.

### Shell into a task

```bash
aws ecs execute-command --cluster britive-broker-cluster --task <task-id> --container broker --interactive --command sh
```

## Parameter reference

| Parameter | Required | Default | Description |
| --------- | -------- | ------- | ----------- |
| `VpcId` | Yes | — | VPC for the task |
| `SubnetIds` | Yes | — | Subnets with a route to the internet on 443 |
| `ImageUri` | Yes | — | Your ECR image from Step 2 |
| `BrokerTenantSubdomain` | Yes | — | Britive tenant subdomain |
| `BrokerAuthToken` | Yes | — | Pool token (`NoEcho`, stored in Secrets Manager) |
| `AssignPublicIp` | No | `DISABLED` | `ENABLED` only for public subnets without NAT |
| `CpuArchitecture` | No | `ARM64` | Must match the image build |
| `TaskCpu` / `TaskMemory` | No | `256` / `512` | Size for your scripts, not the broker |
| `DesiredCount` | No | `1` | Brokers in the pool from this stack |
| `LogFormat` | No | `json` | `text` or `json` |
| `LogRetentionDays` | No | `30` | CloudWatch retention |
| `EnableAwsBrokerScripts` | No | `false` | Scoped AWS permissions for scripts |
| `EksClusterArns` | No | `""` | Clusters the task may `DescribeCluster` |
| `StackNamePrefix` | No | `britive-broker` | Resource names and the secrets prefix |

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Task stops immediately, no application log | Image architecture ≠ `CpuArchitecture` | Rebuild for the right platform or flip the parameter |
| `Broker bootstrap failed … dial tcp … i/o timeout` | No route to the internet | Private subnets need a NAT gateway; or set `AssignPublicIp=ENABLED` on public subnets |
| `Broker bootstrap failed … 401` / `403` | Wrong or deactivated token | Create a new token, update `BrokerAuthToken`, force a new deployment |
| `ResourceInitializationError: unable to pull secrets` | Execution role cannot read the secret | The stack grants it; check the account's Secrets Manager resource policies / SCPs |
| Script fails with `AccessDenied` calling AWS | `EnableAwsBrokerScripts` false, or secret outside the prefix | Enable it; name secrets `<StackNamePrefix>/…` |
| Broker shows in the console under a random name | Hostname is the container ID | Bake a `BRITIVE_BROKER_NAME_GENERATOR` script into the image |

## Cleanup

```bash
aws cloudformation delete-stack --stack-name britive-broker
aws cloudformation wait stack-delete-complete --stack-name britive-broker
aws ecr batch-delete-image --repository-name britive-broker \
  --image-ids "$(aws ecr list-images --repository-name britive-broker --query 'imageIds[*]' --output json)"
aws cloudformation delete-stack --stack-name britive-broker-ecr
```

The pool token secret is deleted with the stack (30-day recovery window);
deactivate the token in the console as well.
