# syntax=docker/dockerfile:1
#
# Britive Access Broker 3.x container image
# ==========================================
# The 3.x broker is a single static binary with no runtime dependencies, so
# the image is Alpine plus the command-line tools your checkout/checkin
# scripts call. Everything the broker needs is configured by environment
# variable; a broker-config.yml is only required to restrict resource_types.
#
# Place the tarball you downloaded from the Britive console next to this file
# (System Administration -> Brokers and Broker Pools -> Download Brokers,
# "Any other Linux", tar.gz). Both architectures are needed for a multi-arch
# build; one is enough for a single-platform build:
#
#   britive-broker-3.0.2-linux-amd64.tar.gz
#   britive-broker-3.0.2-linux-arm64.tar.gz
#
# Build (see build-and-push.sh for the multi-arch registry push):
#   docker build --build-arg BROKER_VERSION=3.0.2 -t britive-broker:3.0.2 .
#
# Optional tool layers, each off by default:
#   --build-arg WITH_AWS_CLI=true      aws        (Secrets Manager, EC2, RDS, EKS)
#   --build-arg WITH_KUBECTL=true      kubectl    (Kubernetes RBAC checkouts)
#   --build-arg WITH_PYWINRM=true      python3 + pywinrm (Windows over WinRM)
#   --build-arg WITH_DB_CLIENTS=true   psql, mysql, ldapsearch
#
# Runtime contract:
#   - runs as uid 1000 (britivebroker), PID 1 is tini
#   - working directory /opt/britive-broker; the broker reads
#     config/broker-config.yml relative to it when present and writes
#     downloaded scripts under cache/
#   - logs to stdout, structured (time= level= msg=)
#   - stops cleanly on SIGTERM

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

ARG BROKER_VERSION=3.0.2
ARG TARGETARCH
ARG WITH_AWS_CLI=false
ARG WITH_KUBECTL=false
ARG WITH_PYWINRM=false
ARG WITH_DB_CLIENTS=false

# Base tools every script can rely on. tini reaps the script processes the
# broker spawns and forwards SIGTERM.
RUN apk add --no-cache \
      tini bash ca-certificates curl jq openssl openssh-client coreutils \
    && update-ca-certificates

# Optional tool layers.
RUN set -eu; \
    if [ "$WITH_AWS_CLI" = "true" ]; then apk add --no-cache aws-cli; fi; \
    if [ "$WITH_KUBECTL" = "true" ]; then apk add --no-cache kubectl; fi; \
    if [ "$WITH_DB_CLIENTS" = "true" ]; then apk add --no-cache postgresql17-client mysql-client openldap-clients; fi; \
    if [ "$WITH_PYWINRM" = "true" ]; then \
        apk add --no-cache python3 py3-pip; \
        python3 -m venv /opt/broker-venv; \
        /opt/broker-venv/bin/pip install --no-cache-dir pywinrm requests-ntlm; \
    fi
# The venv's python3 must be what scripts resolve; PATH carries the venv.
ENV PATH="/opt/broker-venv/bin:${PATH}"

# The broker. The tarball unpacks to britive-broker/{britive-broker,bootstrap,cache,config}.
COPY britive-broker-*.tar.gz /tmp/dist/
RUN set -eu; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
        case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) echo "unsupported $(uname -m)" >&2; exit 1 ;; esac; \
    fi; \
    tarball="/tmp/dist/britive-broker-${BROKER_VERSION}-linux-${arch}.tar.gz"; \
    [ -f "$tarball" ] || { echo "ERROR: $tarball not found - download it from the Britive console and place it next to the Dockerfile" >&2; exit 1; }; \
    tar -xzf "$tarball" -C /opt; \
    rm -rf /tmp/dist; \
    chmod 0755 /opt/britive-broker/britive-broker; \
    mkdir -p /opt/britive-broker/cache /opt/britive-broker/config /opt/britive-broker/scripts; \
    adduser -D -u 1000 -h /opt/britive-broker britivebroker; \
    chown -R britivebroker:britivebroker /opt/britive-broker; \
    /opt/britive-broker/britive-broker help >/dev/null

# Optional: bake local checkout/checkin scripts in and reference them from
# config/broker-config.yml (max_supported_version: local). Scripts uploaded to
# the Britive platform are fetched at checkout time and need no image change.
# COPY --chown=britivebroker:britivebroker scripts/ /opt/britive-broker/scripts/

USER britivebroker
WORKDIR /opt/britive-broker

# No HTTP endpoint exists; liveness is "the broker process is running".
# Anchored on the full command line so the check cannot match its own shell.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD pgrep -f '^/opt/britive-broker/britive-broker( |$)' >/dev/null || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/opt/britive-broker/britive-broker"]
CMD ["run"]
