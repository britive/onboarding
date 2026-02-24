# Britive Session Recording - AWS ECS Fargate Deployment

This directory contains everything needed to deploy the Britive Session Recording stack on AWS ECS Fargate. It mirrors the Docker Compose setup under `../docker/` but targets AWS-native infrastructure with EFS for recording storage, Secrets Manager for credentials, and an ALB for Guacamole web access.

## Architecture

```
Internet
    │
    ▼
[ALB :80/443]
    │
    ▼
[Guacamole :8080]  ──(service discovery)──▶  [GuacD :4822]
    │                                              │
    │  SSH session                                 │
    ▼                                              │
[Broker :22]        ◀─────────────────────────────┘
    │
    ▼
[EFS /recordings]  ◀─── [GuacSync] (optional — converts .guac → .m4v, syncs to S3)
```

| Component   | Image                          | Purpose                                    |
|-------------|--------------------------------|--------------------------------------------|
| Guacamole   | `guacamole/guacamole:1.5.5`    | Web UI — browser-based SSH/RDP sessions    |
| GuacD       | `guacamole/guacd:1.5.5`        | Native protocol daemon (libguac)           |
| Broker      | Custom (ECR)                   | Britive JIT access + SSH server            |
| GuacSync    | Custom (ECR) — optional        | Converts recordings to .m4v, syncs to S3  |

All components share an **EFS filesystem** mounted at `/recordings` for raw Guacamole recording files.

## Prerequisites

1. **AWS CLI** installed and configured

   ```bash
   aws configure        # or: export AWS_PROFILE=my-profile
   aws sts get-caller-identity   # verify
   ```

2. **Docker** installed and running

   ```bash
   docker info
   ```

3. **jq** installed

   ```bash
   brew install jq      # macOS
   apt install jq       # Linux
   ```

4. **britive-broker-\<version\>.jar** placed in `broker/`

   ```bash
   cp /path/to/britive-broker-2.0.0.jar broker/
   ```

5. **Britive Broker Pool Token** from the Britive console:
   - Navigate to: System Administration > Broker Pools
   - Create or select a pool, then copy the token

## Quick Start

### Option 1: Using secrets.json (Recommended)

1. Copy the example secrets file and fill in your values:

   ```bash
   cp secrets.json.example secrets.json
   ```

2. Edit `secrets.json`:

   ```json
   {
     "secrets": {
       "BRITIVE_TENANT": { "value": "mycompany" },
       "BRITIVE_TOKEN":  { "value": "your-token-here" },
       "JSON_SECRET_KEY": { "value": "" }
     }
   }
   ```

   > Leave `JSON_SECRET_KEY` empty — `deploy.sh` will auto-generate a secure 64-character key.

3. Place the broker JAR in `broker/`:

   ```bash
   cp /path/to/britive-broker-2.0.0.jar broker/
   ```

4. Run the deployment:

   ```bash
   chmod +x deploy.sh manage-secrets.sh
   ./deploy.sh
   ```

### Option 2: Direct configuration

Edit the CONFIGURATION section at the top of `deploy.sh` and set:

```bash
BRITIVE_TENANT="mycompany"
BRITIVE_TOKEN="your-token-here"
```

Then run `./deploy.sh`.

### Option 3: CLI flags

```bash
./deploy.sh \
  --broker-version 2.0.0 \
  --region us-west-2 \
  --cluster-name my-recording-cluster \
  --acm-cert-arn arn:aws:acm:us-west-2:123456789:certificate/abc-123
```

The script will:

- Validate prerequisites and required files
- Auto-detect the default VPC and subnets (or use the values you provide)
- Create security groups with correct inter-service rules
- Build and push the broker Docker image to ECR
- Create an EFS filesystem with an access point at `/recordings`
- Store secrets in AWS Secrets Manager under `britive/session-recording/`
- Configure Cloud Map service discovery (`guacd.britive.local`, `broker.britive.local`)
- Create an ALB and target group for Guacamole
- Register ECS task definitions for all services
- Create ECS services and wait for them to stabilize
- Print the Guacamole URL when done

## Configuration Options

### deploy.sh CONFIGURATION section

