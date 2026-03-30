# Britive Broker Scripts — Session Recording

Checkout and checkin scripts for the Britive Access Broker. Each script grants or revokes JIT access to a target host and returns a signed Guacamole token so the session is proxied and recorded through the Guacamole stack.

## Architecture Overview

```text
Britive Platform
      │
      │  triggers checkout/checkin script
      ▼
Britive Broker (Linux container)
      │
      ├─── SSH (port 22) ──────────► Remote Linux host
      │                               creates/removes user + authorized_keys
      │
      └─── WinRM (port 5985) ──────► Remote Windows EC2
                                      creates/removes local admin user

Broker also generates a signed Guacamole token
      │
      ▼
Guacamole (:8080) ──► guacd (:4822) ──► Target host (SSH/RDP)
                                               │
                                         recordings volume
```

## Prerequisites

### Broker Container

The broker runs inside a Docker container based on Ubuntu 24.04. The following must be present:

| Dependency | Purpose | Installed by |
|---|---|---|
| `python3` | Password generation, WinRM client | Dockerfile apt |
| `pywinrm` | WinRM connection to Windows hosts | `pip3 install pywinrm` |
| `openssl` | HMAC-SHA256 signing + AES-128-CBC encryption for Guacamole tokens | Dockerfile apt |
| `jq` | JSON construction and URI encoding | Dockerfile apt |
| `ssh` / `scp` | Remote Linux host access | Dockerfile apt (openssh-client) |
| `/root/.ssh/id_rsa` | Broker RSA private key for SSH to remote Linux hosts | Bind-mounted via docker-compose |

Verify all dependencies are available:
```sh
docker exec britive-broker python3 -c "import winrm; print(winrm.__version__)"
docker exec britive-broker openssl version
docker exec britive-broker jq --version
docker exec britive-broker ssh -V
```

### Remote Linux Hosts

- A service account (`britivebroker` by default) must exist and have sudo privileges
- The broker's public key (`/root/.ssh/id_rsa.pub`) must be in that account's `authorized_keys`
- `sudo` must be available for user management commands

Add the broker's public key to the target host once:
```sh
ssh-copy-id -i /path/to/broker-ssh/id_rsa.pub \
  -o "IdentityFile=/path/to/existing-key" \
  britivebroker@<target-host>
```

### Remote Windows Hosts

WinRM must be enabled with Basic auth over HTTP. Run once on each target Windows EC2 as Administrator:

```powershell
winrm quickconfig -quiet
winrm set winrm/config/service/Auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
```

> For production, use HTTPS (port 5986) with a certificate instead of unencrypted HTTP.

Verify WinRM is reachable from the broker:
```sh
python3 -c "import socket; s=socket.create_connection(('<windows-host>', 5985), timeout=5); print('OK'); s.close()"
```

## Token Generation

All checkout scripts generate a Guacamole JSON auth token. The process:

1. Build a JSON object containing `username`, `expires`, and a `connections` map
2. Sign it: `HMAC-SHA256(JSON, secret_key)` prepended to the raw JSON bytes
3. Encrypt it: `AES-128-CBC(signed_data, secret_key[0:16], IV=0x00*16)`
4. Base64-encode + URL-encode the result

The `SECRET` / `json_secret_key` variable must be a **32 hex character string** (16 bytes) and must match `JSON_SECRET_KEY` in `docker-compose.yaml`.

## Scripts Reference

### Generic

#### `checkout-generic.sh`
Lowest-level token generator. Takes a pre-built `connection` JSON object and wraps it in a signed Guacamole token. Used when the connection object is constructed externally.

**Required variables:** `username`, `connection_name`, `connection` (JSON), `expiration`, `json_secret_key`

---

### SSH — Linux Targets

#### `ssh/checkout-ssh.sh`
Runs **directly on the broker or target host** (broker IS the SSH endpoint). Creates a local OS user, generates a temporary RSA keypair, appends the public key to `authorized_keys`, and returns a Guacamole SSH token. The private key is embedded in the token — guacd uses it to connect back to the broker's SSH server.

**Required variables:** `BRITIVE_USER_EMAIL`, `hostname`, `port`, `connection_name`, `expiration`, `SECRET_KEY`, `url`

**Optional variables:** `BRITIVE_SUDO` (default `0`), `BRITIVE_HOME_ROOT` (default `home`)

---

#### `ssh/checkout-ec2-ssh.sh`
Same as `checkout-ssh.sh` but retrieves `SECRET_KEY` from **AWS Secrets Manager** using the instance's IAM role. Intended for EC2-hosted brokers.

**Additional requirement:** EC2 instance role must have `secretsmanager:GetSecretValue` on the target secret.

**Required variables:** same as `checkout-ssh.sh`, plus `json_secret_key` (Secrets Manager secret name/ARN)

---

#### `ssh/remote-checkout-ssh.sh`
Runs on the broker and **SSHes to a separate remote Linux host** to create the user there. The broker uses its own key (`/root/.ssh/id_rsa`) to authenticate to the remote host as `britivebroker`, then performs user setup with sudo. Returns a Guacamole SSH token pointing at the remote host.

**Key behaviour:**
- Generates a fresh RSA keypair on the broker per checkout
- Appends the public key to the remote user's `authorized_keys` with a `# britive-<TRX>` marker for precise removal at checkin
- Optionally grants passwordless sudo via `/etc/sudoers.d/`

