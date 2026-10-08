# Britive Access Broker — Deployment Options

The Access Broker is a small service that runs inside your network and lets
the Britive platform create and remove just-in-time access on the systems
behind it: servers, databases, Kubernetes clusters, network devices, internal
applications. It connects **outbound only** — no inbound firewall rule, no
public endpoint — and runs the checkout and checkin scripts you define for
each resource type.

Everything here targets **Broker 3.x**, a single static binary per platform
with no Java runtime. Broker 2.0 and below are deprecated by Britive and are
not supported by these templates.

Product documentation: <https://docs.britive.com/v1/docs/brokers> (concepts,
`broker-config.yml` reference) and
<https://docs.britive.com/v1/docs/broker-3-0-1> (platforms, downloads).
Checkout/checkin script examples for dozens of resource types:
<https://github.com/britive/access-broker-examples>.

## How it works

```text
  Your network                                     Britive
  +-----------------------------+   443, outbound  +-------------------+
  |  Access Broker              | ---------------> |  <tenant>         |
  |  - bootstraps with a pool   |   HTTPS + MQTT   |  .britive-app.com |
  |    token                    | <- - - - - - - - |                   |
  |  - receives checkout /      |   commands over  |  Resource Manager |
  |    checkin / scan / rotate  |   the MQTT link  |  profiles,        |
  |    requests                 |                  |  policies, pools  |
  |  - runs your scripts        |                  +-------------------+
  |    against the targets      |
  +------+----------+-----------+
         |          |
     servers,   databases, k8s, ...
```

- The broker **bootstraps** against `https://<tenant>.britive-app.com` with a
  **broker pool token**, then keeps one long-lived **MQTT-over-TLS**
  connection open to receive work.
- Several brokers can share one pool token; Britive load-balances across the
  brokers in a pool. A pool is the unit you attach resources to.
- Configuration is **environment-first**: `BRITIVE_BROKER_TENANT_SUBDOMAIN`
  and `BRITIVE_BROKER_AUTH_TOKEN` are all a broker needs. A
  `broker-config.yml` is optional and only restricts resource types, points at
  locally stored scripts, or configures an authenticated proxy.
- Scripts are **uploaded to the tenant** with the permission definition and
  fetched by the broker at checkout time, so a script change needs no
  redeploy. Scripts baked into the image or host are also supported.

## Before you start

| You need | Where |
| -------- | ----- |
| Tenant subdomain | `acme` for `https://acme.britive-app.com` |
| A broker pool and a token | **System Administration → Brokers and Broker Pools** → create or open a pool → **Tokens**. [`../Britive Bridge/platform-setup/quick-setup.py`](../Britive%20Bridge/platform-setup/) creates both from the CLI |
| The broker package or tarball | **System Administration → Brokers and Broker Pools → Download Brokers**. There is no public download URL |

### Network

Outbound only, from wherever the broker runs:

| Destination | Port | Purpose |
| ----------- | ---- | ------- |
| `<tenant>.britive-app.com` | 443 | Bootstrap and API |
| MQTT host under `.britive-app.com` returned by bootstrap | 443 | Long-lived command channel (TLS) |
| Presigned Amazon S3 URLs | 443 | Fetching scripts uploaded to the tenant |
| Your targets | as needed | SSH 22, WinRM 5985/5986, database ports, Kubernetes API … |

A corporate proxy is supported through the standard `HTTPS_PROXY` /
`NO_PROXY` variables (plain `http://` CONNECT proxies only).

## Choosing an option

| Option | Runs on | Image | Secrets | Best for |
| ------ | ------- | ----- | ------- | -------- |
| [**Linux VM**](linux-vm/) | Any Linux with systemd (deb / rpm / apk / tar.gz) | none | env file at install, or a token generator script | Simplest production path; jump hosts; domain-joined or network-privileged servers |
| [**Docker Compose**](docker-compose/) | One Docker host | [`image/`](image/) | `.env` | Evaluation, labs, small sites |
| [**AWS ECS Fargate**](aws-ecs-fargate/) | AWS, no hosts to manage | [`image/`](image/) in ECR | Secrets Manager | AWS-native production |
| [**Kubernetes (Helm)**](kubernetes/) | EKS, AKS, GKE, any cluster | [`image/`](image/) in your registry | Kubernetes Secret, or External Secrets / CSI | Teams standardized on Kubernetes; Kubernetes RBAC checkouts |

All container options share one [image](image/): Alpine, the broker binary,
and optional tool layers (`aws`, `kubectl`, `pywinrm`, database clients) for
the scripts you run. Build it once, push it to your registry, deploy it
anywhere.

## Verify a deployment

1. The log shows `Britive broker starting version=3.x.y` and, after the first
   few seconds, no `Broker bootstrap failed` lines.
2. **System Administration → Brokers and Broker Pools → your pool →
   Brokers** lists the broker as active, under its hostname or the name your
   `BRITIVE_BROKER_NAME_GENERATOR` script printed.
3. Attach a resource to the pool, create a profile, and run one checkout and
   checkin end to end.

## Directory layout

```text
Access Broker/
├── README.md               # you are here
├── image/                  # the container image (Dockerfile, build-and-push.sh, config example)
├── docker-compose/         # one host
├── linux-vm/               # package install + systemd, token generator, tarball unit
├── aws-ecs-fargate/        # CloudFormation: ECR repo, cluster, service, Secrets Manager
└── kubernetes/             # Helm chart + per-cloud registry notes (EKS, AKS, GKE)
```

## Placeholders

Every file uses `your-tenant`, `<account>`, `<region>`, `example.com`. Replace
them locally; never commit a pool token, an account ID or a real hostname.
