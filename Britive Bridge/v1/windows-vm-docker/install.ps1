<#
.SYNOPSIS
  Run the Britive Bridge container on a Windows VM using Docker (Docker Hub image).

.DESCRIPTION
  britive/bridge is a LINUX container image. Windows can only run it through a
  Linux container runtime, which means one of:
    - Docker Desktop with the WSL 2 backend (Windows 10/11, Server 2022+), OR
    - Docker CE installed INSIDE a WSL 2 distro (run this from that distro's
      shell instead — see the Linux guide).
  Native Windows containers (the default "Windows containers" mode) CANNOT run
  this image. This script verifies you are in Linux-container mode and refuses
  to continue otherwise.

  The script does NOT install Docker (Docker Desktop is a GUI/MSI install and
  WSL 2 setup is interactive). It checks prerequisites, opens the firewall,
  pulls the image, and runs the container.

.PARAMETER Image
  Docker Hub image. Default: britive/bridge:latest

.PARAMETER ContainerName
  Name for the container. Default: bridge

.PARAMETER Port
  Host port published for HTTPS. Default: 8080

.PARAMETER DataVolume
  Docker named volume mounted at /data. Default: bridge-data

.PARAMETER EnvFile
  Env file with the broker credentials. Default: bridge.env

.EXAMPLE
  Copy-Item bridge.env.example bridge.env   # then edit bridge.env
  .\install.ps1

.NOTES
  Run from an ELEVATED PowerShell (Run as Administrator) so the firewall rule
  can be created.
#>

[CmdletBinding()]
param(
  [string]$Image         = "britive/bridge:latest",
  [string]$ContainerName = "bridge",
  [int]   $Port          = 8080,
  [string]$DataVolume    = "bridge-data",
  [string]$EnvFile       = "bridge.env"
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "WARN: $msg" -ForegroundColor Yellow }
function Die($msg)        { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ── 1. Must be elevated (to add the firewall rule) ──────────────────────────
$principal = New-Object Security.Principal.WindowsPrincipal(
  [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Die "Run this from an elevated PowerShell (Run as Administrator)."
}

# ── 2. Docker must be installed and the daemon reachable ────────────────────
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Die "Docker not found. Install Docker Desktop (WSL 2 backend) first — see README."
}
# Native commands don't throw on failure in PowerShell — check the exit code.
docker info *> $null
if ($LASTEXITCODE -ne 0) {
  Die "Docker daemon not reachable. Start Docker Desktop and wait for it to be running."
}

# ── 3. Must be in LINUX container mode (not Windows containers) ─────────────
# 'docker info' reports the daemon OS. britive/bridge is a Linux image.
$daemonOS = (docker info --format '{{.OSType}}').Trim()
Write-Step "Docker daemon OSType: $daemonOS"
if ($daemonOS -ne "linux") {
  Die @"
Docker is in '$daemonOS' container mode. britive/bridge is a LINUX image.
Switch Docker Desktop to Linux containers:
  Right-click the Docker tray icon > 'Switch to Linux containers...'
Then re-run this script.
"@
}

# ── 4. Env file must exist, be edited, and be BOM-free ──────────────────────
if (-not (Test-Path $EnvFile)) {
  Die "Missing $EnvFile. Run: Copy-Item bridge.env.example bridge.env  then edit it."
}
if (Select-String -Path $EnvFile -Pattern '<your-' -SimpleMatch -Quiet) {
  Die "$EnvFile still contains placeholder values (<your-...>). Edit it with your real tenant subdomain and broker token."
}
# A UTF-8 BOM corrupts the first variable name when docker parses --env-file.
$firstBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $EnvFile))[0..2]
if ($firstBytes.Count -ge 3 -and $firstBytes[0] -eq 0xEF -and $firstBytes[1] -eq 0xBB -and $firstBytes[2] -eq 0xBF) {
  Die "$EnvFile starts with a UTF-8 BOM, which breaks docker --env-file. Re-save it as UTF-8 WITHOUT BOM (in VS Code: 'Save with Encoding' > 'UTF-8')."
}

# ── 5. Open the Windows Firewall for the port ───────────────────────────────
$ruleName = "Britive Bridge $Port"
if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
  Write-Step "Adding firewall rule '$ruleName' (inbound TCP $Port)..."
  New-NetFirewallRule -DisplayName $ruleName -Direction Inbound `
    -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
} else {
  Write-Step "Firewall rule '$ruleName' already exists."
}
Write-Warn "Also open inbound TCP $Port in any CLOUD security group / network ACL."

# ── 6. Pull the image and (re)create the container ──────────────────────────
Write-Step "Pulling $Image ..."
docker pull $Image
if ($LASTEXITCODE -ne 0) {
  Die "docker pull failed. Check internet access to Docker Hub and the image name '$Image'."
}

$exists = docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $ContainerName }
if ($exists) {
  Write-Step "Removing existing container '$ContainerName'..."
  docker rm -f $ContainerName | Out-Null
}

Write-Step "Starting container '$ContainerName'..."
# --restart unless-stopped : restart on crash and when the VM/Docker restarts
# --env-file               : load broker creds without exposing them on cmdline
# -v ${DataVolume}:/data    : persist session state in a Docker-managed volume
docker run -d `
  --name $ContainerName `
  --restart unless-stopped `
  -p "$($Port):8080" `
  --env-file $EnvFile `
  -v "$($DataVolume):/data" `
  $Image | Out-Null
if ($LASTEXITCODE -ne 0) {
  Die "docker run failed. Check the output above and your $EnvFile contents."
}

# ── 7. Health check ─────────────────────────────────────────────────────────
Write-Step "Waiting for Bridge to report healthy..."
$healthy = $false
# -SkipCertificateCheck (accepts the self-signed cert) needs PS 6+. On
# Windows PowerShell 5.1, probe from inside the container with curl instead.
$useInvokeWebRequest = $PSVersionTable.PSVersion.Major -ge 6
for ($i = 0; $i -lt 20; $i++) {
  if ($useInvokeWebRequest) {
    try {
      $resp = Invoke-WebRequest -Uri "https://127.0.0.1:$Port/api/health" `
        -SkipCertificateCheck -TimeoutSec 5 -UseBasicParsing
      if ($resp.StatusCode -eq 200) { $healthy = $true; break }
    } catch { }
  } else {
    docker exec $ContainerName curl -sfk "https://127.0.0.1:8080/api/health" *> $null
    if ($LASTEXITCODE -eq 0) { $healthy = $true; break }
  }
  Start-Sleep -Seconds 3
}
if ($healthy) {
  Write-Step "Bridge is healthy at https://127.0.0.1:$Port/api/health"
} else {
  Write-Warn "Health check not passing yet. Inspect: docker logs $ContainerName"
}

Write-Step "Done. Logs: docker logs -f $ContainerName"
