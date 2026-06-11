# Britive Bridge — Windows VM (Docker)

Run the Britive Bridge container (which hosts the broker process) on a Windows VM
using Docker, pulling the image from **Docker Hub** (`britive/bridge`).

> **Read this first — the key Windows nuance:** `britive/bridge` is a **Linux**
> container image. Windows can only run Linux images through a Linux runtime,
> i.e. the **WSL 2 backend**. Native "Windows containers" mode **cannot** run
> this image. Everything below assumes Linux-container mode via WSL 2.

---

## Which path fits your VM?

| Your VM | Recommended runtime |
|---------|---------------------|
| Windows 10/11 Pro/Enterprise | **Docker Desktop** with WSL 2 backend |
| Windows Server 2022 / 2025 | **Docker CE inside a WSL 2 distro** — follow the [Linux guide](../linux-vm-docker/) from that distro's shell. Docker does **not support Docker Desktop on any Windows Server edition** |
| Windows Server 2019 | WSL 2 is not generally available, and WSL 1 cannot run Docker. **Use a Linux VM** ([Linux guide](../linux-vm-docker/)) or upgrade to Server 2022+ |

If you end up running Docker **inside a WSL 2 Linux distro**, follow the
[Linux VM guide](../linux-vm-docker/) from that distro's shell instead — it's
simpler and the same image.

**Licensing note:** Docker Desktop requires a paid subscription for larger
businesses. If that's a blocker, use a Linux VM with Docker Engine (no Desktop
license) per the Linux guide.

---

## Prerequisites

- Windows 10/11 (Pro/Enterprise) or Windows Server 2022+, 64-bit, with
  **virtualization enabled** in BIOS/hypervisor (required for WSL 2).
- **WSL 2** installed: in an elevated PowerShell run `wsl --install` then reboot.
- A Linux-container runtime:
  - Windows 10/11: **Docker Desktop** set to **Linux containers** (tray icon →
    *Switch to Linux containers…* if currently on Windows containers).
  - Windows Server 2022+: **Docker CE inside your WSL 2 distro** (Docker
    Desktop is not supported on Windows Server) — in that case follow the
    [Linux guide](../linux-vm-docker/) from the distro's shell instead of this
    script.
- **Outbound** internet to your Britive tenant (Broker/MQTT) and Docker Hub.
- **Inbound** TCP on the Bridge port (default `8080`) — open the Windows Firewall
  **and** any cloud security group / network ACL.
- PowerShell 5.1+ (built in). `install.ps1` works on both: on 7+ it probes
  health with `Invoke-WebRequest -SkipCertificateCheck`, on 5.1 it falls back
  to `docker exec ... curl` automatically.
- Completed [platform setup](../platform-setup/) — you need
  `BRITIVE_BROKER_TENANT_SUBDOMAIN` and `BRITIVE_BROKER_AUTH_TOKEN`.

---

## Install WSL 2 + Docker Desktop (one-time)

```powershell
# Elevated PowerShell:
wsl --install            # installs WSL 2 + a default Linux distro; reboot after
wsl --status             # confirm "Default Version: 2"
```

Then install **Docker Desktop** (download the MSI from Docker, or via winget):

```powershell
winget install -e --id Docker.DockerDesktop
```

Launch Docker Desktop → Settings → **General**: ensure *Use the WSL 2 based
engine* is checked. Confirm you're in Linux mode:

```powershell
docker info --format '{{.OSType}}'   # must print: linux
```

---

## Quick start (scripted)

```powershell
# 0. Get install.ps1 + bridge.env.example onto the VM (git clone this repo or
#    copy the two files) and run from that folder.

# 1. Provide credentials
Copy-Item bridge.env.example bridge.env
notepad bridge.env       # set tenant subdomain + broker token, save

# 2. Run (elevated PowerShell — needed for the firewall rule)
.\install.ps1

# 3. Verify (PowerShell 7+)
Invoke-WebRequest https://127.0.0.1:8080/api/health -SkipCertificateCheck
# PowerShell 5.1 instead:
#   docker exec bridge curl -sfk https://127.0.0.1:8080/api/health
docker logs -f bridge
```

`install.ps1` verifies Docker is present and in **Linux** mode, opens the
firewall, pulls `britive/bridge:latest`, and runs the container with a persistent
volume and `--restart unless-stopped`. Re-run it to update / recreate.

Override defaults:

```powershell
.\install.ps1 -Port 9443 -ContainerName bridge -Image britive/bridge:latest
```

> **Production:** pin a specific image tag (see Docker Hub `britive/bridge`
> tags) instead of `latest`, so reinstalls don't pull an unplanned version:
> `.\install.ps1 -Image britive/bridge:<version>`

