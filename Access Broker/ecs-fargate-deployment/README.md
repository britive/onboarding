# DRAFT - Beta Deployment strategy


# Britive Access Broker - AWS ECS Fargate Deployment

This directory contains everything needed to deploy the Britive Access Broker on AWS ECS Fargate (serverless container orchestration).

## Overview

The Britive Access Broker enables secure, just-in-time access management through the Britive platform. This deployment uses AWS ECS Fargate for serverless container orchestration, eliminating the need to manage underlying EC2 instances.

**Key Features:**

- All secrets stored securely in AWS Secrets Manager
- Support for multiple secrets with easy management
- Secrets available as environment variables and files at runtime
- Easy secret rotation without code changes

## Prerequisites

Before deploying, ensure you have:

1. **AWS CLI** installed and configured

   ```bash
   # Install AWS CLI
   # macOS
   brew install awscli

   # Linux
   pip install awscli

   # Configure credentials
   aws configure
   ```

2. **Docker** installed and running

   ```bash
   # Verify Docker is running
   docker info
   ```

3. **jq** installed (for JSON processing)

   ```bash
   # macOS
   brew install jq

   # Linux
   apt install jq
   ```

4. **Britive Broker Pool Token** from the Britive console
   - Navigate to: System Administration > Broker Pools
   - Create a new pool or select an existing one
   - Copy the broker pool token

5. **britive-broker-1.0.0.jar** file in this directory

6. **VPC with subnets** (default VPC works, or specify custom VPC)

## Quick Start

### Option 1: Using secrets.json (Recommended)

1. Copy the broker JAR file to this directory:

   ```bash
   cp /path/to/britive-broker-1.0.0.jar .
   ```

2. Edit `secrets.json` and configure your secrets:

   ```json
   {
     "secrets": {
       "BRITIVE_TOKEN": {
         "description": "Britive broker pool authentication token",
         "value": "your-actual-token-here",
         "required": true,
         "inject_as": "env"
       }
     },
     "custom_secrets": {
       "MY_API_KEY": "optional-api-key-value"
     }
   }
   ```

3. Run the deployment script:

   ```bash
   chmod +x deploy.sh manage-secrets.sh
   ./deploy.sh
   ```

### Option 2: Direct Token Configuration

1. Copy the broker JAR file:

   ```bash
   cp /path/to/britive-broker-1.0.0.jar .
   ```

2. Edit `deploy.sh` and set your token directly:

   ```bash
   BRITIVE_TOKEN="your-britive-token-here"
   AWS_REGION="us-west-2"
   ```

3. Run the deployment:

   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

## Secrets Management

All secrets are stored in AWS Secrets Manager under the prefix `britive-broker/secrets/`. This provides:

- **Encryption at rest** using AWS KMS
- **Audit logging** via CloudTrail
- **Fine-grained IAM access control**
- **Easy rotation** without redeployment

### Managing Secrets with manage-secrets.sh

The `manage-secrets.sh` script provides a CLI for managing secrets:

```bash
# Make the script executable
chmod +x manage-secrets.sh

# List all secrets
./manage-secrets.sh list

# Add or update a secret
./manage-secrets.sh set MY_SECRET "secret-value" "Description of the secret"

# Get a secret value
./manage-secrets.sh get MY_SECRET

# Delete a secret
./manage-secrets.sh delete MY_SECRET

# Sync secrets from secrets.json to AWS
./manage-secrets.sh sync

# Restart ECS tasks to pick up new secrets
./manage-secrets.sh restart-tasks

# Update IAM permissions for all secrets
./manage-secrets.sh update-iam
```

### Adding New Secrets

**Method 1: Using the CLI**

```bash
# Add a new secret
./manage-secrets.sh set DATABASE_PASSWORD "my-db-password" "Database credentials"

# Update IAM permissions (if deploy.sh hasn't been run recently)
./manage-secrets.sh update-iam

# Restart tasks to load new secrets
./manage-secrets.sh restart-tasks
```

**Method 2: Using secrets.json**

1. Edit `secrets.json`:

   ```json
   {
     "secrets": {
       "BRITIVE_TOKEN": {
         "description": "Britive broker pool token",
         "value": "your-token",
         "required": true,
         "inject_as": "env"
       }
     },
     "custom_secrets": {
       "DATABASE_PASSWORD": "my-db-password",
       "API_KEY": "my-api-key"
     }
   }
   ```

2. Sync and restart:

   ```bash
   ./manage-secrets.sh sync
   ./manage-secrets.sh restart-tasks
   ```

### Accessing Secrets at Runtime

Secrets are available to the broker in two ways:

1. **Environment Variables**: All secrets are injected as environment variables with their key names

   ```bash
   # In the container
   echo $BRITIVE_TOKEN
   echo $DATABASE_PASSWORD
   ```

