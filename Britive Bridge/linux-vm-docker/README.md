# Britive Bridge — Linux VM (Docker)

Run the Britive Bridge container (which hosts the broker process) on a single
Linux VM using Docker, pulling the image straight from **Docker Hub**
(`britive/bridge`). Good for on-prem hosts, a cloud EC2/Compute instance, or any
long-lived Linux server.

> Want zero scripting and don't care about per-distro detail? The
> [Docker Compose option](../docker-compose/) runs the same container with a
> single file. This guide is the **standalone-VM, fully-explained** path with an
> install helper and OS-specific gotchas.

---

## Prerequisites

- A 64-bit Linux VM (x86_64 or arm64) you have **root / sudo** on. Supported
  families: Ubuntu, Debian, RHEL, Rocky, AlmaLinux, Amazon Linux 2/2023, Fedora.
- **Outbound** internet from the VM to your Britive tenant (Broker/MQTT) and to
  Docker Hub (to pull the image).
- **Inbound** TCP on the Bridge port (default `8080`) reachable by your users —
  open both the host firewall **and** any cloud security group / network ACL.
- Sizing: start with **2 vCPU / 4 GiB RAM** and ~5 GiB free disk for the image +
  data volume. Scale up for heavier session loads.
- Completed [platform setup](../platform-setup/) — you need
  `BRITIVE_BROKER_TENANT_SUBDOMAIN` and `BRITIVE_BROKER_AUTH_TOKEN`.

---

## Quick start (scripted)

```bash
# 0. Get these files onto the VM and cd into the directory, e.g.:
#    git clone <this-repo> && cd "onboarding/Britive Bridge/linux-vm-docker"
#    (or scp install.sh bridge.env.example user@vm:)

# 1. Provide credentials
cp bridge.env.example bridge.env
chmod 600 bridge.env
# edit bridge.env — set tenant subdomain + broker token

# 2. Install Docker + run the container (auto-detects your distro)
sudo ./install.sh

# 3. Verify
curl -sfk https://127.0.0.1:8080/api/health
docker logs -f bridge
```

`install.sh` detects the distro, installs Docker Engine, enables it on boot,
opens the firewall, pulls `britive/bridge:latest`, and starts the container with
a persistent data volume and `--restart unless-stopped`. Re-run it any time to
update the image / recreate the container.

Override defaults via env vars, e.g.:

```bash
sudo IMAGE=britive/bridge:latest PORT=9443 CONTAINER_NAME=bridge ./install.sh
```

> **Production:** pin a specific image tag (see Docker Hub `britive/bridge`
> tags) instead of `latest`, so reinstalls don't pull an unplanned version:
> `sudo IMAGE=britive/bridge:<version> ./install.sh`

---

## Manual steps (if you prefer to do it by hand)

### 1. Install Docker Engine

**Ubuntu / Debian** (apt, official docker-ce repo):

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
# Use "ubuntu" or "debian" in the URL to match your distro:
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

**RHEL / Rocky / AlmaLinux / Fedora** (dnf, docker-ce repo):

```bash
# CentOS repo works for RHEL/Rocky/Alma; use the fedora repo on Fedora.
# (Written directly — `dnf config-manager --add-repo` changed syntax in dnf5.)
sudo curl -fsSL https://download.docker.com/linux/centos/docker-ce.repo \
  -o /etc/yum.repos.d/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

**Amazon Linux** (do **not** use the docker-ce repo — use the bundled package):

```bash
# Amazon Linux 2:
sudo amazon-linux-extras install -y docker
# Amazon Linux 2023:
sudo dnf install -y docker
```

### 2. Enable and start Docker

```bash
sudo systemctl enable --now docker
docker --version
```

### 3. (Optional) run docker without sudo

```bash
sudo usermod -aG docker "$USER"
# log out and back in for the group change to take effect
```

### 4. Open the firewall

```bash
# RHEL / Amazon (firewalld):
sudo firewall-cmd --permanent --add-port=8080/tcp && sudo firewall-cmd --reload
# Ubuntu / Debian (ufw, if active):
sudo ufw allow 8080/tcp
```

Plus: open inbound TCP 8080 in your **cloud security group / network ACL**.

### 5. Run the container

```bash
cp bridge.env.example bridge.env && chmod 600 bridge.env   # then edit it
docker pull britive/bridge:latest
docker run -d \
  --name bridge \
  --restart unless-stopped \
  -p 8080:8080 \
  --env-file bridge.env \
  -v bridge-data:/data \
  britive/bridge:latest