> **Execution policy:** if the script is blocked, run it for this session only:
> `powershell -ExecutionPolicy Bypass -File .\install.ps1`

---

## Manual steps

```powershell
# 1. Confirm Linux-container mode
docker info --format '{{.OSType}}'        # -> linux

# 2. Open the Windows Firewall (elevated)
New-NetFirewallRule -DisplayName "Britive Bridge 8080" -Direction Inbound `
  -Action Allow -Protocol TCP -LocalPort 8080

# 3. Credentials
Copy-Item bridge.env.example bridge.env   # then edit bridge.env

# 4. Pull + run.  Backtick (`) is the PowerShell line-continuation character.
docker pull britive/bridge:latest
docker run -d `
  --name bridge `
  --restart unless-stopped `
  -p 8080:8080 `
  --env-file bridge.env `
  -v bridge-data:/data `
  britive/bridge:latest

# 5. Verify
docker ps
docker logs -f bridge
```

---

## Windows-specific nuances

- **Line continuation.** PowerShell uses a backtick `` ` `` at end-of-line, not
  the shell's `\`. Copy-pasting Linux commands with `\` will break.
- **Container mode matters.** `docker info --format '{{.OSType}}'` must say
  `linux`. If it says `windows`, switch via the Docker tray icon. The image will
  not run otherwise (`no matching manifest for windows/amd64`).
- **WSL 2 file/volume location.** With the WSL 2 backend, the `bridge-data`
  **named volume** lives inside the WSL distro's virtual disk (managed by
  Docker). Prefer named volumes over Windows-path bind mounts — bind-mounting
  `C:\...` into a Linux container crosses the WSL boundary and is slower and
  permission-fiddly.
- **`--env-file` formatting.** Plain `KEY=VALUE` lines, no quotes, no `$env:` or
  `set` prefixes. Save `bridge.env` as UTF-8 **without BOM** (Notepad's default
  ANSI/UTF-8 is fine; avoid "UTF-8 with BOM").
- **Health check TLS.** The container's cert is self-signed.
  `Invoke-WebRequest -SkipCertificateCheck` requires **PowerShell 7+**. On
  Windows PowerShell 5.1, check health from inside the container instead:
  `docker exec bridge curl -sfk https://127.0.0.1:8080/api/health`.
- **Auto-start on reboot.** `--restart unless-stopped` restarts the container,
  but only once **Docker Desktop itself starts**. In Docker Desktop Settings →
  General, enable *Start Docker Desktop when you log in*. For an unattended
  server that should run without an interactive login, a **Linux VM with Docker
  Engine** is the more robust choice.

---

## Custom TLS certificate

```powershell
docker run -d --name bridge --restart unless-stopped `
  -p 8080:8080 --env-file bridge.env `
  -v bridge-data:/data `
  -v C:\certs\cert.pem:/custom-certs/cert.pem:ro `
  -v C:\certs\key.pem:/custom-certs/key.pem:ro `
  -e TLS_CERT_FILE=/custom-certs/cert.pem `
  -e TLS_KEY_FILE=/custom-certs/key.pem `
  britive/bridge:latest
```

(Windows-path bind mounts are passed through WSL 2; ensure the drive is shared
in Docker Desktop → Settings → Resources → File sharing.)

---

## External URL

Users reach Bridge at the `BRIDGE_URL` you registered in platform setup. Point a
DNS record at the VM's public address (or front it with a reverse proxy / load
balancer that terminates TLS) and confirm the Britive Bridge **resource** uses
that URL.

---

## Lifecycle / operations

```powershell
docker logs -f bridge                       # follow logs
docker restart bridge                       # restart
docker pull britive/bridge:latest; docker rm -f bridge; .\install.ps1   # update
docker rm -f bridge                         # stop + remove (keeps volume)
docker volume rm bridge-data                # delete persisted state (destructive)
```

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---------|--------------------|
| `no matching manifest for windows/amd64` | Docker in Windows-container mode — switch to Linux containers |
| `docker: error during connect` / daemon unreachable | Docker Desktop not started, or WSL 2 not running |
| Script "cannot be loaded because running scripts is disabled" | `powershell -ExecutionPolicy Bypass -File .\install.ps1` |
| Health check fails on PS 5.1 | `-SkipCertificateCheck` needs PS 7+; use `docker exec ... curl -k` |
| Container restarts in a loop | Bad/missing broker token — check `docker logs bridge` |
| Reachable locally but not from other hosts | Firewall rule and/or cloud security group not open on 8080 |
| Bind-mounted `C:\` cert not found | Share the drive in Docker Desktop → Resources → File sharing |
| Lost sessions after reboot | Data volume not mounted, or Docker Desktop didn't auto-start |
