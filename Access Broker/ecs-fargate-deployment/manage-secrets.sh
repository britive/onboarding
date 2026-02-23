#!/bin/bash

# Britive Access Broker - Secrets Management Script
# This script manages secrets in AWS Secrets Manager for the ECS Fargate deployment
#
# Usage:
#   ./manage-secrets.sh <command> [options]
#
# Commands:
#   list                    - List all secrets in the britive-broker namespace
#   get <secret-name>       - Get a secret value
#   set <secret-name> <value> - Create or update a secret
#   delete <secret-name>    - Delete a secret
#   sync                    - Sync secrets from secrets.json to AWS Secrets Manager
#   export                  - Export current AWS secrets to secrets.json format
#   restart-tasks           - Force restart ECS tasks to pick up new secrets

set -e

#==============================================================================
# CONFIGURATION
#==============================================================================

AWS_REGION="${AWS_REGION:-us-west-2}"
SECRETS_PREFIX="britive-broker/secrets"
ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME:-britive-broker-cluster}"
ECS_SERVICE_NAME="${ECS_SERVICE_NAME:-britive-broker-service}"

#==============================================================================
# Colors for output
#==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

#==============================================================================
# Functions
#==============================================================================

check_prerequisites() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi

    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run: aws configure"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Please install it: brew install jq (macOS) or apt install jq (Linux)"
        exit 1
    fi
}

list_secrets() {
    log_info "Listing secrets in AWS Secrets Manager (prefix: ${SECRETS_PREFIX})..."
    echo ""

    # Get all secrets with the prefix
    SECRETS=$(aws secretsmanager list-secrets \
        --filter Key=name,Values="${SECRETS_PREFIX}" \
        --query "SecretList[*].[Name,Description,LastChangedDate]" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -z "$SECRETS" ]; then
        log_warning "No secrets found with prefix: ${SECRETS_PREFIX}"
        echo ""
        echo "To create secrets, use:"
        echo "  ./manage-secrets.sh set <secret-name> <value>"
        echo "  ./manage-secrets.sh sync  (to sync from secrets.json)"
        return
    fi

    echo "----------------------------------------------------------------------"
    printf "%-40s %-25s %s\n" "SECRET NAME" "LAST MODIFIED" "DESCRIPTION"
    echo "----------------------------------------------------------------------"

    echo "$SECRETS" | while IFS=$'\t' read -r name desc modified; do
        # Extract the short name (remove prefix)
        short_name="${name#${SECRETS_PREFIX}/}"
        # Format the date if available
        if [ "$modified" != "None" ] && [ -n "$modified" ]; then
            mod_date=$(echo "$modified" | cut -d'T' -f1)
        else
            mod_date="N/A"
        fi
        printf "%-40s %-25s %s\n" "$short_name" "$mod_date" "${desc:-N/A}"
    done
    echo "----------------------------------------------------------------------"
}

get_secret() {
    local secret_name="$1"

    if [ -z "$secret_name" ]; then
        log_error "Usage: ./manage-secrets.sh get <secret-name>"
        exit 1
    fi

    local full_secret_name="${SECRETS_PREFIX}/${secret_name}"

    log_info "Retrieving secret: $secret_name"

    SECRET_VALUE=$(aws secretsmanager get-secret-value \
        --secret-id "$full_secret_name" \
        --query "SecretString" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$SECRET_VALUE" ]; then
        log_error "Secret not found: $secret_name"
        exit 1
    fi

    echo ""
    echo "Secret: $secret_name"
    echo "Value: $SECRET_VALUE"
    echo ""
}

set_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local description="${3:-Britive broker secret}"

    if [ -z "$secret_name" ] || [ -z "$secret_value" ]; then
        log_error "Usage: ./manage-secrets.sh set <secret-name> <value> [description]"
        exit 1
    fi

    local full_secret_name="${SECRETS_PREFIX}/${secret_name}"

    # Check if secret exists
    if aws secretsmanager describe-secret --secret-id "$full_secret_name" --region "$AWS_REGION" &> /dev/null; then
        log_info "Updating existing secret: $secret_name"
        aws secretsmanager update-secret \
            --secret-id "$full_secret_name" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" > /dev/null
        log_success "Secret updated: $secret_name"
    else
        log_info "Creating new secret: $secret_name"
        aws secretsmanager create-secret \
            --name "$full_secret_name" \
            --description "$description" \
            --secret-string "$secret_value" \
            --region "$AWS_REGION" > /dev/null
        log_success "Secret created: $secret_name"
    fi

    echo ""
    log_warning "Note: ECS tasks need to be restarted to pick up the new secret value."
    echo "Run: ./manage-secrets.sh restart-tasks"
}

