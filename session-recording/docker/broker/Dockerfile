FROM ubuntu:24.04
USER root:0

# Broker JAR version baked into the image. Place britive-broker-<version>.jar
# next to this Dockerfile and override at build time:
#   docker build --build-arg BROKER_VERSION=2.0.1 -t broker-docker broker/
# start-broker.sh runs whatever britive-broker-*.jar it finds in /root/broker,
# so nothing else references the version.
ARG BROKER_VERSION=2.0.1

# install all the stuff and clean up, for a smaller image
RUN apt update && \
    apt install -y jq curl openssl openjdk-21-jre-headless wget unzip python3 python3-pip supervisor openssh-server mysql-client && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# make all the needed directories
RUN mkdir -p /root/broker/config/ /root/broker/bootstrap/ /root/broker/cache /var/log/supervisor /var/run/sshd

# install what python needs (pywinrm is used by the remote-*-rdp.sh scripts)
RUN pip3 install jmespath 'britive>=4.1.3' pyjwt cryptography jinja2 pyyaml pywinrm --break-system-packages

# broker jar
COPY ./britive-broker-${BROKER_VERSION}.jar /root/broker/

# config and bootstrap
COPY ./broker-config.yml /root/broker/config/broker-config.yml
COPY ./token-generator.sh /root/broker/bootstrap/token-generator.sh

# copy other things needed to make this all work
COPY ./supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY ./start-broker.sh /root/start-broker.sh

# make all the needed scripts executable
RUN chmod u+x /root/broker/bootstrap/* /root/start-broker.sh

# sshd is only reachable on the compose network: guacd connects to it for the
# "Guac" example in setup.yml.example, authenticating with the per-checkout key.
# Root never logs in and no account accepts a password.
RUN echo "PermitRootLogin no" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
EXPOSE 22

# and lets go!
WORKDIR /root/
CMD ["/usr/bin/supervisord"]