| Variable          | Default                      | Description                              |
|-------------------|------------------------------|------------------------------------------|
| `BRITIVE_TENANT`  | (placeholder)                | Britive tenant subdomain                 |
| `BRITIVE_TOKEN`   | (placeholder)                | Broker pool token                        |
| `JSON_SECRET_KEY` | (auto-generated)             | Guacamole JSON auth secret key           |
| `BROKER_VERSION`  | `2.0.0`                      | Broker JAR version                       |
| `AWS_REGION`      | `us-east-1`                  | AWS region                               |
| `CLUSTER_NAME`    | `britive-session-recording`  | ECS cluster name                         |
| `ENABLE_GUACSYNC` | `false`                      | Enable recording conversion + S3 sync    |
| `S3_BUCKET`       | (empty)                      | S3 bucket for GuacSync                   |
| `ACM_CERT_ARN`    | (empty)                      | ACM certificate ARN for HTTPS            |
| `VPC_ID`          | (auto-detect)                | VPC to deploy into                       |
| `SUBNET_IDS`      | (auto-detect)                | Comma-separated subnet IDs               |
| `DESIRED_COUNT`   | `1`                          | Number of broker task replicas           |

### CLI flags

| Flag                     | Description                                      |
|--------------------------|--------------------------------------------------|
| `--broker-version <ver>` | Override broker JAR version (default: `2.0.0`)  |
| `--region <region>`      | AWS region                                       |
| `--cluster-name <name>`  | ECS cluster name                                 |
| `--enable-guacsync`      | Enable GuacSync service                          |
| `--s3-bucket <bucket>`   | S3 bucket for GuacSync (required with above)     |
| `--acm-cert-arn <arn>`   | Enable HTTPS on ALB (creates HTTP→HTTPS redirect)|
| `--vpc-id <id>`          | Override auto-detected VPC                       |
| `--subnets <ids>`        | Override auto-detected subnets                   |
| `--use-secrets-json`     | Force load from secrets.json                     |

## Secrets Management

Secrets are stored in AWS Secrets Manager under `britive/session-recording/` and injected into ECS tasks at launch.

```bash
# List all secrets
./manage-secrets.sh list

# Add or update a secret
./manage-secrets.sh set MY_SECRET "value" "Description"

# Read a secret value
./manage-secrets.sh get BRITIVE_TOKEN

# Sync all secrets from secrets.json
./manage-secrets.sh sync

# Restart tasks to pick up new secret values
./manage-secrets.sh restart-tasks

# Update IAM permissions after adding new secrets
./manage-secrets.sh update-iam
```

### Environment variables for manage-secrets.sh

| Variable               | Default                         |
|------------------------|---------------------------------|
| `AWS_REGION`           | `us-east-1`                     |
| `ECS_CLUSTER_NAME`     | `britive-session-recording`     |
| `ECS_BROKER_SERVICE`   | `britive-session-recording-broker-service`    |
| `ECS_GUACD_SERVICE`    | `britive-session-recording-guacd-service`     |
| `ECS_GUACAMOLE_SERVICE`| `britive-session-recording-guacamole-service` |

## AWS Resources Created

| Resource                      | Name / Identifier                                         |
|-------------------------------|-----------------------------------------------------------|
| ECR repository (broker)       | `britive-session-recording/broker`                        |
| ECR repository (guacsync)     | `britive-session-recording/guacsync` (if enabled)         |
| EFS filesystem                | `britive-recordings-efs`                                  |
| ECS cluster                   | `britive-session-recording`                               |
| ECS services                  | `…-broker-service`, `…-guacd-service`, `…-guacamole-service` |
| ALB                           | `britive-session-recording-alb`                           |
| Secrets Manager secrets       | `britive/session-recording/BRITIVE_TOKEN`, etc.           |
| Cloud Map namespace           | `britive.local` (private)                                 |
| IAM roles                     | `britive-sr-execution-role`, `britive-sr-task-role`       |
| CloudWatch log groups         | `/ecs/britive-session-recording/{broker,guacd,guacamole}` |
| Security groups               | `britive-sr-{alb,guacamole,guacd,broker}-sg`              |

## Files

