#!/usr/bin/env bash
#
# install.sh — Install Docker and run the Britive Bridge container on a Linux VM.
#
# Supports the common server distros and handles their differences:
#   - Debian / Ubuntu            (apt, docker-ce repo)
#   - RHEL / Rocky / AlmaLinux   (dnf, docker-ce repo, firewalld, SELinux)
#   - Amazon Linux 2 / 2023      (amazon-linux-extras vs dnf)
#   - Fedora                     (dnf, docker-ce repo)
#
# Usage:
#   cp bridge.env.example bridge.env   # then edit bridge.env
#   sudo ./install.sh
#
# Idempotent: re-running re-pulls the image and recreates the container.
#
# This script intentionally does ONE thing per step and prints what it does, so
# you can also follow it by hand from the README if you prefer.

set -euo pipefail

# ── Tunables (override via env: IMAGE=... PORT=... ./install.sh) ────────────
IMAGE="${IMAGE:-britive/bridge:latest}"   # Docker Hub image
CONTAINER_NAME="${CONTAINER_NAME:-bridge}"
PORT="${PORT:-8080}"                       # host:container port for HTTPS
DATA_VOLUME="${DATA_VOLUME:-bridge-data}"  # named volume for /data persistence
# Default bridge.env to the script's own directory so the script works when
# invoked from anywhere (docker --env-file resolves relative to the cwd).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/bridge.env}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo ./install.sh)."
[ -f "$ENV_FILE" ]   || die "Missing ${ENV_FILE}. Run: cp ${SCRIPT_DIR}/bridge.env.example ${ENV_FILE}  then edit it."
# Catch unedited template placeholders before the container crash-loops on them.
if grep -q '<your-' "$ENV_FILE"; then
  die "${ENV_FILE} still contains placeholder values (<your-...>). Edit it with your real tenant subdomain and broker token."
fi

# ── 1. Detect the distro ────────────────────────────────────────────────────
# /etc/os-release is the portable source of truth across modern Linux.
[ -r /etc/os-release ] || die "Cannot read /etc/os-release; unsupported OS."
# shellcheck disable=SC1091
. /etc/os-release
log "Detected: ${PRETTY_NAME:-$ID ${VERSION_ID:-}} ($(uname -m))"

# ── 2. Install Docker Engine (skip if already present) ──────────────────────
install_docker_debian() {
  # Ubuntu and Debian share the apt-based docker-ce repo flow.
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  # $ID is "ubuntu" or "debian" — the repo path differs by distro.
  # --yes: overwrite a keyring left by a previous partial run (re-run safety)
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
    | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

install_docker_rhel() {
  # RHEL / Rocky / AlmaLinux / Fedora via dnf + docker-ce repo.
  # Write the repo file directly instead of `dnf config-manager --add-repo`:
  # dnf5 (Fedora 41+) changed that command's syntax, this works on both.
  local repo_distro="centos"
  [ "$ID" = "fedora" ] && repo_distro="fedora"  # Fedora has its own repo path
  curl -fsSL "https://download.docker.com/linux/${repo_distro}/docker-ce.repo" \
    -o /etc/yum.repos.d/docker-ce.repo
  dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

install_docker_amazon() {
  # Amazon Linux ships its own docker package — do NOT use the docker-ce repo.
  if [ "${VERSION_ID%%.*}" = "2" ]; then
    # Amazon Linux 2: docker lives in amazon-linux-extras.
    amazon-linux-extras install -y docker
  else
    # Amazon Linux 2023: plain dnf package named "docker".
    dnf install -y docker
  fi
}

if command -v docker >/dev/null 2>&1; then
  log "Docker already installed: $(docker --version)"
else
  log "Installing Docker Engine..."
  case "$ID" in
    ubuntu|debian)            install_docker_debian ;;
    # centos = CentOS Stream 9+ (dnf); CentOS 7 (yum-only) is EOL/unsupported.
    rhel|rocky|almalinux|centos|fedora) install_docker_rhel ;;
    amzn)                     install_docker_amazon ;;
    *) die "Unsupported distro '$ID'. Install Docker manually, then re-run." ;;
  esac
fi

# ── 3. Enable + start the Docker service ────────────────────────────────────
# systemd is standard on all supported distros. Enabling makes it survive reboot.
log "Enabling and starting the docker service..."
systemctl enable --now docker

# ── 4. Open the firewall (distro-dependent) ─────────────────────────────────
# Ubuntu/Debian: ufw (often inactive). RHEL/Amazon: firewalld (often active).
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  log "firewalld active — opening ${PORT}/tcp..."
  firewall-cmd --permanent --add-port="${PORT}/tcp"
  firewall-cmd --reload
elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  log "ufw active — opening ${PORT}/tcp..."
  ufw allow "${PORT}/tcp"
else
  warn "No active host firewall detected. Ensure your CLOUD security group / network ACL allows inbound TCP ${PORT} from your users."
fi

# ── 5. SELinux note (RHEL/Amazon family) ────────────────────────────────────
# When SELinux is enforcing, bind-mounted host paths need a :z/:Z label or the
# container can't read them. We use a NAMED volume (managed by Docker), which is
# labeled correctly automatically — so no relabeling needed here. If you switch
# to a host bind mount, append :Z to the -v flag (see README).
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
  log "SELinux is Enforcing. Using a named volume (no relabel needed)."
fi

# ── 6. Pull the image and (re)create the container ──────────────────────────
log "Pulling ${IMAGE}..."
docker pull "$IMAGE"

# Remove any previous container so this script is safely re-runnable.
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  log "Removing existing container '${CONTAINER_NAME}'..."
  docker rm -f "$CONTAINER_NAME"
fi

log "Starting container '${CONTAINER_NAME}'..."
# --restart unless-stopped  : auto-restart on crash and on VM reboot
# --env-file                : load broker creds without putting them on the cmdline
# -v ${DATA_VOLUME}:/data    : persist session/checkout state across restarts
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "${PORT}:8080" \
  --env-file "$ENV_FILE" \
  -v "${DATA_VOLUME}:/data" \
  "$IMAGE"

# ── 7. Health check ─────────────────────────────────────────────────────────
log "Waiting for Bridge to report healthy..."
# Probe with host curl if present, else with curl inside the container.
health_probe() {
  if command -v curl >/dev/null 2>&1; then
    # -k: accept the self-signed cert. -s/-f: quiet + fail on non-2xx.
    curl -sfk "https://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1
  else
    docker exec "$CONTAINER_NAME" curl -sfk "https://127.0.0.1:8080/api/health" >/dev/null 2>&1
  fi
}
HEALTHY=0
for i in $(seq 1 20); do
  if health_probe; then
    HEALTHY=1
    log "Bridge is healthy at https://127.0.0.1:${PORT}/api/health"
    break
  fi
  sleep 3
done

if [ "$HEALTHY" -eq 1 ]; then
  log "Done. Logs: docker logs -f ${CONTAINER_NAME}"
else
  warn "Bridge did not report healthy within 60s. Inspect: docker logs ${CONTAINER_NAME}"
  exit 1
fi
