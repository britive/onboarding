#!/bin/bash

# Britive Session Recording - AWS ECS Fargate Destroy Script
# Tears down all resources created by deploy.sh
#
# Usage:
#   ./destroy.sh [options]
#
# Options:
#   --region <region>         AWS region (default: us-west-2)
#   --cluster-name <name>     ECS cluster name (default: britive-session-recording)
#   --delete-secrets          Also delete Secrets Manager secrets
#   --delete-ecr              Also delete ECR repositories and images
#   --delete-efs              Also delete EFS filesystem and recordings
#   --delete-all              Delete everything including secrets, ECR, and EFS
#   --yes                     Skip confirmation prompt

set -e

#==============================================================================
# CONFIGURATION — must match what was used in deploy.sh
#==============================================================================

AWS_REGION="${AWS_REGION:-us-west-2}"
CLUSTER_NAME="britive-session-recording"
SECRETS_PREFIX="britive/session-recording"
ECR_BROKER_REPO="britive-session-recording/broker"
ECR_GUACSYNC_REPO="britive-session-recording/guacsync"
EFS_NAME="britive-recordings-efs"
NAMESPACE="britive.local"
EXECUTION_ROLE_NAME="britive-sr-execution-role"
TASK_ROLE_NAME="britive-sr-task-role"
ALB_NAME="${CLUSTER_NAME}-alb"
TG_NAME="britive-sr-guacamole-tg"

DELETE_SECRETS=false
DELETE_ECR=false
DELETE_EFS=false
SKIP_CONFIRM=false

#==============================================================================
# Colors
#==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[DONE]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[SKIP]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

#==============================================================================
# Parse CLI arguments
#==============================================================================

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --region)          AWS_REGION="$2"; shift ;;
        --cluster-name)    CLUSTER_NAME="$2"; shift ;;
        --delete-secrets)  DELETE_SECRETS=true ;;
        --delete-ecr)      DELETE_ECR=true ;;
        --delete-efs)      DELETE_EFS=true ;;
        --delete-all)      DELETE_SECRETS=true; DELETE_ECR=true; DELETE_EFS=true ;;
        --yes)             SKIP_CONFIRM=true ;;
        *)                 log_error "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

# Re-derive names after parsing --cluster-name
ALB_NAME="${CLUSTER_NAME}-alb"
ECS_BROKER_SERVICE="${CLUSTER_NAME}-broker-service"
ECS_GUACD_SERVICE="${CLUSTER_NAME}-guacd-service"
ECS_GUACAMOLE_SERVICE="${CLUSTER_NAME}-guacamole-service"
ECS_GUACSYNC_SERVICE="${CLUSTER_NAME}-guacsync-service"

#==============================================================================
# Confirmation
#==============================================================================

echo ""
echo "============================================================"
echo "  DESTROY: Britive Session Recording (ECS Fargate)"
echo "============================================================"
echo ""
echo "  Cluster:   $CLUSTER_NAME"
echo "  Region:    $AWS_REGION"
echo ""
echo "  Will delete:"
echo "    - ECS services (broker, guacd, guacamole, guacsync)"
echo "    - ECS cluster"
echo "    - ALB, target group, and listeners"
echo "    - Cloud Map service discovery namespace"
echo "    - Security groups (alb, guacamole, guacd, broker)"
echo "    - IAM roles and inline policies"
echo "    - CloudWatch log groups"
echo "    - Task definitions (deregistered)"
[ "$DELETE_SECRETS" = true ] && echo "    - Secrets Manager secrets (${SECRETS_PREFIX}/*)"
[ "$DELETE_ECR" = true ]     && echo "    - ECR repositories and images"
[ "$DELETE_EFS" = true ]     && echo "    - EFS filesystem and all recordings"
echo ""

if [ "$SKIP_CONFIRM" != true ]; then
    read -r -p "Type 'destroy' to confirm: " confirm
    if [ "$confirm" != "destroy" ]; then
        echo "Aborted."
        exit 0
    fi
fi

echo ""

#==============================================================================
# Helper
#==============================================================================