```

### 6. Verify

```bash
docker ps
curl -sfk https://127.0.0.1:8080/api/health
docker logs -f bridge
```

---

## Distro-specific nuances

| Topic | Debian / Ubuntu | RHEL / Rocky / Alma / Fedora | Amazon Linux |
|-------|-----------------|------------------------------|--------------|
| Package source | `docker-ce` apt repo | `docker-ce` dnf repo | **bundled** `docker` pkg (NOT docker-ce) |
| Installer | `apt-get` | `dnf` | `amazon-linux-extras` (AL2) / `dnf` (AL2023) |
| Default firewall | ufw (often inactive) | **firewalld** (often active) | firewalld (often active) |
| SELinux | usually disabled | **Enforcing** by default | Enforcing by default |
| Default login user | `ubuntu` / admin user | `cloud-user` / root | `ec2-user` |

### SELinux + bind mounts (RHEL / Amazon family)

When SELinux is **Enforcing**, a host **bind mount** must be relabeled or the
container can't read it. This guide uses a **named volume** (`bridge-data`),
which Docker labels correctly — so no action needed. If you switch to a host
path, add the `:Z` (private) or `:z` (shared) label:

```bash
docker run -d --name bridge --restart unless-stopped \
  -p 8080:8080 --env-file bridge.env \
  -v /srv/britive-bridge/data:/data:Z \
  britive/bridge:latest
```

### Image architecture

`britive/bridge` is multi-arch; Docker pulls the variant matching your VM
(`uname -m` → `x86_64`/amd64 or `aarch64`/arm64) automatically. If you pin a
single-arch tag, make sure it matches the VM's architecture.

### Rootless / Podman

On RHEL/Fedora you may have **Podman** instead of Docker. The same commands work
via `podman` (install `podman-docker` to alias `docker`). Note: rootless Podman
**cannot bind to ports < 1024** — fine here since we use 8080. For auto-start
under rootless Podman, generate a systemd unit with `podman generate systemd`.

---

## Custom TLS certificate

By default the container serves a **self-signed cert** on 8080 (browsers warn).
To present your own cert, mount it and point the env vars at the in-container
paths:

```bash
docker run -d --name bridge --restart unless-stopped \
  -p 8080:8080 --env-file bridge.env \
  -v bridge-data:/data \
  -v /etc/ssl/bridge/cert.pem:/custom-certs/cert.pem:ro \
  -v /etc/ssl/bridge/key.pem:/custom-certs/key.pem:ro \
  -e TLS_CERT_FILE=/custom-certs/cert.pem \
  -e TLS_KEY_FILE=/custom-certs/key.pem \
  britive/bridge:latest
```

(On SELinux-enforcing hosts add `:Z` to those `-v` mounts, e.g. `...cert.pem:ro,Z`.)

---

## External URL

Users reach Bridge at the `BRIDGE_URL` you registered in platform setup. Point a
DNS record at the VM's public address (or front it with your own reverse proxy /
load balancer that terminates TLS) and confirm the Britive Bridge **resource**
uses that URL.

---

## Lifecycle / operations

```bash
docker logs -f bridge                 # follow logs
docker restart bridge                 # restart
sudo ./install.sh                     # update: re-pulls image, recreates container
docker rm -f bridge                   # stop + remove (keeps data volume)
docker volume rm bridge-data          # delete persisted state (destructive)
sudo firewall-cmd --permanent --remove-port=8080/tcp && sudo firewall-cmd --reload
                                      # close the port on uninstall (firewalld)
```

**Auto-start on reboot** is handled by `--restart unless-stopped` plus
`systemctl enable docker`. Verify with `sudo reboot` then `docker ps`.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| `curl` to `/api/health` hangs from another host | Firewall/security group not open on 8080 |
| Container restarts in a loop | Bad/missing broker token — check `docker logs bridge` |
| `permission denied` on `docker` | Add user to `docker` group (step 3) or use `sudo` |
| Can't read mounted cert (RHEL) | SELinux — add `:Z` to the `-v` mount |
| Image won't pull | No outbound to Docker Hub, or Docker Hub rate limit (log in: `docker login`) |
| Lost sessions after restart | Data volume not mounted — ensure `-v bridge-data:/data` |