delete_secret() {
    local secret_name="$1"

    if [ -z "$secret_name" ]; then
        log_error "Usage: ./manage-secrets.sh delete <secret-name>"
        exit 1
    fi

    local full_secret_name="${SECRETS_PREFIX}/${secret_name}"

    log_warning "This will permanently delete secret: $secret_name"
    read -p "Are you sure? (y/N): " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "Cancelled."
        exit 0
    fi

    aws secretsmanager delete-secret \
        --secret-id "$full_secret_name" \
        --force-delete-without-recovery \
        --region "$AWS_REGION" > /dev/null

    log_success "Secret deleted: $secret_name"
}

sync_secrets() {
    local secrets_file="${1:-secrets.json}"

    if [ ! -f "$secrets_file" ]; then
        log_error "Secrets file not found: $secrets_file"
        log_info "Create a secrets.json file or specify the path: ./manage-secrets.sh sync <path>"
        exit 1
    fi

    log_info "Syncing secrets from: $secrets_file"
    echo ""

    # Track created/updated secrets for IAM policy
    declare -a SECRET_ARNS

    # Process main secrets
    SECRETS=$(jq -r '.secrets | to_entries[] | select(.value.value != "" and .value.value != "your-britive-token-here") | @json' "$secrets_file" 2>/dev/null)

    if [ -n "$SECRETS" ]; then
        echo "$SECRETS" | while read -r entry; do
            key=$(echo "$entry" | jq -r '.key')
            value=$(echo "$entry" | jq -r '.value.value')
            desc=$(echo "$entry" | jq -r '.value.description // "Britive broker secret"')

            if [ -n "$value" ]; then
                log_info "Syncing secret: $key"
                set_secret "$key" "$value" "$desc" 2>/dev/null || true
            fi
        done
    fi

    # Process custom secrets
    CUSTOM_SECRETS=$(jq -r '.custom_secrets | to_entries[] | select(.value != "") | @json' "$secrets_file" 2>/dev/null)

    if [ -n "$CUSTOM_SECRETS" ]; then
        echo "$CUSTOM_SECRETS" | while read -r entry; do
            key=$(echo "$entry" | jq -r '.key')
            value=$(echo "$entry" | jq -r '.value')

            if [ -n "$value" ]; then
                log_info "Syncing custom secret: $key"
                set_secret "$key" "$value" "Custom secret for Britive broker" 2>/dev/null || true
            fi
        done
    fi

    echo ""
    log_success "Secrets synced to AWS Secrets Manager"
    echo ""
    log_info "Next steps:"
    echo "  1. Run ./deploy.sh to update IAM permissions and task definition"
    echo "  2. Or run ./manage-secrets.sh restart-tasks to restart with existing config"
}

export_secrets() {
    log_info "Exporting secrets from AWS Secrets Manager..."

    echo "{"
    echo '  "secrets": {'

    SECRETS=$(aws secretsmanager list-secrets \
        --filter Key=name,Values="${SECRETS_PREFIX}" \
        --query "SecretList[*].Name" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ -n "$SECRETS" ]; then
        first=true
        for secret_name in $SECRETS; do
            short_name="${secret_name#${SECRETS_PREFIX}/}"

            if [ "$first" = true ]; then
                first=false
            else
                echo ","
            fi

            # Values are intentionally not fetched here; use 'get <name>' to retrieve individual values
            echo -n "    \"${short_name}\": \"***HIDDEN***\""
        done
    fi

    echo ""
    echo '  }'
    echo "}"

    echo ""
    log_warning "Secret values are hidden. Use 'get' command to retrieve individual values."
}

