# Britive Broker Scripts - Session Recording (legacy)

> Legacy. New deployments use [Britive Bridge](../../Britive%20Bridge/v2/README.md).
> See [../README.md](../README.md).

Checkout and check-in scripts for the Britive Access Broker. A checkout grants
JIT access on the target host and returns a signed Guacamole token; the session
is proxied and recorded by the Guacamole stack in [../docker/](../docker/README.md).
A check-in revokes that access.

## Architecture

```text
Britive Platform
      |
      |  runs checkout / check-in script
      v
Britive Broker (Linux container)
      |
      +--- SSH (key, pinned host key) ----> Remote Linux host
      |                                      creates/removes user + authorized_keys entry
      |
      +--- WinRM (http or https) ---------> Remote Windows host
                                             creates/removes local admin user

Broker also returns a signed Guacamole token
      |
      v
Guacamole (:8080) -> guacd (:4822) -> Target host (SSH/RDP)
                                            |
                                      recordings volume
```

## Naming

- `remote-*` runs on the broker and reaches the target over SSH or WinRM. Each checkout has a matching check-in.
- `checkout-rdp.ps1` / `checkin-rdp.ps1` run on the Windows target itself (for example through SSM Run Command).
- `*-ec2-*` reads the Guacamole secret from AWS Secrets Manager with the EC2 instance role; for brokers running on EC2, not in the container.
- `checkout-rdp.sh` is token only: an existing domain or local account, nothing created, no check-in.

## Prerequisites

### Broker container

The broker image (`../docker/broker/Dockerfile`, Ubuntu 24.04) provides:

| Dependency           | Purpose                                                            |
|----------------------|--------------------------------------------------------------------|
| `python3`, `pywinrm` | Password generation, WinRM client for the Windows scripts          |
| `openssl`            | HMAC-SHA256 signing and AES-128-CBC encryption of the token        |
| `jq`                 | Builds the connection JSON and URL-encodes the token               |
| `ssh`, `scp`         | Remote Linux host access                                           |
| `/root/.ssh/id_rsa`  | Broker key for SSH to Linux targets, bind-mounted from `docker/broker-ssh/` |

```sh
docker exec britive-broker python3 -c "import winrm; print(winrm.__version__)"
docker exec britive-broker jq --version
docker exec britive-broker ssh -V
```

### Remote Linux hosts

- A service account, `britivebroker`, with sudo.
- The broker's public key (`docker/broker-ssh/id_rsa.pub`) in that account's `authorized_keys`:

  ```sh
  ssh-copy-id -i /path/to/broker-ssh/id_rsa.pub britivebroker@<target-host>
  ```

- Host keys: the scripts use `StrictHostKeyChecking=accept-new`. The first
  connection to a host pins its key in `/root/.ssh/known_hosts` (persisted in
  `docker/broker-ssh/known_hosts` through the bind mount, which must be
  writable). A later key change makes checkout and check-in fail until the
  stale line is removed. To avoid trusting the first connection, pre-populate
  the file: `ssh-keyscan <target-host> >> docker/broker-ssh/known_hosts`.

### Remote Windows hosts

WinRM must be enabled. Two modes are supported, chosen with `WINRM_SCHEME` and
`WINRM_TRANSPORT`:

- **https + ntlm** (recommended). Needs a WinRM HTTPS listener with a
  certificate. If the certificate is self-signed, set
  `WINRM_CERT_VALIDATION=ignore`.

  ```powershell
  winrm quickconfig -transport:https -quiet
  ```

- **http + basic** (default, lab use only; the admin password crosses the
  network base64-encoded):

  ```powershell
  winrm quickconfig -quiet
  winrm set winrm/config/service/Auth '@{Basic="true"}'
  winrm set winrm/config/service '@{AllowUnencrypted="true"}'
  ```

Check reachability from the broker (5986 for https):

```sh
docker exec britive-broker python3 -c "import socket; socket.create_connection(('<windows-host>', 5985), timeout=5); print('OK')"
```

## Token generation

Every checkout builds the Guacamole JSON auth object with `jq` and then:

1. signs it: `HMAC-SHA256(JSON, key)` prepended to the JSON bytes
2. encrypts it: `AES-128-CBC(signed, key, IV = 16 zero bytes)`
3. base64- and URL-encodes the result

The key (`SECRET`, `SECRET_KEY` or `json_secret_key`) is 32 hex characters,
generated with `openssl rand -hex 16`, and must equal `JSON_SECRET_KEY` in
`docker/.env`. Scripts refuse to run with anything else.

The `${GUAC_DATE}`, `${GUAC_TIME}` and `${HISTORY_UUID}` placeholders in the
recording paths are Guacamole tokens, substituted by Guacamole, not by the
shell.

## Scripts

### SSH, Linux targets

#### `ssh/remote-checkout-ssh.sh`

SSHes to the target as `britivebroker`, creates the user if missing, generates
a fresh RSA key pair on the broker and appends the public key to the user's
`authorized_keys` tagged `# britive-<TRX>`. The private key is embedded in the
token so guacd can log in. Optionally grants passwordless sudo.

Required: `BRITIVE_USER_EMAIL`, `BRITIVE_REMOTE_HOST`, `SECRET`, `connection_name`, `url`
Optional: `port` (22), `expiration` (3600), `recording_path`, `BRITIVE_USER_GROUP`, `BRITIVE_SUDO` (0), `BRITIVE_HOME_ROOT` (home), `TRX` (set by Britive)

#### `ssh/remote-checkin-ssh.sh`

