# Use Ubuntu 24.04 as the base image
FROM ubuntu:24.04

# Set user to root (UID 0, GID 0)
USER root:0

# Install required system packages and tools
RUN dpkgArch=$(dpkg --print-architecture) && \
    # Fix for arm64 architecture to use correct APT repo
    if [ "$dpkgArch" = "arm64" ]; then \
        sed -i 's|http://ports.ubuntu.com|http://archive.ubuntu.com|g' /etc/apt/sources.list; \
    fi && \
    # Update package list
    apt update && \
    # Install packages: 
    # - jq: JSON processor
    # - openjdk: Java runtime for broker
    # - wget/unzip: for downloading/unpacking files
    # - python3/pip: required for Britive and scripting
    # - supervisor: process manager
    # - openssh-server: for SSH support if needed
    # - mysql-client: for interacting with MySQL
    # - curl: to make HTTP requests (required by token-generator.sh or other utilities)
    # - gnupg & ca-certificates: ensure secure downloads (needed by curl and apt)
    apt install -y jq openjdk-21-jre-headless wget unzip python3 python3-pip \
                   supervisor openssh-server mysql-client curl gnupg ca-certificates && \
    \
    # Install kubectl (latest stable version)
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl && \
    \
    # Clean up to reduce image size
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# Create required directories for broker, logs, and SSH daemon
RUN mkdir -p /root/broker/config/ /root/broker/bootstrap/ /root/broker/cache \
             /var/log/supervisor /var/run/sshd

# Install Python dependencies for the broker
# --break-system-packages is needed in Ubuntu 24.04 to allow pip to install globally
RUN pip3 install jmespath 'britive>=4.1.3' pyjwt cryptography jinja2 pyyaml --break-system-packages

# Copy the broker JAR file into the image
COPY ./britive-broker-0.1.3.jar /root/broker/britive-broker-0.1.3.jar

# Copy broker configuration and bootstrap scripts
COPY ./broker-config.yml /root/broker/config/broker-config.yml
COPY ./token-generator.sh /root/broker/bootstrap/token-generator.sh

# Copy Supervisor configuration file
COPY ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy the main startup script for the broker
COPY ./start-broker.sh /root/start-broker.sh

# Make all shell scripts executable
RUN chmod u+x /root/broker/bootstrap/*
RUN chmod u+x /root/start-broker.sh

# Set the working directory
WORKDIR /root/

# Start all services using Supervisor (main process of container)
CMD ["/usr/bin/supervisord"]