| File / Directory        | Description                                              |
|-------------------------|----------------------------------------------------------|
| `deploy.sh`             | Main deployment script                                   |
| `manage-secrets.sh`     | Secrets management CLI                                   |
| `secrets.json`          | Secrets configuration (fill in and keep private)         |
| `secrets.json.example`  | Template — copy to `secrets.json` to get started         |
| `broker/Dockerfile`     | Broker + SSH server container image                      |
| `broker/start-broker.sh`| Broker startup and config generation script              |
| `broker/supervisord.conf`| Process supervisor (sshd + broker)                      |
| `broker/token-generator.sh` | Token provider called by the broker                 |
| `guacsync/Dockerfile`   | GuacSync image (builds guacenc from source)              |
| `guacsync/guacsync.sh`  | Recording conversion and S3 sync loop                    |

## Monitoring and Troubleshooting

### View logs

```bash
# Broker logs
aws logs tail /ecs/britive-session-recording/broker --follow --region us-east-1

# Guacamole logs
aws logs tail /ecs/britive-session-recording/guacamole --follow --region us-east-1

# GuacD logs
aws logs tail /ecs/britive-session-recording/guacd --follow --region us-east-1
```

### Check service status

```bash
aws ecs describe-services \
  --cluster britive-session-recording \
  --services britive-session-recording-broker-service \
             britive-session-recording-guacd-service \
             britive-session-recording-guacamole-service \
  --region us-east-1
```

### List running tasks

```bash
aws ecs list-tasks \
  --cluster britive-session-recording \
  --service-name britive-session-recording-broker-service \
  --region us-east-1
```

### Common issues

1. **Guacamole can't reach GuacD** — verify service discovery is working. The `GUACD_HOSTNAME` env var is set to `guacd.britive.local`. Check the Cloud Map namespace and guacd service registration.

2. **Broker JAR not found** — ensure `broker/britive-broker-<VERSION>.jar` exists before running `deploy.sh`.

3. **ECS tasks failing to pull secrets** — run `./manage-secrets.sh update-iam` to refresh IAM permissions, then restart tasks.

4. **Recordings not appearing** — confirm EFS mount targets exist in the same subnets as your ECS tasks and security groups allow NFS (port 2049).

## Cleanup

```bash
# Remove ECS services
aws ecs update-service --cluster britive-session-recording --service britive-session-recording-broker-service   --desired-count 0 --region us-east-1
aws ecs update-service --cluster britive-session-recording --service britive-session-recording-guacd-service    --desired-count 0 --region us-east-1
aws ecs update-service --cluster britive-session-recording --service britive-session-recording-guacamole-service --desired-count 0 --region us-east-1

aws ecs delete-service --cluster britive-session-recording --service britive-session-recording-broker-service    --region us-east-1
aws ecs delete-service --cluster britive-session-recording --service britive-session-recording-guacd-service     --region us-east-1
aws ecs delete-service --cluster britive-session-recording --service britive-session-recording-guacamole-service --region us-east-1

# Delete ECS cluster
aws ecs delete-cluster --cluster britive-session-recording --region us-east-1

# Delete secrets (use with caution)
./manage-secrets.sh delete BRITIVE_TOKEN
./manage-secrets.sh delete BRITIVE_TENANT
./manage-secrets.sh delete JSON_SECRET_KEY

# Remove ECR images
aws ecr delete-repository --repository-name britive-session-recording/broker --force --region us-east-1
```

> **Note:** EFS filesystem and ALB are not deleted by these commands. Delete them manually via the AWS console or CLI if no longer needed.

## Security Considerations

1. **HTTPS**: Always use the `--acm-cert-arn` flag (or set `ACM_CERT_ARN` in `deploy.sh`) for production deployments to encrypt Guacamole web traffic.

2. **Secrets**: `secrets.json` contains sensitive values — add it to `.gitignore` and never commit it to source control.

3. **SSH**: The broker container enables root SSH login for Guacamole compatibility. Restrict broker security group ingress to only the Guacamole security group (this is done automatically by `deploy.sh`).

4. **Recordings**: Session recordings on EFS are encrypted at rest (enabled during filesystem creation). Restrict EFS access using security groups and IAM.
