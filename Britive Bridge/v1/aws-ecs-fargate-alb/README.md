# Britive Bridge — AWS ECS Fargate + ALB (ACM TLS)

> **Legacy — Bridge v1.x.** Do not use this for new deployments. New
> implementations should use [Bridge v2](../../v2/), which is the current
> release line. This option remains for existing v1 deployments only.
>
> Images are pinned to `britive/bridge:v1.0.2`. Do **not** use
> `britive/bridge:latest` — it now tracks v2.x, which cannot run on these
> templates.

Run Bridge on AWS ECS Fargate behind an internet-facing **Application Load
Balancer (ALB)** that **terminates TLS with an ACM certificate** on port 443.
This is the recommended production path on AWS when you have a custom domain and
want a browser-trusted certificate.

The ALB re-encrypts to the container over HTTPS:8080; the container keeps its
self-signed cert and the ALB target group is configured to **not verify** it.

## What it deploys

CloudFormation template `ecs-fargate-alb.yaml` creates the same core stack as
the [NLB option](../aws-ecs-fargate-nlb/) (ECS cluster/task/service, EFS, IAM,
CloudWatch logs, broker-token secret), with an **ALB instead of an NLB**:

- An **ALB** with:
  - HTTPS:443 listener using your **ACM certificate** (TLS 1.2/1.3 policy)
  - HTTP:80 listener that **redirects to 443**
  - An HTTPS target group on 8080 with health checks on `/api/health`
- A dedicated **ALB security group** (443 + 80 from your `IngressCidr`); the
  task SG only accepts 8080 **from the ALB SG**

Traffic path: `client → ALB:443 (ACM TLS) → task:8080 (HTTPS, cert not verified)`.

## Prerequisites

- AWS CLI v2 with credentials that can create ECS/EFS/ELB/IAM/Logs
- A **VPC** and **two public subnets** in different AZs
- An **ACM certificate** in the **same region** as the ALB, covering your
  domain (e.g. `bridge.example.com` or `*.example.com`)
- A DNS zone where you can create an ALIAS/CNAME to the ALB
- Completed [platform setup](../../platform-setup/)

## Configure

```bash
cp params.example.json params.json
```

Edit `params.json` — same parameters as the NLB option, **plus**:

| Parameter | Notes |
|-----------|-------|
| `AcmCertificateArn` | ARN of your ACM cert, same region as the ALB: `arn:aws:acm:<region>:<account-id>:certificate/<id>` |
| `DomainName` | DNS name users will use (e.g. `bridge.example.com`) — makes the `BridgeUrl` output ready to paste. Optional. |

> Keep `params.json` out of source control (broker token + cert ARN).

## Deploy

```bash
aws cloudformation deploy \
  --stack-name britive-bridge \
  --template-file ecs-fargate-alb.yaml \
  --parameter-overrides file://params.json \
  --capabilities CAPABILITY_NAMED_IAM
```

## After deploy

```bash
aws cloudformation describe-stacks --stack-name britive-bridge \
  --query "Stacks[0].Outputs" --output table
```

1. Take `LoadBalancerDnsName` from the outputs and create a **DNS ALIAS/CNAME**
   record for your domain (e.g. `bridge.example.com`) pointing at it.
2. Use `https://bridge.example.com` as your `BRIDGE_URL` and make sure the
   Britive Bridge **resource** uses that URL — re-run
   `platform-setup/quick-setup.py` with it (updates the resource in place),
   or edit the resource in the Britive UI.
3. Verify:

   ```bash
   curl -sf https://bridge.example.com/api/health
   ```

   (No `-k` needed now — the ALB serves a trusted ACM cert.)

## Notes

- The ALB→container hop stays encrypted (HTTPS:8080) but skips CA verification,
  which is why the container's self-signed cert is fine. Do not set
  `TLS_CERT_FILE`/`TLS_KEY_FILE` on the container for this setup.
- Health checks hit `/api/health` and expect HTTP 200.
- Tighten `IngressCidr` to known client ranges for production.

## Teardown

```bash
aws cloudformation delete-stack --stack-name britive-bridge
```

> The broker-token secret is retained with a recovery window after stack
> deletion. To redeploy the same stack name immediately, force-delete it first:
> `aws secretsmanager delete-secret --secret-id britive-bridge/broker/auth-token --force-delete-without-recovery`
