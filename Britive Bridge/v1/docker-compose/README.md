# Britive Bridge — Docker Compose

Run Bridge as a single container on any Docker host or VM. Simplest option —
ideal for local trials, POCs, and single-VM deployments.

## Prerequisites

- Docker Engine 20.10+ with the Compose plugin (`docker compose`)
- Outbound network access from the host to your Britive tenant (Broker/MQTT)
- Completed [platform setup](../../platform-setup/) — you need:
  - `BRITIVE_BROKER_TENANT_SUBDOMAIN`
  - `BRITIVE_BROKER_AUTH_TOKEN`

## What it deploys

- One `britive/bridge` container
- Port `8080` published on the host (HTTPS API + WebSocket + browser protocols)
- A named Docker volume `bridge-data` mounted at `/data` for persistence
- A health check against `https://127.0.0.1:8080/api/health`

## Install

1. Provide the broker credentials. Either export them in your shell:

   ```bash
   export BRITIVE_BROKER_TENANT_SUBDOMAIN="<your-tenant-subdomain>"
   export BRITIVE_BROKER_AUTH_TOKEN="<your-broker-auth-token>"
   ```

   …or copy the template and fill it in (compose reads `.env` automatically):

   ```bash
   cp .env.example .env
   # then edit .env with your real values
   ```

   > Do not commit `.env` — add it to `.gitignore`.

2. Start it:

   ```bash
   docker compose up -d
   ```

3. Check health and logs:

   ```bash
   docker compose ps
   docker compose logs -f bridge
   curl -sfk https://localhost:8080/api/health
   ```

## Equivalent `docker run`

```bash
docker run -d --name bridge -p 8080:8080 \
  --restart unless-stopped \
  -e BRITIVE_BROKER_TENANT_SUBDOMAIN="<your-tenant-subdomain>" \
  -e BRITIVE_BROKER_AUTH_TOKEN="<your-broker-auth-token>" \
  -v bridge-data:/data \
  britive/bridge:latest
```

## TLS

By default the container serves an **auto-generated self-signed certificate**.
To use your own certificate, uncomment the `TLS_CERT_FILE` / `TLS_KEY_FILE`
environment variables and the matching bind mounts in `docker-compose.yaml`:

```yaml
    environment:
      TLS_CERT_FILE: "/custom-certs/cert.pem"
      TLS_KEY_FILE: "/custom-certs/key.pem"
    volumes:
      - ./certs/cert.pem:/custom-certs/cert.pem:ro
      - ./certs/key.pem:/custom-certs/key.pem:ro
```

## Persistent storage options

The `volumes:` block in `docker-compose.yaml` includes commented examples for
binding the data volume to a host path or an NFS export. Use those for backups
or shared storage; the default named volume is fine for single-host use.

## External URL

For browser users to reach Bridge, the host's `8080` must be reachable at the
URL you registered during platform setup (`BRIDGE_URL`). On a cloud VM, open the
security group / firewall for `8080` (or front the host with your own reverse
proxy / load balancer terminating TLS).

Once you know the final external URL, make the Bridge **resource** in Britive
use it — re-run `platform-setup/quick-setup.py` with that URL (updates the
resource in place), or edit the resource in the Britive UI — then verify:

```bash
curl -sfk https://<external-url>/api/health
```

## Lifecycle

```bash
docker compose pull        # get a newer image (on :latest this is all you need;
                           # on a pinned tag, update the tag in the file first)
docker compose up -d       # apply changes
docker compose down        # stop and remove the container (keeps the volume)
docker compose down -v     # also delete the data volume (destroys session state)
```

> **Production:** pin a specific image tag in `docker-compose.yaml` (see Docker
> Hub `britive/bridge` tags) instead of `latest`, so updates are deliberate.
