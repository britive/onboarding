# Britive Access Broker - Azure AKS Deployment
# This Dockerfile creates a container image for running the Britive Access Broker
# on Azure Kubernetes Service (AKS)

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

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

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

# Default command - start supervisor
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
