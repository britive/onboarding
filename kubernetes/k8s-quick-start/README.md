# Kubernetes quick start (OIDC)

Register a cluster as an environment of a Britive **Kubernetes** application
and configure the cluster to trust Britive as an OIDC identity provider.
After this, `pybritive checkout` of a profile gives the user a kubeconfig
whose `groups` claim is the profile's permission, and the `RoleBinding`s in
[`role-config/`](role-config/) decide what that group may do. No broker.

Product guides: [EKS](https://docs.britive.com/docs/onboarding-an-eks-cluster),
[K3s](https://docs.britive.com/docs/onboarding-a-k3s-cluster),
[OpenShift (ROSA)](https://docs.britive.com/docs/onboarding-openshift);
[terminology](https://docs.britive.com/docs/terminology-kubernetes). The
same four OIDC settings apply to any API server that accepts an external
issuer: `oidc-issuer-url`, `oidc-client-id`, `oidc-username-claim=sub`,
`oidc-groups-claim=groups`.

| Platform | `--platform` | What the script does on the cluster side |
| -------- | ------------ | --------------------------------------- |
| Amazon EKS | `eks` | `aws eks associate-identity-provider-config` (reads endpoint and CA from `describe-cluster`) |
| K3s | `k3s` | Prints the `kube-apiserver-arg` block for `/etc/rancher/k3s/config.yaml` |
| OpenShift ROSA | `openshift` | Prints the `rosa create idp` command and claim mappings (the OpenShift application type in Britive) |
| Anything else (kubeadm, RKE2, …) | `generic` | Prints the `kube-apiserver` flags |

Managed control planes that do not accept a custom OIDC issuer (AKS, GKE
without Identity Service) are not covered by Britive's guides; use the
[Access Broker](../../access-broker/kubernetes/) model there.

## Prerequisites

- `pybritive` (`pip install pybritive`), `kubectl`, `jq`; `aws` CLI for EKS
- A **Kubernetes** application created in Britive (System Administration →
  Tenant Applications → Create Application → Kubernetes; for ROSA, the
  **OpenShift** application); its application ID is in the URL
- The API server URL and CA certificate of the cluster (EKS: read by the
  script); admin rights to change the cluster's authentication configuration
  and `kubectl` admin access to apply the RBAC manifests

## 1. Register the cluster and configure OIDC

```bash
export BRITIVE_TENANT=your-tenant
./k8s-oidc-setup.sh <application-id> <environment-name> --platform eks --cluster <eks-cluster-name>
./k8s-oidc-setup.sh <application-id> <environment-name> --platform k3s --server https://<host>:6443 --ca-file /var/lib/rancher/k3s/server/tls/server-ca.crt
./k8s-oidc-setup.sh <application-id> <environment-name> --platform generic --server https://<host>:6443 --ca-file ca.crt
```

The script creates the environment in Britive, stores the cluster's API
endpoint and CA (base64, as in a kubeconfig) on it, reads back the issuer URL
and client ID Britive generated for that environment, and then either
configures the cluster (EKS) or prints exactly what to put in the API server
configuration. EKS allows one OIDC provider per cluster and the association
takes a few minutes to become `ACTIVE`; K3s and self-managed API servers
need a restart.

## 2. Create the roles and bindings

```bash
kubectl apply -f role-config/jit-roles.yaml
kubectl apply -f role-config/jit-rolebindings.yaml
```

| Britive permission (groups claim) | RoleBinding | Role | Grants |
| --------------------------------- | ----------- | ---- | ------ |
| `developers` | `pod-reader-binding` | `pod-reader` | get/list/watch pods in `jit` |
| `ns-managers` | `nsmanager-binding` | `ns-manager` | all core-API resources in `jit` |
| `jit-admins` | `jit-admin-binding` | `jit-admin` | everything in `jit` (demo only) |

The group names are what you name the permissions on the Britive profile.
Replace these demo roles with your own least-privilege roles for anything
beyond an evaluation; `jit-admin` is a deliberate wildcard.

## 3. Check out and connect

In Britive, create a profile on the environment with permissions named after
the groups above, then:

```bash
pybritive checkout "<application name>/<environment-name>/<profile>" --mode kube-exec   # or: pybritive cache kubeconfig
export KUBECONFIG=~/.kube/config:~/.britive/kube/config
kubectl config get-contexts
kubectl get pods -n jit --context <context from the list>
```

## Files

| File | Purpose |
| ---- | ------- |
| `k8s-oidc-setup.sh` | Environment in Britive + OIDC trust on the cluster, per platform |
| `role-config/jit-roles.yaml` | Namespace `jit` and three demo `Role`s |
| `role-config/jit-rolebindings.yaml` | Bindings from the Britive group names to those roles |

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `issuer or client id missing on the environment` | The application is not of type Kubernetes, or the environment was created without the OIDC attributes | Create the environment under a Kubernetes application; check its Settings tab in the console |
| `aws eks associate-identity-provider-config` fails with an existing config | EKS allows one OIDC provider per cluster | Disassociate the old one or use the Access Broker model |
| `kubectl` returns `Unauthorized` after checkout | OIDC not yet active, wrong CA on the environment, or claims not `sub`/`groups` | Wait for `ACTIVE` (EKS) or restart the API server; compare the CA with the cluster's; check the four settings |
| Checkout works but every request is `forbidden` | No `RoleBinding` for the group named by the profile's permission | Apply bindings whose `subjects` group equals the permission name (case sensitive) |
