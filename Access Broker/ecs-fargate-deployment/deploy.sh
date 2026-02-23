#!/bin/bash

# Britive Access Broker - AWS ECS Fargate Deployment Script
# This script automates the deployment of Britive Access Broker to AWS ECS Fargate
#
# Prerequisites:
# 1. AWS CLI installed and configured
# 2. Docker installed and running
# 3. britive-broker-1.0.0.jar in current directory
#
# Usage:
# 1. Set configuration variables below
# 2. Run: ./deploy.sh

set -e

#==============================================================================
# CONFIGURATION - MODIFY THESE VALUES
#==============================================================================

# Secrets Configuration
# Option 1: Set BRITIVE_TOKEN directly here (for simple deployments)
# Option 2: Use secrets.json file for multiple secrets (recommended)
#
# Get your Britive token from: Britive Console > System Administration > Broker Pools > Create/Select Pool > Token
BRITIVE_TOKEN="your-britive-token-here"

# Secrets are stored in AWS Secrets Manager under this prefix
SECRETS_PREFIX="britive-broker/secrets"

# AWS Configuration
AWS_REGION="${AWS_REGION:-us-west-2}"

# ECS Configuration
ECS_CLUSTER_NAME="britive-broker-cluster"
ECS_SERVICE_NAME="britive-broker-service"
ECR_REPO_NAME="britive-broker"
TASK_FAMILY="britive-broker"

# Networking - Set these to your VPC configuration
# Leave empty to auto-detect default VPC
VPC_ID=""
SUBNET_IDS=""          # Comma-separated subnet IDs (e.g., "subnet-xxx,subnet-yyy")
SECURITY_GROUP_ID=""   # Security group for the tasks

# Number of tasks (replicas)
DESIRED_COUNT=2

#==============================================================================
# DO NOT MODIFY BELOW THIS LINE
#==============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for secrets.json first - it determines whether BRITIVE_TOKEN must be set here
# (Option 1: secrets.json is the recommended path; Option 2: token set directly in this script)
USE_SECRETS_FILE=false
if [ -f "secrets.json" ]; then
    log_success "Found secrets.json - will use for secrets configuration"
    USE_SECRETS_FILE=true
fi

# Check if token is configured (only required when NOT using secrets.json)
if [ "$USE_SECRETS_FILE" = false ] && [ "$BRITIVE_TOKEN" == "your-britive-token-here" ]; then
    log_error "Please set BRITIVE_TOKEN in this script, or create a secrets.json file (recommended)"
    log_info "Get your token from: Britive Console > System Administration > Broker Pools"
    log_info "See README.md Option 1 for the secrets.json approach"
    exit 1
fi

# Check for required files
log_info "Checking required files..."
REQUIRED_FILES=("britive-broker-1.0.0.jar" "supervisord.conf" "start-broker.sh" "token-generator.sh" "task-definition.json")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "$file not found in current directory"
        exit 1
    fi
done
log_success "Required files found"

# Check AWS CLI
log_info "Checking AWS CLI..."
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install it:"
    log_info "  macOS: brew install awscli"
    log_info "  Linux: pip install awscli"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run: aws configure"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_success "AWS CLI configured - Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"

# Check jq
log_info "Checking jq..."
if ! command -v jq &> /dev/null; then
    log_error "jq not found. Please install it:"
    log_info "  macOS: brew install jq"
    log_info "  Linux: apt install jq"
    exit 1
fi
log_success "jq is available"

# Check Docker
log_info "Checking Docker..."
if ! command -v docker &> /dev/null; then
    log_error "Docker not found. Please install Docker Desktop"
    exit 1
fi

if ! docker info &> /dev/null; then
    log_error "Docker daemon not running. Please start Docker Desktop"
    exit 1
fi
log_success "Docker is running"

# Auto-detect VPC if not specified
if [ -z "$VPC_ID" ]; then
    log_info "Auto-detecting default VPC..."
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
        log_error "No default VPC found. Please set VPC_ID in this script."
        exit 1
    fi
    log_success "Using default VPC: $VPC_ID"
fi

# Auto-detect subnets if not specified
if [ -z "$SUBNET_IDS" ]; then
    log_info "Auto-detecting subnets..."
    SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query "Subnets[*].SubnetId" --output text --region "$AWS_REGION" | tr '\t' ',')

    if [ -z "$SUBNET_IDS" ]; then
        log_error "No subnets found in VPC. Please set SUBNET_IDS in this script."
        exit 1
    fi
    log_success "Using subnets: $SUBNET_IDS"
fi

