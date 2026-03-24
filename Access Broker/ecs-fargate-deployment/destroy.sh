#!/bin/bash

# Britive Access Broker - AWS ECS Fargate Destroy Script
# Tears down all resources created by deploy.sh
#
# Usage:
#   ./destroy.sh              # Interactive mode (prompts for confirmation)
#   ./destroy.sh --force      # Skip confirmation prompts
#   ./destroy.sh --keep-secrets  # Destroy everything except Secrets Manager secrets

set -e

#==============================================================================
# CONFIGURATION — must match the values used in deploy.sh
#==============================================================================

AWS_REGION="${AWS_REGION:-us-west-2}"

ECS_CLUSTER_NAME="britive-broker-cluster"
ECS_SERVICE_NAME="britive-broker-service"
ECR_REPO_NAME="britive-broker"
TASK_FAMILY="britive-broker"

SECRETS_PREFIX="britive-broker/secrets"

EXECUTION_ROLE_NAME="ecsTaskExecutionRole"
TASK_ROLE_NAME="britive-broker-task-role"

SECURITY_GROUP_NAME="britive-broker-sg"
LOG_GROUP_NAME="/ecs/britive-broker"

#==============================================================================
# DO NOT MODIFY BELOW THIS LINE
#==============================================================================

# Parse flags
FORCE=false
KEEP_SECRETS=false
for arg in "$@"; do
    case $arg in
        --force)      FORCE=true ;;
        --keep-secrets) KEEP_SECRETS=true ;;
    esac
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

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install it."
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run: aws configure"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_info "AWS Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"

# Confirmation prompt
if [ "$FORCE" = false ]; then
    echo ""
    log_warning "This will destroy the following resources in account $AWS_ACCOUNT_ID ($AWS_REGION):"
    echo "  - ECS Service:        $ECS_SERVICE_NAME"
    echo "  - ECS Cluster:        $ECS_CLUSTER_NAME"
    echo "  - Task Definitions:   $TASK_FAMILY (all revisions)"
    echo "  - ECR Repository:     $ECR_REPO_NAME (all images)"
    echo "  - IAM Role:           $TASK_ROLE_NAME"
    echo "  - IAM Inline Policy:  britive-secrets-access (on $EXECUTION_ROLE_NAME)"
    echo "  - Security Group:     $SECURITY_GROUP_NAME"
    echo "  - CloudWatch Logs:    $LOG_GROUP_NAME"
    if [ "$KEEP_SECRETS" = false ]; then
        echo "  - Secrets Manager:    ${SECRETS_PREFIX}/* (ALL secrets)"
    else
        echo "  - Secrets Manager:    (KEPT — --keep-secrets flag set)"
    fi
    echo ""
    read -p "Are you sure? Type 'yes' to proceed: " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_info "Aborted."
        exit 0
    fi
    echo ""
fi

ERRORS=0

# Helper: run a command, log warning on failure but continue
try() {
    local description="$1"
    shift
    log_info "$description"
    if "$@" 2>/dev/null; then
        log_success "$description — done"
    else
        log_warning "$description — skipped (not found or already deleted)"
        ((ERRORS++)) || true
    fi
}

#==============================================================================
# 1. Stop and delete ECS service
#==============================================================================

# Scale to 0 first to stop running tasks
log_info "Scaling ECS service to 0..."
aws ecs update-service \
    --cluster "$ECS_CLUSTER_NAME" \
    --service "$ECS_SERVICE_NAME" \
    --desired-count 0 \
    --region "$AWS_REGION" > /dev/null 2>&1 || true

log_info "Waiting for tasks to drain..."
aws ecs wait services-stable \
    --cluster "$ECS_CLUSTER_NAME" \
    --services "$ECS_SERVICE_NAME" \
    --region "$AWS_REGION" 2>/dev/null || true

try "Deleting ECS service" \
    aws ecs delete-service \
        --cluster "$ECS_CLUSTER_NAME" \
        --service "$ECS_SERVICE_NAME" \
        --force \
        --region "$AWS_REGION"

