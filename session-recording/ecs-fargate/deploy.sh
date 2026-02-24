#!/bin/bash

# Britive Session Recording - AWS ECS Fargate Deployment Script
# Deploys Guacamole (guacd + web app), Britive broker, and optional GuacSync
# to AWS ECS Fargate with service discovery, EFS for recordings, and an ALB.
#
# Prerequisites:
# 1. AWS CLI installed and configured (aws configure)
# 2. Docker installed and running
# 3. jq installed
# 4. britive-broker-<VERSION>.jar placed in the broker/ directory
#
# Usage:
#   ./deploy.sh [options]
#
# Options:
#   --broker-version <ver>    Broker JAR version to use (default: 2.0.0)
#   --region <region>         AWS region (default: us-east-1)
#   --cluster-name <name>     ECS cluster name (default: britive-session-recording)
#   --enable-guacsync         Enable GuacSync recording conversion and S3 sync
#   --s3-bucket <bucket>      S3 bucket for GuacSync (required when --enable-guacsync is set)
#   --acm-cert-arn <arn>      ACM certificate ARN — enables HTTPS/443 on the ALB
#   --vpc-id <id>             VPC ID (default: auto-detect default VPC)
#   --subnets <ids>           Comma-separated subnet IDs (default: auto-detect)
#   --use-secrets-json        Force-load configuration from secrets.json

set -e

#==============================================================================
# CONFIGURATION - MODIFY THESE VALUES
#==============================================================================

# Secrets Configuration
# Option 1 (recommended): Use secrets.json — set BRITIVE_TENANT, BRITIVE_TOKEN, and
#   JSON_SECRET_KEY there. All are stored in AWS Secrets Manager and auto-injected
#   into tasks at runtime. Leave the values below as placeholders when using Option 1.
#
# Option 2 (direct): Set values here if not using secrets.json.
#   BRITIVE_TENANT: subdomain of your Britive URL (e.g. "mycompany" for mycompany.britive-app.com)
#   BRITIVE_TOKEN:  broker pool token from System Administration > Broker Pools
#   JSON_SECRET_KEY: secret key for Guacamole JSON auth — auto-generated if left empty
BRITIVE_TENANT="your-tenant-subdomain-here"
BRITIVE_TOKEN="your-britive-token-here"
JSON_SECRET_KEY=""   # Leave empty to auto-generate a random 64-character hex key

# Broker version — must match the JAR file in broker/ (broker/britive-broker-<VERSION>.jar)
BROKER_VERSION="2.0.0"

# Secrets are stored in AWS Secrets Manager under this prefix
SECRETS_PREFIX="britive/session-recording"

# AWS Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"

# ECS Configuration
CLUSTER_NAME="britive-session-recording"
ECR_BROKER_REPO="britive-session-recording/broker"
ECR_GUACSYNC_REPO="britive-session-recording/guacsync"
IMAGE_TAG="latest"

# EFS — shared volume for session recordings
EFS_NAME="britive-recordings-efs"

# Service Discovery — private DNS namespace for inter-service communication
NAMESPACE="britive.local"

# GuacSync — optional recording conversion and S3 sync service
ENABLE_GUACSYNC=false
S3_BUCKET=""

# ALB — optional ACM certificate ARN enables HTTPS/443; without it HTTP/80 is used
ACM_CERT_ARN=""

# Networking — leave empty to auto-detect default VPC and subnets
VPC_ID=""
SUBNET_IDS=""   # Comma-separated, e.g. "subnet-aaa,subnet-bbb"

# Number of broker replicas
DESIRED_COUNT=1

#==============================================================================
# DO NOT MODIFY BELOW THIS LINE
#==============================================================================

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --broker-version)
            if [ -z "$2" ] || [[ "$2" == --* ]]; then
                echo "ERROR: --broker-version requires a value"
                exit 1
            fi
            BROKER_VERSION="$2"; shift ;;
        --region)
            AWS_REGION="$2"; shift ;;
        --cluster-name)
            CLUSTER_NAME="$2"; shift ;;
        --enable-guacsync)
            ENABLE_GUACSYNC=true ;;
        --s3-bucket)
            S3_BUCKET="$2"; shift ;;
        --acm-cert-arn)
            ACM_CERT_ARN="$2"; shift ;;
        --vpc-id)
            VPC_ID="$2"; shift ;;
        --subnets)
            SUBNET_IDS="$2"; shift ;;
        --use-secrets-json)
            FORCE_SECRETS_FILE=true ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: ./deploy.sh [--broker-version <ver>] [--region <region>] [--cluster-name <name>]"
            echo "                   [--enable-guacsync] [--s3-bucket <bucket>] [--acm-cert-arn <arn>]"
            echo "                   [--vpc-id <id>] [--subnets <ids>] [--use-secrets-json]"
            exit 1 ;;
    esac
    shift
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Derived names (built after CLI parsing so --cluster-name takes effect)
ECS_BROKER_SERVICE="${CLUSTER_NAME}-broker-service"
ECS_GUACD_SERVICE="${CLUSTER_NAME}-guacd-service"
ECS_GUACAMOLE_SERVICE="${CLUSTER_NAME}-guacamole-service"
ECS_GUACSYNC_SERVICE="${CLUSTER_NAME}-guacsync-service"
EXECUTION_ROLE_NAME="britive-sr-execution-role"
TASK_ROLE_NAME="britive-sr-task-role"