2. **Files**: Secrets are also written to `/root/broker/secrets/` directory

   ```bash
   # In the container
   cat /root/broker/secrets/BRITIVE_TOKEN
   cat /root/broker/secrets/DATABASE_PASSWORD
   ```

### Secret Naming Conventions

- **Standard secrets**: Use uppercase with underscores (e.g., `BRITIVE_TOKEN`, `API_KEY`)
- **Custom broker secrets**: Prefix with `BROKER_` for automatic file writing (e.g., `BROKER_CUSTOM_CONFIG`)
- **AWS Secrets Manager path**: `britive-broker/secrets/<SECRET_NAME>`

## Configuration

### Environment Variables

| Variable | Description | Required | Source |
| -------- | ----------- | -------- | ------ |
| `BRITIVE_TOKEN` | Broker pool authentication token | Yes | Secrets Manager |
| `KUBECONFIG` | Path to kubeconfig | Auto | Container |
| `KUBECONFIG_BASE64` | Base64-encoded kubeconfig (for external clusters) | No | Secrets Manager |
| `EKS_CLUSTER_NAME` | EKS cluster name (auto-configures kubectl) | No | Task definition |
| `AWS_REGION` | AWS region for EKS access | No | Task definition |
| `SECRETS_DIR` | Directory for file-based secrets | Auto | `/root/broker/secrets` |

### Resource Configuration

| Resource | Value | Description |
| -------- | ----- | ----------- |
| CPU | 512 (0.5 vCPU) | Fargate CPU units |
| Memory | 1024 MB | Fargate memory |
| Desired Count | 2 | Number of tasks |

### Networking Requirements

- **VPC**: Tasks run in your VPC
- **Subnets**: Specify subnets with internet access (for Britive connectivity)
- **Security Group**: Allow outbound HTTPS (443) for Britive API
- **Public IP**: Enabled by default (or use NAT Gateway for private subnets)

## Files

| File | Description |
| ---- | ----------- |
| `deploy.sh` | Automated deployment script |
| `manage-secrets.sh` | Secrets management CLI |
| `secrets.json` | Secrets configuration file |
| `task-definition.json` | ECS task definition template |
| `Dockerfile` | Container image definition |
| `supervisord.conf` | Process supervisor configuration |
| `start-broker.sh` | Broker startup script |
| `token-generator.sh` | Token provider script |
| `README.md` | This documentation |

## AWS Resources Created

1. **ECR Repository** (`britive-broker`) - Container image storage
2. **ECS Cluster** (`britive-broker-cluster`) - Fargate cluster
3. **ECS Service** (`britive-broker-service`) - Manages broker tasks
4. **ECS Task Definition** (`britive-broker`) - Task configuration
5. **IAM Roles**:
   - `ecsTaskExecutionRole` - For pulling images and accessing secrets
   - `britive-broker-task-role` - For broker runtime permissions
6. **Secrets Manager Secrets** (`britive-broker/secrets/*`) - All configured secrets
7. **CloudWatch Log Group** (`/ecs/britive-broker`) - Container logs
8. **Security Group** (`britive-broker-sg`) - Network security

## IAM Permissions

### Task Execution Role (`ecsTaskExecutionRole`)

Required for ECS to pull images and retrieve secrets:

- `AmazonECSTaskExecutionRolePolicy` (AWS managed)
- Secrets Manager access for all `britive-broker/secrets/*` secrets

### Task Role (`britive-broker-task-role`)

Permissions for the broker at runtime:

```json
{
  "Effect": "Allow",
  "Action": [
    "eks:DescribeCluster",
    "eks:ListClusters",
    "sts:AssumeRole"
  ],
  "Resource": "*"
}
```

**Note**: If the broker needs to manage EKS clusters, ensure the task role can assume roles that have Kubernetes RBAC permissions on those clusters.

## Managing External Kubernetes Clusters

Since ECS Fargate isn't a Kubernetes environment, the broker can manage external Kubernetes clusters in two ways:

### Option 1: EKS Clusters (Recommended for AWS)

Add environment variables to the task definition:

```json
{
  "name": "EKS_CLUSTER_NAME",
  "value": "your-eks-cluster"
},
{
  "name": "AWS_REGION",
  "value": "us-west-2"
}
```

The startup script will automatically configure kubectl for the specified EKS cluster.

### Option 2: Any Kubernetes Cluster (via kubeconfig)

Store the kubeconfig as a secret:

```bash
# Base64 encode your kubeconfig
KUBECONFIG_B64=$(cat ~/.kube/config | base64)

# Store in Secrets Manager
./manage-secrets.sh set KUBECONFIG_BASE64 "$KUBECONFIG_B64" "Kubeconfig for external cluster"

# Restart tasks
./manage-secrets.sh restart-tasks
```

## Monitoring & Troubleshooting

### View Logs