# Run a command, suppress errors if the resource doesn't exist
safe() {
    "$@" 2>/dev/null || true
}

#==============================================================================
# 1. ECS Services — scale to 0, then delete
#==============================================================================

log_info "Removing ECS services..."

for svc in "$ECS_BROKER_SERVICE" "$ECS_GUACD_SERVICE" "$ECS_GUACAMOLE_SERVICE" "$ECS_GUACSYNC_SERVICE"; do
    EXISTS=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$svc" \
        --query "services[?status=='ACTIVE'].serviceName" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -n "$EXISTS" ]; then
        log_info "  Scaling down $svc..."
        safe aws ecs update-service \
            --cluster "$CLUSTER_NAME" \
            --service "$svc" \
            --desired-count 0 \
            --region "$AWS_REGION" > /dev/null

        log_info "  Deleting $svc..."
        safe aws ecs delete-service \
            --cluster "$CLUSTER_NAME" \
            --service "$svc" \
            --force \
            --region "$AWS_REGION" > /dev/null
        log_success "Deleted service: $svc"
    else
        log_warning "Service not found: $svc"
    fi
done

#==============================================================================
# 2. ECS Cluster
#==============================================================================

log_info "Deleting ECS cluster: $CLUSTER_NAME"
safe aws ecs delete-cluster --cluster "$CLUSTER_NAME" --region "$AWS_REGION" > /dev/null
log_success "ECS cluster deleted"

#==============================================================================
# 3. Task definitions — deregister all revisions
#==============================================================================

log_info "Deregistering task definitions..."
for family in britive-sr-guacd britive-sr-guacamole britive-sr-broker britive-sr-guacsync; do
    TASK_ARNS=$(aws ecs list-task-definitions \
        --family-prefix "$family" \
        --query "taskDefinitionArns[]" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -n "$TASK_ARNS" ]; then
        for arn in $TASK_ARNS; do
            safe aws ecs deregister-task-definition \
                --task-definition "$arn" \
                --region "$AWS_REGION" > /dev/null
        done
        log_success "Deregistered: $family"
    else
        log_warning "No task definitions: $family"
    fi
done

#==============================================================================
# 4. ALB — listeners, target group, load balancer
#==============================================================================

