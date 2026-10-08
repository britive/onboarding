#!/usr/bin/env bash
#
# Register an EKS cluster as a Britive Kubernetes environment and configure
# the cluster to trust Britive as an OIDC identity provider.
#
# Usage: eks-quick-start.sh <britive-application-id> <eks-cluster-name>
#
# Requires: pybritive (logged in, or BRITIVE_API_TOKEN set), aws, jq.
# BRITIVE_TENANT must be set (pybritive reads it).
#
# Product guide: https://docs.britive.com/docs/onboarding-an-eks-cluster

set -euo pipefail

APP_ID="${1:?britive application id (from the application URL)}"
CLUSTER="${2:?eks cluster name}"
: "${BRITIVE_TENANT:?set BRITIVE_TENANT to your tenant subdomain}"

for tool in pybritive aws jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing: $tool" >&2; exit 1; }
done

echo "==> Reading cluster $CLUSTER"
cluster_json=$(aws eks describe-cluster --name "$CLUSTER")
endpoint=$(jq -r '.cluster.endpoint' <<<"$cluster_json")
ca_data=$(jq -r '.cluster.certificateAuthority.data' <<<"$cluster_json")

echo "==> Creating environment $CLUSTER in Britive application $APP_ID"
env_json=$(pybritive api application_management.environments.create --application-id "$APP_ID" --name "$CLUSTER")
env_id=$(jq -r '.id' <<<"$env_json")
[ -n "$env_id" ] && [ "$env_id" != "null" ] || { echo "environment creation returned no id: $env_json" >&2; exit 1; }

echo "==> Storing the API endpoint and CA on environment $env_id"
pybritive api application_management.environments.update \
  --application-id "$APP_ID" --environment-id "$env_id" \
  --apiServerUrl "$endpoint" --certificateAuthorityData "$ca_data" >/dev/null

echo "==> Reading the OIDC issuer and client id Britive generated"
env_detail=$(pybritive api application_management.environments.get --application-id "$APP_ID" --environment-id "$env_id")
issuer=$(jq -r '.catalogApplication.propertyTypes[] | select(.name == "oidcIssuerUrl") | .value' <<<"$env_detail")
client_id=$(jq -r '.catalogApplication.propertyTypes[] | select(.name == "clientId") | .value' <<<"$env_detail")
[ -n "$issuer" ] && [ -n "$client_id" ] || { echo "issuer or client id missing on the environment; check the application in the console" >&2; exit 1; }

echo "==> Associating Britive as the OIDC provider on $CLUSTER (one provider per cluster; takes a few minutes)"
aws eks associate-identity-provider-config --cluster-name "$CLUSTER" \
  --oidc "identityProviderConfigName=britive,issuerUrl=$issuer,clientId=$client_id,usernameClaim=sub,groupsClaim=groups"

cat <<EOF

Done. Next:
  kubectl apply -f role-config/jit-roles.yaml -f role-config/jit-rolebindings.yaml
  create a profile on the Kubernetes application with permissions named after the groups
  pybritive checkout "Kubernetes/$CLUSTER/<profile>" --mode kube-exec
Watch the association: aws eks describe-identity-provider-config --cluster-name $CLUSTER --identity-provider-config type=oidc,name=britive
EOF
