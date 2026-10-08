# Access Broker container image

One image for every container deployment in this directory (Docker Compose,
ECS Fargate, Kubernetes). Alpine plus the Britive Broker 3.x static binary
plus the command-line tools your checkout and checkin scripts call.

## 1. Get the broker

The broker is downloaded from your tenant, not from a public URL:
**System Administration → Brokers and Broker Pools → Download Brokers**,
expand **Any other Linux**, and download the `tar.gz` for `amd64` and `arm64`
(one is enough if you only build for one platform). Place the files next to
the `Dockerfile`; they are gitignored.

```text
britive-broker-3.0.2-linux-amd64.tar.gz
britive-broker-3.0.2-linux-arm64.tar.gz
```

## 2. Build and push

```bash
# Amazon ECR (repository created on demand, immutable tags, scan on push)
REGISTRY=<account>.dkr.ecr.<region>.amazonaws.com ./build-and-push.sh

# Azure Container Registry
az acr login --name myregistry
REGISTRY=myregistry.azurecr.io ./build-and-push.sh

# Google Artifact Registry
gcloud auth configure-docker us-docker.pkg.dev
REGISTRY=us-docker.pkg.dev/my-project/britive ./build-and-push.sh
```

Defaults: `BROKER_VERSION=3.0.2`, `TAG=3.0.2-r1`, both architectures. Bump
`-rN` on every rebuild; `latest` is refused.

Add tool layers for the scripts you run:

| Build arg | Installs | Needed by |
| --------- | -------- | --------- |
| `WITH_AWS_CLI=true` | `aws` | Secrets Manager lookups, EC2/RDS discovery, `aws eks update-kubeconfig` |
| `WITH_KUBECTL=true` | `kubectl` | Kubernetes RBAC checkouts |
| `WITH_PYWINRM=true` | `python3`, `pywinrm`, `requests-ntlm` | Windows local users over WinRM |
| `WITH_DB_CLIENTS=true` | `psql`, `mysql`, `ldapsearch` | Database and LDAP checkouts |

```bash
REGISTRY=… WITH_AWS_CLI=true WITH_KUBECTL=true ./build-and-push.sh
```

Local single-platform build and smoke test (the bootstrap fails because the
tenant is a placeholder; what matters is that the binary starts as a non-root
user and logs to stdout):

```bash
docker build -t britive-broker:local .
docker run --rm -e BRITIVE_BROKER_TENANT_SUBDOMAIN=your-tenant -e BRITIVE_BROKER_AUTH_TOKEN=x britive-broker:local
# time=… level=INFO msg="Britive broker starting" version=3.0.2 …
# time=… level=ERROR msg="Broker bootstrap failed" error="… lookup your-tenant.britive-app.com …"
docker run --rm --entrypoint id britive-broker:local          # uid=1000(britivebroker)
docker run --rm --entrypoint sh britive-broker:local -c 'command -v aws kubectl psql python3'
```

## 3. Configure at runtime

| Variable | Required | Meaning |
| -------- | -------- | ------- |
| `BRITIVE_BROKER_TENANT_SUBDOMAIN` | yes | `acme` for `acme.britive-app.com` |
| `BRITIVE_BROKER_AUTH_TOKEN` | yes | Broker pool token. Inject from a secret store, never bake it in |
| `BRITIVE_BROKER_NAME_GENERATOR` | no | Script printing the broker's display name (default: hostname) |
| `BRITIVE_BROKER_LOG_FORMAT` | no | `json` for log pipelines |
| `HTTPS_PROXY`, `NO_PROXY` | no | Standard proxy variables; all broker traffic is TLS on 443 |

A `broker-config.yml` is optional. Mount
[`broker-config.yml.example`](broker-config.yml.example) (edited) at
`/opt/britive-broker/config/broker-config.yml` only to restrict
`resource_types`, run image-baked scripts, or set proxy credentials. Without
it the broker accepts every resource type the tenant sends.

Outbound network from the container: HTTPS 443 to
`<tenant>.britive-app.com`, a long-lived MQTT-over-TLS connection to the
`.britive-app.com` host returned by bootstrap, and 443 to the presigned S3
URLs remote scripts are fetched from. Nothing inbound.

## 4. Verify

The log shows the version and, once connected, no further
`Broker bootstrap failed` lines. In the console, **System Administration →
Brokers and Broker Pools → your pool → Brokers** lists the broker as active
under its hostname (or the name your generator script printed).

## Upgrading

Download the new tarballs, `BROKER_VERSION=3.x.y ./build-and-push.sh`, then
point the deployment at the new tag. The broker holds one long-lived
connection; a rolling replacement briefly runs two brokers in the pool, which
is supported.

## Legacy 2.x (Java) brokers

Broker 2.0 and below are deprecated by Britive. Nothing in this directory
supports the JAR; the 3.x package replaces it and reuses the same
`broker-config.yml` keys.
