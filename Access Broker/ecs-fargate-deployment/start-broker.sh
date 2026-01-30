#!/bin/bash

# Britive Access Broker startup script for ECS Fargate
# Handles graceful shutdown and logging

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
java -Djavax.net.debug=all -jar britive-broker-1.0.0.jar >> /var/log/britive-broker.log 2>&1 &
BROKER_PID=$!

echo "Broker started with PID: $BROKER_PID"
wait $BROKER_PID
