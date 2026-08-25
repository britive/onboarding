# Britive Bridge — Kubernetes

Run Bridge on any Kubernetes cluster (EKS, AKS, GKE, or on-prem) using plain
manifests. Use this when your team is standardized on Kubernetes.

> **Helm chart on the roadmap** — see [Roadmap](#roadmap-public-helm-chart)
> below. The manifests here map 1:1 to the chart's templates, so migrating later
> is straightforward.

## What it deploys

Manifests in [`manifests/`](manifests/):

| File | Purpose |
|------|---------|
| `namespace.yaml` | `britive-bridge` namespace |
| `secret.example.yaml` | Broker credentials (template — **don't commit a filled copy**) |
| `pvc.yaml` | PersistentVolumeClaim for `/data` (5Gi, RWO) |
| `deployment.yaml` | The `britive/bridge` Deployment (1 replica, HTTPS probes) |
| `service.yaml` | ClusterIP service (443 → container 8080) |
| `ingress.yaml` | ingress-nginx Ingress with HTTPS backend + WebSocket support |
| `external-secret.example.yaml` | *(optional)* Source broker creds from an external store via the External Secrets Operator |
| `pvc-rwm.example.yaml` | *(optional, HA — not officially supported)* ReadWriteMany PVC — use **instead of** `pvc.yaml` |
| `ha-deployment-patch.example.yaml` | *(optional, HA — not officially supported)* Patch: replicas + rolling-update + anti-affinity |

Traffic path: `client → Ingress (TLS) → Service:443 → pod:8080 (HTTPS, self-signed)`.

## Prerequisites

- A Kubernetes cluster (1.25+) and `kubectl` context pointing at it
- An **Ingress controller** (examples use [ingress-nginx](https://kubernetes.github.io/ingress-nginx/))
- A **StorageClass** for the PVC (RWO is fine for a single replica; use RWX for HA)
- A way to get a TLS cert for your domain — e.g.
  [cert-manager](https://cert-manager.io/) — or bring your own cert
- Completed [platform setup](../../platform-setup/) — you need
  `BRITIVE_BROKER_TENANT_SUBDOMAIN` and `BRITIVE_BROKER_AUTH_TOKEN`

## Install

1. **Namespace**

   ```bash
   kubectl apply -f manifests/namespace.yaml
   ```

2. **Broker credentials secret** (preferred: create imperatively, no plaintext on disk):

   ```bash
   kubectl -n britive-bridge create secret generic bridge-broker \
     --from-literal=BRITIVE_BROKER_TENANT_SUBDOMAIN='<your-tenant-subdomain>' \
     --from-literal=BRITIVE_BROKER_AUTH_TOKEN='<your-broker-auth-token>'
   ```

   (`manifests/secret.example.yaml` shows the equivalent declarative form. For
   production, prefer External Secrets Operator / Sealed Secrets / Vault.)

3. **Storage, workload, service**

   ```bash
   kubectl apply -f manifests/pvc.yaml
   kubectl apply -f manifests/deployment.yaml
   kubectl apply -f manifests/service.yaml
   ```

4. **Ingress** — edit `manifests/ingress.yaml` first:
   - Replace `bridge.example.com` with your hostname (two places).
   - Adjust `ingressClassName` / annotations for your controller (see
     "Controller-specific ingress hints" below).
   - For automatic certs, uncomment the `cert-manager.io/cluster-issuer`
     annotation and set your issuer.

   ```bash
   kubectl apply -f manifests/ingress.yaml
   ```

## Verify

```bash
kubectl -n britive-bridge get pods,svc,ingress
kubectl -n britive-bridge logs deploy/britive-bridge -f

# in-cluster health check
kubectl -n britive-bridge exec deploy/britive-bridge -- \
  curl -sfk https://127.0.0.1:8080/api/health
```

Then point a DNS record for your host at the ingress controller's external
address and make the Bridge **resource** in Britive use that URL — re-run
`platform-setup/quick-setup.py` with it (updates the resource in place), or
edit the resource in the Britive UI. Finally verify from outside the cluster:

```bash
curl -sf https://bridge.example.com/api/health
```

## Key configuration notes

- **Image tag.** The manifest ships `britive/bridge:latest` with
  `imagePullPolicy: Always` so rollouts pick up new images. For production,
  pin a versioned tag and switch to `IfNotPresent`.
- **HTTPS backend.** The container serves HTTPS with a self-signed cert on 8080.
  Probes and the Service/Ingress all use the HTTPS scheme; the ingress is
  configured with `backend-protocol: HTTPS` + `proxy-ssl-verify: off`.
- **WebSocket.** Bridge upgrades connections to WebSocket — the ingress sets
  long read/send timeouts. Other controllers (ALB, Traefik, HAProxy) need their
  own WebSocket/timeout settings.
- **Persistence.** `/data` is backed by a PVC. For `replicas > 1` you need a
  `ReadWriteMany` volume (EFS CSI on AWS, Azure Files, Filestore on GCP) and
  should change the Deployment strategy accordingly.
- **Ingress alternatives.** On EKS you can swap the Ingress for the AWS Load
  Balancer Controller (ALB ingress class) with ACM annotations; on other clouds
  use their respective controllers.

## Controller-specific ingress hints

- **ingress-nginx** (provided): `backend-protocol: HTTPS`,
  `proxy-ssl-verify: off`, long `proxy-read/send-timeout` for WebSocket.
- **AWS Load Balancer Controller:** `alb.ingress.kubernetes.io/backend-protocol: HTTPS`,
  `alb.ingress.kubernetes.io/certificate-arn: <acm-arn>`,
  `alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'`.
- **Traefik:** a `ServersTransport` with `insecureSkipVerify: true` plus an
  HTTPS scheme on the service.

## Optional: production hardening

Both of these work with the plain manifests today — no Helm needed. When the
chart ships they become `values.yaml` toggles, but the behavior is identical.

### External Secrets Operator (ESO)

Instead of a raw Kubernetes Secret, pull the broker credentials from AWS Secrets
Manager / Vault / GCP / Azure. See `manifests/external-secret.example.yaml`.

1. Install ESO and grant it read access to your backend secret (IRSA on EKS,
   workload identity on GKE, etc.).
2. Edit the example for your provider/region and backend secret name.
3. Apply it **instead of** `secret.example.yaml` — ESO creates the same
   `bridge-broker` Secret, so the Deployment is unchanged.

### High availability (multiple replicas)

Bridge persists session state to `/data`, so running `replicas > 1` requires a
**ReadWriteMany** (RWX) volume shared across pods. Choose HA **at install
time** — PVC access modes are immutable, so switching later means deleting the
RWO PVC and losing `/data`.

1. Provision an RWX storage class (EFS CSI on AWS, Azure Files, Filestore on GCP).
2. Apply `manifests/pvc-rwm.example.yaml` **instead of** `pvc.yaml` (step 3 of
   the install), then apply the remaining manifests as usual.
3. Patch the Deployment for replicas + rolling updates (includes pod
   anti-affinity to spread replicas across nodes):

   ```bash
   kubectl -n britive-bridge patch deployment britive-bridge \
     --type strategic --patch-file manifests/ha-deployment-patch.example.yaml
   ```

> **Not officially supported yet.** Multiple replicas sharing `/data` work on
> Bridge v1.x, but the configuration is not covered by support — run a single
> replica for production until Britive announces HA support.

## Teardown

```bash
kubectl delete -f manifests/ingress.yaml -f manifests/service.yaml \
  -f manifests/deployment.yaml -f manifests/pvc.yaml
kubectl -n britive-bridge delete secret bridge-broker
kubectl delete -f manifests/namespace.yaml
```

> Deleting the PVC destroys persisted session state.

---

## Helm chart

A public Helm chart (OCI artifact on Docker Hub) is planned. Until it ships,
the manifests in this directory are the supported install path; they map 1:1
to the planned chart values, so migrating later is mechanical.
