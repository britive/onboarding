# syntax=docker/dockerfile:1
#
# Custom Britive Bridge image
# ===========================
# Extends the stock britive/bridge image (which bundles the broker + bridge.sh)
# with the extra CLI utilities that the broker's checkout/checkin scripts need:
#
#   - openssh-client : ssh, ssh-keygen        (Linux SSH key provisioning example)
#   - python3        : JSON encoding in the SSH checkout payload
#   - mysql/mariadb  : mysql client            (Aurora MySQL examples)
#   - jq             : parse Secrets Manager JSON
#   - awscli v2      : read DB master creds from AWS Secrets Manager
#   - ca-certificates, bash, coreutils (base64/tr/head)
#
# The broker fetches the actual checkout/checkin scripts from the Britive
# platform at runtime, so they do NOT need to be baked in. We optionally COPY
# the example scripts under /opt/britive-broker/custom-scripts for reference /
# local testing — see the COPY block near the bottom (commented by default).
#
# The base image's distro is detected at build time, so this Dockerfile works
# whether britive/bridge is Debian/Ubuntu (apt), Alpine (apk), or RHEL-like
# (dnf/microdnf) based.
#
# Build (multi-arch recommended so it runs on Fargate ARM64 and x86 nodes):
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     -t <your-registry>/britive-bridge-custom:latest --push .
#
# Or single-arch for local use:
#   docker build -t britive-bridge-custom:latest .

ARG BASE_IMAGE=britive/bridge:latest
FROM ${BASE_IMAGE}

# Root needed to install packages; the base image's own entrypoint/user is
# preserved (we do not override USER, ENTRYPOINT, or CMD).
USER root

# TARGETARCH is provided automatically by buildx (amd64 / arm64). Falls back to
# the build host arch for a plain `docker build`.
ARG TARGETARCH

# Single RUN layer. The leading `set -eu` aborts the build on any failure.
RUN set -eu; \
    # ── 1. Install OS packages via whichever package manager exists ──────────
    if command -v apt-get >/dev/null 2>&1; then \
        export DEBIAN_FRONTEND=noninteractive; \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            ca-certificates curl unzip bash coreutils \
            openssh-client python3 jq \
            default-mysql-client; \
        rm -rf /var/lib/apt/lists/*; \
        PKG=apt; \
    elif command -v apk >/dev/null 2>&1; then \
        apk add --no-cache \
            ca-certificates curl unzip bash coreutils \
            openssh-client python3 jq \
            mysql-client \
            aws-cli; \
        PKG=apk; \
    elif command -v microdnf >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then \
        DNF=$(command -v dnf || command -v microdnf); \
        $DNF install -y \
            ca-certificates curl unzip bash coreutils \
            openssh-clients python3 jq \
            mariadb; \
        $DNF clean all || true; \
        PKG=dnf; \
    else \
        echo "ERROR: no supported package manager (apt/apk/dnf) in base image" >&2; \
        exit 1; \
    fi; \
    # ── 2. AWS CLI v2 ────────────────────────────────────────────────────────
    # apk already installed aws-cli above (the official v2 installer is glibc-
    # only and won't run on Alpine/musl). For apt/dnf (glibc) use the official
    # v2 installer, picking the bundle that matches the target architecture.
    if [ "$PKG" != "apk" ]; then \
        case "${TARGETARCH:-$(uname -m)}" in \
            amd64|x86_64)  AWS_ARCH=x86_64 ;; \
            arm64|aarch64) AWS_ARCH=aarch64 ;; \
            *) echo "ERROR: unsupported arch '${TARGETARCH:-$(uname -m)}'" >&2; exit 1 ;; \
        esac; \
        curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip; \
        unzip -q /tmp/awscliv2.zip -d /tmp; \
        /tmp/aws/install; \
        rm -rf /tmp/aws /tmp/awscliv2.zip; \
    fi; \
    # ── 3. Sanity check: every utility the example scripts call must resolve ──
    for c in ssh ssh-keygen base64 python3 jq aws mysql bash; do \
        command -v "$c" >/dev/null 2>&1 || { echo "MISSING: $c" >&2; exit 1; }; \
    done; \
    # The final USER directive below assumes the base image defines a 'bridge'
    # user — fail the build here, not at container start, if it doesn't.
    id bridge >/dev/null 2>&1 || { echo "MISSING: 'bridge' user in base image — adjust the USER directive" >&2; exit 1; }; \
    echo "All required utilities present."

# ── Optional: bake the example scripts in for reference / local testing ──────
# In production the Britive platform delivers checkout/checkin scripts to the
# broker at runtime, so this is NOT required. Uncomment to ship them in-image.
# COPY scripts/ /opt/britive-broker/custom-scripts/
# RUN chmod -R 0755 /opt/britive-broker/custom-scripts

# Drop back to the base image's runtime user if it defined one. The stock image
# runs as the 'bridge' user; restore it so we don't run the broker as root.
# (If the base image's user is not 'bridge', adjust or remove this line.)
USER bridge