log_info "Removing ALB resources..."

ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names "$ALB_NAME" \
    --query "LoadBalancers[0].LoadBalancerArn" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$ALB_ARN" != "None" ] && [ -n "$ALB_ARN" ]; then
    # Delete all listeners first
    LISTENER_ARNS=$(aws elbv2 describe-listeners \
        --load-balancer-arn "$ALB_ARN" \
        --query "Listeners[*].ListenerArn" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    for listener in $LISTENER_ARNS; do
        safe aws elbv2 delete-listener --listener-arn "$listener" --region "$AWS_REGION"
    done
    log_success "ALB listeners deleted"

    # Delete the ALB
    safe aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION"
    log_success "ALB deleted: $ALB_NAME"

    # Wait for ALB to fully deregister before deleting target group
    log_info "Waiting for ALB to finish draining..."
    safe aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN" --region "$AWS_REGION"
else
    log_warning "ALB not found: $ALB_NAME"
fi

# Delete target group
TG_ARN=$(aws elbv2 describe-target-groups \
    --names "$TG_NAME" \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$TG_ARN" != "None" ] && [ -n "$TG_ARN" ]; then
    safe aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region "$AWS_REGION"
    log_success "Target group deleted: $TG_NAME"
else
    log_warning "Target group not found: $TG_NAME"
fi

#==============================================================================
# 5. Cloud Map — service discovery
#==============================================================================

log_info "Removing Cloud Map service discovery..."

NAMESPACE_ID=$(aws servicediscovery list-namespaces \
    --query "Namespaces[?Name=='${NAMESPACE}'].Id | [0]" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

if [ "$NAMESPACE_ID" != "None" ] && [ -n "$NAMESPACE_ID" ]; then
    # Delete all services in the namespace first
    SD_SERVICES=$(aws servicediscovery list-services \
        --filters "Name=NAMESPACE_ID,Values=${NAMESPACE_ID},Condition=EQ" \
        --query "Services[*].Id" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    for sd_svc_id in $SD_SERVICES; do
        # Deregister all instances first
        INSTANCES=$(aws servicediscovery list-instances \
            --service-id "$sd_svc_id" \
            --query "Instances[*].Id" \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")

        for inst_id in $INSTANCES; do
            safe aws servicediscovery deregister-instance \
                --service-id "$sd_svc_id" \
                --instance-id "$inst_id" \
                --region "$AWS_REGION" > /dev/null
        done

        safe aws servicediscovery delete-service \
            --id "$sd_svc_id" \
            --region "$AWS_REGION"
    done
    log_success "Cloud Map services deleted"

    # Delete the namespace
    safe aws servicediscovery delete-namespace \
        --id "$NAMESPACE_ID" \
        --region "$AWS_REGION"
    log_success "Cloud Map namespace deleted: $NAMESPACE"
else
    log_warning "Cloud Map namespace not found: $NAMESPACE"
fi

#==============================================================================
# 6. EFS
#==============================================================================

if [ "$DELETE_EFS" = true ]; then
    log_info "Removing EFS filesystem..."

    EFS_ID=$(aws efs describe-file-systems \
        --query "FileSystems[?Name=='${EFS_NAME}'].FileSystemId | [0]" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")

    if [ "$EFS_ID" != "None" ] && [ -n "$EFS_ID" ]; then
        # Delete access points
        AP_IDS=$(aws efs describe-access-points \
            --file-system-id "$EFS_ID" \
            --query "AccessPoints[*].AccessPointId" \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")

        for ap in $AP_IDS; do
            safe aws efs delete-access-point --access-point-id "$ap" --region "$AWS_REGION"
        done

        # Delete mount targets (must be removed before filesystem)
        MT_IDS=$(aws efs describe-mount-targets \
            --file-system-id "$EFS_ID" \
            --query "MountTargets[*].MountTargetId" \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")

        for mt in $MT_IDS; do
            safe aws efs delete-mount-target --mount-target-id "$mt" --region "$AWS_REGION"
        done

        if [ -n "$MT_IDS" ]; then
            log_info "Waiting for mount targets to be removed..."
            sleep 30
        fi

        safe aws efs delete-file-system --file-system-id "$EFS_ID" --region "$AWS_REGION"
        log_success "EFS deleted: $EFS_ID"
    else
        log_warning "EFS not found: $EFS_NAME"
    fi
else
    log_warning "Skipping EFS deletion (use --delete-efs or --delete-all to remove)"
fi

#==============================================================================
# 7. Security groups
#==============================================================================

log_info "Removing security groups..."

# Get VPC ID for SG lookup
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "None")

delete_sg() {
    local name="$1"
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${name}" "Name=vpc-id,Values=${VPC_ID}" \
        --query "SecurityGroups[0].GroupId" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "None")

    if [ "$sg_id" != "None" ] && [ -n "$sg_id" ]; then
        # Revoke all ingress rules first to clear cross-SG dependencies
        RULES=$(aws ec2 describe-security-groups \
            --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissions" \
            --output json \
            --region "$AWS_REGION" 2>/dev/null || echo "[]")

        if [ "$RULES" != "[]" ] && [ -n "$RULES" ]; then
            safe aws ec2 revoke-security-group-ingress \
                --group-id "$sg_id" \
                --ip-permissions "$RULES" \
                --region "$AWS_REGION" > /dev/null
        fi

        safe aws ec2 delete-security-group --group-id "$sg_id" --region "$AWS_REGION"
        log_success "Deleted security group: $name ($sg_id)"
    else
        log_warning "Security group not found: $name"
    fi
}

# Delete in reverse dependency order — ALB SG last since others may reference it
for sg_name in britive-sr-broker-sg britive-sr-guacd-sg britive-sr-guacamole-sg britive-sr-efs-sg britive-sr-alb-sg; do
    delete_sg "$sg_name"
done

#==============================================================================
# 8. IAM roles and inline policies
#==============================================================================

log_info "Removing IAM roles..."

delete_role() {
    local role_name="$1"

    if ! aws iam get-role --role-name "$role_name" &> /dev/null; then
        log_warning "IAM role not found: $role_name"
        return
    fi

    # Detach managed policies
    ATTACHED=$(aws iam list-attached-role-policies \
        --role-name "$role_name" \
        --query "AttachedPolicies[*].PolicyArn" \
        --output text 2>/dev/null || echo "")

    for policy_arn in $ATTACHED; do
        safe aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
    done

    # Delete inline policies
    INLINE=$(aws iam list-role-policies \
        --role-name "$role_name" \
        --query "PolicyNames[]" \
        --output text 2>/dev/null || echo "")

    for policy_name in $INLINE; do
        safe aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name"
    done

    safe aws iam delete-role --role-name "$role_name"
    log_success "Deleted IAM role: $role_name"
}

delete_role "$EXECUTION_ROLE_NAME"
delete_role "$TASK_ROLE_NAME"

#==============================================================================
# 9. CloudWatch log groups
#==============================================================================

log_info "Removing CloudWatch log groups..."
for svc in broker guacd guacamole guacsync; do
    LOG_GROUP="/ecs/britive-session-recording/${svc}"
    if aws logs describe-log-groups \
        --log-group-name-prefix "$LOG_GROUP" \
        --query "logGroups[?logGroupName=='${LOG_GROUP}'].logGroupName" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null | grep -q "$LOG_GROUP"; then
        safe aws logs delete-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION"
        log_success "Deleted log group: $LOG_GROUP"
    else
        log_warning "Log group not found: $LOG_GROUP"
    fi
done

#==============================================================================
# 10. Secrets Manager
#==============================================================================

if [ "$DELETE_SECRETS" = true ]; then
    log_info "Removing Secrets Manager secrets..."

    SECRET_ARNS=$(aws secretsmanager list-secrets \
        --filter Key=name,Values="${SECRETS_PREFIX}" \
        --query "SecretList[*].ARN" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -n "$SECRET_ARNS" ]; then
        for arn in $SECRET_ARNS; do
            NAME=$(aws secretsmanager describe-secret \
                --secret-id "$arn" \
                --query "Name" \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || echo "$arn")
            safe aws secretsmanager delete-secret \
                --secret-id "$arn" \
                --force-delete-without-recovery \
                --region "$AWS_REGION" > /dev/null
            log_success "Deleted secret: $NAME"
        done
    else
        log_warning "No secrets found under ${SECRETS_PREFIX}/"
    fi
else
    log_warning "Skipping secrets deletion (use --delete-secrets or --delete-all to remove)"
fi

#==============================================================================
# 11. ECR repositories
#==============================================================================

if [ "$DELETE_ECR" = true ]; then
    log_info "Removing ECR repositories..."

    for repo in "$ECR_BROKER_REPO" "$ECR_GUACSYNC_REPO"; do
        if aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" &> /dev/null; then
            safe aws ecr delete-repository \
                --repository-name "$repo" \
                --force \
                --region "$AWS_REGION" > /dev/null
            log_success "Deleted ECR repo: $repo"
        else
            log_warning "ECR repo not found: $repo"
        fi
    done
else
    log_warning "Skipping ECR deletion (use --delete-ecr or --delete-all to remove)"
fi

#==============================================================================
# Done
#==============================================================================

echo ""
echo "============================================================"
echo "        DESTROY COMPLETE"
echo "============================================================"
echo ""
echo "  Cluster:  $CLUSTER_NAME"
echo "  Region:   $AWS_REGION"
echo ""
[ "$DELETE_SECRETS" != true ] && echo "  Note: Secrets preserved — use --delete-secrets to remove"
[ "$DELETE_ECR" != true ]     && echo "  Note: ECR repos preserved — use --delete-ecr to remove"
[ "$DELETE_EFS" != true ]     && echo "  Note: EFS filesystem preserved — use --delete-efs to remove"
echo ""
echo "  To redeploy: ./deploy.sh"
echo ""
echo "============================================================"