# Determine whether to load from secrets.json
USE_SECRETS_FILE=false
if [ "${FORCE_SECRETS_FILE:-false}" = true ] || [ -f "secrets.json" ]; then
    log_success "Found secrets.json — will use for secrets configuration"
    USE_SECRETS_FILE=true
fi

# When not using secrets.json, validate required values
if [ "$USE_SECRETS_FILE" = false ]; then
    if [ "$BRITIVE_TENANT" = "your-tenant-subdomain-here" ]; then
        log_error "Please set BRITIVE_TENANT in this script, or add it to secrets.json (recommended)"
        exit 1
    fi
    if [ "$BRITIVE_TOKEN" = "your-britive-token-here" ]; then
        log_error "Please set BRITIVE_TOKEN in this script, or add it to secrets.json (recommended)"
        exit 1
    fi
fi

# Validate GuacSync options
if [ "$ENABLE_GUACSYNC" = true ] && [ -z "$S3_BUCKET" ]; then
    log_error "--enable-guacsync requires --s3-bucket <bucket-name>"
    exit 1
fi

# Check for required broker JAR
log_info "Checking required files..."
log_info "Using broker version: $BROKER_VERSION"
if [ ! -f "broker/britive-broker-${BROKER_VERSION}.jar" ]; then
    log_error "broker/britive-broker-${BROKER_VERSION}.jar not found"
    log_info "Place the broker JAR in the broker/ directory and try again"
    exit 1
fi
log_success "Broker JAR found: broker/britive-broker-${BROKER_VERSION}.jar"

# Check AWS CLI
log_info "Checking AWS CLI..."
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Install it:"
    log_info "  macOS: brew install awscli"
    log_info "  Linux: pip install awscli"
    exit 1
fi
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run: aws configure"
    exit 1
fi
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_success "AWS CLI configured — Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"

# Check jq
if ! command -v jq &> /dev/null; then
    log_error "jq not found. Install it: brew install jq (macOS) or apt install jq (Linux)"
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

#------------------------------------------------------------------------------
# VPC and subnet detection
#------------------------------------------------------------------------------

if [ -z "$VPC_ID" ]; then
    log_info "Auto-detecting default VPC..."
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query "Vpcs[0].VpcId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")
    if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
        log_error "No default VPC found. Please set VPC_ID in this script or use --vpc-id."
        exit 1
    fi
    log_success "Using default VPC: $VPC_ID"
fi

if [ -z "$SUBNET_IDS" ]; then
    log_info "Auto-detecting subnets in VPC $VPC_ID..."
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "Subnets[*].SubnetId" \
        --output text \
        --region "$AWS_REGION" | tr '\t' ',')
    if [ -z "$SUBNET_IDS" ]; then
        log_error "No subnets found in VPC. Please set SUBNET_IDS or use --subnets."
        exit 1
    fi
    log_success "Using subnets: $SUBNET_IDS"
fi

# Build JSON subnet array for ECS network config (use first 2 subnets)
SUBNET_ARRAY=$(echo "$SUBNET_IDS" | tr ',' '\n' | head -2 | jq -R . | jq -s .)

#------------------------------------------------------------------------------
# Security groups
#------------------------------------------------------------------------------

log_info "Setting up security groups..."

create_sg_if_missing() {
    local name="$1" desc="$2"
    local existing
    existing=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${name}" "Name=vpc-id,Values=${VPC_ID}" \
        --query "SecurityGroups[0].GroupId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")
    if [ "$existing" = "None" ] || [ -z "$existing" ]; then
        aws ec2 create-security-group \
            --group-name "$name" \
            --description "$desc" \
            --vpc-id "$VPC_ID" \
            --query "GroupId" \
            --output text \
            --region "$AWS_REGION"
    else
        echo "$existing"
    fi
}

ALB_SG_ID=$(create_sg_if_missing "britive-sr-alb-sg" "Britive session recording ALB")
GUACAMOLE_SG_ID=$(create_sg_if_missing "britive-sr-guacamole-sg" "Britive session recording Guacamole")
GUACD_SG_ID=$(create_sg_if_missing "britive-sr-guacd-sg" "Britive session recording GuacD")
BROKER_SG_ID=$(create_sg_if_missing "britive-sr-broker-sg" "Britive session recording Broker")

log_success "Security groups ready:"
log_info "  ALB:       $ALB_SG_ID"
log_info "  Guacamole: $GUACAMOLE_SG_ID"
log_info "  GuacD:     $GUACD_SG_ID"
log_info "  Broker:    $BROKER_SG_ID"

# Helper — adds an ingress rule only if it doesn't already exist
add_ingress_if_missing() {
    local sg_id="$1" proto="$2" port="$3" source="$4"
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol "$proto" \
        --port "$port" \
        --source-group "$source" \
        --region "$AWS_REGION" 2>/dev/null || true
}

add_ingress_cidr_if_missing() {
    local sg_id="$1" proto="$2" port="$3" cidr="$4"
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol "$proto" \
        --port "$port" \
        --cidr "$cidr" \
        --region "$AWS_REGION" 2>/dev/null || true
}

# ALB: inbound HTTP and HTTPS from the internet
add_ingress_cidr_if_missing "$ALB_SG_ID" tcp 80 "0.0.0.0/0"
add_ingress_cidr_if_missing "$ALB_SG_ID" tcp 443 "0.0.0.0/0"

# Guacamole: inbound from ALB only
add_ingress_if_missing "$GUACAMOLE_SG_ID" tcp 8080 "$ALB_SG_ID"

