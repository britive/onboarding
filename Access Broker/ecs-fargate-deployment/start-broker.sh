#!/bin/bash

# Britive Access Broker startup script for ECS Fargate
# Handles graceful shutdown, secrets management, and logging

# Signal handler for graceful shutdown
cleanup() {
    echo "Received shutdown signal, cleaning up..."
    if [ ! -z "$BROKER_PID" ]; then
        kill -TERM "$BROKER_PID" 2>/dev/null
        wait "$BROKER_PID" 2>/dev/null
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT

# Optional startup delay (default 5 seconds)
DELAY=${1:-5}
if [ "$DELAY" -gt 0 ]; then
    echo "Waiting $DELAY seconds before starting..."
    sleep $DELAY
fi

# Secrets directory for file-based secrets
SECRETS_DIR="${SECRETS_DIR:-/root/broker/secrets}"
mkdir -p "$SECRETS_DIR"

# Write environment-based secrets to files for applications that need file-based access
# This allows secrets to be accessed either as environment variables or files
echo "Setting up secrets directory: $SECRETS_DIR"

# Write BRITIVE_TOKEN to file if set
if [ ! -z "$BRITIVE_TOKEN" ]; then
    echo "$BRITIVE_TOKEN" > "$SECRETS_DIR/BRITIVE_TOKEN"
    chmod 600 "$SECRETS_DIR/BRITIVE_TOKEN"
    echo "BRITIVE_TOKEN written to secrets directory"
fi

# Write any custom secrets that start with BROKER_ prefix to files
env | grep "^BROKER_" | while IFS='=' read -r key value; do
    if [ ! -z "$value" ]; then
        echo "$value" > "$SECRETS_DIR/$key"
        chmod 600 "$SECRETS_DIR/$key"
        echo "$key written to secrets directory"
    fi
done

# List secrets directory contents (without showing values)
echo "Secrets directory contents:"
ls -la "$SECRETS_DIR" 2>/dev/null || echo "  (empty)"

# Setup kubeconfig from environment if provided
if [ ! -z "$KUBECONFIG_BASE64" ]; then
    echo "Setting up kubeconfig from environment..."
    mkdir -p /root/.kube
    echo "$KUBECONFIG_BASE64" | base64 -d > /root/.kube/config
    chmod 600 /root/.kube/config
    export KUBECONFIG=/root/.kube/config
    echo "Kubeconfig configured"
fi

# Setup kubeconfig for EKS cluster if EKS variables provided
if [ ! -z "$EKS_CLUSTER_NAME" ] && [ ! -z "$AWS_REGION" ]; then
    echo "Configuring kubectl for EKS cluster: $EKS_CLUSTER_NAME"
    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"
    echo "EKS kubeconfig configured"
fi

echo "Starting Britive broker..."
cd /root/broker
# Note: broker stdout/stderr is written to /var/log/britive-broker.log (visible inside container).
# Startup messages from this script are captured by supervisord → CloudWatch via awslogs driver.
java -jar britive-broker-2.0.0.jar >> /var/log/britive-broker.log 2>&1 &
BROKER_PID=$!

echo "Broker started with PID: $BROKER_PID"
wait $BROKER_PID