# Create security group if not specified
if [ -z "$SECURITY_GROUP_ID" ]; then
    log_info "Creating security group for Britive broker..."

    # Check if security group already exists
    EXISTING_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=britive-broker-sg" "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[0].GroupId" --output text --region "$AWS_REGION" 2>/dev/null || echo "None")

    if [ "$EXISTING_SG" != "None" ] && [ -n "$EXISTING_SG" ]; then
        SECURITY_GROUP_ID="$EXISTING_SG"
        log_success "Using existing security group: $SECURITY_GROUP_ID"
    else
        SECURITY_GROUP_ID=$(aws ec2 create-security-group \
            --group-name "britive-broker-sg" \
            --description "Security group for Britive Access Broker" \
            --vpc-id "$VPC_ID" \
            --query "GroupId" \
            --output text \
            --region "$AWS_REGION")

        # Allow outbound traffic (default)
        log_info "Security group created: $SECURITY_GROUP_ID"
    fi
fi

# Create ECR repository
log_info "Setting up ECR repository..."
ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

if ! aws ecr describe-repositories --repository-names "$ECR_REPO_NAME" --region "$AWS_REGION" &> /dev/null; then
    log_info "Creating ECR repository: $ECR_REPO_NAME"
    aws ecr create-repository --repository-name "$ECR_REPO_NAME" --region "$AWS_REGION" > /dev/null
    log_success "ECR repository created"
else
    log_success "ECR repository exists"
fi

# Authenticate Docker with ECR
log_info "Authenticating Docker with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
log_success "Docker authenticated with ECR"

# Build Docker image
log_info "Building Docker image (AMD64 architecture)..."
docker build --platform linux/amd64 -t "$ECR_REPO_NAME:latest" .

# Verify architecture
ARCH=$(docker inspect "$ECR_REPO_NAME:latest" --format '{{.Architecture}}')
log_info "Image architecture: $ARCH"

if [ "$ARCH" != "amd64" ]; then
    log_error "Image architecture is not amd64. Fargate requires amd64 images."
    exit 1
fi
log_success "Image built successfully"

# Test image locally
log_info "Testing image locally..."
CONTAINER_ID=$(docker run -d --name test-broker -e BRITIVE_TOKEN="test" "$ECR_REPO_NAME:latest")
sleep 5

if docker ps | grep -q test-broker; then
    log_success "Container started successfully"
    docker logs test-broker 2>&1 | head -20 || true
else
    log_error "Container failed to start"
    docker logs test-broker 2>&1 || true
fi

docker stop test-broker 2>/dev/null || true
docker rm test-broker 2>/dev/null || true

# Tag and push image
log_info "Pushing image to ECR..."
docker tag "$ECR_REPO_NAME:latest" "$ECR_REPO_URI:latest"
docker push "$ECR_REPO_URI:latest"
log_success "Image pushed to ECR"

# Create CloudWatch log group
log_info "Setting up CloudWatch log group..."
aws logs create-log-group --log-group-name "/ecs/britive-broker" --region "$AWS_REGION" 2>/dev/null || true
log_success "CloudWatch log group ready"

# Create or get IAM roles
log_info "Setting up IAM roles..."

# ECS Task Execution Role
EXECUTION_ROLE_NAME="ecsTaskExecutionRole"
EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${EXECUTION_ROLE_NAME}"

if ! aws iam get-role --role-name "$EXECUTION_ROLE_NAME" &> /dev/null; then
    log_info "Creating ECS task execution role..."

    cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws iam create-role \
        --role-name "$EXECUTION_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json > /dev/null

    aws iam attach-role-policy \
        --role-name "$EXECUTION_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"

    rm /tmp/trust-policy.json
    log_success "Execution role created"
else
    log_success "Execution role exists"
fi

# Create Task Role for Britive broker
TASK_ROLE_NAME="britive-broker-task-role"
TASK_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TASK_ROLE_NAME}"

if ! aws iam get-role --role-name "$TASK_ROLE_NAME" &> /dev/null; then
    log_info "Creating Britive broker task role..."

    cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws iam create-role \
        --role-name "$TASK_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json > /dev/null

    # Create policy for EKS access (if broker needs to manage EKS clusters)
    cat > /tmp/broker-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sts:AssumeRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    aws iam put-role-policy \
        --role-name "$TASK_ROLE_NAME" \
        --policy-name "britive-broker-policy" \
        --policy-document file:///tmp/broker-policy.json

    rm /tmp/trust-policy.json /tmp/broker-policy.json
    log_success "Task role created"
else
    log_success "Task role exists"
fi

# Create Secrets Manager secrets
log_info "Setting up Secrets Manager secrets..."

# Array to track all secret ARNs for IAM policy
declare -a SECRET_ARNS
declare -a SECRET_NAMES