# GuacD: inbound from Guacamole only
add_ingress_if_missing "$GUACD_SG_ID" tcp 4822 "$GUACAMOLE_SG_ID"

# Broker: inbound SSH from Guacamole (for proxied SSH sessions)
add_ingress_if_missing "$BROKER_SG_ID" tcp 22 "$GUACAMOLE_SG_ID"

log_success "Security group rules configured"

#------------------------------------------------------------------------------
# ECR — build and push broker image
#------------------------------------------------------------------------------

log_info "Setting up ECR repository for broker..."
ECR_BROKER_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_BROKER_REPO}"

if ! aws ecr describe-repositories --repository-names "$ECR_BROKER_REPO" --region "$AWS_REGION" &> /dev/null; then
    log_info "Creating ECR repository: $ECR_BROKER_REPO"
    aws ecr create-repository --repository-name "$ECR_BROKER_REPO" --region "$AWS_REGION" > /dev/null
fi
log_success "ECR broker repository ready"

log_info "Authenticating Docker with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
log_success "Docker authenticated with ECR"

log_info "Building broker Docker image (AMD64, version: $BROKER_VERSION)..."
docker build \
    --platform linux/amd64 \
    --build-arg BROKER_VERSION="$BROKER_VERSION" \
    -t "britive-sr-broker:${IMAGE_TAG}" \
    broker/

ARCH=$(docker inspect "britive-sr-broker:${IMAGE_TAG}" --format '{{.Architecture}}')
if [ "$ARCH" != "amd64" ]; then
    log_error "Broker image architecture is $ARCH but ECS Fargate requires amd64."
    exit 1
fi
log_success "Broker image built (amd64)"

# Quick local smoke test
log_info "Testing broker image locally..."
docker run -d --name test-sr-broker \
    -e BRITIVE_TOKEN="test" \
    -e BRITIVE_TENANT="test" \
    "britive-sr-broker:${IMAGE_TAG}"
sleep 5
if docker ps | grep -q test-sr-broker; then
    log_success "Broker container started successfully"
    docker logs test-sr-broker 2>&1 | head -10 || true
else
    log_warning "Broker container exited early — check image and start-broker.sh"
    docker logs test-sr-broker 2>&1 || true
fi
docker stop test-sr-broker 2>/dev/null || true
docker rm  test-sr-broker 2>/dev/null || true

log_info "Pushing broker image to ECR..."
docker tag "britive-sr-broker:${IMAGE_TAG}" "${ECR_BROKER_URI}:${IMAGE_TAG}"
docker push "${ECR_BROKER_URI}:${IMAGE_TAG}"
log_success "Broker image pushed to ECR"

# GuacSync image (optional)
ECR_GUACSYNC_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_GUACSYNC_REPO}"
if [ "$ENABLE_GUACSYNC" = true ]; then
    log_info "Setting up ECR repository for GuacSync..."
    if ! aws ecr describe-repositories --repository-names "$ECR_GUACSYNC_REPO" --region "$AWS_REGION" &> /dev/null; then
        aws ecr create-repository --repository-name "$ECR_GUACSYNC_REPO" --region "$AWS_REGION" > /dev/null
    fi
    log_info "Building GuacSync image..."
    docker build --platform linux/amd64 -t "britive-sr-guacsync:${IMAGE_TAG}" guacsync/
    docker tag "britive-sr-guacsync:${IMAGE_TAG}" "${ECR_GUACSYNC_URI}:${IMAGE_TAG}"
    docker push "${ECR_GUACSYNC_URI}:${IMAGE_TAG}"
    log_success "GuacSync image pushed to ECR"
fi

#------------------------------------------------------------------------------
# EFS — shared recording storage
#------------------------------------------------------------------------------

