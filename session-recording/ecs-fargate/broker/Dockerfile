# Britive Session Recording Broker - AWS ECS Fargate
# Runs the Britive Access Broker alongside an SSH server so that Guacamole
# can open SSH sessions through it and record them to the shared EFS volume.

FROM --platform=linux/amd64 ubuntu:24.04

USER root:0

ENV DEBIAN_FRONTEND=noninteractive

# Install required packages
RUN apt-get update && apt-get install -y \
    openjdk-21-jre-headless \
    curl wget unzip ca-certificates \
    supervisor jq \
    openssh-server \
    mysql-client \
    python3 python3-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages required by Britive broker scripts
RUN pip3 install --break-system-packages \
    jmespath "britive>=4.1.3" pyjwt cryptography jinja2 pyyaml

# Install kubectl (for clusters the broker manages)
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Create required directories
RUN mkdir -p \
    /root/broker/config \
    /root/broker/bootstrap \
    /root/broker/cache \
    /root/broker/secrets \
    /root/.kube \
    /root/.ssh \
    /var/log/supervisor \
    /var/run/sshd

# Configure SSH — root login is required for Guacamole session recording
RUN echo 'root:root' | chpasswd \
    && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config \
    && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config

EXPOSE 22

# Broker version — override at build time: docker build --build-arg BROKER_VERSION=x.y.z
ARG BROKER_VERSION=2.0.0

# Copy Britive broker JAR
COPY britive-broker-${BROKER_VERSION}.jar /root/broker/

# Copy supervisor configuration and startup scripts
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY start-broker.sh /root/start-broker.sh
COPY token-generator.sh /root/broker/bootstrap/token-generator.sh

RUN chmod +x /root/start-broker.sh /root/broker/bootstrap/token-generator.sh

# Health check — verify the broker Java process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD pgrep -f "britive-broker" > /dev/null || exit 1

WORKDIR /root/
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
