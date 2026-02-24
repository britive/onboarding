FROM --platform=linux/amd64 ubuntu:24.04
USER root:0

# install all the stuff including kubectl and clean up, for a smaller image
RUN dpkgArch=$(dpkg --print-architecture) && \
    if [ "$dpkgArch" = "arm64" ]; then \
        sed -i 's|http://ports.ubuntu.com|http://archive.ubuntu.com|g' /etc/apt/sources.list; \
    fi && \
    apt update && \
    apt install -y jq openjdk-21-jre-headless wget unzip supervisor curl ca-certificates && \
    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/kubectl && \
    # Verify kubectl installation
    kubectl version --client && \
    # Clean up
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# Make all the needed directories
RUN mkdir -p /root/broker/config/ /root/broker/bootstrap/ /root/broker/cache /root/.kube /var/log/supervisor /var/run/sshd

# Broker jar
COPY ./britive-broker-1.0.0.jar /root/broker/britive-broker-1.0.0.jar

# Copy supervisor config
COPY ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf


# config and bootstrap files
# COPY ./broker-config.yml /root/broker/config/broker-config.yml
# COPY ./token-generator.sh /root/broker/bootstrap/token-generator.sh
# COPY ./start-broker.sh /root/start-broker.sh

# make all the needed scripts executable
# RUN chmod u+x /root/broker/bootstrap/*
# RUN chmod u+x /root/start-broker.sh


# and lets go!
WORKDIR /root/
CMD ["/usr/bin/supervisord"]