log_info "Setting up EFS filesystem for recordings..."
EFS_ID=$(aws efs describe-file-systems \
    --query "FileSystems[?Name=='${EFS_NAME}'].FileSystemId | [0]" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$EFS_ID" = "None" ] || [ -z "$EFS_ID" ]; then
    log_info "Creating EFS filesystem: $EFS_NAME"
    EFS_ID=$(aws efs create-file-system \
        --encrypted \
        --tags "Key=Name,Value=${EFS_NAME}" \
        --query "FileSystemId" \
        --output text \
        --region "$AWS_REGION")
    log_success "EFS created: $EFS_ID"

    # Wait for filesystem to become available
    log_info "Waiting for EFS to become available..."
    aws efs wait file-system-available --file-system-id "$EFS_ID" --region "$AWS_REGION" 2>/dev/null || sleep 15
else
    log_success "EFS exists: $EFS_ID"
fi

# Create EFS access point for /recordings
EFS_AP_ID=$(aws efs describe-access-points \
    --file-system-id "$EFS_ID" \
    --query "AccessPoints[?RootDirectory.Path=='/recordings'].AccessPointId | [0]" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$EFS_AP_ID" = "None" ] || [ -z "$EFS_AP_ID" ]; then
    log_info "Creating EFS access point at /recordings..."
    EFS_AP_ID=$(aws efs create-access-point \
        --file-system-id "$EFS_ID" \
        --root-directory "Path=/recordings,CreationInfo={OwnerUid=0,OwnerGid=0,Permissions=755}" \
        --query "AccessPointId" \
        --output text \
        --region "$AWS_REGION")
    log_success "EFS access point created: $EFS_AP_ID"
else
    log_success "EFS access point exists: $EFS_AP_ID"
fi

# Create EFS mount targets in each subnet (idempotent)
log_info "Creating EFS mount targets in subnets..."
for subnet in $(echo "$SUBNET_IDS" | tr ',' '\n' | head -2); do
    aws efs create-mount-target \
        --file-system-id "$EFS_ID" \
        --subnet-id "$subnet" \
        --security-groups "$GUACD_SG_ID" \
        --region "$AWS_REGION" 2>/dev/null || true
done
log_success "EFS mount targets ready"

#------------------------------------------------------------------------------
# CloudWatch log groups
#------------------------------------------------------------------------------

log_info "Setting up CloudWatch log groups..."
for svc in broker guacd guacamole guacsync; do
    aws logs create-log-group \
        --log-group-name "/ecs/britive-session-recording/${svc}" \
        --region "$AWS_REGION" 2>/dev/null || true
done
log_success "CloudWatch log groups ready"

#------------------------------------------------------------------------------
# IAM roles
#------------------------------------------------------------------------------

log_info "Setting up IAM roles..."

TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}'

# Execution role
if ! aws iam get-role --role-name "$EXECUTION_ROLE_NAME" &> /dev/null; then
    log_info "Creating ECS task execution role: $EXECUTION_ROLE_NAME"
    echo "$TRUST_POLICY" > /tmp/sr-trust-policy.json
    aws iam create-role \
        --role-name "$EXECUTION_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/sr-trust-policy.json > /dev/null
    aws iam attach-role-policy \
        --role-name "$EXECUTION_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    rm -f /tmp/sr-trust-policy.json
    log_success "Execution role created"
else
    log_success "Execution role exists"
fi
EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${EXECUTION_ROLE_NAME}"

# Task role
if ! aws iam get-role --role-name "$TASK_ROLE_NAME" &> /dev/null; then
    log_info "Creating ECS task role: $TASK_ROLE_NAME"
    echo "$TRUST_POLICY" > /tmp/sr-trust-policy.json
    aws iam create-role \
        --role-name "$TASK_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/sr-trust-policy.json > /dev/null
    rm -f /tmp/sr-trust-policy.json
    log_success "Task role created"
else
    log_success "Task role exists"
fi
TASK_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TASK_ROLE_NAME}"

# Attach S3 policy to task role if GuacSync is enabled
if [ "$ENABLE_GUACSYNC" = true ]; then
    log_info "Adding S3 permissions to task role for GuacSync..."
    cat > /tmp/sr-s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject", "s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::${S3_BUCKET}",
      "arn:aws:s3:::${S3_BUCKET}/*"
    ]
  }]
}
EOF
    aws iam put-role-policy \
        --role-name "$TASK_ROLE_NAME" \
        --policy-name "britive-sr-s3-access" \
        --policy-document file:///tmp/sr-s3-policy.json
    rm -f /tmp/sr-s3-policy.json
    log_success "S3 permissions attached to task role"
fi

# ECS service-linked role (required once per AWS account)
aws iam create-service-linked-role --aws-service-name ecs.amazonaws.com 2>/dev/null || true

#------------------------------------------------------------------------------
# Secrets Manager
#------------------------------------------------------------------------------

log_info "Setting up Secrets Manager secrets..."

create_or_update_secret() {
    local key="$1" value="$2" desc="$3"
    local full_name="${SECRETS_PREFIX}/${key}"
    if aws secretsmanager describe-secret --secret-id "$full_name" --region "$AWS_REGION" &> /dev/null; then
        aws secretsmanager update-secret \
            --secret-id "$full_name" \
            --secret-string "$value" \
            --region "$AWS_REGION" > /dev/null
    else
        aws secretsmanager create-secret \
            --name "$full_name" \
            --description "$desc" \
            --secret-string "$value" \
            --region "$AWS_REGION" > /dev/null
    fi
    log_success "Secret configured: $key"
}

# Auto-generate JSON_SECRET_KEY if not provided
if [ -z "$JSON_SECRET_KEY" ]; then
    if [ "$USE_SECRETS_FILE" = true ]; then
        JSON_SECRET_KEY=$(jq -r '.secrets.JSON_SECRET_KEY.value // ""' secrets.json 2>/dev/null || echo "")
    fi
    if [ -z "$JSON_SECRET_KEY" ]; then
        log_info "Generating JSON_SECRET_KEY (not found in secrets.json)..."
        JSON_SECRET_KEY=$(openssl rand -hex 32)
        log_success "JSON_SECRET_KEY generated (64-char hex)"
    fi
fi

if [ "$USE_SECRETS_FILE" = true ]; then
    log_info "Processing secrets from secrets.json..."
    SECRETS_JSON=$(cat secrets.json)

    echo "$SECRETS_JSON" | jq -r '.secrets | to_entries[] | select(.value.value != "" and .value.value != "your-britive-token-here" and .value.value != "your-tenant-subdomain-here") | @json' | while read -r entry; do
        key=$(echo "$entry" | jq -r '.key')
        value=$(echo "$entry" | jq -r '.value.value')
        desc=$(echo "$entry" | jq -r '.value.description // "Britive session recording secret"')
        [ -n "$value" ] && create_or_update_secret "$key" "$value" "$desc"
    done

    echo "$SECRETS_JSON" | jq -r '.custom_secrets | to_entries[] | select(.value != "" and .value != null) | @json' | while read -r entry; do
        key=$(echo "$entry" | jq -r '.key')
        value=$(echo "$entry" | jq -r '.value')
        [ -n "$value" ] && create_or_update_secret "$key" "$value" "Custom secret"
    done
