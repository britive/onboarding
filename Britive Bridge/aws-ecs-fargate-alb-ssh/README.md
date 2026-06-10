# Britive Bridge — AWS ECS Fargate + ALB + SSH key

Everything in the [ALB option](../aws-ecs-fargate-alb/), **plus** an SSH private
key delivered to the broker so it can SSH into your EC2 instances. The key is
stored in **AWS Secrets Manager** and injected into the container at runtime —
it is **never baked into the image**.

Use this when Bridge brokers SSH sessions to EC2 hosts and the broker needs a
private key to authenticate.

## What it adds over the ALB option

CloudFormation template `ecs-fargate-alb-ssh.yaml` adds:

- A **Secrets Manager secret** holding the PEM-encoded private key (alongside
  the broker auth token secret that all variants create)
- Execution-role permission to **read those secrets** at task start
- A container `Secrets` mapping that injects the key as `SSH_PRIVATE_KEY`
- A container entrypoint that writes the key to `/home/bridge/.ssh/id_ed25519`
  (mode `600`) before starting Bridge
- Task-role permissions for **ECS Exec** (SSM) and CloudWatch Logs

Everything else (ALB + ACM TLS, EFS, security groups) matches the ALB option.

## Prerequisites

- All prerequisites from the [ALB option](../aws-ecs-fargate-alb/)
- An **SSH key pair** whose **public** key is installed on the target EC2
  instances (in the relevant user's `authorized_keys`). You provide the
  **private** key to this stack.

## Configure

```bash
cp params.example.json params.json
```

Same parameters as the ALB option, **plus**:

| Parameter | Notes |
|-----------|-------|
| `BrokerSSHPrivateKey` | PEM-encoded private key (ed25519 or RSA). **Highly sensitive.** |

### Filling in the private key safely

Avoid pasting the key into a file by hand — JSON requires the newlines to be
escaped, and doing that manually corrupts the key. Let `jq` do the escaping:

```bash
jq --arg key "$(cat ~/.ssh/bridge_ed25519)" \
  'map(if .ParameterKey == "BrokerSSHPrivateKey" then .ParameterValue = $key else . end)' \
  params.example.json > params.json
# fill in the remaining placeholder values, then delete params.json after deploy
```

Do **not** pre-escape the key (e.g. with `awk`/`sed`) before passing it to
`jq` — it gets escaped twice and the container receives literal `\n` text
instead of newlines, breaking SSH authentication.

> **Never commit `params.json`** with a real key. Delete it locally once the
> stack is up — the key lives in Secrets Manager from then on. To rotate, update
> the secret value (or redeploy with a new key) and restart the service.

## Deploy

```bash
aws cloudformation deploy \
  --stack-name britive-bridge \
  --template-file ecs-fargate-alb-ssh.yaml \
  --parameter-overrides file://params.json \
  --capabilities CAPABILITY_NAMED_IAM
```

## After deploy

Same as the ALB option (DNS record → `LoadBalancerDnsName`, set `BRIDGE_URL`,
verify `/api/health`). Additional output:

- `BrokerSSHKeySecretArn` — the Secrets Manager ARN holding the broker key.

Confirm the broker can reach a target host by checking out an SSH session
through Bridge, or inspect the running task with ECS Exec:

```bash
aws ecs execute-command --cluster <ClusterName> --task <task-id> \
  --container bridge --interactive --command "/bin/sh"
# inside: ls -l /home/bridge/.ssh/id_ed25519   (should be mode 600)
```

## Security notes

- The private key is marked `NoEcho` in CloudFormation and stored only in
  Secrets Manager; it is not written to CloudWatch.
- Scope the target instances' `authorized_keys` to the minimum needed; prefer a
  dedicated, low-privilege broker user.
- Rotate the key periodically by updating the secret and restarting the service.

## Teardown

```bash
aws cloudformation delete-stack --stack-name britive-bridge
```

> The Secrets Manager secrets are retained with a recovery window after stack
> deletion. To redeploy the same stack name immediately, force-delete them first:
>
> ```bash
> aws secretsmanager delete-secret --secret-id britive-bridge/broker/ssh-private-key --force-delete-without-recovery
> aws secretsmanager delete-secret --secret-id britive-bridge/broker/auth-token --force-delete-without-recovery
> ```
