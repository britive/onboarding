FROM ubuntu:24.04
USER root:0

# install all the stuff and clean up, for a smaller image
RUN dpkgArch=$(dpkg --print-architecture) && \
    if [ "$dpkgArch" = "arm64" ]; then \
        sed -i 's|http://ports.ubuntu.com|http://archive.ubuntu.com|g' /etc/apt/sources.list; \
    fi && \
    apt update && \
    apt install -y jq openjdk-21-jre-headless wget unzip python3 python3-pip supervisor openssh-server mysql-client && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# make all the needed directories
RUN mkdir -p /root/broker/config/ /root/broker/bootstrap/ /root/broker/cache /var/log/supervisor /var/run/sshd

# install what python needs
RUN pip3 install jmespath britive>=4.1.3 pyjwt cryptography jinja2 pyyaml --break-system-packages

# broker jar
COPY ./britive-broker-0.1.3.jar /root/broker/britive-broker-0.1.3.jar

# config and bootstrap
COPY ./broker-config.yml /root/broker/config/broker-config.yml
COPY ./tenant-generator.sh /root/broker/bootstrap/tenant-generator.sh
COPY ./token-generator.sh /root/broker/bootstrap/token-generator.sh


# copy other things needed to make this all work
COPY ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY ./start-broker.sh /root/start-broker.sh

# make all the needed scripts executable
RUN chmod u+x /root/broker/bootstrap/*
RUN chmod u+x /root/start-broker.sh

# configure ssh
RUN echo 'root:root' | chpasswd
RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
RUN echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
EXPOSE 22

# and lets go!
WORKDIR /root/
CMD ["/usr/bin/supervisord"]