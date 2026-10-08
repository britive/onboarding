# Access Broker on Kubernetes (Helm)

One Helm chart for every cluster — EKS, AKS, GKE, on-prem. The chart deploys
the image you built from [`../image/`](../image/) with the pool token in a
Secret, runs it as a non-root user on a read-only root filesystem, and
optionally grants it the RBAC needed for Kubernetes JIT checkouts in this
cluster.

```text
charts/britive-broker/     the chart
values.example.yaml        starting point for your values file
```

## Prerequisites

- `helm` 3.12+ and `kubectl` with access to the cluster
- Outbound 443 from the pods to `<tenant>.britive-app.com` (NAT or egress
  gateway; add `extraEnv` for `HTTPS_PROXY` / `NO_PROXY` behind a proxy)
- The image pushed to a registry the cluster can pull from (below)
- A broker pool token (**System Administration → Brokers and Broker Pools**)

## Step 1: Push the image to your registry

```bash
cd ../image
```

**EKS — Amazon ECR** (node role pulls from ECR without an image pull secret):

```bash
REGISTRY=<account>.dkr.ecr.<region>.amazonaws.com ./build-and-push.sh
```

**AKS — Azure Container Registry** (attach the registry to the cluster once:
`az aks update -n <cluster> -g <rg> --attach-acr <registry>`):

```bash
az acr login --name <registry>
REGISTRY=<registry>.azurecr.io ./build-and-push.sh
```

**GKE — Artifact Registry** (the node service account needs
`roles/artifactregistry.reader`):

```bash
gcloud artifacts repositories create britive --repository-format=docker --location=us
gcloud auth configure-docker us-docker.pkg.dev
REGISTRY=us-docker.pkg.dev/<project>/britive ./build-and-push.sh
```

Add `WITH_KUBECTL=true` for Kubernetes checkouts, `WITH_AWS_CLI=true` /
`WITH_PYWINRM=true` / `WITH_DB_CLIENTS=true` for the scripts you run.

## Step 2: Provide the token

For an evaluation, let the chart create the Secret with
`--set britive.authToken=<token>`. For anything else, create the Secret with
your secret tooling and reference it:

```bash
# plain kubectl (the value lands in your shell history; prefer the operators below)
kubectl -n britive create secret generic britive-broker-token \
  --from-literal=BRITIVE_BROKER_AUTH_TOKEN=<broker-pool-token>
```

- **External Secrets Operator:** an `ExternalSecret` that maps the token from
  AWS Secrets Manager / Azure Key Vault / GCP Secret Manager into
  `britive-broker-token` with key `BRITIVE_BROKER_AUTH_TOKEN`.
- **Secrets Store CSI driver:** a `SecretProviderClass` with
  `secretObjects` producing the same Secret.

## Step 3: Install

```bash
cp values.example.yaml values.yaml      # edit image.repository, britive.tenantSubdomain, secret
helm upgrade --install britive-broker charts/britive-broker \
  -n britive --create-namespace -f values.yaml
```

The chart refuses to render without `image.repository`,
`britive.tenantSubdomain`, and either `britive.authToken` or
`britive.existingSecret.name`.

## Step 4: Verify

```bash
kubectl -n britive get pods -l app.kubernetes.io/name=britive-broker
kubectl -n britive logs -l app.kubernetes.io/name=britive-broker -f
```

Expect `Britive broker starting version=3.x.y` and no `Broker bootstrap
failed` lines after the first seconds. The broker shows as active in the
pool's **Brokers** tab under the pod name.

## Kubernetes JIT checkouts in this cluster

Scripts that grant access by creating a `RoleBinding` at checkout and
deleting it at checkin run with the pod's service account. Enable the RBAC
the chart ships, scoped to the namespaces that should be reachable:

```yaml
rbac:
  create: true
  namespaces: [dev, staging]
```

The broker can only hand out permissions it holds itself (Kubernetes
prevents escalation), so the `Role`s your checkouts bind must already exist
in those namespaces and the chart's rules must cover them. Leave
`namespaces` empty for a cluster-wide `ClusterRole` only if you accept that
scope. Build the image with `WITH_KUBECTL=true`; in-cluster credentials are
picked up automatically.

## Cloud identity for scripts

Scripts that call the cloud API (Secrets Manager, EC2, Key Vault, Secret
Manager) authenticate with the pod's workload identity:

| Cluster | Values |
| ------- | ------ |
| EKS (IRSA) | `serviceAccount.annotations: {eks.amazonaws.com/role-arn: arn:aws:iam::<account>:role/britive-broker}` |
| GKE (Workload Identity) | `serviceAccount.annotations: {iam.gke.io/gcp-service-account: britive-broker@<project>.iam.gserviceaccount.com}` |
| AKS (Workload Identity) | `serviceAccount.annotations: {azure.workload.identity/client-id: <client-id>}` and `podLabels: {azure.workload.identity/use: "true"}` |

Create the cloud role/identity with least privilege for what the scripts do
(for example `secretsmanager:GetSecretValue` on one secret prefix) and bind it
to `system:serviceaccount:britive:britive-broker`.

## Operations

- **Rotate the token:** update the Secret (or `--set britive.authToken`),
  then `kubectl -n britive rollout restart deployment/britive-broker`. Delete
  the old token in the console once the new pod shows active.
- **Upgrade the broker:** push a new image tag, `helm upgrade … --set
  image.tag=3.x.y-r1`. Rolling update briefly runs two brokers in the pool;
  that is supported.
- **Restrict resource types:** set `config:` to a `broker-config.yml` (see
  [`../image/broker-config.yml.example`](../image/broker-config.yml.example));
  the chart mounts it and restarts pods when it changes.
- **Uninstall:** `helm -n britive uninstall britive-broker`, then deactivate
  the token.

## Chart values

Run `helm show values charts/britive-broker` for the full list with
comments. The ones everyone sets:

| Value | Required | Description |
| ----- | -------- | ----------- |
| `image.repository`, `image.tag` | yes | Your pushed image |
| `britive.tenantSubdomain` | yes | Tenant subdomain |
| `britive.authToken` or `britive.existingSecret.name` | yes | Pool token |
| `replicaCount` | no | Brokers in the pool (default 1) |
| `config` | no | Inline `broker-config.yml` |
| `rbac.create`, `rbac.namespaces` | no | RoleBinding management for Kubernetes checkouts |
| `serviceAccount.annotations`, `podLabels` | no | Workload identity |
| `extraEnv`, `extraVolumes`, `extraVolumeMounts` | no | Proxy, SSH keys, anything else scripts need |
