# Kubernetes quick start (OIDC)

Register an EKS cluster as a Britive Kubernetes environment and configure
the cluster to trust Britive as an OIDC identity provider. After this,
`pybritive checkout` of a profile gives the user a kubeconfig whose
`groups` claim is the profile's permission, and the `RoleBinding`s in
[`role-config/`](role-config/) decide what that group may do.

Product guide: [Onboarding an EKS cluster](https://docs.britive.com/docs/onboarding-an-eks-cluster).
Other platforms follow the same shape with their own OIDC provider command
(GKE: identity service; AKS: OIDC issuer + structured authentication; K3s /
OpenShift: API server OIDC flags).

## Prerequisites

- `pybritive` (`pip install pybritive`), `aws` CLI, `kubectl`, `jq`
- A **Kubernetes** application created in Britive (System Administration →
  Tenant Applications → Create Application → Kubernetes); its application ID
  is in the URL
- Permission to run `aws eks associate-identity-provider-config` on the
  cluster, and `kubectl` admin access to apply the RBAC manifests

## 1. Register the cluster and configure OIDC

```bash
export BRITIVE_TENANT=your-tenant
./eks-quick-start.sh <application-id> <eks-cluster-name>
```

The script creates the environment in Britive, writes the cluster's API
endpoint and CA into it, reads back the issuer URL and client ID Britive
generated for that environment, and associates them with the cluster as an
OIDC provider (`usernameClaim=sub`, `groupsClaim=groups`). EKS allows one
OIDC provider per cluster, and the association takes a few minutes to become
`ACTIVE`.

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

In Britive, create a profile on the Kubernetes application with permissions
named after the groups above, then:

```bash
pybritive checkout "Kubernetes/<cluster-name>/<profile>" --mode kube-exec   # or: pybritive cache kubeconfig
export KUBECONFIG=~/.kube/config:~/.britive/kube/config
kubectl config get-contexts
kubectl get pods -n jit --context <context from the list>
```

## Files

| File | Purpose |
| ---- | ------- |
| `eks-quick-start.sh` | Steps 1–2 of the product guide for EKS |
| `role-config/jit-roles.yaml` | Namespace `jit` and three demo `Role`s |
| `role-config/jit-rolebindings.yaml` | Bindings from the Britive group names to those roles |