restart_tasks() {
    log_info "Forcing ECS service to restart tasks..."

    # Check if service exists
    SERVICE_STATUS=$(aws ecs describe-services \
        --cluster "$ECS_CLUSTER_NAME" \
        --services "$ECS_SERVICE_NAME" \
        --query "services[0].status" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "")

    if [ "$SERVICE_STATUS" != "ACTIVE" ]; then
        log_error "ECS service not found or not active: $ECS_SERVICE_NAME"
        log_info "Cluster: $ECS_CLUSTER_NAME"
        exit 1
    fi

    aws ecs update-service \
        --cluster "$ECS_CLUSTER_NAME" \
        --service "$ECS_SERVICE_NAME" \
        --force-new-deployment \
        --region "$AWS_REGION" > /dev/null

    log_success "Service update triggered. New tasks will be launched with updated secrets."
    echo ""
    log_info "Monitor progress:"
    echo "  aws ecs describe-services --cluster $ECS_CLUSTER_NAME --services $ECS_SERVICE_NAME --region $AWS_REGION"
}

update_iam_permissions() {
    log_info "Updating IAM permissions for secrets access..."

    EXECUTION_ROLE_NAME="ecsTaskExecutionRole"

    # Get all secret ARNs
    SECRET_ARNS=$(aws secretsmanager list-secrets \
        --filter Key=name,Values="${SECRETS_PREFIX}" \
        --query "SecretList[*].ARN" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    if [ -z "$SECRET_ARNS" ]; then
        log_warning "No secrets found to configure permissions for."
        return
    fi

    # Build JSON array of ARNs
    ARN_ARRAY=$(echo "$SECRET_ARNS" | tr '\t' '\n' | jq -R . | jq -s .)

    # Create policy document
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

    rm -f /tmp/secrets-policy.json

    SECRET_COUNT=$(echo "$SECRET_ARNS" | tr '\t' '\n' | grep -c . || echo 0)
    log_success "IAM permissions updated for ${SECRET_COUNT} secrets"
}

show_help() {
    echo "Britive Access Broker - Secrets Management"
    echo ""
    echo "Usage: ./manage-secrets.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list                        List all secrets in AWS Secrets Manager"
    echo "  get <name>                  Get a secret value"
    echo "  set <name> <value> [desc]   Create or update a secret"
    echo "  delete <name>               Delete a secret"
    echo "  sync [file]                 Sync secrets from secrets.json (or specified file)"
    echo "  export                      Export secrets list (values hidden)"
    echo "  restart-tasks               Restart ECS tasks to pick up new secrets"
    echo "  update-iam                  Update IAM permissions for all secrets"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION          AWS region (default: us-west-2)"
    echo "  ECS_CLUSTER_NAME    ECS cluster name (default: britive-broker-cluster)"
    echo "  ECS_SERVICE_NAME    ECS service name (default: britive-broker-service)"
    echo ""
    echo "Examples:"
    echo "  ./manage-secrets.sh list"
    echo "  ./manage-secrets.sh set MY_API_KEY 'secret-value-here' 'API key for external service'"
    echo "  ./manage-secrets.sh get MY_API_KEY"
    echo "  ./manage-secrets.sh sync"
    echo "  ./manage-secrets.sh restart-tasks"
}

#==============================================================================
# Main
#==============================================================================

check_prerequisites

case "${1:-}" in
    list)
        list_secrets
        ;;
    get)
        get_secret "$2"
        ;;
    set)
        set_secret "$2" "$3" "$4"
        ;;
    delete)
        delete_secret "$2"
        ;;
    sync)
        sync_secrets "$2"
        ;;
    export)
        export_secrets
        ;;
    restart-tasks|restart)
        restart_tasks
        ;;
    update-iam)
        update_iam_permissions
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
