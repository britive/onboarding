# Kubernetes

Two different ways Britive grants Kubernetes access. Pick by how your
cluster authenticates.

| Directory | Model | Use it when |
| --------- | ----- | ----------- |
| [`k8s-quick-start/`](k8s-quick-start/) | **Native Kubernetes application**: the cluster trusts Britive as an OIDC provider; a checkout issues a short-lived kubeconfig whose `groups` claim matches `RoleBinding`s you create once | EKS, K3s, OpenShift ROSA, or any API server that accepts an external OIDC issuer. No broker needed. Product guides: [EKS](https://docs.britive.com/docs/onboarding-an-eks-cluster), [K3s](https://docs.britive.com/docs/onboarding-a-k3s-cluster), [OpenShift](https://docs.britive.com/docs/onboarding-openshift) |
| **Access Broker** | A broker inside the cluster creates and deletes `RoleBinding`s at checkout/checkin time with scripts | Clusters that cannot add an OIDC provider, or when access must be provisioned by a script. Deploy the broker with the Helm chart in [`../access-broker/kubernetes/`](../access-broker/kubernetes/) (`rbac.create: true`); script examples: [access-broker-examples/k8s](https://github.com/britive/access-broker-examples/tree/main/k8s) |

In both cases the Kubernetes `Role`s and `ClusterRole`s are yours; Britive
binds identities to them for the duration of a checkout.
