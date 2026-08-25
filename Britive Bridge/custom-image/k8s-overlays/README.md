# Kubernetes overlays for the custom image

Ready-to-apply manifests that wire the [custom image](../) into the base
[Kubernetes deployment](../../v1/kubernetes/) for the two examples.

| File | Purpose |
|------|---------|
| `serviceaccount-irsa.yaml` | IRSA service account → AWS Secrets Manager (Aurora MySQL) |
| `deployment-patch.yaml` | Strategic-merge patch: custom image + SA + SSH key (init container chowns it to `bridge`, mode 0600, in-memory volume) |

## Apply order

```bash
# 0. Base manifests already applied (namespace, broker secret, pvc, deployment, service, ingress)
#    from ../../v1/kubernetes/manifests/  — see that README.

# 1. SSH provisioning key (Linux SSH example) — the broker's private key.
#    Generate it once with: ssh-keygen -t ed25519 -f ./bridge_ed25519 -N ''
#    and install bridge_ed25519.pub on each target host's provisioning user.
kubectl -n britive-bridge create secret generic bridge-ssh-key \
  --from-file=id_ed25519=./bridge_ed25519

# 2. IRSA service account (Aurora MySQL example) — edit the role ARN first.
#    Skip if you used `eksctl create iamserviceaccount` (it makes this SA for you).
kubectl apply -f serviceaccount-irsa.yaml

# 3. Patch the running Deployment: set your image, SA, and SSH mount.
#    Must be --type strategic: a plain merge patch would replace the
#    containers/volumes lists and wipe the base ports, envFrom, probes, and
#    PVC mount.
kubectl -n britive-bridge patch deployment britive-bridge \
  --type strategic --patch-file deployment-patch.yaml
```

## Before applying — edit these placeholders

- `deployment-patch.yaml` → `image:` → your pushed image
  (`docker.io/yourorg/britive-bridge-custom:latest` or your ECR URI).
- `serviceaccount-irsa.yaml` → `eks.amazonaws.com/role-arn` → the IAM role with
  `secretsmanager:GetSecretValue` on your DB master secret.

## Notes

- **Only need one example?** Apply just the parts you use — the SSH-key Secret +
  mount for SSH, the IRSA SA for MySQL. The patch includes both; trim the patch
  if you only want one.
- **Egress:** the MySQL example needs the pod to reach the Aurora endpoint on
  3306 — allow it in your network policy / security group.
- **Non-EKS clusters:** swap the IRSA SA for your platform's workload identity
  (GKE Workload Identity, AKS workload identity) or mount AWS creds via a Secret.
- **Private registries:** a private Docker Hub repo (or ECR from a non-EKS
  cluster) needs an image pull secret — `kubectl create secret docker-registry`
  and reference it via `imagePullSecrets` in the patch. EKS nodes pull from ECR
  via their node role without one.
