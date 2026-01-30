# Britive Access Broker - AWS ECS Fargate Deployment

This directory contains everything needed to deploy the Britive Access Broker on AWS ECS Fargate (serverless container orchestration).

## Overview

The Britive Access Broker enables secure, just-in-time access management through the Britive platform. This deployment uses AWS ECS Fargate for serverless container orchestration, eliminating the need to manage underlying EC2 instances.

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

3. **Britive Broker Pool Token** from the Britive console
   - Navigate to: System Administration > Broker Pools
   - Create a new pool or select an existing one
   - Copy the broker pool token

4. **britive-broker-1.0.0.jar** file in this directory

5. **VPC with subnets** (default VPC works, or specify custom VPC)

## Quick Start

### Option 1: Automated Deployment (Recommended)

1. Copy the broker JAR file to this directory:
   ```bash
   cp /path/to/britive-broker-1.0.0.jar .
   ```

2. Edit `deploy.sh` and set your configuration:
   ```bash
   BRITIVE_TOKEN="your-britive-token-here"
   AWS_REGION="us-west-2"                    # Your AWS region
   ECS_CLUSTER_NAME="britive-broker-cluster" # Cluster name
   DESIRED_COUNT=2                            # Number of tasks
   ```

3. Run the deployment script:
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```

The script will:
- Validate all prerequisites
- Create ECR repository and push the container image
- Create IAM roles for ECS tasks
- Store the Britive token in AWS Secrets Manager
- Create CloudWatch log group
- Register the ECS task definition
- Create ECS cluster and service
- Deploy the specified number of tasks

### Option 2: Manual Deployment

1. **Create ECR Repository**:
   ```bash
   aws ecr create-repository --repository-name britive-broker
   ```

2. **Build and push Docker image**:
   ```bash
   # Login to ECR
   aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com

   # Build image
   docker build --platform linux/amd64 -t britive-broker:latest .

   # Tag and push
   docker tag britive-broker:latest <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/britive-broker:latest
   docker push <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/britive-broker:latest
   ```

3. **Create Secrets Manager secret**:
   ```bash
   aws secretsmanager create-secret \
       --name britive-broker/token \
       --secret-string '{"britive-token":"your-token-here"}'
   ```

4. **Create IAM roles** (see IAM section below)

5. **Update task-definition.json** with your values

6. **Register task definition**:
   ```bash
   aws ecs register-task-definition --cli-input-json file://task-definition.json
   ```

7. **Create cluster and service**:
   ```bash
   aws ecs create-cluster --cluster-name britive-broker-cluster

   aws ecs create-service \
       --cluster britive-broker-cluster \
       --service-name britive-broker-service \
       --task-definition britive-broker \
       --desired-count 2 \
       --launch-type FARGATE \
       --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
   ```

## Configuration

### Environment Variables

| Variable | Description | Required | Source |
|----------|-------------|----------|--------|
| `BRITIVE_TOKEN` | Broker pool authentication token | Yes | Secrets Manager |
| `KUBECONFIG` | Path to kubeconfig | Auto | Container |
| `KUBECONFIG_BASE64` | Base64-encoded kubeconfig (for external clusters) | No | Task definition |
| `EKS_CLUSTER_NAME` | EKS cluster name (auto-configures kubectl) | No | Task definition |
| `AWS_REGION` | AWS region for EKS access | No | Task definition |

### Resource Configuration

| Resource | Value | Description |
|----------|-------|-------------|
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
|------|-------------|
| `deploy.sh` | Automated deployment script |
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
6. **Secrets Manager Secret** (`britive-broker/token`) - Stores Britive token
7. **CloudWatch Log Group** (`/ecs/britive-broker`) - Container logs
8. **Security Group** (`britive-broker-sg`) - Network security

## IAM Permissions

### Task Execution Role (`ecsTaskExecutionRole`)
Required for ECS to pull images and retrieve secrets:
- `AmazonECSTaskExecutionRolePolicy` (AWS managed)
- Secrets Manager access for the Britive token

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
Provide a base64-encoded kubeconfig:
```json
{
  "name": "KUBECONFIG_BASE64",
  "value": "base64-encoded-kubeconfig-here"
}
```

Generate the base64 value:
```bash
cat ~/.kube/config | base64
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

### View in AWS Console
```
https://us-west-2.console.aws.amazon.com/ecs/home?region=us-west-2#/clusters/britive-broker-cluster/services
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

4. **Network timeout**: Ensure security group allows outbound HTTPS (443)

5. **Task stuck in PENDING**: Check subnet has available IP addresses and internet access

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

# Delete secret
aws secretsmanager delete-secret --secret-id britive-broker/token --force-delete-without-recovery --region us-west-2

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

1. **Secrets**: Britive token stored in Secrets Manager (encrypted at rest)
2. **Network**: Use private subnets with NAT Gateway for production
3. **IAM**: Follow least-privilege principle for task roles
4. **Logging**: CloudWatch logs are encrypted by default
5. **Image scanning**: Enable ECR image scanning for vulnerabilities

## Support

For issues with:
- **Britive Platform**: Contact Britive support
- **AWS ECS/Fargate**: Check AWS documentation or contact AWS support
- **This deployment**: Check the troubleshooting section above