else
    [ "$BRITIVE_TENANT" != "your-tenant-subdomain-here" ] && \
        create_or_update_secret "BRITIVE_TENANT" "$BRITIVE_TENANT" "Britive tenant subdomain"
    [ "$BRITIVE_TOKEN" != "your-britive-token-here" ] && \
        create_or_update_secret "BRITIVE_TOKEN" "$BRITIVE_TOKEN" "Britive broker pool token"
fi

# Always ensure JSON_SECRET_KEY is in Secrets Manager
create_or_update_secret "JSON_SECRET_KEY" "$JSON_SECRET_KEY" "Guacamole JSON authentication secret key"

# Collect all secret ARNs for IAM policy and task definitions
ALL_SECRET_ARNS=$(aws secretsmanager list-secrets \
    --filter Key=name,Values="${SECRETS_PREFIX}" \
    --query "SecretList[*].ARN" \
    --output text \
    --region "$AWS_REGION" | tr '\t' '\n')

if [ -z "$ALL_SECRET_ARNS" ]; then
    log_error "No secrets found after setup. Check Secrets Manager and try again."
    exit 1
fi

ARN_ARRAY=$(echo "$ALL_SECRET_ARNS" | jq -R . | jq -s .)
SECRET_COUNT=$(echo "$ALL_SECRET_ARNS" | grep -c . || echo 0)
log_success "Total secrets configured: $SECRET_COUNT"

# Grant execution role access to all secrets
log_info "Updating IAM execution role with Secrets Manager permissions..."
cat > /tmp/sr-secrets-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["secretsmanager:GetSecretValue"],
    "Resource": ${ARN_ARRAY}
  }]
}
EOF
aws iam put-role-policy \
    --role-name "$EXECUTION_ROLE_NAME" \
    --policy-name "britive-sr-secrets-access" \
    --policy-document file:///tmp/sr-secrets-policy.json 2>/dev/null || true
rm -f /tmp/sr-secrets-policy.json
log_success "IAM permissions updated"

# Build secrets array for ECS task definitions
# Each secret in Secrets Manager becomes an env var inside the container
build_secrets_array() {
    local filter_prefix="${1:-}"   # optional: only include secrets with this key prefix
    local arr="["
    local first=true
    for arn in $ALL_SECRET_ARNS; do
        full_name=$(aws secretsmanager describe-secret \
            --secret-id "$arn" \
            --query "Name" \
            --output text \
            --region "$AWS_REGION" 2>/dev/null)
        key_name="${full_name#${SECRETS_PREFIX}/}"
        # Skip secrets that don't match the optional prefix filter
        if [ -n "$filter_prefix" ] && [[ "$key_name" != ${filter_prefix}* ]]; then
            continue
        fi
        [ "$first" = true ] && first=false || arr+=","
        arr+="{\"name\":\"${key_name}\",\"valueFrom\":\"${arn}\"}"
    done
    arr+="]"
    echo "$arr"
}

ALL_SECRETS_ARRAY=$(build_secrets_array)
JSON_KEY_ARN=$(aws secretsmanager describe-secret \
    --secret-id "${SECRETS_PREFIX}/JSON_SECRET_KEY" \
    --query "ARN" --output text --region "$AWS_REGION" 2>/dev/null || echo "")
GUACAMOLE_SECRETS_ARRAY="[{\"name\":\"JSON_SECRET_KEY\",\"valueFrom\":\"${JSON_KEY_ARN}\"}]"

#------------------------------------------------------------------------------
# Cloud Map — service discovery
#------------------------------------------------------------------------------

log_info "Setting up Cloud Map service discovery (namespace: ${NAMESPACE})..."

NAMESPACE_ID=$(aws servicediscovery list-namespaces \
    --query "Namespaces[?Name=='${NAMESPACE}'].Id | [0]" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$NAMESPACE_ID" = "None" ] || [ -z "$NAMESPACE_ID" ]; then
    log_info "Creating private DNS namespace: $NAMESPACE"
    NAMESPACE_OP=$(aws servicediscovery create-private-dns-namespace \
        --name "$NAMESPACE" \
        --vpc "$VPC_ID" \
        --region "$AWS_REGION" \
        --output json)
    OP_ID=$(echo "$NAMESPACE_OP" | jq -r '.OperationId')
    # Wait for namespace creation
    for i in {1..20}; do
        STATUS=$(aws servicediscovery get-operation --operation-id "$OP_ID" \
            --query "Operation.Status" --output text --region "$AWS_REGION" 2>/dev/null)
        [ "$STATUS" = "SUCCESS" ] && break
        sleep 5
    done
    NAMESPACE_ID=$(aws servicediscovery list-namespaces \
        --query "Namespaces[?Name=='${NAMESPACE}'].Id | [0]" \
        --output text --region "$AWS_REGION")
    log_success "Namespace created: $NAMESPACE_ID"
else
    log_success "Namespace exists: $NAMESPACE_ID"
fi

create_sd_service_if_missing() {
    local name="$1"
    local existing
    existing=$(aws servicediscovery list-services \
        --filters "Name=NAMESPACE_ID,Values=${NAMESPACE_ID},Condition=EQ" \
        --query "Services[?Name=='${name}'].Id | [0]" \
        --output text --region "$AWS_REGION" 2>/dev/null || echo "None")
    if [ "$existing" = "None" ] || [ -z "$existing" ]; then
        aws servicediscovery create-service \
            --name "$name" \
            --dns-config "NamespaceId=${NAMESPACE_ID},DnsRecords=[{Type=A,TTL=60}]" \
            --health-check-custom-config "FailureThreshold=1" \
            --query "Service.Id" \
            --output text \
            --region "$AWS_REGION"
    else
        echo "$existing"
    fi
}

GUACD_SD_ID=$(create_sd_service_if_missing "guacd")
BROKER_SD_ID=$(create_sd_service_if_missing "broker")
log_success "Service discovery ready (guacd.${NAMESPACE}, broker.${NAMESPACE})"

#------------------------------------------------------------------------------
# ALB — Application Load Balancer for Guacamole
#------------------------------------------------------------------------------

log_info "Setting up Application Load Balancer..."

ALB_NAME="${CLUSTER_NAME}-alb"
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names "$ALB_NAME" \
    --query "LoadBalancers[0].LoadBalancerArn" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$ALB_ARN" = "None" ] || [ -z "$ALB_ARN" ]; then
    log_info "Creating ALB: $ALB_NAME"
    SUBNET_LIST=$(echo "$SUBNET_IDS" | tr ',' ' ')
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets $SUBNET_LIST \
        --security-groups "$ALB_SG_ID" \
        --scheme internet-facing \
        --type application \
        --query "LoadBalancers[0].LoadBalancerArn" \
        --output text \
        --region "$AWS_REGION")
    log_success "ALB created: $ALB_ARN"
