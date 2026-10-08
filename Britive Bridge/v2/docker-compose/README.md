# Britive Bridge v2 — Docker Compose (single server)

PostgreSQL 17 and `britive/bridge:v2.3.1` on one host, following the official
[single-server guide](https://learn.britive.com/bridge/deploy/single/).
Suitable for evaluation, POCs and small deployments. It does not scale across
machines or survive host failure — for that, use
[ECS Fargate](../aws-ecs-fargate-nlb/) or the Helm chart.

## Prerequisites

- A Linux host with Docker Engine 24+ and the Compose plugin (`docker compose version`)
- Outbound HTTPS from the host to `<tenant>.britive-app.com` (broker MQTT and license fetch)
- The broker pool token from [platform setup](../../platform-setup/)
- Ports 443, 2222, 3389, 3306 and 15432 free on the host (change the mappings in
  `docker-compose.yaml` if not)

## Quickstart

```bash
cp .env.example .env

# Generate the secrets and paste them into .env
echo "BRIDGE_ENCRYPTION_KEY_B64=$(openssl rand -base64 32)"   # REQUIRED, permanent
echo "BRIDGE_CLUSTER_TOKEN=$(openssl rand -hex 32)"           # required with the broker
echo "BRIDGE_HOST_KEY_SEED=$(openssl rand -hex 16)"           # recommended
echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)"

# Then set BRITIVE_TENANT and BRITIVE_BROKER_AUTH_TOKEN in .env

docker compose up -d

# Verify
curl -sk https://localhost/readyz                 # readiness
curl -sk https://localhost/livez                  # liveness
curl -sk https://localhost/api/license/status     # license, fetched automatically via the broker token
docker compose logs bridge | grep -iE 'started|broker|license|error'
```

In the Britive console (**System Administration → Brokers and Broker Pools**)
the broker appears in the pool the token belongs to. Re-run
`../../platform-setup/quick-setup.py` with the real `BRIDGE_URL` so checkouts
return the right link, then run a test checkout end to end.

## Configuration

The Bridge reads [`../../custom-image/bridge.yaml`](../../custom-image/bridge.yaml),
bind-mounted read-only, and the environment in `docker-compose.yaml` overrides
the few values that differ from the ECS option:

| Overridden | Why |
| ---------- | --- |
| `BRIDGE_TLS_ENABLED=true` | No load balancer in front; the container serves its own self-signed certificate (generated under `/data/certs` on first start). Mount a real certificate at `/data/certs/api-cert.pem` + `api-key.pem` to replace it. |
| `BRIDGE_DATASTORE_*` | Points at the bundled `postgres` service over the Compose network. |
| `BRITIVE_TENANT` | Replaces the `your-tenant` placeholder in the file, so the shared file needs no edit here. |
| `BRIDGE_SERVER_AUTH_BRITIVE_REDIRECT_URL` | Built from `BRIDGE_URL` when set, so Britive SSO redirects to the public hostname rather than `localhost`. |

Everything else — which protocols are enabled, idle timeouts, recording
options — is edited in `bridge.yaml` and picked up with `docker compose up -d`
(no image rebuild needed here, unlike ECS).

## Ports

| Host | Container | What |
| ---- | --------- | ---- |
| 443 | 8080 | Web UI / API / browser protocols |
| 2222 | 2222 | Native SSH (`ssh -p 2222 -l '<email>%<target-host>' <bridge-host>`) — not 22, see note |
| 3389 | 3389 | Native RDP |
| 3306 | 3306 | Native MySQL |
| **15432** | 5432 | Native PostgreSQL proxy (remapped so host 5432 stays free) |

SSH is on **2222, not 22**, to keep the shared `bridge.yaml` identical to the
ECS deployment, where Fargate cannot bind privileged ports. Change the host
side of the mapping (`"22:2222"`) if you want 22 externally.

## Operations

- **Data.** Recordings, generated certificates and host keys persist in the
  `bridge-data` volume; PostgreSQL data in `pgdata`. **Back up both** —
  PostgreSQL holds checkouts, sessions and the audit index.
- **Never change `BRIDGE_ENCRYPTION_KEY_B64` after go-live.** Encrypted checkout
  payloads become unreadable. Every other secret rotates with an `.env` edit
  and `docker compose up -d`.
- **Upgrade.** Bump the pinned image tag in `docker-compose.yaml` (or
  `BRIDGE_IMAGE` in `.env`), then `docker compose pull && docker compose up -d`.
  Read the [release notes](https://learn.britive.com/releases/) first — a new
  version may apply one-way schema migrations, so dump the database if you
  need a rollback path.
- **Custom image.** If your checkout scripts need extra tools, build one with
  [`../../custom-image/`](../../custom-image/) (leave `BAKE_CONFIG=false`; the
  file is bind-mounted here) and set `BRIDGE_IMAGE` in `.env`.
- **Teardown.** `docker compose down` keeps the volumes;
  `docker compose down -v` deletes them, including the database.

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `bridge` restarts, log says `at least one protocol must be enabled` | `bridge.yaml` edited with every protocol off | Enable at least one and `docker compose up -d` |
| `failed to apply schema migrations` | PostgreSQL not ready or wrong password | `docker compose logs postgres`; confirm `POSTGRES_PASSWORD` in `.env` matches what the volume was initialised with (`docker compose down -v` to reset in a POC) |
| Login redirects to `https://localhost/...` from another machine | `BRIDGE_URL` unset | Set it in `.env` to the public URL and restart |
| Native checkout returns 403, browser works | No license (limited mode) | `curl -sk https://localhost/api/license/status`; confirm `BRITIVE_BROKER_AUTH_TOKEN` is set and the broker shows connected in the console |
| Browser warns about the certificate | Self-signed default | Mount a real certificate and key at `/data/certs/api-cert.pem` and `/data/certs/api-key.pem` |