Removes only the `authorized_keys` line tagged with this transaction's
`# britive-<TRX>` marker, so concurrent sessions and shared accounts are safe.
With `BRITIVE_CLEANUP_USER=1` the account, its home directory and its sudoers
entry are removed once no Britive keys remain.

Required: `BRITIVE_USER_EMAIL`, `BRITIVE_REMOTE_HOST`, `TRX`
Optional: `port`, `BRITIVE_CLEANUP_USER` (0), `BRITIVE_USER_GROUP`, `BRITIVE_SUDO`, `BRITIVE_HOME_ROOT`

### RDP, Windows targets

#### `rdp/remote-checkout-rdp.sh`

Connects over WinRM, creates a local administrator named
`<email-prefix, 16 chars max>-rec` (or resets its password if it exists) with a
random 16-character password that meets Windows complexity rules, and returns
a token with those credentials embedded. Secrets are handed to the embedded
Python through its environment, never written into the script text.

Required: `BRITIVE_USER_EMAIL`, `BRITIVE_REMOTE_HOST`, `WINRM_PASSWORD`, `SECRET`, `connection_name`, `url`
Optional: `WINRM_USER` (Administrator), `WINRM_SCHEME` (http), `WINRM_PORT` (5985 / 5986), `WINRM_TRANSPORT` (basic), `WINRM_CERT_VALIDATION` (validate), `port` (3389), `expiration` (3600), `recording_path`

#### `rdp/remote-checkin-rdp.sh`

Connects over WinRM, logs off every session of the temporary user
(`Invoke-RDUserLogoff` where the RemoteDesktop module exists, `logoff.exe`
otherwise) and removes the account.

Required: `BRITIVE_USER_EMAIL`, `BRITIVE_REMOTE_HOST`, `WINRM_PASSWORD`
Optional: the same `WINRM_*` variables as the checkout

#### `rdp/checkout-rdp.ps1`

Runs on the Windows target. Same account scheme as the remote variant, with a
CSPRNG password. Logs to `%ProgramData%\Britive\logs\<ResourceName>.log` and
exits 1 on failure.

Environment: `user_email`, `ResourceName`, `hostname`, `port`, `json_secret_key`, `url`, `expiration` (3600)

#### `rdp/checkin-rdp.ps1`

Runs on the Windows target. Logs off the user's sessions (with the same
`logoff.exe` fallback) and removes the account.

Environment: `user_email`

#### `rdp/checkout-rdp.sh`

Token only, for a user who signs in to the Windows host with their own domain
or local password. Nothing is created and there is no check-in.

Required: `BRITIVE_USER_EMAIL`, `hostname`, `connection_name`, `url`, `SECRET_KEY`
Optional: `port` (3389), `domain`, `security` (nla), `ignore_cert` (true), `expiration` (3600), `recording_path`

#### `rdp/checkout-ec2-rdp.sh`

As `checkout-rdp.sh`, but for a broker on EC2: the key is read from Secrets
Manager (`json_secret_key` is the secret name or ARN; the secret value is
`{"key": "<32 hex chars>"}`) using the instance role, which needs
`secretsmanager:GetSecretValue`. Requires the `aws` CLI and `ec2metadata` on
the instance.

## Variable reference

| Variable                | Used by                       | Description                                                                  |
|-------------------------|-------------------------------|------------------------------------------------------------------------------|
| `BRITIVE_USER_EMAIL`    | all                           | User's email. The Guacamole username; the OS username is derived from the prefix |
| `BRITIVE_REMOTE_HOST`   | `remote-*`                    | Hostname or IP of the target                                                 |
| `SECRET`                | `remote-*` checkouts          | 32 hex char Guacamole key                                                    |
| `SECRET_KEY`            | `checkout-rdp.sh`             | 32 hex char Guacamole key                                                    |
| `json_secret_key`       | `checkout-ec2-rdp.sh`, `.ps1` | Secrets Manager secret id (ec2) or the key itself (PowerShell)              |
| `TRX`                   | `remote-*-ssh.sh`             | Britive transaction id, injected by the platform                            |
| `connection_name`       | all checkouts                 | Connection label shown in Guacamole                                          |
| `expiration`            | all checkouts                 | Token lifetime in seconds (default 3600)                                     |
| `url`                   | all checkouts                 | Guacamole base URL, e.g. `http://host:8080/guacamole`                        |
| `recording_path`        | all checkouts                 | Path inside guacd (default `/home/guacd/recordings`)                         |
| `port`                  | all                           | Target SSH (22) or RDP (3389) port                                           |
| `BRITIVE_SUDO`          | `remote-*-ssh.sh`             | `1` grants passwordless sudo                                                 |
| `BRITIVE_CLEANUP_USER`  | `remote-checkin-ssh.sh`       | `1` removes the account when no Britive keys remain                          |
| `WINRM_USER`            | `remote-*-rdp.sh`             | Windows admin account for WinRM (default `Administrator`)                    |
| `WINRM_PASSWORD`        | `remote-*-rdp.sh`             | Its password; mark as secret in Britive                                      |
| `WINRM_SCHEME`          | `remote-*-rdp.sh`             | `http` (default) or `https`                                                  |
| `WINRM_PORT`            | `remote-*-rdp.sh`             | Default 5985 for http, 5986 for https                                        |
| `WINRM_TRANSPORT`       | `remote-*-rdp.sh`             | `basic` (default) or `ntlm`                                                  |
| `WINRM_CERT_VALIDATION` | `remote-*-rdp.sh`             | `validate` (default) or `ignore`, https only                                 |