**Required variables:** `BRITIVE_USER_EMAIL`, `BRITIVE_REMOTE_HOST`, `SECRET`, `connection_name`, `expiration`, `url`, `recording_path`

**Optional variables:** `BRITIVE_USER_GROUP`, `BRITIVE_SUDO` (default `0`), `BRITIVE_HOME_ROOT` (default `home`), `TRX` (auto-set by Britive), `port` (default `22`)

---

#### `ssh/remote-checkin-ssh.sh`
Runs on the broker and **SSHes to the remote Linux host** to revoke access. Removes the specific `authorized_keys` entry tagged with `# britive-<TRX>`. By default the user account is left in place.

**Key behaviour:**
- Only removes the key matching the TRX marker — safe for shared accounts or concurrent sessions
- `BRITIVE_CLEANUP_USER=1` enables full user removal (home dir + sudoers) when no keys remain

**Required variables:** `BRITIVE_USER_EMAIL`, `BRITIVE_REMOTE_HOST`, `TRX`

**Optional variables:** `BRITIVE_CLEANUP_USER` (default `0`), `BRITIVE_USER_GROUP`, `BRITIVE_SUDO`, `BRITIVE_HOME_ROOT`

---

### RDP — Windows Targets

#### `rdp/checkout-rdp.sh`
Generates a Guacamole RDP token for an **existing domain or local user** — no user creation. Use when the user authenticates with their own AD credentials or a pre-existing account.

**Required variables:** `BRITIVE_USER_EMAIL`, `hostname`, `port`, `connection_name`, `expiration`, `SECRET_KEY`, `url`

**Optional variables:** `DOMAIN`, `security` (default `nla`), `ignore_cert` (default `true`), `recording_path`

---

#### `rdp/checkout-ec2-rdp.sh`
Same as `checkout-rdp.sh` but retrieves `SECRET_KEY` from **AWS Secrets Manager**.

---

#### `rdp/checkout-rdp.ps1`
PowerShell script that runs **directly on the Windows target**. Creates a temporary local admin user, generates a password, and returns a Guacamole RDP token. Use when Britive can execute scripts on the Windows host directly (e.g. via SSM Run Command).

**Required variables (env):** `user_email`, `ResourceName`, `hostname`, `port`, `json_secret_key`, `expiration`, `url`

---

#### `rdp/checkin-rdp.ps1`
PowerShell script that runs **directly on the Windows target**. Kills active RDP sessions for the user and removes the local account.

**Required variables (env):** `user_email`

---

#### `rdp/remote-checkout-rdp.sh`
Runs on the broker and connects to a **remote Windows host via WinRM** to create a temporary local admin user. Returns a Guacamole RDP token with the generated credentials embedded. Session is recorded via guacd.

**Key behaviour:**
- Creates user if not present, or resets the password if already exists (idempotent)
- Password satisfies Windows complexity requirements (upper, lower, digit, special)
- Username derived from email prefix, truncated to 16 chars + `-rec` suffix (max 20 chars)

**Required variables:** `BRITIVE_USER_EMAIL`, `BRITIVE_REMOTE_HOST`, `WINRM_PASSWORD`, `SECRET`, `connection_name`, `expiration`, `url`, `recording_path`

**Optional variables:** `WINRM_USER` (default `Administrator`), `WINRM_PORT` (default `5985`), `port` (default `3389`)

---

#### `rdp/remote-checkin-rdp.sh`
Runs on the broker and connects to the **remote Windows host via WinRM** to revoke access. Kills active RDP sessions for the user then removes the local account.

**Required variables:** `BRITIVE_USER_EMAIL`, `BRITIVE_REMOTE_HOST`, `WINRM_PASSWORD`

**Optional variables:** `WINRM_USER` (default `Administrator`), `WINRM_PORT` (default `5985`)

---

## Variable Reference

| Variable | Used by | Description |
|---|---|---|
| `BRITIVE_USER_EMAIL` | all | User's email address — username is derived from the prefix |
| `BRITIVE_REMOTE_HOST` | remote scripts | Hostname or IP of the target server |
| `SECRET` | remote-checkout scripts | 32 hex char Guacamole secret key |
| `json_secret_key` | local/ec2 scripts | Secret key value or Secrets Manager ARN |
| `TRX` | ssh remote scripts | Britive transaction ID — auto-injected by the platform |
| `connection_name` | all checkout | Connection label shown in Guacamole UI |
| `expiration` | all checkout | Session duration in seconds |
| `url` | all checkout | Guacamole base URL (e.g. `http://host:8080/guacamole`) |
| `recording_path` | all checkout | Path inside guacd container (default `/home/guacd/recordings`) |
| `BRITIVE_SUDO` | ssh scripts | `1` to grant passwordless sudo to the created user |
| `BRITIVE_CLEANUP_USER` | remote-checkin-ssh | `1` to remove user account on checkin (default `0`) |
| `WINRM_USER` | rdp remote scripts | Windows admin account for WinRM auth (default `Administrator`) |
| `WINRM_PASSWORD` | rdp remote scripts | Password for the WinRM admin account (mark as secret in Britive) |
| `WINRM_PORT` | rdp remote scripts | WinRM port (default `5985`) |