# Function to create or update a secret
create_or_update_secret() {
    local secret_key="$1"
    local secret_value="$2"
    local description="$3"
    local full_secret_name="${SECRETS_PREFIX}/${secret_key}"

    if aws secretsmanager describe-secret --secret-id "$full_secret_name" --region "$AWS_REGION" &> /dev/null; then
        log_info "Updating secret: $secret_key"
        aws secretsmanager update-secret \
            --secret-id "$full_secret_name" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" > /dev/null
    else
        log_info "Creating secret: $secret_key"
        aws secretsmanager create-secret \
            --name "$full_secret_name" \
            --description "$description" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" > /dev/null
    fi

    # Get the ARN
    local arn=$(aws secretsmanager describe-secret --secret-id "$full_secret_name" --query "ARN" --output text --region "$AWS_REGION")
    SECRET_ARNS+=("$arn")
    SECRET_NAMES+=("$secret_key")
    log_success "Secret configured: $secret_key"
}

# Process secrets from secrets.json if available
if [ "$USE_SECRETS_FILE" = true ]; then
    log_info "Processing secrets from secrets.json..."

    # Process main secrets
    SECRETS_JSON=$(cat secrets.json)

    # Extract and create each secret from the secrets object
    echo "$SECRETS_JSON" | jq -r '.secrets | to_entries[] | select(.value.value != "" and .value.value != "your-britive-token-here") | @base64' | while read -r entry; do
        key=$(echo "$entry" | base64 -d | jq -r '.key')
        value=$(echo "$entry" | base64 -d | jq -r '.value.value')
        desc=$(echo "$entry" | base64 -d | jq -r '.value.description // "Britive broker secret"')

        if [ -n "$value" ] && [ "$value" != "null" ]; then
            create_or_update_secret "$key" "$value" "$desc"
        fi
    done

    # Process custom secrets
    echo "$SECRETS_JSON" | jq -r '.custom_secrets | to_entries[] | select(.value != "" and .value != null) | @base64' | while read -r entry; do
        key=$(echo "$entry" | base64 -d | jq -r '.key')
        value=$(echo "$entry" | base64 -d | jq -r '.value')

        if [ -n "$value" ] && [ "$value" != "null" ]; then
            create_or_update_secret "$key" "$value" "Custom secret for Britive broker"
        fi
    done
else
    # Fallback: Use BRITIVE_TOKEN from script configuration
    if [ "$BRITIVE_TOKEN" != "your-britive-token-here" ]; then
        create_or_update_secret "BRITIVE_TOKEN" "$BRITIVE_TOKEN" "Britive Access Broker token"
    fi
fi

# Get all secrets for this deployment (in case some were created outside this run)
ALL_SECRET_ARNS=$(aws secretsmanager list-secrets \
    --filter Key=name,Values="${SECRETS_PREFIX}" \
    --query "SecretList[*].ARN" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null | tr '\t' '\n')

if [ -z "$ALL_SECRET_ARNS" ]; then
    log_error "No secrets found. Please configure BRITIVE_TOKEN or secrets.json"
    exit 1
fi

# Build JSON array of all secret ARNs
ARN_ARRAY=$(echo "$ALL_SECRET_ARNS" | jq -R . | jq -s .)

log_success "Total secrets configured: $(echo "$ALL_SECRET_ARNS" | wc -l | tr -d ' ')"

# Add Secrets Manager permission to execution role for all secrets
log_info "Adding Secrets Manager permissions to execution role..."
cat > /tmp/secrets-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": ${ARN_ARRAY}
    }
  ]
}
EOF

aws iam put-role-policy \
    --role-name "$EXECUTION_ROLE_NAME" \
    --policy-name "britive-secrets-access" \
    --policy-document file:///tmp/secrets-policy.json 2>/dev/null || true

rm /tmp/secrets-policy.json

# Update task definition
log_info "Preparing task definition..."
cp task-definition.json task-definition-deploy.json

# Build secrets array for task definition
# Each secret in Secrets Manager becomes an environment variable
SECRETS_JSON_ARRAY="["
first_secret=true

for secret_arn in $ALL_SECRET_ARNS; do
    # Extract secret name from ARN (last part after the colon)
    secret_name=$(echo "$secret_arn" | sed 's/.*:secret://' | sed 's/-.*//' | sed "s|${SECRETS_PREFIX}/||")
    # Get the full secret name (without the random suffix)
    full_name=$(aws secretsmanager describe-secret --secret-id "$secret_arn" --query "Name" --output text --region "$AWS_REGION" 2>/dev/null)
    # Extract just the key name from the path
    key_name="${full_name#${SECRETS_PREFIX}/}"

    if [ "$first_secret" = true ]; then
        first_secret=false
    else
        SECRETS_JSON_ARRAY+=","
    fi

    SECRETS_JSON_ARRAY+="{\"name\":\"${key_name}\",\"valueFrom\":\"${secret_arn}\"}"
done

SECRETS_JSON_ARRAY+="]"