else
    log_success "ALB exists: $ALB_ARN"
fi

ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --query "LoadBalancers[0].DNSName" \
    --output text \
    --region "$AWS_REGION")

# Target group for Guacamole
TG_NAME="${CLUSTER_NAME}-guacamole-tg"
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$TG_ARN" = "None" ] || [ -z "$TG_ARN" ]; then
    log_info "Creating target group: $TG_NAME"
    TG_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-path "/guacamole/" \
        --health-check-interval-seconds 30 \
        --healthy-threshold-count 2 \
        --query "TargetGroups[0].TargetGroupArn" \
        --output text \
        --region "$AWS_REGION")
    log_success "Target group created"
else
    log_success "Target group exists"
fi

# ALB listener (HTTP/80 or HTTPS/443 depending on ACM cert)
LISTENER_ARN=$(aws elbv2 describe-listeners \
    --load-balancer-arn "$ALB_ARN" \
    --query "Listeners[0].ListenerArn" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$LISTENER_ARN" = "None" ] || [ -z "$LISTENER_ARN" ]; then
    if [ -n "$ACM_CERT_ARN" ]; then
        log_info "Creating HTTPS listener on port 443..."
        LISTENER_ARN=$(aws elbv2 create-listener \
            --load-balancer-arn "$ALB_ARN" \
            --protocol HTTPS \
            --port 443 \
            --certificates "CertificateArn=${ACM_CERT_ARN}" \
            --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" \
            --query "Listeners[0].ListenerArn" \
            --output text \
            --region "$AWS_REGION")
        # Redirect HTTP → HTTPS
        aws elbv2 create-listener \
            --load-balancer-arn "$ALB_ARN" \
            --protocol HTTP \
            --port 80 \
            --default-actions "Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}" \
            --region "$AWS_REGION" > /dev/null 2>/dev/null || true
        log_success "HTTPS listener created (HTTP→HTTPS redirect enabled)"
    else
        log_info "Creating HTTP listener on port 80..."
        LISTENER_ARN=$(aws elbv2 create-listener \
            --load-balancer-arn "$ALB_ARN" \
            --protocol HTTP \
            --port 80 \
            --default-actions "Type=forward,TargetGroupArn=${TG_ARN}" \
            --query "Listeners[0].ListenerArn" \
            --output text \
            --region "$AWS_REGION")
        log_success "HTTP listener created"
        log_warning "No ACM certificate specified — traffic is unencrypted. Pass --acm-cert-arn to enable HTTPS."
    fi
else
    log_success "ALB listener exists"
fi

#------------------------------------------------------------------------------
# ECS cluster
#------------------------------------------------------------------------------

log_info "Setting up ECS cluster: $CLUSTER_NAME"
if ! aws ecs describe-clusters \
        --clusters "$CLUSTER_NAME" \
        --query "clusters[?status=='ACTIVE'].clusterName" \
        --output text \
        --region "$AWS_REGION" | grep -q "$CLUSTER_NAME"; then
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null
    log_success "ECS cluster created"
else
    log_success "ECS cluster exists"
fi

#------------------------------------------------------------------------------
# Task definitions
#------------------------------------------------------------------------------

log_info "Registering ECS task definitions..."

EFS_VOLUME_CONFIG=$(cat << EOF
{
  "name": "recordings",
  "efsVolumeConfiguration": {
    "fileSystemId": "${EFS_ID}",
    "transitEncryption": "ENABLED",
    "authorizationConfig": {
      "accessPointId": "${EFS_AP_ID}",
      "iam": "DISABLED"
    }
  }
}
EOF
)

# guacd task definition
GUACD_TASK_DEF=$(cat << EOF
{
  "family": "britive-sr-guacd",
  "executionRoleArn": "${EXECUTION_ROLE_ARN}",
  "taskRoleArn": "${TASK_ROLE_ARN}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "volumes": [${EFS_VOLUME_CONFIG}],
  "containerDefinitions": [{
    "name": "guacd",
    "image": "guacamole/guacd:1.5.5",
    "essential": true,
    "portMappings": [{"containerPort": 4822, "protocol": "tcp"}],
    "mountPoints": [{"sourceVolume": "recordings", "containerPath": "/recordings"}],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/britive-session-recording/guacd",
        "awslogs-region": "${AWS_REGION}",
        "awslogs-stream-prefix": "guacd"
      }
    }
  }],
  "runtimePlatform": {
    "cpuArchitecture": "X86_64",
    "operatingSystemFamily": "LINUX"
  }
}
EOF
)

