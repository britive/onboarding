# Britive Bridge v2 on Kubernetes (official Helm chart)

Britive publishes the Bridge Helm chart at
`oci://registry-1.docker.io/britive/bridge-chart` (chart 2.1.1 deploys Bridge
v2.3.1) and documents it at
[learn.britive.com/bridge/deploy/kubernetes/](https://learn.britive.com/bridge/deploy/kubernetes/).
Nothing from the chart is copied here. This directory holds a
production-shaped **values file** and the **Secret** the chart expects, with
the reasons for each setting, for a cluster that already has a load-balancer
controller, a shared-storage class and a managed PostgreSQL.

| File | Purpose |
| ---- | ------- |
| `values.example.yaml` | Pinned image, external datastore, RWX recordings, NLB with TLS, native SSH/RDP/MySQL/PostgreSQL ports, worker identity, resources |
| `external-secret.example.yaml` | External Secrets Operator manifest producing the `bridge-secrets` Secret from AWS Secrets Manager |

## How the chart runs Bridge

Clustered mode. An **orchestrator** Deployment (2 replicas, leader election)
runs migrations and the reconciler and spawns **session** and **proxy** pods
through the in-cluster driver as load requires; a Service fronts the ready
proxies. Workers are not Helm resources: their spec comes from `worker.*`,
they are garbage-collected on `helm uninstall`, and a `helm upgrade` does
not restart them — they cycle on `config.cluster.*.lifespan` (48 h default).

The same requirements as every v2 deployment apply: a PostgreSQL datastore, a
permanent `BRIDGE_ENCRYPTION_KEY_B64`, and at least one protocol enabled.
Here the configuration file is rendered by the chart from `config.*` (and
`config.extraConfig` for keys the chart does not expose), so no baked image
is needed; a [custom image](../../custom-image/) is only for extra tools.

## Prerequisites

| Need | EKS | Elsewhere |
| ---- | --- | --------- |
| `helm` 3.8+ (OCI), `kubectl`, a namespace | | |
| Platform objects: broker pool and token | [`../../platform-setup/`](../../platform-setup/) | same |
| **Managed PostgreSQL** reachable from the cluster | RDS PostgreSQL ([`../aws-ecs-fargate-nlb/rds-postgres.yaml`](../aws-ecs-fargate-nlb/rds-postgres.yaml) works unchanged) | Cloud SQL, Azure Database for PostgreSQL, your own |
| **ReadWriteMany StorageClass** for recordings | EFS CSI driver with an access point owning the volume as `102:103` (StorageClass below) | Azure Files with `uid=102,gid=103` mount options; Filestore; NFS exported as `102:103` |
| **L4 load balancer** with TLS on 443 | AWS Load Balancer Controller, an ACM certificate | Any controller that provisions a TCP LB; TLS at the LB or `config.tls.enabled: true` |
| A DNS name for the LB and the matching certificate | | |
| Secrets management | External Secrets Operator + Secrets Manager (example here) | ESO with GCP Secret Manager / Key Vault, or a Secret created by your pipeline |

The EFS StorageClass the chart's README prescribes — without the access
point, the first recording write fails with `Permission denied`, because
the EFS driver ignores `fsGroup`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-xxxxxxxx
  directoryPerms: "775"
  uid: "102"
  gid: "103"
```

## Deploy

```bash
kubectl create namespace bridge

# 1. Secrets: generate once, keep forever (the encryption key cannot be rotated)
aws secretsmanager create-secret --name bridge/prod --secret-string "$(jq -n \
  --arg ct "$(openssl rand -hex 32)" --arg ek "$(openssl rand -base64 32)" \
  --arg hs "$(openssl rand -hex 32)" --arg bt "<broker pool token>" --arg dp "<RDS password>" \
  '{clusterToken:$ct, encryptionKeyB64:$ek, hostKeySeed:$hs, brokerAuthToken:$bt, datastorePassword:$dp}')"
kubectl apply -f external-secret.example.yaml          # after editing the RDS host
kubectl -n bridge get secret bridge-secrets             # must exist before the install

# 2. Values
cp values.example.yaml values.yaml                      # tenant, redirectUrl, certificate ARN, storage class, ports

# 3. Install
helm upgrade --install bridge oci://registry-1.docker.io/britive/bridge-chart \
  --version 2.1.1 -n bridge -f values.yaml
kubectl -n bridge get pods -w                           # orchestrator, then session/proxy workers
```

Point the DNS name at the load balancer (`kubectl -n bridge get svc`), then
re-run [`../../platform-setup/`](../../platform-setup/) with the real
`https://` URL so the Britive resource carries it.

## Verify

```bash
kubectl -n bridge get pods                       # orchestrator Running, proxy/session workers Ready
LB=$(kubectl -n bridge get svc -l app.kubernetes.io/instance=bridge -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')
curl -s https://bridge.example.com/readyz
curl -s https://bridge.example.com/api/license/status   # licensed once the broker token is valid
ssh -p 2222 -l '<email>%<target-host>' bridge.example.com   # native SSH, after a checkout
```

In the Britive console the Bridge's broker appears active in the pool
(**System Administration → Brokers and Broker Pools**), once per orchestrator
replica.

## Values worth understanding

| Value | Why |
| ----- | --- |
| `image.tag: v2.3.1` | The chart defaults to `latest`, which moves without notice |
| `secrets.existingSecret` | The chart renders no Secret when set; yours must carry the three `BRIDGE_*` secrets, `BRITIVE_BROKER_AUTH_TOKEN` and every `BRIDGE_DATASTORE_*` key. `datastore.*` values are then ignored |
| `config.auth.britive.redirectUrl` | An L4 NLB does not pass `X-Forwarded-Proto`, so Bridge would derive an `http://` OAuth redirect and login would loop |
| `config.extraConfig.server.trusted_proxies` | Session recordings capture real client IPs instead of the LB's |
| `config.protocols` + `proxyService.ports/extraPorts` | A native protocol enabled without a Service port produces a connect command that never works, and vice versa |
| `recordings.pvc.accessMode: ReadWriteMany` | Session workers write and proxies read on different nodes; `hostPath` is single-node only and not a compliance control |
| `postgres.enabled: false` | The bundled PostgreSQL is evaluation only and needs block storage |
| `worker.serviceAccount.annotations` | Cloud identity for checkout scripts, bound to workers only; see [`../../custom-image/`](../../custom-image/) for scripts that need Secrets Manager or SSH keys |
| `orchestrator.replicas: 2` | HA; both mount the recordings claim, hence RWX |

Pod Security Standards: the defaults satisfy `restricted` as long as
`recordings.mode` is `pvc`.

## Operations

| Task | How |
| ---- | --- |
| Change configuration | Edit `values.yaml`, `helm upgrade`. The orchestrator restarts on a config checksum; existing workers keep the old config until they cycle (`lifespan`) — delete them to force it |
| Rotate the cluster token or datastore password | Update the Secret (ESO refreshes within `refreshInterval`), then `kubectl -n bridge rollout restart deployment/bridge-orchestrator`; the chart cannot hash an external Secret. Never rotate `BRIDGE_ENCRYPTION_KEY_B64` |
| Upgrade Bridge | `image.tag` → new version, `helm upgrade`; check the chart version too (`helm show chart oci://registry-1.docker.io/britive/bridge-chart`) |
| Custom image | Build with [`../../custom-image/`](../../custom-image/) (`BAKE_CONFIG=false`: the chart renders the config), set `image.repository`/`image.tag`, add `imagePullSecrets` for a private registry |
| Argo CD | Use annotation-based resource tracking so runtime worker pods are not pruned; the chart README has the Pod health customization |
| Uninstall | `helm -n bridge uninstall bridge` removes the orchestrator, Service and spawned workers. The recordings PVC and your database remain; deactivate the pool token |

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| Install fails: `recordings.mode=pvc` needs `storageClassName` | No RWX class named | Create the StorageClass above and set `recordings.pvc.storageClassName` |
| Orchestrator `CrashLoopBackOff`, log mentions the datastore | RDS unreachable, wrong `BRIDGE_DATASTORE_*` keys, or `sslmode` mismatch | Check the Secret's keys and the security group between nodes and RDS; `require` for RDS |
| Session pod log `Permission denied` under `/data/recordings` | Volume not owned by `102:103` (EFS ignores `fsGroup`) | StorageClass with an access point `uid: "102"`, `gid: "103"` |
| Second orchestrator replica `Pending` | Recordings claim is ReadWriteOnce | RWX class, or `orchestrator.replicas: 1` |
| Browser login loops back to the login page | OAuth redirect derived as `http://` behind the NLB | Set `config.auth.britive.redirectUrl` to `https://<host>/api/auth/britive/callback` |
| `ssh -p 2222` connects then drops; native checkouts refused | No licence (limited mode) | Valid `BRITIVE_BROKER_AUTH_TOKEN` in the Secret, or install the licence in the admin console |
| Native command for MySQL/RDP never connects | Protocol enabled in `extraConfig`/`protocols` but no matching Service port (or the reverse) | Keep `config.protocols`, `extraConfig` and `proxyService.ports/extraPorts` in step |
| Workers keep old settings after `helm upgrade` | Upgrades do not rewrite spawned pods | Wait for `lifespan` cycling or delete the worker pods |