#==============================================================================
# 2. Deregister all task definition revisions
#==============================================================================

log_info "Deregistering task definitions ($TASK_FAMILY)..."
TASK_DEFS=$(aws ecs list-task-definitions \
    --family-prefix "$TASK_FAMILY" \
    --query "taskDefinitionArns[]" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$TASK_DEFS" ]; then
    for td in $TASK_DEFS; do
        aws ecs deregister-task-definition --task-definition "$td" --region "$AWS_REGION" > /dev/null 2>&1 || true
    done
    log_success "Task definitions deregistered"
else
    log_warning "No task definitions found"
fi

#==============================================================================
# 3. Delete ECS cluster
#==============================================================================

try "Deleting ECS cluster" \
    aws ecs delete-cluster \
        --cluster "$ECS_CLUSTER_NAME" \
        --region "$AWS_REGION"

#==============================================================================
# 4. Delete ECR repository (and all images)
#==============================================================================

try "Deleting ECR repository" \
    aws ecr delete-repository \
        --repository-name "$ECR_REPO_NAME" \
        --force \
        --region "$AWS_REGION"

#==============================================================================
# 5. Delete Secrets Manager secrets
#==============================================================================

if [ "$KEEP_SECRETS" = false ]; then
    log_info "Deleting Secrets Manager secrets (${SECRETS_PREFIX}/*)..."
    SECRETS=$(aws secretsmanager list-secrets \
        --filter Key=name,Values="$SECRETS_PREFIX" \
        --query "SecretList[*].Name" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -n "$SECRETS" ]; then
        for secret in $SECRETS; do
            aws secretsmanager delete-secret \
                --secret-id "$secret" \
                --force-delete-without-recovery \
                --region "$AWS_REGION" > /dev/null 2>&1 || true
        done
        log_success "Secrets deleted"
    else
        log_warning "No secrets found"
    fi
else
    log_info "Keeping Secrets Manager secrets (--keep-secrets)"
fi

#==============================================================================
# 6. Clean up IAM roles and policies
#==============================================================================

# Remove inline britive-secrets-access policy from execution role
# (don't delete the execution role itself — it may be shared with other ECS services)
try "Removing britive-secrets-access policy from $EXECUTION_ROLE_NAME" \
    aws iam delete-role-policy \
        --role-name "$EXECUTION_ROLE_NAME" \
        --policy-name "britive-secrets-access"

# Delete the broker task role (inline policy + role)
log_info "Deleting task role: $TASK_ROLE_NAME..."
aws iam delete-role-policy \
    --role-name "$TASK_ROLE_NAME" \
    --policy-name "britive-broker-policy" 2>/dev/null || true

try "Deleting IAM role $TASK_ROLE_NAME" \
    aws iam delete-role \
        --role-name "$TASK_ROLE_NAME"

#==============================================================================
# 7. Delete CloudWatch log group
#==============================================================================

try "Deleting CloudWatch log group" \
    aws logs delete-log-group \
        --log-group-name "$LOG_GROUP_NAME" \
        --region "$AWS_REGION"

#==============================================================================
# 8. Delete security group
#==============================================================================

log_info "Deleting security group: $SECURITY_GROUP_NAME..."
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
    --query "SecurityGroups[0].GroupId" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    try "Deleting security group $SG_ID" \
        aws ec2 delete-security-group \
            --group-id "$SG_ID" \
            --region "$AWS_REGION"
else
    log_warning "Security group not found"
fi

#==============================================================================
# Done
#==============================================================================

echo ""
echo "=============================================="
echo "         DESTROY COMPLETE"
echo "=============================================="
echo ""
if [ "$ERRORS" -gt 0 ]; then
    log_warning "$ERRORS resource(s) were already missing or could not be deleted."
    log_info "This is normal if they were previously deleted or never created."
else
    log_success "All resources destroyed successfully."
fi
echo ""