GUACD_TASK_ARN=$(aws ecs register-task-definition \
    --cli-input-json "$GUACD_TASK_DEF" \
    --query "taskDefinition.taskDefinitionArn" \
    --output text \
    --region "$AWS_REGION")
log_success "guacd task definition registered"

# guacamole task definition
GUACAMOLE_TASK_DEF=$(cat << EOF
{
  "family": "britive-sr-guacamole",
  "executionRoleArn": "${EXECUTION_ROLE_ARN}",
  "taskRoleArn": "${TASK_ROLE_ARN}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "volumes": [${EFS_VOLUME_CONFIG}],
  "containerDefinitions": [{
    "name": "guacamole",
    "image": "guacamole/guacamole:1.5.5",
    "essential": true,
    "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
    "mountPoints": [{"sourceVolume": "recordings", "containerPath": "/recordings"}],
    "environment": [
      {"name": "GUACD_HOSTNAME", "value": "guacd.${NAMESPACE}"},
      {"name": "GUACD_PORT",     "value": "4822"},
      {"name": "GUACAMOLE_HOME", "value": "/etc/guacamole"}
    ],
    "secrets": ${GUACAMOLE_SECRETS_ARRAY},
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/britive-session-recording/guacamole",
        "awslogs-region": "${AWS_REGION}",
        "awslogs-stream-prefix": "guacamole"
      }
    }
  }],
  "runtimePlatform": {
    "cpuArchitecture": "X86_64",
    "operatingSystemFamily": "LINUX"
  }
}
EOF
)

GUACAMOLE_TASK_ARN=$(aws ecs register-task-definition \
    --cli-input-json "$GUACAMOLE_TASK_DEF" \
    --query "taskDefinition.taskDefinitionArn" \
    --output text \
    --region "$AWS_REGION")
log_success "guacamole task definition registered"

# broker task definition
BROKER_TASK_DEF=$(cat << EOF
{
  "family": "britive-sr-broker",
  "executionRoleArn": "${EXECUTION_ROLE_ARN}",
  "taskRoleArn": "${TASK_ROLE_ARN}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "volumes": [${EFS_VOLUME_CONFIG}],
  "containerDefinitions": [{
    "name": "britive-broker",
    "image": "${ECR_BROKER_URI}:${IMAGE_TAG}",
    "essential": true,
    "portMappings": [{"containerPort": 22, "protocol": "tcp"}],
    "mountPoints": [{"sourceVolume": "recordings", "containerPath": "/recordings"}],
    "secrets": ${ALL_SECRETS_ARRAY},
    "healthCheck": {
      "command": ["CMD-SHELL", "pgrep -f britive-broker > /dev/null || exit 1"],
      "interval": 30,
      "timeout": 10,
      "retries": 3,
      "startPeriod": 60
    },
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/britive-session-recording/broker",
        "awslogs-region": "${AWS_REGION}",
        "awslogs-stream-prefix": "broker"
      }
    }
  }],
  "runtimePlatform": {
    "cpuArchitecture": "X86_64",
    "operatingSystemFamily": "LINUX"
  }
}
EOF
)

BROKER_TASK_ARN=$(aws ecs register-task-definition \
    --cli-input-json "$BROKER_TASK_DEF" \
    --query "taskDefinition.taskDefinitionArn" \
    --output text \
    --region "$AWS_REGION")
log_success "broker task definition registered"

# GuacSync task definition (optional)
if [ "$ENABLE_GUACSYNC" = true ]; then
    GUACSYNC_TASK_DEF=$(cat << EOF
{
  "family": "britive-sr-guacsync",
  "executionRoleArn": "${EXECUTION_ROLE_ARN}",
  "taskRoleArn": "${TASK_ROLE_ARN}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "volumes": [${EFS_VOLUME_CONFIG}],
  "containerDefinitions": [{
    "name": "guacsync",
    "image": "${ECR_GUACSYNC_URI}:${IMAGE_TAG}",
    "essential": true,
    "mountPoints": [{"sourceVolume": "recordings", "containerPath": "/recordings"}],
    "environment": [
      {"name": "REC_DIR",          "value": "/recordings"},
      {"name": "BUCKET",           "value": "${S3_BUCKET}"},
      {"name": "AUTOCONVERT",      "value": "true"},
      {"name": "AUTOCONVERT_WAIT", "value": "30"},
      {"name": "PARALLEL",         "value": "true"},
      {"name": "CONCURRENT_LIMIT", "value": "4"}
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/britive-session-recording/guacsync",
        "awslogs-region": "${AWS_REGION}",
        "awslogs-stream-prefix": "guacsync"
      }
    }
  }],
  "runtimePlatform": {
    "cpuArchitecture": "X86_64",
    "operatingSystemFamily": "LINUX"
  }
}
EOF
)
    GUACSYNC_TASK_ARN=$(aws ecs register-task-definition \
        --cli-input-json "$GUACSYNC_TASK_DEF" \
        --query "taskDefinition.taskDefinitionArn" \
        --output text \
        --region "$AWS_REGION")
    log_success "guacsync task definition registered"
