# Britive Bridge — AWS ECS Fargate + NLB

Run Bridge serverlessly on AWS ECS Fargate, fronted by an internet-facing
**Network Load Balancer (NLB)** that passes TLS straight through to the
container. **No ACM certificate required** — the container's own self-signed
cert terminates TLS.

Use this when you want the simplest AWS production path and don't have (or don't
want to manage) an ACM certificate and custom domain. If you do want a real cert
on a custom domain, use the [ALB option](../aws-ecs-fargate-alb/) instead.

## What it deploys

CloudFormation template `ecs-fargate-nlb.yaml` creates:

- ECS **cluster**, **task definition**, and **service** (Fargate, ARM64 by default)
- An internet-facing **NLB** with a TCP:443 listener → target group TCP:8080
- **EFS** file system + access point + mount targets, mounted at `/data` (encrypted, transit encryption on)
- **Security groups** (NLB allows 443 from your `IngressCidr`; task allows 8080
  only from the NLB security group — covers forwarded traffic and NLB health
  checks; EFS allows 2049 from the task)
- **IAM** execution + task roles
- A **Secrets Manager secret** for the broker token (`<prefix>/broker/auth-token`),
  injected into the container at task start
- A **CloudWatch** log group (30-day retention)
- ECS Exec enabled for debugging

Traffic path: `client → NLB:443 (TCP passthrough) → task:8080 (container self-signed TLS)`.

## Prerequisites

- AWS CLI v2 configured with credentials that can create ECS/EFS/ELB/IAM/Logs
- A **VPC** and **two public subnets** in different AZs
- Completed [platform setup](../platform-setup/) — you need
  `BrokerTenantSubdomain` and `BrokerAuthToken`
- IAM permission to create the resources above (CAPABILITY_NAMED_IAM)

## Configure

Copy the example params and fill in real values:

```bash
cp params.example.json params.json
```

Edit `params.json`:

| Parameter | Notes |
|-----------|-------|
| `StackNamePrefix` | Prefix for named resources (default `britive-bridge`) |
| `VpcId` | Your VPC ID |
| `PublicSubnetIds` | **Two** public subnet IDs, comma-separated |
| `IngressCidr` | CIDR allowed to reach Bridge (default `0.0.0.0/0` — tighten this) |
| `ImageUri` | Container image (default `britive/bridge:latest`) |
| `CpuArchitecture` | `ARM64` (default) or `X86_64` — must match the image |
| `TaskCpu` / `TaskMemory` | Fargate sizing |
| `DesiredCount` | Number of tasks (1–4) |
| `BrokerTenantSubdomain` | From platform setup |
| `BrokerAuthToken` | From platform setup — **secret** |

> Keep `params.json` out of source control (it contains the broker token).

## Deploy

```bash
aws cloudformation deploy \
  --stack-name britive-bridge \
  --template-file ecs-fargate-nlb.yaml \
  --parameter-overrides file://params.json \
  --capabilities CAPABILITY_NAMED_IAM
```

> `deploy` expects `ParameterKey/ParameterValue` pairs via
> `--parameter-overrides`. If you prefer `create-stack`/`update-stack`, pass
> the same file with `--parameters file://params.json`.

## After deploy

Get the outputs (NLB DNS name and the Bridge URL):

```bash
aws cloudformation describe-stacks --stack-name britive-bridge \
  --query "Stacks[0].Outputs" --output table
```

Key outputs:

- `BridgeUrl` — use this as your `BRIDGE_URL` (point a DNS record at
  `LoadBalancerDnsName` if you want a friendly hostname)
- `LoadBalancerDnsName`, `ClusterName`, `ServiceName`, `DataFileSystemId`

Make sure the Bridge **resource** in Britive (from platform setup) uses this
URL — re-run `platform-setup/quick-setup.py` with the new URL (it updates the
resource in place), or edit the resource in the Britive UI. Then verify
(`<LoadBalancerDnsName>` is the output from the table above):

```bash
curl -sfk https://<LoadBalancerDnsName>/api/health
```

## Notes

- Because the NLB passes TCP through, browsers will see the container's
  **self-signed certificate** and warn. For a trusted cert on a custom domain,
  use the [ALB option](../aws-ecs-fargate-alb/).
- EFS keeps `/data` durable across task restarts and across AZs.
- Tighten `IngressCidr` to your corporate egress ranges for production.

## Teardown

```bash
aws cloudformation delete-stack --stack-name britive-bridge
```

> The broker-token secret is retained with a recovery window after stack
> deletion. To redeploy the same stack name immediately, force-delete it first:
> `aws secretsmanager delete-secret --secret-id britive-bridge/broker/auth-token --force-delete-without-recovery`
