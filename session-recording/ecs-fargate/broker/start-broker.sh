#!/bin/bash

# Britive Session Recording Broker - ECS Fargate startup script
# Handles graceful shutdown, secrets management, SSH setup, and broker launch.

# Signal handler for graceful shutdown
cleanup() {
    echo "Received shutdown signal, cleaning up..."
    if [ -n "$BROKER_PID" ]; then
        kill -TERM "$BROKER_PID" 2>/dev/null
        wait "$BROKER_PID" 2>/dev/null
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT

# Optional startup delay (default 5 seconds — gives sshd time to start first)
DELAY=${1:-5}
if [ "$DELAY" -gt 0 ]; then
    echo "Waiting $DELAY seconds before starting broker..."
    sleep "$DELAY"
fi

# Secrets directory for file-based secrets
SECRETS_DIR="${SECRETS_DIR:-/root/broker/secrets}"
mkdir -p "$SECRETS_DIR"

echo "Setting up secrets directory: $SECRETS_DIR"

# Write BRITIVE_TOKEN to file (ECS injects it from Secrets Manager as an env var)
if [ -n "$BRITIVE_TOKEN" ]; then
    echo -n "$BRITIVE_TOKEN" > "$SECRETS_DIR/BRITIVE_TOKEN"
    chmod 600 "$SECRETS_DIR/BRITIVE_TOKEN"
    echo "BRITIVE_TOKEN written to secrets directory"
fi

# Write JSON_SECRET_KEY to file so broker scripts can read it
if [ -n "$JSON_SECRET_KEY" ]; then
    echo -n "$JSON_SECRET_KEY" > "$SECRETS_DIR/JSON_SECRET_KEY"
    chmod 600 "$SECRETS_DIR/JSON_SECRET_KEY"
    echo "JSON_SECRET_KEY written to secrets directory"
fi

# Write any BROKER_* prefixed secrets to individual files
env | grep "^BROKER_" | while IFS='=' read -r key value; do
    if [ -n "$value" ]; then
        echo -n "$value" > "$SECRETS_DIR/$key"
        chmod 600 "$SECRETS_DIR/$key"
        echo "$key written to secrets directory"
    fi
done

echo "Secrets directory contents:"
ls -la "$SECRETS_DIR" 2>/dev/null || echo "  (empty)"

# Setup kubeconfig from base64-encoded value if provided
if [ -n "$KUBECONFIG_BASE64" ]; then
    echo "Setting up kubeconfig from environment..."
    mkdir -p /root/.kube
    echo "$KUBECONFIG_BASE64" | base64 -d > /root/.kube/config
    chmod 600 /root/.kube/config
    export KUBECONFIG=/root/.kube/config
    echo "Kubeconfig configured"
fi

# Setup kubeconfig for EKS cluster if EKS variables provided
if [ -n "$EKS_CLUSTER_NAME" ] && [ -n "$AWS_REGION" ]; then
    echo "Configuring kubectl for EKS cluster: $EKS_CLUSTER_NAME"
    aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$AWS_REGION"
    echo "EKS kubeconfig configured"
fi

# Generate SSH host keys (safe to run multiple times)
ssh-keygen -A 2>/dev/null || true
echo "SSH host keys ready"

# Generate broker-config.yml
# BRITIVE_TENANT and BRITIVE_TOKEN are injected from Secrets Manager at task launch.
if [ -z "$BRITIVE_TENANT" ]; then
    echo "ERROR: BRITIVE_TENANT is not set. Configure it in secrets.json or deploy.sh."
    exit 1
fi
if [ -z "$BRITIVE_TOKEN" ]; then
    echo "ERROR: BRITIVE_TOKEN is not set. Check Secrets Manager configuration."
    exit 1
fi

mkdir -p /root/broker/config
cat > /root/broker/config/broker-config.yml << EOF
config:
  version: 2
  bootstrap:
    tenant_subdomain: ${BRITIVE_TENANT}
    authentication_token: "${BRITIVE_TOKEN}"
EOF
chmod 600 /root/broker/config/broker-config.yml
echo "Broker config generated for tenant: $BRITIVE_TENANT"

# Find the broker JAR — respects BROKER_VERSION if set; otherwise uses any available version
BROKER_VERSION="${BROKER_VERSION:-2.0.0}"
JAR_FILE="/root/broker/britive-broker-${BROKER_VERSION}.jar"

if [ ! -f "$JAR_FILE" ]; then
    echo "WARNING: Expected JAR not found at $JAR_FILE — searching for any broker JAR..."
    JAR_FILE=$(find /root/broker -maxdepth 1 -name "britive-broker-*.jar" | head -1)
    if [ -z "$JAR_FILE" ]; then
        echo "ERROR: No britive-broker-*.jar found in /root/broker/"
        exit 1
    fi
    echo "Using: $JAR_FILE"
fi

echo "Starting Britive broker: $JAR_FILE"
cd /root/broker
java -jar "$JAR_FILE" >> /var/log/britive-broker.log 2>&1 &
BROKER_PID=$!

echo "Broker started with PID: $BROKER_PID"
wait "$BROKER_PID"
