# Access Broker — Docker Compose

The broker on one Docker host. For an evaluation, a lab, or a small site that
already runs Docker. It does not survive host failure; for that use
[ECS Fargate](../aws-ecs-fargate/) or [Kubernetes](../kubernetes/), or install
the package directly on a VM with systemd ([linux-vm](../linux-vm/)).

## Prerequisites

- Docker Engine 24+ with the Compose plugin
- Outbound HTTPS from the host to `<tenant>.britive-app.com` (see
  [../README.md](../README.md#network))
- The image from [../image/](../image/) — built locally
  (`docker build -t britive-broker:local .`) or pushed to a registry
- A broker pool token from **System Administration → Brokers and Broker
  Pools**

## Run

```bash
cp .env.example .env          # fill in the tenant subdomain and token
docker compose up -d
docker compose logs -f broker
```

A healthy start logs `Britive broker starting` followed by MQTT connection
lines and no `Broker bootstrap failed`. The broker then appears under its
hostname in the pool's **Brokers** tab.

## Options

- **Restrict resource types or run baked-in scripts:** copy
  [`../image/broker-config.yml.example`](../image/broker-config.yml.example)
  to `broker-config.yml` here, edit it, and uncomment the config mount in
  `docker-compose.yaml`.
- **SSH-based checkouts:** generate a key pair (`ssh-keygen -t ed25519 -f
  broker-ssh/id_ed25519 -N ''`), install the public key on the targets'
  provisioning account, and uncomment the `broker-ssh` mount. Keep the
  directory out of git.
- **Proxy:** set `HTTPS_PROXY` / `NO_PROXY` in `.env` and uncomment them in
  the compose file.
- **Rotate the token:** create a new token on the pool, update `.env`,
  `docker compose up -d` (the container is recreated), then delete the old
  token once the broker shows active.
- **Upgrade:** rebuild the image with the new tarball, update `BROKER_IMAGE`,
  `docker compose up -d`.

## Teardown

```bash
docker compose down        # keeps the cache volume
docker compose down -v
```