# Use jq to properly inject secrets array into task definition
jq --argjson secrets "$SECRETS_JSON_ARRAY" \
   --arg image "$ECR_REPO_URI:latest" \
   --arg exec_role "$EXECUTION_ROLE_ARN" \
   --arg task_role "$TASK_ROLE_ARN" \
   --arg region "$AWS_REGION" \
   '.executionRoleArn = $exec_role |
    .taskRoleArn = $task_role |
    .containerDefinitions[0].image = $image |
    .containerDefinitions[0].secrets = $secrets |
    .containerDefinitions[0].logConfiguration.options["awslogs-region"] = $region' \
   task-definition.json > task-definition-deploy.json

log_success "Task definition prepared with $(echo "$ALL_SECRET_ARNS" | wc -l | tr -d ' ') secrets"

# Register task definition
log_info "Registering task definition..."
TASK_DEFINITION_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://task-definition-deploy.json \
    --query "taskDefinition.taskDefinitionArn" \
    --output text \
    --region "$AWS_REGION")

rm -f task-definition-deploy.json
log_success "Task definition registered: $TASK_DEFINITION_ARN"

# Create ECS cluster if it doesn't exist
log_info "Setting up ECS cluster..."
if ! aws ecs describe-clusters --clusters "$ECS_CLUSTER_NAME" --query "clusters[?status=='ACTIVE']" --output text --region "$AWS_REGION" | grep -q "$ECS_CLUSTER_NAME"; then
    log_info "Creating ECS cluster: $ECS_CLUSTER_NAME"
    aws ecs create-cluster --cluster-name "$ECS_CLUSTER_NAME" --region "$AWS_REGION" > /dev/null
    log_success "ECS cluster created"
else
    log_success "ECS cluster exists"
fi

# Convert subnet IDs to JSON array (limit to 2 subnets for the service network config;
# for higher availability across more AZs, increase or remove the head -2 limit)
SUBNET_ARRAY=$(echo "$SUBNET_IDS" | tr ',' '\n' | head -2 | jq -R . | jq -s .)

# Create or update ECS service
log_info "Deploying ECS service..."

SERVICE_EXISTS=$(aws ecs describe-services --cluster "$ECS_CLUSTER_NAME" --services "$ECS_SERVICE_NAME" --query "services[?status=='ACTIVE'].serviceName" --output text --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$SERVICE_EXISTS" ]; then
    log_info "Updating existing service..."
    aws ecs update-service \
        --cluster "$ECS_CLUSTER_NAME" \
        --service "$ECS_SERVICE_NAME" \
        --task-definition "$TASK_DEFINITION_ARN" \
        --desired-count "$DESIRED_COUNT" \
        --force-new-deployment \
        --region "$AWS_REGION" > /dev/null
else
    log_info "Creating new service..."
    aws ecs create-service \
        --cluster "$ECS_CLUSTER_NAME" \
        --service-name "$ECS_SERVICE_NAME" \
        --task-definition "$TASK_DEFINITION_ARN" \
        --desired-count "$DESIRED_COUNT" \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=$SUBNET_ARRAY,securityGroups=[\"$SECURITY_GROUP_ID\"],assignPublicIp=ENABLED}" \
        --region "$AWS_REGION" > /dev/null
fi

log_success "Service deployed"

# Wait for service to stabilize
log_info "Waiting for service to stabilize..."
aws ecs wait services-stable --cluster "$ECS_CLUSTER_NAME" --services "$ECS_SERVICE_NAME" --region "$AWS_REGION" || \
    log_warning "Service may still be stabilizing. Check AWS console for status."

log_success "Deployment complete!"

# Show status
echo ""
echo "=============================================="
echo "         DEPLOYMENT STATUS"
echo "=============================================="
echo ""
echo "Cluster:    $ECS_CLUSTER_NAME"
echo "Service:    $ECS_SERVICE_NAME"
echo "Task Def:   $TASK_DEFINITION_ARN"
echo "Region:     $AWS_REGION"
echo ""

# Get running tasks
log_info "Running tasks:"
aws ecs list-tasks --cluster "$ECS_CLUSTER_NAME" --service-name "$ECS_SERVICE_NAME" --query "taskArns" --output table --region "$AWS_REGION"

echo ""
echo "=============================================="
echo ""
log_info "To view logs:"
log_info "  aws logs tail /ecs/britive-broker --follow --region $AWS_REGION"
echo ""
log_info "To check service status:"
log_info "  aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION"
echo ""
log_info "To view in AWS Console:"
log_info "  https://${AWS_REGION}.console.aws.amazon.com/ecs/home?region=${AWS_REGION}#/clusters/${ECS_CLUSTER_NAME}/services/${ECS_SERVICE_NAME}/details"
echo ""
log_success "Britive Access Broker deployed to ECS Fargate!"