```bash
# Stream logs
aws logs tail /ecs/britive-broker --follow --region us-west-2

# View recent logs
aws logs get-log-events \
    --log-group-name /ecs/britive-broker \
    --log-stream-name ecs/britive-broker/<task-id> \
    --region us-west-2
```

### Check Service Status

```bash
# Describe service
aws ecs describe-services \
    --cluster britive-broker-cluster \
    --services britive-broker-service \
    --region us-west-2

# List running tasks
aws ecs list-tasks \
    --cluster britive-broker-cluster \
    --service-name britive-broker-service \
    --region us-west-2

# Describe specific task
aws ecs describe-tasks \
    --cluster britive-broker-cluster \
    --tasks <task-arn> \
    --region us-west-2
```

### Common Issues

1. **Task fails to start**: Check CloudWatch logs for Java errors

   ```bash
   aws logs tail /ecs/britive-broker --since 10m --region us-west-2
   ```

2. **Image pull failures**: Verify ECR repository and execution role permissions

   ```bash
   aws ecr describe-images --repository-name britive-broker --region us-west-2
   ```

3. **Secret access denied**: Check execution role has Secrets Manager permissions

   ```bash
   ./manage-secrets.sh update-iam
   ```

4. **Network timeout**: Ensure security group allows outbound HTTPS (443)

5. **Task stuck in PENDING**: Check subnet has available IP addresses and internet access

6. **Secrets not updating**: Force restart tasks after changing secrets

   ```bash
   ./manage-secrets.sh restart-tasks
   ```

## Scaling

### Manual Scaling

```bash
aws ecs update-service \
    --cluster britive-broker-cluster \
    --service britive-broker-service \
    --desired-count 4 \
    --region us-west-2
```

### Auto Scaling (Optional)

Configure Application Auto Scaling for the ECS service:

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --resource-id service/britive-broker-cluster/britive-broker-service \
    --scalable-dimension ecs:service:DesiredCount \
    --min-capacity 2 \
    --max-capacity 10

# Create scaling policy (CPU-based)
aws application-autoscaling put-scaling-policy \
    --service-namespace ecs \
    --resource-id service/britive-broker-cluster/britive-broker-service \
    --scalable-dimension ecs:service:DesiredCount \
    --policy-name cpu-scaling \
    --policy-type TargetTrackingScaling \
    --target-tracking-scaling-policy-configuration file://scaling-policy.json
```

## Cleanup

To remove the deployment:

```bash
# Delete service (stops all tasks)
aws ecs update-service \
    --cluster britive-broker-cluster \
    --service britive-broker-service \
    --desired-count 0 \
    --region us-west-2

aws ecs delete-service \
    --cluster britive-broker-cluster \
    --service britive-broker-service \
    --region us-west-2

# Delete cluster
aws ecs delete-cluster --cluster britive-broker-cluster --region us-west-2

# Delete task definition (all revisions)
TASK_DEFS=$(aws ecs list-task-definitions --family-prefix britive-broker --query "taskDefinitionArns" --output text --region us-west-2)
for td in $TASK_DEFS; do
    aws ecs deregister-task-definition --task-definition $td --region us-west-2
done

# Delete ECR repository
aws ecr delete-repository --repository-name britive-broker --force --region us-west-2

# Delete all secrets
SECRETS=$(aws secretsmanager list-secrets --filter Key=name,Values="britive-broker/secrets" --query "SecretList[*].Name" --output text --region us-west-2)
for secret in $SECRETS; do
    aws secretsmanager delete-secret --secret-id $secret --force-delete-without-recovery --region us-west-2
done

# Delete log group
aws logs delete-log-group --log-group-name /ecs/britive-broker --region us-west-2

# Delete security group
aws ec2 delete-security-group --group-name britive-broker-sg --region us-west-2

# Delete IAM roles (if created by this deployment)
aws iam delete-role-policy --role-name britive-broker-task-role --policy-name britive-broker-policy
aws iam delete-role --role-name britive-broker-task-role
```

## Cost Optimization

ECS Fargate pricing is based on vCPU and memory per second. To optimize costs:

1. **Right-size tasks**: Start with 0.5 vCPU / 1GB and adjust based on metrics
2. **Use Fargate Spot**: Add `capacityProviderStrategy` for non-critical workloads
3. **Scale based on demand**: Implement auto-scaling to reduce tasks during low usage

## Security Considerations

1. **Secrets**: All secrets stored in AWS Secrets Manager (encrypted at rest with KMS)
2. **No local secrets**: Secrets are never stored in code, environment files, or container images
3. **Network**: Use private subnets with NAT Gateway for production
4. **IAM**: Follow least-privilege principle for task roles
5. **Logging**: CloudWatch logs are encrypted by default
6. **Image scanning**: Enable ECR image scanning for vulnerabilities
7. **Secret rotation**: Update secrets via `manage-secrets.sh` and restart tasks
