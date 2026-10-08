# Access Broker — Linux VM (package install)

Install the broker as a systemd (or OpenRC) service straight from the package
Britive ships. No container runtime, no Java. This is the simplest production
option for an on-prem server or a cloud VM, and the right one when the broker
must run on a host that already has the tools and network position your
scripts need (a jump host, a domain-joined server, a database subnet).

Britive's own instructions are at
<https://docs.britive.com/v1/docs/linux-broker-v301>; this page is the
condensed, copy-paste version plus the hardening steps the docs leave out.

## 1. Download the package

**System Administration → Brokers and Broker Pools → Download Brokers**. Pick
the package for your distribution and architecture:

| Distribution | Package |
| ------------ | ------- |
| RHEL, Rocky, Amazon Linux, Fedora | `britive-broker-<version>.x86_64.rpm` / `.aarch64.rpm` |
| Debian, Ubuntu | `britive-broker_<version>_amd64.deb` / `_arm64.deb` |
| Alpine | `britive-broker_<version>_x86_64.apk` / `_aarch64.apk` |
| Arch | `britive-broker-<version>-x86_64.pkg.tar.zst` |
| Anything else | `britive-broker-<version>-linux-<arch>.tar.gz` (see [Tarball](#tarball)) |

Copy the link from the console if you need to fetch it on the server with
`curl -O`.

## 2. Install with the tenant and token supplied

The package creates the `britivebroker` user, installs under
`/opt/britive-broker/`, writes `/opt/britive-broker/config/broker-config.yml`
from a template, registers `britive-broker.service`, and starts it when the
tenant and token are known at install time.

Pass them through an env file the package reads and that you delete
afterwards (works on every distribution, required on Alpine):

```bash
sudo mkdir -p /etc/britive-broker
sudo install -m 0600 -o root -g root /dev/stdin /etc/britive-broker/install.env <<'EOF'
BRITIVE_BROKER_TENANT_SUBDOMAIN=your-tenant
BRITIVE_BROKER_AUTH_TOKEN=<broker-pool-token>
EOF

# then one of:
sudo dnf install -y ./britive-broker-<version>.x86_64.rpm
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ./britive-broker_<version>_amd64.deb
sudo apk add --allow-untrusted ./britive-broker_<version>_x86_64.apk
sudo pacman -U --noconfirm ./britive-broker-<version>-x86_64.pkg.tar.zst

sudo shred -u /etc/britive-broker/install.env
```

Or inline for a one-off (not Alpine; the values land in your shell history):

```bash
sudo BRITIVE_BROKER_TENANT_SUBDOMAIN=your-tenant \
     BRITIVE_BROKER_AUTH_TOKEN=<broker-pool-token> \
     apt-get install -y ./britive-broker_<version>_amd64.deb
```

Installing with neither leaves the placeholders in `broker-config.yml` and the
service stopped; edit the file, then `systemctl enable --now britive-broker`.

## 3. Verify

```bash
sudo systemctl status britive-broker --no-pager
sudo journalctl -u britive-broker -n 50 --no-pager
```

Expect `Britive broker starting version=3.x.y` and no repeated
`Broker bootstrap failed`. In the console the broker is listed as active in
the pool under this host's hostname.

## 4. Keep the token out of the config file

The package writes the token into `broker-config.yml` (mode 0600, owned by
root, readable by the service). To keep it in a secret store instead, point
the broker at a generator script that prints the token and remove it from the
file:

```bash
# /opt/britive-broker/bootstrap/token-generator.sh  (0750, owner root:britivebroker)
#!/bin/sh
exec aws secretsmanager get-secret-value --secret-id britive/broker-pool-token \
     --query SecretString --output text
```

```bash
sudo mkdir -p /etc/systemd/system/britive-broker.service.d
sudo tee /etc/systemd/system/britive-broker.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment=BRITIVE_BROKER_AUTH_TOKEN_GENERATOR=/opt/britive-broker/bootstrap/token-generator.sh
EOF
sudo sed -i 's/^\(\s*\)authentication_token:.*/\1# authentication_token: supplied by BRITIVE_BROKER_AUTH_TOKEN_GENERATOR/' \
     /opt/britive-broker/config/broker-config.yml
sudo systemctl daemon-reload && sudo systemctl restart britive-broker
```

Use the override directory for every customization — proxy variables
(`Environment=HTTPS_PROXY=…`), log format
(`Environment=BRITIVE_BROKER_LOG_FORMAT=json`), resource limits. Package
upgrades replace the shipped unit file but keep `override.conf` and your
`broker-config.yml` edits.

## 5. Restrict what this broker serves (optional)

By default the broker accepts every resource type the tenant sends. To limit
it, add a `resource_types` section to
`/opt/britive-broker/config/broker-config.yml` (example in
[`../image/broker-config.yml.example`](../image/broker-config.yml.example)) and
restart. Local scripts referenced with `max_supported_version: local` should
live under `/opt/britive-broker/scripts/`, owned by root, mode 0755, so the
service account can execute but not modify them.

## Upgrade, rotate, remove

- **Upgrade:** install the newer package the same way. The service restarts
  only if it was running.
- **Rotate the token:** create a new token on the pool, update the config (or
  the secret the generator reads), `systemctl restart britive-broker`, delete
  the old token.
- **Remove:** `systemctl disable --now britive-broker`, then
  `dnf remove britive-broker` / `apt-get purge britive-broker`. Config under
  `/opt/britive-broker/config/` may be left behind; delete it by hand.

## Tarball

For a distribution without a package, the `tar.gz` unpacks to
`britive-broker/{britive-broker,bootstrap/,cache/,config/}`. Run it under a
unit you write:

```bash
sudo tar -xzf britive-broker-<version>-linux-amd64.tar.gz -C /opt
sudo useradd --system --home /opt/britive-broker --shell /usr/sbin/nologin britivebroker
sudo chown -R britivebroker:britivebroker /opt/britive-broker

sudo tee /etc/systemd/system/britive-broker.service >/dev/null <<'EOF'
[Unit]
Description=Britive Access Broker
After=network-online.target
Wants=network-online.target

[Service]
User=britivebroker
WorkingDirectory=/opt/britive-broker
EnvironmentFile=/etc/britive-broker/env
ExecStart=/opt/britive-broker/britive-broker run
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/britive-broker/cache
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

sudo install -m 0600 -o root -g root /dev/stdin /etc/britive-broker/env <<'EOF'
BRITIVE_BROKER_TENANT_SUBDOMAIN=your-tenant
BRITIVE_BROKER_AUTH_TOKEN=<broker-pool-token>
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now britive-broker
```

`ProtectSystem=strict` makes the filesystem read-only for the service except
the cache directory; add paths to `ReadWritePaths=` if your scripts write
elsewhere.
