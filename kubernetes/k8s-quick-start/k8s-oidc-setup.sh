#!/usr/bin/env bash
#
# Register a Kubernetes cluster as an environment of a Britive Kubernetes
# application and configure the cluster to trust Britive as an OIDC identity
# provider: Britive generates an issuer URL and client ID per environment;
# this script writes them where the platform expects them.
#
# Usage:
#   k8s-oidc-setup.sh <britive-application-id> <environment-name> --platform eks --cluster <eks-cluster-name>
#   k8s-oidc-setup.sh <britive-application-id> <environment-name> --platform k3s --server <api-url> --ca-file <ca.crt>
#   k8s-oidc-setup.sh <britive-application-id> <environment-name> --platform openshift --cluster <rosa-cluster-name> --server <api-url> --ca-file <ca.crt>
#   k8s-oidc-setup.sh <britive-application-id> <environment-name> --platform generic --server <api-url> --ca-file <ca.crt>
#
# What each platform does after the environment exists in Britive:
#   eks        aws eks associate-identity-provider-config (one OIDC provider per cluster)
#   k3s        prints the kube-apiserver-arg block for /etc/rancher/k3s/config.yaml
#   openshift  prints the rosa create idp command and the claim mappings
#   generic    prints the kube-apiserver flags
#
# Requires: pybritive (logged in, or BRITIVE_API_TOKEN set), jq; aws for eks.
# BRITIVE_TENANT must be set (pybritive reads it).
#
# Product guides: https://docs.britive.com/docs/onboarding-an-eks-cluster,
# onboarding-a-k3s-cluster, onboarding-openshift.

set -euo pipefail

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

APP_ID="${1:-}"
ENV_NAME="${2:-}"
[ -n "$APP_ID" ] && [ -n "$ENV_NAME" ] || usage
shift 2

PLATFORM=""
CLUSTER=""
SERVER=""
CA_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --platform) PLATFORM="${2:?eks|k3s|openshift|generic}"; shift ;;
    --cluster)  CLUSTER="${2:?cluster name}"; shift ;;
    --server)   SERVER="${2:?API server URL}"; shift ;;
    --ca-file)  CA_FILE="${2:?CA certificate file}"; shift ;;
    -h|--help)  usage ;;
    *) echo "unknown option: $1" >&2; usage ;;
  esac
  shift
done

: "${BRITIVE_TENANT:?set BRITIVE_TENANT to your tenant subdomain}"
case "$PLATFORM" in
  eks)       [ -n "$CLUSTER" ] || { echo "--platform eks needs --cluster" >&2; exit 1; } ;;
  k3s|generic) [ -n "$SERVER" ] && [ -n "$CA_FILE" ] || { echo "--platform $PLATFORM needs --server and --ca-file" >&2; exit 1; } ;;
  openshift) [ -n "$CLUSTER" ] && [ -n "$SERVER" ] && [ -n "$CA_FILE" ] || { echo "--platform openshift needs --cluster, --server and --ca-file" >&2; exit 1; } ;;
  *) echo "--platform must be eks, k3s, openshift or generic" >&2; exit 1 ;;
esac

for tool in pybritive jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing: $tool" >&2; exit 1; }
done
[ "$PLATFORM" != eks ] || command -v aws >/dev/null 2>&1 || { echo "missing: aws" >&2; exit 1; }

# -- cluster endpoint and CA --------------------------------------------------
if [ "$PLATFORM" = eks ]; then
  echo "==> Reading cluster $CLUSTER"
  cluster_json=$(aws eks describe-cluster --name "$CLUSTER")
  endpoint=$(jq -r '.cluster.endpoint' <<<"$cluster_json")
  ca_data=$(jq -r '.cluster.certificateAuthority.data' <<<"$cluster_json")
else
  [ -f "$CA_FILE" ] || { echo "CA file not found: $CA_FILE" >&2; exit 1; }
  endpoint="$SERVER"
  # Britive stores the CA as base64 (the form found in a kubeconfig). Accept a
  # PEM file or an already-encoded one.
  if grep -q 'BEGIN CERTIFICATE' "$CA_FILE"; then
    ca_data=$(base64 < "$CA_FILE" | tr -d '\n')
  else
    ca_data=$(tr -d '\n' < "$CA_FILE")
  fi
fi

# -- environment in Britive ---------------------------------------------------
echo "==> Creating environment $ENV_NAME in Britive application $APP_ID"
env_json=$(pybritive api application_management.environments.create --application-id "$APP_ID" --name "$ENV_NAME")
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
echo "    issuer:    $issuer"
echo "    client id: $client_id"

# -- cluster side -------------------------------------------------------------
case "$PLATFORM" in
  eks)
    echo "==> Associating Britive as the OIDC provider on $CLUSTER (one provider per cluster; takes a few minutes)"
    aws eks associate-identity-provider-config --cluster-name "$CLUSTER" \
      --oidc "identityProviderConfigName=britive,issuerUrl=$issuer,clientId=$client_id,usernameClaim=sub,groupsClaim=groups"
    echo "Watch it: aws eks describe-identity-provider-config --cluster-name $CLUSTER --identity-provider-config type=oidc,name=britive"
    ;;
  k3s)
    cat <<EOF

==> Add this to /etc/rancher/k3s/config.yaml on the server node(s), then restart k3s:
kube-apiserver-arg:
  - "oidc-issuer-url=$issuer"
  - "oidc-client-id=$client_id"
  - "oidc-username-claim=sub"
  - "oidc-groups-claim=groups"
EOF
    ;;
  openshift)
    cat <<EOF

==> Create the identity provider on the ROSA cluster (interactive; the client
    secret is one you generate, Britive does not issue it):
rosa create idp --cluster=$CLUSTER --name=britive --type=openid --mapping-method=claim \\
  --issuer-url=$issuer --client-id=$client_id --client-secret=<generate one>

Claim mappings when prompted: Email: sub   Name: name   Preferred username: sub   Groups: groups   Extra scopes: profile
Then copy the console login URL and the IdP name from the output into the environment's settings in Britive.
EOF
    ;;
  generic)
    cat <<EOF

==> kube-apiserver flags for this cluster:
  --oidc-issuer-url=$issuer
  --oidc-client-id=$client_id
  --oidc-username-claim=sub
  --oidc-groups-claim=groups
EOF
    ;;
esac

cat <<EOF

Next:
  kubectl apply -f role-config/jit-roles.yaml -f role-config/jit-rolebindings.yaml
  create a profile on the application with permissions named after the groups in those bindings
  pybritive checkout "<application name>/$ENV_NAME/<profile>" --mode kube-exec
EOF
