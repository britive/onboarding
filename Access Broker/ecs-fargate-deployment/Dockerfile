# Britive Access Broker - AWS ECS Fargate Deployment
# This Dockerfile creates a container image for running the Britive Access Broker
# on AWS ECS Fargate (serverless container orchestration)

FROM --platform=linux/amd64 ubuntu:24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    openjdk-21-jre-headless \
    curl \
    wget \
    unzip \
    ca-certificates \
    supervisor \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl (for managing external Kubernetes clusters)
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Install AWS CLI v2 (for EKS cluster access if needed)
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# Create directories
RUN mkdir -p /root/broker/config \
    && mkdir -p /root/broker/bootstrap \
    && mkdir -p /root/broker/cache \
    && mkdir -p /root/.kube \
    && mkdir -p /var/log/supervisor \
    && mkdir -p /var/run/sshd

# Copy Britive broker JAR
COPY britive-broker-1.0.0.jar /root/broker/

# Copy supervisor configuration
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy startup scripts
COPY start-broker.sh /root/start-broker.sh
COPY token-generator.sh /root/broker/bootstrap/token-generator.sh
RUN chmod +x /root/start-broker.sh /root/broker/bootstrap/token-generator.sh

# Health check - verify Java process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD pgrep -f java || exit 1

# Default command - start supervisor
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