fi

#------------------------------------------------------------------------------
# ECS services
#------------------------------------------------------------------------------

log_info "Deploying ECS services..."

deploy_service() {
    local service_name="$1"
    local task_arn="$2"
    local sg_id="$3"
    local desired="${4:-1}"
    local extra_args="${5:-}"

    local existing
    existing=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$service_name" \
        --query "services[?status=='ACTIVE'].serviceName" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -n "$existing" ]; then
        log_info "Updating service: $service_name"
        aws ecs update-service \
            --cluster "$CLUSTER_NAME" \
            --service "$service_name" \
            --task-definition "$task_arn" \
            --desired-count "$desired" \
            --force-new-deployment \
            --region "$AWS_REGION" > /dev/null
    else
        log_info "Creating service: $service_name"
        # shellcheck disable=SC2086
        aws ecs create-service \
            --cluster "$CLUSTER_NAME" \
            --service-name "$service_name" \
            --task-definition "$task_arn" \
            --desired-count "$desired" \
            --launch-type FARGATE \
            --network-configuration "awsvpcConfiguration={subnets=${SUBNET_ARRAY},securityGroups=[\"${sg_id}\"],assignPublicIp=ENABLED}" \
            --region "$AWS_REGION" \
            $extra_args > /dev/null
    fi
    log_success "Service deployed: $service_name"
}

# guacd — service discovery registration
deploy_service "$ECS_GUACD_SERVICE" "$GUACD_TASK_ARN" "$GUACD_SG_ID" 1 \
    "--service-registries registryArn=${GUACD_SD_ID}"

# broker — service discovery registration
deploy_service "$ECS_BROKER_SERVICE" "$BROKER_TASK_ARN" "$BROKER_SG_ID" "$DESIRED_COUNT" \
    "--service-registries registryArn=${BROKER_SD_ID}"

# guacamole — attached to ALB target group
GUACAMOLE_LB_CONFIG="loadBalancers=[{targetGroupArn=${TG_ARN},containerName=guacamole,containerPort=8080}]"
deploy_service "$ECS_GUACAMOLE_SERVICE" "$GUACAMOLE_TASK_ARN" "$GUACAMOLE_SG_ID" 1 \
    "--load-balancers ${GUACAMOLE_LB_CONFIG}"

# guacsync (optional)
if [ "$ENABLE_GUACSYNC" = true ]; then
    deploy_service "$ECS_GUACSYNC_SERVICE" "$GUACSYNC_TASK_ARN" "$GUACD_SG_ID" 1
fi

#------------------------------------------------------------------------------
# Wait for stabilization
#------------------------------------------------------------------------------

log_info "Waiting for services to stabilize (this may take a few minutes)..."

SERVICES_TO_WATCH=("$ECS_GUACD_SERVICE" "$ECS_BROKER_SERVICE" "$ECS_GUACAMOLE_SERVICE")
[ "$ENABLE_GUACSYNC" = true ] && SERVICES_TO_WATCH+=("$ECS_GUACSYNC_SERVICE")

aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "${SERVICES_TO_WATCH[@]}" \
    --region "$AWS_REGION" || \
    log_warning "Some services may still be stabilizing. Check the AWS console."

log_success "Deployment complete!"

#------------------------------------------------------------------------------
# Status
#------------------------------------------------------------------------------

GUACAMOLE_PROTO="http"
GUACAMOLE_PORT_LABEL="80"
if [ -n "$ACM_CERT_ARN" ]; then
    GUACAMOLE_PROTO="https"
    GUACAMOLE_PORT_LABEL="443"
fi

echo ""
echo "============================================================"
echo "        DEPLOYMENT STATUS"
echo "============================================================"
echo ""
echo "Cluster:        $CLUSTER_NAME"
echo "Region:         $AWS_REGION"
echo "Broker version: $BROKER_VERSION"
echo ""
echo "Services:"
for svc in "${SERVICES_TO_WATCH[@]}"; do
    echo "  - $svc"
done
echo ""
echo "Guacamole URL:  ${GUACAMOLE_PROTO}://${ALB_DNS}/guacamole/"
echo ""
echo "EFS Filesystem: $EFS_ID"
echo "Secrets prefix: $SECRETS_PREFIX"
echo ""
echo "============================================================"
echo ""
log_info "View logs:"
log_info "  aws logs tail /ecs/britive-session-recording/broker     --follow --region $AWS_REGION"
log_info "  aws logs tail /ecs/britive-session-recording/guacd      --follow --region $AWS_REGION"
log_info "  aws logs tail /ecs/britive-session-recording/guacamole  --follow --region $AWS_REGION"
echo ""
log_info "Check service status:"
log_info "  aws ecs describe-services --cluster $CLUSTER_NAME --services ${ECS_BROKER_SERVICE} --region $AWS_REGION"
echo ""
log_info "Manage secrets:"
log_info "  ./manage-secrets.sh list"
log_info "  ./manage-secrets.sh restart-tasks"
echo ""
log_info "AWS Console:"
log_info "  https://${AWS_REGION}.console.aws.amazon.com/ecs/home?region=${AWS_REGION}#/clusters/${CLUSTER_NAME}"
echo ""
log_success "Britive Session Recording deployed to ECS Fargate!"
