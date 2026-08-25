# =============================================================================
# Britive Bridge v2 — deployment image
# =============================================================================
# Builds on the official britive/bridge image and adds two things it does not
# ship:
#
#   1. Your bridge.yaml, baked in at /etc/britive-bridge/config.yaml. The
#      upstream image has a default config that enables NO protocols, and the
#      Bridge refuses to start unless at least one is on.
#   2. The runtime a broker needs. Checkout/checkin scripts are bash and shell
#      out to CLIs the base Alpine image does not include.
#
# Build with build-and-push.sh, which tags and pushes to your ECR repository.
# =============================================================================

# Upstream Bridge release. Check https://hub.docker.com/r/britive/bridge/tags
# for newer versions. Override at build time: BRIDGE_VERSION=v2.1.1 ./build-and-push.sh
ARG BRIDGE_VERSION=v2.1.0
FROM britive/bridge:${BRIDGE_VERSION}

# Your configuration. Everything the Bridge needs at startup EXCEPT secrets,
# which the ECS task injects from Secrets Manager as environment variables.
COPY bridge.yaml /etc/britive-bridge/config.yaml

# RDS global CA bundle, added to the system trust store.
#
# The Bridge's Go proxy verifies a target database's certificate against this
# when a checkout sets target_tls=true; without it the connection fails with
# "x509: certificate signed by unknown authority". Checkout scripts can also
# reference it as DB_CA_CERT=/etc/ssl/certs/ca-certificates.crt.
ADD https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem \
    /usr/local/share/ca-certificates/rds-global-bundle.crt

USER root

# Broker script runtime:
#   bash            - scripts use #!/bin/bash; Alpine's default shell is sh
#   aws-cli         - read/write Secrets Manager, describe EC2/RDS
#   jq              - JSON handling, used by nearly every script
#   curl, openssl   - misc
#   ca-certificates - provides update-ca-certificates
#
# update-ca-certificates prints this while processing the RDS bundle:
#
#   WARNING: ca-cert-rds-global-bundle.pem does not contain exactly one
#            certificate or CRL: skipping
#
# It is EXPECTED and harmless here. The warning refers only to the per-
# certificate hash symlinks in /etc/ssl/certs/, which Alpine builds one file at
# a time. Every certificate in the bundle is still concatenated into
# /etc/ssl/certs/ca-certificates.crt, which is what the Bridge's Go proxy and
# the AWS CLI actually read. The build below fails if that concatenation did not
# happen, so a silent regression cannot ship.
RUN apk add --no-cache \
      bash \
      aws-cli \
      jq \
      curl \
      openssl \
      ca-certificates \
 && chmod 0644 /usr/local/share/ca-certificates/rds-global-bundle.crt \
 && before="$(grep -c 'BEGIN CERTIFICATE' /etc/ssl/certs/ca-certificates.crt)" \
 && bundle="$(grep -c 'BEGIN CERTIFICATE' /usr/local/share/ca-certificates/rds-global-bundle.crt)" \
 && update-ca-certificates \
 && after="$(grep -c 'BEGIN CERTIFICATE' /etc/ssl/certs/ca-certificates.crt)" \
 && echo "trust store: ${before} + ${bundle} bundle certs = ${after}" \
 && [ "$after" -ge "$((before + bundle))" ]

# ---------------------------------------------------------------------------
# OPTIONAL EXTRAS — uncomment only what your checkout scripts actually use.
# Each one grows the image, so start empty and add as you adopt script families.
# ---------------------------------------------------------------------------
# RUN apk add --no-cache \
#       openssh-client \       # ssh to Linux / Windows / AD targets
#       mariadb-client \       # `mysql` CLI for MySQL and Aurora MySQL flows
#       mariadb-connector-c \  # caching_sha2_password auth (MySQL 8 admins)
#       postgresql-client \    # `psql` for PostgreSQL flows
#       openldap-clients \     # `ldapsearch` / `ldapmodify` for Active Directory
#       python3 py3-pip        # helper scripts; pywinrm for WinRM flows
#
# kubectl (Kubernetes exec flows):
# RUN ARCH="$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')" \
#  && curl -fsSLo /usr/local/bin/kubectl \
#       "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" \
#  && chmod 0755 /usr/local/bin/kubectl
#
# SQL Server: Microsoft's mssql-tools are glibc + amd64 only and will NOT run on
# this musl/Alpine image. Use go-sqlcmd, a statically linked Go binary with
# native linux-arm64 and linux-amd64 builds.

# Drop back to the unprivileged user the base image runs as.
USER bridge
